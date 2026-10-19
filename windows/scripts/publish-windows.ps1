param(
    [ValidateSet("win-x64", "win-arm64")]
    [string]$Runtime = "win-x64",
    [string]$Configuration = "Release",
    [switch]$KeepExistingReleases,
    [switch]$SkipTests
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$projectPath = Join-Path $root "src/DraftBook.Windows/DraftBook.Windows.csproj"
$testProjectPath = Join-Path $root "tests/DraftBook.Core.Tests/DraftBook.Core.Tests.csproj"
$updateSmokeProjectPath = Join-Path $root "tests/DraftBook.UpdateSmoke/DraftBook.UpdateSmoke.csproj"
$publishDirectory = Join-Path $root "artifacts/publish/$Runtime"
$releaseDirectory = Join-Path $root "artifacts/releases/$Runtime"
$iconPath = Join-Path $root "src/DraftBook.Windows/Assets/DraftBook.ico"
$releaseNotesPath = Join-Path $root "installer/RELEASE_NOTES.md"

$architecture = if ($Runtime -eq "win-arm64") { "arm64" } else { "x64" }
$channel = "win-$architecture-beta"
$velopackRuntime = "win10-$architecture"
$version = (dotnet msbuild $projectPath -getProperty:Version).Trim()
$friendlySetupName = "DraftBook-v$version-Windows-$architecture-Setup.exe"

dotnet tool restore --tool-manifest (Join-Path $root ".config/dotnet-tools.json")
if (-not $SkipTests) { dotnet test $testProjectPath -c $Configuration }

if (Test-Path $publishDirectory) { Remove-Item $publishDirectory -Recurse -Force }
if ((-not $KeepExistingReleases) -and (Test-Path $releaseDirectory)) {
    Remove-Item $releaseDirectory -Recurse -Force
}

dotnet publish $projectPath `
    -c $Configuration -r $Runtime --self-contained true `
    -p:PublishSingleFile=true -p:DebugType=None -p:DebugSymbols=false `
    -o $publishDirectory

$publishedExe = Join-Path $publishDirectory "DraftBook.exe"
if (-not (Test-Path $publishedExe)) { throw "DraftBook.exe was not published for $Runtime" }

dotnet tool run vpk -- `
    pack `
    --outputDir $releaseDirectory `
    --channel $channel `
    --runtime $velopackRuntime `
    --packId com.yangyuxuan.DraftBook `
    --packVersion $version `
    --packDir $publishDirectory `
    --packAuthors "杨昱轩" `
    --packTitle "DraftBook 草稿本" `
    --releaseNotes $releaseNotesPath `
    --icon $iconPath `
    --mainExe DraftBook.exe `
    --shortcuts Desktop,StartMenuRoot `
    --splashProgressColor "#E85C4A" `
    --noPortable

$generatedSetupPath = Join-Path $releaseDirectory "com.yangyuxuan.DraftBook-$channel-Setup.exe"
if (-not (Test-Path $generatedSetupPath)) { throw "Missing generated installer: $generatedSetupPath" }
Copy-Item $generatedSetupPath (Join-Path $releaseDirectory $friendlySetupName) -Force
$setupPath = Join-Path $releaseDirectory $friendlySetupName
$hash = (Get-FileHash $setupPath -Algorithm SHA256).Hash.ToLowerInvariant()
Set-Content -Path "$setupPath.sha256" -Value "$hash  $friendlySetupName" -Encoding ascii

$feedPath = Join-Path $releaseDirectory "releases.$channel.json"
$fullPackages = @(Get-ChildItem $releaseDirectory -Filter "*-$version-$channel-full.nupkg" -File)
if ($fullPackages.Count -ne 1) { throw "Expected one full update package for $version, found $($fullPackages.Count)" }
$fullPackage = $fullPackages[0]
if (-not (Test-Path $feedPath)) { throw "Missing Velopack feed: $feedPath" }
if (-not (Test-Path $setupPath)) { throw "Missing installer: $setupPath" }
if (-not $fullPackage) { throw "Missing full update package" }

$smokePackageDirectory = Join-Path $root "artifacts/update-smoke/$Runtime"
dotnet run --project $updateSmokeProjectPath -c $Configuration -- `
    $releaseDirectory $smokePackageDirectory $channel $version

Write-Host "Created installer: $setupPath"
Write-Host "Created update feed: $feedPath"
Write-Host "Created update package: $($fullPackage.FullName)"
