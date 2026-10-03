# Exercise the public wrapper with a failing fake tool; never build the application.
$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$fixture = Join-Path $env:TEMP ('build-wrapper-test-' + [Guid]::NewGuid().ToString('N'))
$bin = Join-Path $fixture 'bin'
New-Item -ItemType Directory -Path $bin -Force | Out-Null
$oldPath = $env:PATH
$oldTarget = $env:CARGO_TARGET_DIR
$oldBuild = $env:CARGO_BUILD_BUILD_DIR
$oldGradle = $env:GRADLE_USER_HOME
$wrapper = Join-Path $repo 'apps\desktop\scripts\Invoke-LocalBuild.ps1'
$parameters = @{TaskId='native-failure';ReasonCode='ExistingTask';StateDirectory=(Join-Path $fixture 'state');ExpectedPeakGB=0;ReserveGB=0}
try {
    if (Test-Path -LiteralPath $wrapper) {
        [IO.File]::WriteAllText((Join-Path $bin 'npm.cmd'),"@exit /b 7`r`n",[Text.Encoding]::ASCII)
        $env:CARGO_TARGET_DIR = $null; $env:CARGO_BUILD_BUILD_DIR = $null
    } else {
        $wrapper = Join-Path $PSScriptRoot 'Invoke-WindowsAndroidBuild.ps1'
        [IO.File]::WriteAllText((Join-Path $bin 'flutter.bat'),"@exit /b 7`r`n",[Text.Encoding]::ASCII)
        $parameters.ExpectedCommit = (& git -C $repo rev-parse HEAD).Trim()
        $parameters.GradleUserHome = Join-Path $fixture 'gradle-home'
    }
    $env:PATH = $bin + ';' + $oldPath
    $plan = & $wrapper @parameters -DryRun
    if ($plan.status -ne 'dry-run' -or (Test-Path -LiteralPath $parameters.StateDirectory)) { throw 'Wrapper DryRun wrote state.' }
    $failed = $false
    try { & $wrapper @parameters | Out-Null } catch { $failed = $true }
    if (!$failed) { throw 'Native nonzero exit was ignored.' }
    $manifest = Get-Content -LiteralPath (Join-Path $parameters.StateDirectory 'native-failure.json') -Raw | ConvertFrom-Json
    if ($manifest.status -ne 'failed' -or $manifest.cleanupCandidates.Count -ne 0) { throw 'Native failure did not produce a failed manifest.' }
} finally {
    $env:PATH = $oldPath; $env:CARGO_TARGET_DIR = $oldTarget; $env:CARGO_BUILD_BUILD_DIR = $oldBuild
}
if ($env:GRADLE_USER_HOME -ne $oldGradle) { throw 'Gradle environment leaked.' }
Write-Output "PASS public wrapper DryRun/native failure/environment restoration; fixture: $fixture"
