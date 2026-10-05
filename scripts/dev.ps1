$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$env:PAGEFORGE_PROJECT_ROOT = $projectRoot
New-Item -ItemType Directory -Path (Join-Path $projectRoot 'bin') -Force | Out-Null
Push-Location (Join-Path $projectRoot 'backend')
try {
    & go build -o (Join-Path $projectRoot 'bin\pageforge-backend.exe') ./cmd/pageforge
    if ($LASTEXITCODE -ne 0) { throw 'Go build failed' }
} finally { Pop-Location }
Push-Location (Join-Path $projectRoot 'apps\desktop')
try {
    $cmakeCache = Join-Path (Get-Location).Path 'build\windows\x64\CMakeCache.txt'
    if (Test-Path -LiteralPath $cmakeCache) {
        $cachedSource = Select-String -LiteralPath $cmakeCache -Pattern '^CMAKE_HOME_DIRECTORY:INTERNAL=' | Select-Object -First 1
        $expectedSource = (Join-Path (Get-Location).Path 'windows').Replace('\', '/')
        if ($cachedSource -and $cachedSource.Line.Split('=', 2)[1] -ne $expectedSource) {
            & flutter clean
            if ($pubExit -ne 0) { throw 'Flutter clean failed after project relocation' }
            $ErrorActionPreference = 'Continue'
            & flutter pub get 2>&1 | Tee-Object -Variable pubOutput
            $pubExit = $LASTEXITCODE
            $ErrorActionPreference = 'Stop'
            if ($pubExit -ne 0) {
                if (($pubOutput -join "`n") -notmatch 'Building with plugins requires symlink support') { throw 'Flutter dependencies failed' }
                & (Join-Path $PSScriptRoot 'plugins.ps1')
            }
        }
    }
    & (Join-Path $PSScriptRoot 'plugins.ps1')
    $ErrorActionPreference = 'Continue'
    & flutter run -d windows --no-pub 2>&1 | Tee-Object -Variable runOutput
    $runExit = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'
    if ($runExit -ne 0) {
        if (($runOutput -join "`n") -notmatch 'Building with plugins requires symlink support') { throw 'Flutter run failed' }
        & (Join-Path $PSScriptRoot 'plugins.ps1')
        & flutter run -d windows --no-pub
        if ($LASTEXITCODE -ne 0) { throw 'Flutter run failed after plugin links were refreshed' }
    }
}
finally { Pop-Location }
