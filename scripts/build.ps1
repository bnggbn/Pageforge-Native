param([switch]$RunChecks)
$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$appDirectory = Join-Path $projectRoot 'apps\desktop'
New-Item -ItemType Directory -Path (Join-Path $projectRoot 'bin') -Force | Out-Null
Push-Location (Join-Path $projectRoot 'backend')
try {
    if ($RunChecks) {
        & go test ./...
        if ($LASTEXITCODE -ne 0) { throw 'Go tests failed' }
        & go vet ./...
        if ($LASTEXITCODE -ne 0) { throw 'Go vet failed' }
    }
    & go build -trimpath -o (Join-Path $projectRoot 'bin\pageforge-backend.exe') ./cmd/pageforge
    if ($LASTEXITCODE -ne 0) { throw 'Go build failed' }
} finally { Pop-Location }
Push-Location $appDirectory
try {
    $cmakeCache = Join-Path $appDirectory 'build\windows\x64\CMakeCache.txt'
    if (Test-Path -LiteralPath $cmakeCache) {
        $cachedSource = Select-String -LiteralPath $cmakeCache -Pattern '^CMAKE_HOME_DIRECTORY:INTERNAL=' | Select-Object -First 1
        $expectedSource = (Join-Path $appDirectory 'windows').Replace('\', '/')
        if ($cachedSource -and $cachedSource.Line.Split('=', 2)[1] -ne $expectedSource) {
            & flutter clean
            if ($LASTEXITCODE -ne 0) { throw 'Flutter clean failed after project relocation' }
        }
    }
    $pubPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        & flutter pub get 2>&1 | Tee-Object -Variable pubOutput
        $pubExit = $LASTEXITCODE
    } finally { $ErrorActionPreference = $pubPreference }
    if ($pubExit -ne 0) {
        if (($pubOutput -join "`n") -notmatch 'Building with plugins requires symlink support') { throw 'Flutter dependencies failed' }
        & (Join-Path $PSScriptRoot 'plugins.ps1')
    }
    if ($RunChecks) {
        & flutter analyze --no-pub
        if ($LASTEXITCODE -ne 0) { throw 'Flutter analysis failed' }
        & flutter test --no-pub
        if ($LASTEXITCODE -ne 0) { throw 'Flutter tests failed' }
    }
    & (Join-Path $PSScriptRoot 'plugins.ps1')
    $buildPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        & flutter build windows --release --no-pub 2>&1 | Tee-Object -Variable windowsOutput
        $windowsExit = $LASTEXITCODE
    } finally { $ErrorActionPreference = $buildPreference }
    if ($windowsExit -ne 0) {
        if (($windowsOutput -join "`n") -notmatch 'Building with plugins requires symlink support') { throw 'Windows build failed' }
        & (Join-Path $PSScriptRoot 'plugins.ps1')
        & flutter build windows --release --no-pub
        if ($LASTEXITCODE -ne 0) { throw 'Windows build failed after plugin links were refreshed' }
    }
} finally { Pop-Location }
$release = Join-Path $appDirectory 'build\windows\x64\runner\Release'
Copy-Item -LiteralPath (Join-Path $projectRoot 'bin\pageforge-backend.exe') -Destination $release
Copy-Item -LiteralPath (Join-Path $projectRoot 'pageforge.config.json') -Destination $release
Copy-Item -LiteralPath (Join-Path $projectRoot 'pageforge.design.json') -Destination $release
Write-Host "Built: $release\pageforge.exe"
