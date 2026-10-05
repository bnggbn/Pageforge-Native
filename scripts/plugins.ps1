$ErrorActionPreference = 'Stop'
$appDirectory = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\apps\desktop'))
$metadata = Get-Content -LiteralPath (Join-Path $appDirectory '.flutter-plugins-dependencies') -Raw | ConvertFrom-Json
$linkDirectory = Join-Path $appDirectory 'windows\flutter\ephemeral\.plugin_symlinks'
New-Item -ItemType Directory -Path $linkDirectory -Force | Out-Null
foreach ($plugin in $metadata.plugins.windows) {
    $linkPath = Join-Path $linkDirectory $plugin.name
    $resolvedLink = [IO.Path]::GetFullPath($linkPath)
    if (-not $resolvedLink.StartsWith($linkDirectory + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'Invalid plugin link path' }
    if (-not (Test-Path -LiteralPath $linkPath)) {
        New-Item -ItemType Junction -Path $linkPath -Target $plugin.path | Out-Null
    }
}
