param(
    [string]$GoPath = 'go',
    [string]$FlutterPath = 'flutter',
    [int[]]$UICharacters = @(100000, 1000000),
    [ValidateSet('editor', 'plain', 'markdown')]
    [string[]]$Views = @('editor', 'plain', 'markdown'),
    [switch]$SkipBackend,
    [switch]$SkipUI
)
$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$reportRoot = Join-Path $projectRoot ('.preview\large-document-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
foreach ($count in $UICharacters) {
    if ($count -lt 1000 -or $count -gt 5000000) { throw 'UICharacters must be between 1000 and 5000000' }
}
New-Item -ItemType Directory -Path $reportRoot | Out-Null
$metadata = @{
    timestamp = (Get-Date).ToString('o')
    os = [Environment]::OSVersion.VersionString
    processors = [Environment]::ProcessorCount
    uiCharacters = $UICharacters
    views = $Views
}
Push-Location $projectRoot
try {
    $metadata.commit = (& git rev-parse HEAD)
    $metadata.branch = (& git branch --show-current)
    $metadata | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $reportRoot 'environment.json') -Encoding UTF8
} finally { Pop-Location }

# Serial execution avoids backend/UI probes competing with one another.
if (-not $SkipBackend) {
    $previousProbe = [Environment]::GetEnvironmentVariable('PAGEFORGE_LONG_DOCUMENT_PROBE', 'Process')
    Push-Location (Join-Path $projectRoot 'backend')
    try {
        $env:PAGEFORGE_LONG_DOCUMENT_PROBE = '1'
        & $GoPath test ./internal/api -run '^TestLargeDocumentProbe$' -count=1 -timeout=5m -v 2>&1 |
            Tee-Object -FilePath (Join-Path $reportRoot 'backend.log')
        if ($LASTEXITCODE -ne 0) { throw 'Backend probe failed; inspect backend.log' }
    } finally {
        [Environment]::SetEnvironmentVariable('PAGEFORGE_LONG_DOCUMENT_PROBE', $previousProbe, 'Process')
        Pop-Location
    }
}
if (-not $SkipUI) {
    Push-Location (Join-Path $projectRoot 'apps\desktop')
    try {
        foreach ($count in $UICharacters) {
            foreach ($view in $Views) {
                & $FlutterPath test --no-pub test/large_document_probe_test.dart --reporter=expanded `
                    --dart-define=PAGEFORGE_LONG_DOCUMENT_PROBE=true `
                    "--dart-define=PAGEFORGE_PROBE_CHARACTERS=$count" `
                    "--dart-define=PAGEFORGE_PROBE_VIEW=$view" 2>&1 |
                    Tee-Object -FilePath (Join-Path $reportRoot "ui-$view-$count.log")
                if ($LASTEXITCODE -ne 0) { throw "UI probe failed: $view / $count; inspect its log" }
            }
        }
    } finally { Pop-Location }
}
Write-Host "Probe reports: $reportRoot"
