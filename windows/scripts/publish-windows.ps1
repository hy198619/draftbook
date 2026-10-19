param(
    [ValidateSet("win-x64", "win-arm64")]
    [string]$Runtime = "win-x64",
    [string]$Configuration = "Release"
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$output = Join-Path $root "artifacts/$Runtime"
$projectPath = Join-Path $root "src/DraftBook.Windows/DraftBook.Windows.csproj"
[xml]$project = Get-Content $projectPath
$version = [string]$project.Project.PropertyGroup.Version
$archiveName = "DraftBook-Windows-$version-$Runtime.zip"
$archive = Join-Path $root "artifacts/$archiveName"

dotnet test (Join-Path $root "tests/DraftBook.Core.Tests/DraftBook.Core.Tests.csproj") -c $Configuration
dotnet publish $projectPath `
    -c $Configuration -r $Runtime --self-contained true `
    -p:PublishSingleFile=true -p:DebugType=None -p:DebugSymbols=false -o $output

if (Test-Path $archive) { Remove-Item $archive }
Compress-Archive -Path (Join-Path $output "*") -DestinationPath $archive
$hash = (Get-FileHash $archive -Algorithm SHA256).Hash.ToLowerInvariant()
Set-Content -Path "$archive.sha256" -Value "$hash  $archiveName" -Encoding ascii
Write-Host "Created $archive"
