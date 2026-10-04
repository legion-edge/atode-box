# Self-contained tests: no npm/Cargo/Flutter build, daemon control, network, or cleanup.
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'BuildGuard.psm1') -Force
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$fixture = Join-Path $env:TEMP ('build-guard-tests-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixture | Out-Null
$state = Join-Path $fixture 'state'
$build = Join-Path $repo ('.build-guard-tests\' + [Guid]::NewGuid().ToString('N'))
$calls = 0
$passed = 0
function Check([bool]$Condition,[string]$Label) { if (!$Condition) { throw "Test failed: $Label" }; $script:passed++ }
function Must-Fail([scriptblock]$Body,[string]$Label) {
    $failed = $false
    try { & $Body | Out-Null } catch { $failed = $true }
    Check $failed $Label
}
$common = @{Repository=$repo;BuildDirectory=$build;StateDirectory=$state;TaskId='fixture';ReasonCode='IsolatedValidation';ExpectedPeakGB=1;ReserveGB=1;ConcurrentPeakGB=0;NewHeavyIsolated=$true;FreeBytesProvider={param($root) 200e9};BuildAction={$script:calls++}}
$plan = Invoke-GuardedBuild @common -DryRun
Check ($plan.status -eq 'dry-run' -and $calls -eq 0 -and !(Test-Path $fixture\state)) 'DryRun has no writes or build invocation'
$low = $common.Clone(); $low.FreeBytesProvider = {param($root) 59e9}
Must-Fail { Invoke-GuardedBuild @low -DryRun } 'new isolated build blocked below 60 GB'
$peak = $common.Clone(); $peak.ExpectedPeakGB = 200
Must-Fail { Invoke-GuardedBuild @peak -DryRun } 'planned peak and reserve enforced'
$unc = $common.Clone(); $unc.StateDirectory = '\\server\share\state'
Must-Fail { Invoke-GuardedBuild @unc -DryRun } 'UNC state rejected without contacting NAS'
$unsafe = $common.Clone(); $unsafe.Artifacts = @((Join-Path $repo 'AGENTS.md'))
Must-Fail { Invoke-GuardedBuild @unsafe -DryRun } 'source file cannot be an artifact'
New-Item -ItemType Directory -Path $state | Out-Null
$handle = [IO.File]::Open((Join-Path $state 'capacity.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
try { Must-Fail { Invoke-GuardedBuild @common } 'parallel run refused' } finally { $handle.Dispose() }
Check ($calls -eq 0) 'lock refusal does not invoke build'
$failing = $common.Clone(); $failing.BuildAction = { throw 'fixture failure, not a real build' }
Must-Fail { Invoke-GuardedBuild @failing } 'build failure propagated'
$failed = Get-Content -LiteralPath (Join-Path $state 'fixture.json') -Raw | ConvertFrom-Json
Check ($failed.status -eq 'failed' -and $failed.cleanupCandidates.Count -eq 0) 'failed manifest gives no cleanup approval'
$success = $common.Clone()
$artifact = Join-Path $build 'fixture.exe'
$success.Artifacts = @($artifact,$artifact)
$success.CleanupDirectories = @($build)
$success.BuildAction = { New-Item -ItemType Directory -Path $build -Force | Out-Null; [IO.File]::WriteAllBytes($artifact,[byte[]](1,2,3,4)) }.GetNewClosure()
Invoke-GuardedBuild @success | Out-Null
Invoke-GuardedBuild @success | Out-Null
$manifest = Get-Content -LiteralPath (Join-Path $state 'fixture.json') -Raw | ConvertFrom-Json
Check ($manifest.status -eq 'succeeded') 'locks released after failure'
Check ($manifest.retainedArtifacts.Count -eq 1) 'duplicate/repeated preservation stores one artifact'
Check ((Get-FileHash -LiteralPath $artifact).Hash -eq (Get-FileHash -LiteralPath $manifest.retainedArtifacts[0].path).Hash) 'preserved artifact verified'
Check ($manifest.cleanupExecuted -eq $false -and $manifest.cleanupCandidates[0].approvalRequired) 'cleanup report never authorizes deletion'
Check (!(($manifest | ConvertTo-Json -Depth 8) -match 'fixture failure|token|password|commandLine')) 'manifest excludes raw failure/credentials/command line'
$originalGradle = $env:GRADLE_USER_HOME
$cacheRun = $common.Clone(); $cacheRun.TaskId='cache-one'; $cacheRun.CacheDirectory=Join-Path $fixture 'cache-one'
$cacheRun.BuildAction={ if ($env:GRADLE_USER_HOME -ne (Join-Path $fixture 'cache-one')) { throw 'cache env not set' } }.GetNewClosure()
Invoke-GuardedBuild @cacheRun | Out-Null
Check ($env:GRADLE_USER_HOME -eq $originalGradle) 'cache environment restored'
$cross = $cacheRun.Clone(); $cross.TaskId='different-task'
Must-Fail { Invoke-GuardedBuild @cross } 'cross-task cache reuse not enabled'
$cacheTwo=$cacheRun.Clone(); $cacheTwo.TaskId='cache-two'; $cacheTwo.CacheDirectory=Join-Path $fixture 'cache-two'; $cacheTwo.BuildAction={}
Invoke-GuardedBuild @cacheTwo | Out-Null
$cacheThree=$cacheTwo.Clone(); $cacheThree.TaskId='cache-three'; $cacheThree.CacheDirectory=Join-Path $fixture 'cache-three'
Must-Fail { Invoke-GuardedBuild @cacheThree } 'dedicated cache slots bounded at two'
$changeCache=$cacheRun.Clone(); $changeCache.CacheDirectory=Join-Path $fixture 'another-cache'
Must-Fail { Invoke-GuardedBuild @changeCache } 'task cannot orphan its previous cache by switching paths'
$bounded=$success.Clone(); $bounded.StateDirectory=Join-Path $fixture 'bounded'; $bounded.TaskId='artifact-limit'
for ($i=0; $i -lt 8; $i++) {
    $value=[byte]$i
    $bounded.BuildAction={ New-Item -ItemType Directory -Path $build -Force | Out-Null; [IO.File]::WriteAllBytes($artifact,[byte[]]($value)) }.GetNewClosure()
    Invoke-GuardedBuild @bounded | Out-Null
}
$bounded.BuildAction={ [IO.File]::WriteAllBytes($artifact,[byte[]](99)) }.GetNewClosure()
Must-Fail { Invoke-GuardedBuild @bounded } 'ninth distinct artifact held without overwrite/delete'
$boundedManifest=Get-Content -LiteralPath (Join-Path $bounded.StateDirectory 'artifact-limit.json') -Raw | ConvertFrom-Json
Check ($boundedManifest.retainedArtifacts.Count -eq 8 -and $boundedManifest.status -eq 'failed') 'artifact limit retains all eight prior copies'
$capacity=$common.Clone(); $capacity.StateDirectory=Join-Path $fixture 'capacity'
New-Item -ItemType Directory -Path $capacity.StateDirectory | Out-Null
for ($i=0; $i -lt 64; $i++) { [IO.File]::WriteAllText((Join-Path $capacity.StateDirectory ("task-$i.json")),'{}') }
Must-Fail { Invoke-GuardedBuild @capacity } '65th task manifest held'
Check (!(Test-Path -LiteralPath (Join-Path $capacity.StateDirectory 'fixture.json'))) 'capacity refusal creates no extra manifest'
Must-Fail { Invoke-GuardedBuild @capacity -DryRun } 'DryRun applies manifest capacity'
Must-Fail { Invoke-GuardedBuild @cross -DryRun } 'DryRun applies cross-task cache restrictions'
$dropping=$common.Clone(); $dropping.StateDirectory=Join-Path $fixture 'dropping'
$counter=[pscustomobject]@{calls=0}
$dropping.FreeBytesProvider={param($root) $counter.calls++; if($counter.calls -eq 1){200e9}else{1e9} }.GetNewClosure()
Must-Fail { Invoke-GuardedBuild @dropping } 'free space rechecked after lock acquisition'
Check (!(Test-Path -LiteralPath (Join-Path $dropping.StateDirectory 'fixture.json'))) 'lock-time low space never starts a manifest/build'
$collision=$success.Clone(); $collision.StateDirectory=Join-Path $fixture 'collision'; $collision.TaskId='collision'
$digest=(Get-FileHash -LiteralPath $artifact).Hash.ToLowerInvariant()
$destination=Join-Path $collision.StateDirectory ('artifacts\collision\'+$digest+'-fixture.exe')
New-Item -ItemType Directory -Path ([IO.Path]::GetDirectoryName($destination)) -Force | Out-Null
[IO.File]::WriteAllBytes($destination,[byte[]](9))
$collision.BuildAction={}
Must-Fail { Invoke-GuardedBuild @collision } 'existing destination collision is not overwritten'
Check (([IO.File]::ReadAllBytes($destination))[0] -eq 9) 'collision file retained unchanged'
$partial=$success.Clone(); $partial.StateDirectory=Join-Path $fixture 'partial'; $partial.TaskId='partial'
$moduleUnderTest = Get-Module BuildGuard | Where-Object { $_.Path -eq (Join-Path $PSScriptRoot 'BuildGuard.psm1') }
& $moduleUnderTest {
    function script:Copy-GuardArtifact {
        param([string]$Source,[string]$Destination)
        [IO.File]::WriteAllBytes($Destination,[byte[]](1))
        throw 'injected partial copy failure'
    }
}
Must-Fail { Invoke-GuardedBuild @partial } 'partial copy failure propagated'
$partialManifest=Get-Content -LiteralPath (Join-Path $partial.StateDirectory 'partial.json') -Raw | ConvertFrom-Json
Check ($partialManifest.retainedArtifacts.Count -eq 1 -and $partialManifest.retainedArtifacts[0].status -eq 'pending') 'partial copy consumes a recorded artifact slot'
Import-Module (Join-Path $PSScriptRoot 'BuildGuard.psm1') -Force
Must-Fail { Invoke-GuardedBuild @partial -DryRun } 'partial copy requires owner review before retry'
$linked=$common.Clone(); $linked.StateDirectory=Join-Path $fixture 'linked-state'
New-Item -ItemType Junction -Path $linked.StateDirectory -Target $state | Out-Null
Must-Fail { Invoke-GuardedBuild @linked -DryRun } 'junction state rejected'
$linkedRecord=$common.Clone(); $linkedRecord.StateDirectory=Join-Path $fixture 'linked-record'
New-Item -ItemType Directory -Path $linkedRecord.StateDirectory | Out-Null
New-Item -ItemType Junction -Path (Join-Path $linkedRecord.StateDirectory 'unsafe.json') -Target $state | Out-Null
Must-Fail { Invoke-GuardedBuild @linkedRecord -DryRun } 'reparse manifest entry rejected before reading'
$restoreFailure=$common.Clone(); $restoreFailure.StateDirectory=Join-Path $fixture 'restore-failure'; $restoreFailure.BuildAction={}
$startingLocation=(Get-Location).Path
$moduleUnderTest=Get-Module BuildGuard | Where-Object { $_.Path -eq (Join-Path $PSScriptRoot 'BuildGuard.psm1') }
& $moduleUnderTest {
    param($starting)
    $script:failRestore=$starting
    function script:Set-Location {
        param($LiteralPath)
        if ([string]$LiteralPath -eq $script:failRestore) { throw 'injected location restoration failure' }
        Microsoft.PowerShell.Management\Set-Location -LiteralPath $LiteralPath
    }
} $startingLocation
Must-Fail { Invoke-GuardedBuild @restoreFailure } 'location restoration failure propagated'
Import-Module (Join-Path $PSScriptRoot 'BuildGuard.psm1') -Force
Microsoft.PowerShell.Management\Set-Location -LiteralPath $startingLocation
Invoke-GuardedBuild @restoreFailure | Out-Null
Check ($true) 'locks released even when location restoration fails'
# Regression tests for the owner-required 60 GiB floor, even on existing tasks.
$floor = [long](60 * 1GB)
$existingLow = $common.Clone(); $existingLow.ReasonCode='ExistingTask'; $existingLow.NewHeavyIsolated=$false; $existingLow.ExpectedPeakGB=0; $existingLow.ReserveGB=0
$existingLow.FreeBytesProvider={param($root) 59e9}
Must-Fail { Invoke-GuardedBuild @existingLow -DryRun } 'existing tasks cannot bypass low-space floor'
$existingLow.FreeBytesProvider={param($root) 60e9}
Must-Fail { Invoke-GuardedBuild @existingLow -DryRun } '60 decimal GB is below 60 GiB'
$boundary=$existingLow.Clone(); $boundary.FreeBytesProvider={param($root) $floor}.GetNewClosure()
$boundaryPlan=Invoke-GuardedBuild @boundary -DryRun
Check ($boundaryPlan.space[0].projectedRemainingBytes -eq $floor) 'exact 60 GiB boundary allowed with zero declared consumption'
$below=$boundary.Clone(); $below.FreeBytesProvider={param($root) ($floor-1)}.GetNewClosure()
Must-Fail { Invoke-GuardedBuild @below -DryRun } 'one byte below fixed floor held'
$projected=$boundary.Clone(); $projected.ExpectedPeakGB=5; $projected.FreeBytesProvider={param($root) ($floor+5e9-1)}.GetNewClosure()
Must-Fail { Invoke-GuardedBuild @projected -DryRun } 'peak consumption cannot cross fixed floor'
$projected.FreeBytesProvider={param($root) ($floor+5e9)}.GetNewClosure()
$projectedPlan=Invoke-GuardedBuild @projected -DryRun
Check ($projectedPlan.space[0].projectedRemainingBytes -eq $floor) 'peak budget preserves floor at exact boundary'
$parallel=$projected.Clone(); $parallel.ConcurrentPeakGB=0.1
Must-Fail { Invoke-GuardedBuild @parallel -DryRun } 'declared parallel growth prevents oversubscription'
$parallel=$common.Clone(); $parallel.ConcurrentPeakGB=8
$parallelPlan=Invoke-GuardedBuild @parallel -DryRun
Check ($parallelPlan.budget.concurrentPeakGB -eq 8 -and $parallelPlan.budget.minimumRemainingGiB -eq 60) 'DryRun records declared parallel budget and fixed floor'
$highReserve=$boundary.Clone(); $highReserve.ReserveGB=70
Must-Fail { Invoke-GuardedBuild @highReserve -DryRun } 'reserve larger than floor remains enforced'
$post=$common.Clone(); $post.StateDirectory=Join-Path $fixture 'post-build-low'
$postCounter=[pscustomobject]@{calls=0}
$post.FreeBytesProvider={param($root) $postCounter.calls++; if($postCounter.calls -le 2){200e9}else{$floor-1}}.GetNewClosure()
Must-Fail { Invoke-GuardedBuild @post } 'unexpected consumption after build cannot claim success'
$postManifest=Get-Content -LiteralPath (Join-Path $post.StateDirectory 'fixture.json') -Raw | ConvertFrom-Json
Check ($postManifest.status -eq 'failed' -and $postManifest.cleanupCandidates.Count -eq 0) 'post-build low space preserves evidence without cleanup candidates'
Check ($postManifest.spaceAfterBuild[0].freeBytes -eq ($floor-1)) 'failed post-build measurement remains in audit manifest'
$copyLow=$success.Clone(); $copyLow.StateDirectory=Join-Path $fixture 'copy-low'
$copyCounter=[pscustomobject]@{calls=0}
$copyLow.FreeBytesProvider={param($root) $copyCounter.calls++; if($copyCounter.calls -le 3){200e9}else{$floor+1}}.GetNewClosure()
Must-Fail { Invoke-GuardedBuild @copyLow } 'artifact preservation cannot cross fixed floor'
$copyManifest=Get-Content -LiteralPath (Join-Path $copyLow.StateDirectory 'fixture.json') -Raw | ConvertFrom-Json
Check ($copyManifest.status -eq 'failed' -and $copyManifest.retainedArtifacts.Count -eq 0 -and (Get-Item -LiteralPath $artifact).Length -eq 4) 'copy refusal preserves original and creates no partial reservation'
Check ($manifest.budget.minimumRemainingGiB -eq 60 -and $manifest.retentionPolicy -eq 'owner-review-no-auto-delete') 'manifest persists floor and non-deleting retention policy'
Check ($manifest.cleanupCandidates[0].category -eq 'regenerable-build-output' -and $manifest.cleanupCandidates[0].approvalRequired) 'classified candidates still require explicit approval'
$finalLow=$success.Clone(); $finalLow.StateDirectory=Join-Path $fixture 'final-low'
$finalCounter=[pscustomobject]@{calls=0}
$finalLow.FreeBytesProvider={param($root) $finalCounter.calls++; if($finalCounter.calls -le 4){200e9}else{$floor-1}}.GetNewClosure()
Must-Fail { Invoke-GuardedBuild @finalLow } 'last preservation phase cannot claim success below floor'
$finalManifest=Get-Content -LiteralPath (Join-Path $finalLow.StateDirectory 'fixture.json') -Raw | ConvertFrom-Json
Check ($finalManifest.status -eq 'failed' -and $finalManifest.cleanupCandidates.Count -eq 0 -and $finalManifest.retainedArtifacts[0].status -eq 'verified') 'final low-space failure preserves already verified artifact and withholds cleanup candidates'
Check ($finalManifest.spaceAfterPreservation[0].freeBytes -eq ($floor-1)) 'failed final measurement recorded for owner audit'
# Fixture files intentionally remain for inspection; no deletion routine is part of this test.
Write-Output "PASS $passed checks; fixture: $fixture; generated output: $build"
