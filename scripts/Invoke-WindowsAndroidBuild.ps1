[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$TaskId,
    [Parameter(Mandatory=$true)][ValidateSet('ExistingTask','NewTask','IsolatedValidation','Recovery')][string]$ReasonCode,
    [Parameter(Mandatory=$true)][string]$StateDirectory,
    [Parameter(Mandatory=$true)][string]$GradleUserHome,
    [Parameter(Mandatory=$true)][ValidatePattern('^[a-f0-9]{40}$')][string]$ExpectedCommit,
    [ValidateRange(0,10000)][double]$ExpectedPeakGB = 8,
    [ValidateRange(0,10000)][double]$ReserveGB = 30,
    [switch]$DryRun
)
$ErrorActionPreference = 'Stop'
$repository = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if ($repository -notmatch '^[A-Za-z]:\\[\x20-\x7E]+$') { throw 'Use an ASCII-path build checkout; do not create a copy of uncommitted source.' }
$head = @(& git -C $repository rev-parse --verify HEAD)
if ($LASTEXITCODE -ne 0 -or $head.Count -ne 1 -or $head[0] -ne $ExpectedCommit) { throw 'Build checkout HEAD does not match the approved commit.' }
$dirty = @(& git -C $repository status --porcelain --untracked-files=all)
if ($LASTEXITCODE -ne 0 -or $dirty.Count) { throw 'Commit changes before building an Android candidate.' }
Import-Module (Join-Path $PSScriptRoot 'BuildGuard.psm1') -Force
# This first stage never selects or enables a shared cache automatically.
$build = Join-Path $repository 'build'
$action = {
    flutter.bat build apk --debug --target-platform android-arm64
    if ($LASTEXITCODE -ne 0) { throw 'Flutter Android build failed.' }
}.GetNewClosure()
Invoke-GuardedBuild -Repository $repository -BuildDirectory $build -StateDirectory $StateDirectory -CacheDirectory $GradleUserHome -TaskId $TaskId -ReasonCode $ReasonCode -BuildAction $action -Artifacts @(Join-Path $build 'app\outputs\flutter-apk\app-debug.apk') -CleanupDirectories @($build) -ExpectedPeakGB $ExpectedPeakGB -ReserveGB $ReserveGB -NewHeavyIsolated:($ReasonCode -ne 'ExistingTask') -DryRun:$DryRun
