# Local Windows build guard. No cleanup, daemon control, networking, or global settings.
Set-StrictMode -Version 2

function Assert-GuardLocalPath {
    param([string]$Path)
    if ($Path -notmatch '^[A-Za-z]:[\\/]' -or $Path.StartsWith('\\')) { throw 'A local absolute Windows path is required.' }
    $full = [IO.Path]::GetFullPath($Path).TrimEnd('\')
    $drive = [IO.DriveInfo]::new([IO.Path]::GetPathRoot($full))
    if ($drive.DriveType -ne [IO.DriveType]::Fixed) { throw 'Only a local fixed disk is supported.' }
    $current = $full
    while ($current) {
        if (Test-Path -LiteralPath $current) {
            if ((Get-Item -LiteralPath $current -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Reparse paths are not supported.' }
        }
        $parent = [IO.Path]::GetDirectoryName($current)
        if ($parent -eq $current) { break }
        $current = $parent
    }
    return $full
}

function Get-GuardPathKey {
    param([string]$Path)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Path.ToLowerInvariant())))).Replace('-','').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function Assert-GuardSpace {
    param([string[]]$Roots,[scriptblock]$Provider,[double]$PeakGB,[double]$ReserveGB,[double]$ConcurrentPeakGB,[Collections.IList]$Observations)
    # GB inputs are decimal; the fixed post-consumption floor is 60 GiB, for EVERY task.
    $plannedBytes = [long][Math]::Ceiling(($PeakGB + $ConcurrentPeakGB) * 1e9)
    $remainingBytes = [long][Math]::Max((60 * 1GB), [Math]::Ceiling($ReserveGB * 1e9))
    foreach ($root in ($Roots | Select-Object -Unique)) {
        $free = [long](& $Provider $root)
        $observation = [pscustomobject]@{root=$root;freeBytes=$free;projectedRemainingBytes=($free - $plannedBytes);requiredRemainingBytes=$remainingBytes;observedUtc=[DateTime]::UtcNow.ToString('o')}
        if ($null -ne $Observations) { $null = $Observations.Add($observation) }
        if ($free -lt 100e9) { Write-Warning 'Less than 100 GB free; review the planned build and recording budget.' }
        if ($free -lt ($plannedBytes + $remainingBytes)) { throw 'Build held: declared build/concurrent peaks would leave less than 60 GiB or the requested reserve.' }
        $observation
    }
}

function Get-GuardState {
    param([string]$State,[string]$ManifestPath,[string]$Task,[string]$Repo,[string]$Build,[string]$Cache)
    $records = @()
    if (Test-Path -LiteralPath $State) { $records = @(Get-ChildItem -LiteralPath $State -Filter '*.json' -Force) }
    if (!(Test-Path -LiteralPath $ManifestPath) -and $records.Count -ge 64) { throw 'Manifest capacity reached (64 tasks); request an archive review.' }
    $homes = @(); $retained = @()
    foreach ($file in $records) {
        Assert-GuardLocalPath $file.FullName | Out-Null
        if ($file.PSIsContainer -or $file.Length -gt 131072) { throw 'Invalid manifest file.' }
        $record = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($record.schemaVersion -ne 1) { throw 'Unsupported manifest schema.' }
        if ($record.cacheDirectory) {
            $homes += $record.cacheDirectory
            if ($Cache -and $record.cacheDirectory -eq $Cache -and $record.taskId -ne $Task) { throw 'Cross-task cache reuse has not been validated; hold this build.' }
        }
        if ($file.FullName -eq $ManifestPath) {
            if ($record.taskId -ne $Task -or $record.repository -ne $Repo -or $record.buildDirectory -ne $Build -or ([string]$record.cacheDirectory) -ne ([string]$Cache)) { throw 'Manifest identity mismatch; do not orphan an older cache or build.' }
            if ($Cache -and $record.status -ne 'succeeded') { throw 'A failed or unfinished cache requires owner review before reuse.' }
            $retained = @($record.retainedArtifacts)
            if ($retained.Count -gt 8) { throw 'Artifact capacity reached.' }
            foreach ($artifact in $retained) {
                if ($artifact.status -ne 'verified') { throw 'An incomplete artifact requires owner review; no overwrite or retry.' }
                $p = Assert-GuardLocalPath $artifact.path
                if (!$p.StartsWith((Join-Path $State ('artifacts\' + $Task)) + '\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe retained artifact path.' }
                if (!(Test-Path -LiteralPath $p -PathType Leaf) -or (Get-Item -LiteralPath $p -Force).Length -ne $artifact.bytes -or (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLowerInvariant() -ne $artifact.sha256) { throw 'Previously retained artifact is missing or changed.' }
            }
        }
    }
    if ($Cache) {
        if ($Cache -notin $homes -and @($homes | Select-Object -Unique).Count -ge 2) { throw 'Two dedicated cache slots are already recorded; request a lifecycle review.' }
        if (!(Test-Path -LiteralPath $ManifestPath) -and (Test-Path -LiteralPath $Cache) -and @(Get-ChildItem -LiteralPath $Cache -Force).Count) { throw 'Unregistered nonempty cache cannot be adopted in this first stage.' }
    }
    return [pscustomobject]@{retained=$retained}
}

function Write-GuardManifest {
    param([string]$Path,$Manifest)
    Assert-GuardLocalPath $Path | Out-Null
    $pending = $Path + '.pending'
    Assert-GuardLocalPath $pending | Out-Null
    if (Test-Path -LiteralPath $pending) { throw 'Pending manifest requires owner review.' }
    $bytes = [Text.Encoding]::UTF8.GetBytes(($Manifest | ConvertTo-Json -Depth 8))
    $stream = [IO.File]::Open($pending,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try { $stream.Write($bytes,0,$bytes.Length); $stream.Flush($true) } finally { $stream.Dispose() }
    if (Test-Path -LiteralPath $Path) { [IO.File]::Replace($pending,$Path,[NullString]::Value) } else { [IO.File]::Move($pending,$Path) }
}

function Copy-GuardArtifact {
    param([string]$Source,[string]$Destination)
    $sourceStream = [IO.File]::Open($Source,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
    try {
        $output = [IO.File]::Open($Destination,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
        try { $sourceStream.CopyTo($output); $output.Flush($true) } finally { $output.Dispose() }
    } finally { $sourceStream.Dispose() }
}

function Invoke-GuardedBuild {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Repository,
        [Parameter(Mandatory=$true)][string]$BuildDirectory,
        [Parameter(Mandatory=$true)][string]$StateDirectory,
        [Parameter(Mandatory=$true)][ValidatePattern('^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$')][string]$TaskId,
        [Parameter(Mandatory=$true)][ValidateSet('ExistingTask','NewTask','IsolatedValidation','Recovery')][string]$ReasonCode,
        [Parameter(Mandatory=$true)][scriptblock]$BuildAction,
        [string]$CacheDirectory,
        [string[]]$Artifacts = @(),
        [string[]]$CleanupDirectories = @(),
        [ValidateRange(0,10000)][double]$ExpectedPeakGB = 25,
        [ValidateRange(0,10000)][double]$ReserveGB = 30,
        [Parameter(Mandatory=$true)][ValidateRange(0,10000)][double]$ConcurrentPeakGB,
        [switch]$NewHeavyIsolated,
        [switch]$DryRun,
        [scriptblock]$FreeBytesProvider = { param($root) ([IO.DriveInfo]::new($root)).AvailableFreeSpace }
    )
    $ErrorActionPreference = 'Stop'
    $repo = Assert-GuardLocalPath $Repository
    $build = Assert-GuardLocalPath $BuildDirectory
    $state = Assert-GuardLocalPath $StateDirectory
    $userRoot = [IO.Path]::GetFullPath([Environment]::GetFolderPath('UserProfile')).TrimEnd('\')
    if (!$state.StartsWith($userRoot + '\',[StringComparison]::OrdinalIgnoreCase)) { throw 'State must be in the current user profile, outside shared/system folders.' }
    if (!(Test-Path -LiteralPath $repo -PathType Container)) { throw 'Repository does not exist.' }
    if ($state -eq $repo -or $state.StartsWith($repo + '\',[StringComparison]::OrdinalIgnoreCase)) { throw 'State must be outside the repository.' }
    if ($build -eq $repo -or !$build.StartsWith($repo + '\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Build output must be a child of this repository.' }
    if ($build.Split('\') -contains '.git') { throw 'Git storage is never a build output.' }
    $candidatePaths = @()
    foreach ($candidate in $CleanupDirectories) {
        $c = Assert-GuardLocalPath $candidate
        if ($c -ne $build -and !$c.StartsWith($build + '\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Cleanup candidates must be within build output.' }
        $candidatePaths += $c
    }
    if ($CacheDirectory) { $cache = Assert-GuardLocalPath $CacheDirectory } else { $cache = $null }
    if ($cache -and !$cache.StartsWith($userRoot + '\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Dedicated cache must be in the current user profile.' }
    $artifactPaths = @()
    foreach ($artifact in $Artifacts) {
        $a = Assert-GuardLocalPath $artifact
        if (!$a.StartsWith($build + '\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Artifacts must be inside the declared build output.' }
        if ([IO.Path]::GetExtension($a).ToLowerInvariant() -notin @('.exe','.apk','.pdb')) { throw 'Only explicit exe/APK/PDB artifacts can be preserved.' }
        $artifactPaths += $a
    }
    $roots = @([IO.Path]::GetPathRoot($build),[IO.Path]::GetPathRoot($state))
    if ($cache) { $roots += [IO.Path]::GetPathRoot($cache) }
    $space = @(Assert-GuardSpace $roots $FreeBytesProvider $ExpectedPeakGB $ReserveGB $ConcurrentPeakGB)
    $head = @(& git -C $repo rev-parse --verify HEAD)
    if ($LASTEXITCODE -ne 0 -or $head.Count -ne 1 -or $head[0] -notmatch '^[a-f0-9]{40}$') { throw 'Cannot verify repository HEAD.' }
    $changes = @(& git -C $repo status --porcelain --untracked-files=all)
    if ($LASTEXITCODE -ne 0) { throw 'Cannot verify working tree state.' }
    $dirty = $changes.Count -gt 0
    $manifestPath = Join-Path $state ($TaskId + '.json')
    Assert-GuardLocalPath $manifestPath | Out-Null
    Assert-GuardLocalPath ($manifestPath + '.pending') | Out-Null
    if (Test-Path -LiteralPath ($manifestPath + '.pending')) { throw 'Pending manifest requires owner review.' }
    $prior = Get-GuardState $state $manifestPath $TaskId $repo $build $cache
    if ($DryRun) {
        return [pscustomobject]@{status='dry-run';taskId=$TaskId;reasonCode=$ReasonCode;commit=$head[0];workingTreeDirty=$dirty;buildDirectory=$build;cacheDirectory=$cache;manifest=$manifestPath;cleanupExecuted=$false;budget=@{expectedPeakGB=$ExpectedPeakGB;concurrentPeakGB=$ConcurrentPeakGB;reserveGB=$ReserveGB;minimumRemainingGiB=60};space=$space}
    }
    New-Item -ItemType Directory -Path $state -Force | Out-Null
    $locks = @()
    $oldLocation = Get-Location
    $oldGradle = $env:GRADLE_USER_HOME
    $manifest = $null
    try {
        # Sorted resource keys avoid deadlocks. Persistent lock files are never deleted.
        $capacityPath = Assert-GuardLocalPath (Join-Path $state 'capacity.lock')
        $locks += [IO.File]::Open($capacityPath,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
        $space = @(Assert-GuardSpace $roots $FreeBytesProvider $ExpectedPeakGB $ReserveGB $ConcurrentPeakGB)
        $prior = Get-GuardState $state $manifestPath $TaskId $repo $build $cache
        $keys = @(('manifest-' + (Get-GuardPathKey $manifestPath)), ('build-' + (Get-GuardPathKey $build)))
        if ($cache) { $keys += 'cache-' + (Get-GuardPathKey $cache) }
        foreach ($key in ($keys | Sort-Object -Unique)) {
            $lockPath = Assert-GuardLocalPath (Join-Path $state ($key + '.lock'))
            $locks += [IO.File]::Open($lockPath,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
        }
        $retained = @($prior.retained)
        $manifest = [ordered]@{schemaVersion=1;taskId=$TaskId;reasonCode=$ReasonCode;repository=$repo;commit=$head[0];workingTreeDirty=$dirty;buildDirectory=$build;cacheDirectory=$cache;startedUtc=[DateTime]::UtcNow.ToString('o');finishedUtc=$null;status='running';retainedArtifacts=$retained;cleanupCandidates=@();cleanupExecuted=$false;budget=@{expectedPeakGB=$ExpectedPeakGB;concurrentPeakGB=$ConcurrentPeakGB;reserveGB=$ReserveGB;minimumRemainingGiB=60};spaceBeforeBuild=$space;spaceAfterBuild=@();spaceAfterPreservation=@();retentionPolicy='owner-review-no-auto-delete'}
        Write-GuardManifest $manifestPath $manifest
        if ($cache) { $env:GRADLE_USER_HOME = $cache }
        Set-Location -LiteralPath $repo
        & $BuildAction | Out-Host
        $afterBuild = New-Object 'System.Collections.Generic.List[object]'
        try { $null = @(Assert-GuardSpace $roots $FreeBytesProvider 0 $ReserveGB $ConcurrentPeakGB $afterBuild) }
        finally { $manifest.spaceAfterBuild = @($afterBuild.ToArray()) }
        foreach ($a in ($artifactPaths | Select-Object -Unique)) {
            Assert-GuardLocalPath $a | Out-Null
            $info = Get-Item -LiteralPath $a -Force
            if ($info.PSIsContainer) { throw 'An artifact must be a file.' }
            $digest = (Get-FileHash -LiteralPath $a -Algorithm SHA256).Hash.ToLowerInvariant()
            $filename = [IO.Path]::GetFileName($a)
            if ($filename -notmatch '^[A-Za-z0-9_.-]+$') { throw 'Artifact filename must be ASCII.' }
            $destination = Join-Path $state ('artifacts\' + $TaskId + '\' + $digest + '-' + $filename)
            Assert-GuardLocalPath $destination | Out-Null
            $existing = @($retained | Where-Object { $_.path -eq $destination })
            if (!$existing.Count) {
                if ($retained.Count -ge 8) { throw 'Artifact capacity reached (8/task); request an archive review.' }
                $null = @(Assert-GuardSpace @([IO.Path]::GetPathRoot($state)) $FreeBytesProvider ($info.Length / 1e9) $ReserveGB $ConcurrentPeakGB)
                $reservation = [pscustomobject]@{path=$destination;sha256=$digest;bytes=$info.Length;commit=$head[0];workingTreeDirty=$dirty;status='pending'}
                $retained += $reservation
                $manifest.retainedArtifacts = $retained
                Write-GuardManifest $manifestPath $manifest
                New-Item -ItemType Directory -Path ([IO.Path]::GetDirectoryName($destination)) -Force | Out-Null
                if (Test-Path -LiteralPath $destination) {
                    if ((Get-Item -LiteralPath $destination -Force).Length -ne $info.Length -or (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash.ToLowerInvariant() -ne $digest) { throw 'Artifact collision; no overwrite.' }
                } else {
                    Copy-GuardArtifact $a $destination
                    if ((Get-Item -LiteralPath $destination -Force).Length -ne $info.Length -or (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash.ToLowerInvariant() -ne $digest) { throw 'Artifact verification failed; original retained.' }
                }
                $reservation.status = 'verified'
                # Record each verified copy so a later failure cannot orphan successful copies.
                $manifest.retainedArtifacts = $retained
                Write-GuardManifest $manifestPath $manifest
            }
        }
        $afterPreservation = New-Object 'System.Collections.Generic.List[object]'
        try { $null = @(Assert-GuardSpace $roots $FreeBytesProvider 0 $ReserveGB $ConcurrentPeakGB $afterPreservation) }
        finally { $manifest.spaceAfterPreservation = @($afterPreservation.ToArray()) }
        $manifest.status = 'succeeded'
        $manifest.cleanupCandidates = @($candidatePaths | ForEach-Object { [pscustomobject]@{path=$_;category='regenerable-build-output';retentionRule='owner-review-no-age-based-deletion';ownerConfirmationRequired=$true;approvalRequired=$true;retainedArtifactsVerified=$true;boundaryReviewRequired=$true} })
        return [pscustomobject]@{status='succeeded';manifest=$manifestPath;cleanupExecuted=$false}
    } catch {
        if ($manifest) { $manifest.status = 'failed'; $manifest.cleanupCandidates = @() }
        throw
    } finally {
        try {
            if ($manifest) { $manifest.finishedUtc = [DateTime]::UtcNow.ToString('o'); Write-GuardManifest $manifestPath $manifest }
        } finally {
            $env:GRADLE_USER_HOME = $oldGradle
            try { Set-Location -LiteralPath $oldLocation }
            finally { foreach ($handle in $locks) { $handle.Dispose() } }
        }
    }
}
Export-ModuleMember -Function Invoke-GuardedBuild
