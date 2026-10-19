using Velopack;
using Velopack.Locators;
using Velopack.Sources;

if (args.Length != 4)
{
    throw new ArgumentException("Expected feed directory, package directory, channel, and target version.");
}

var feedDirectory = Path.GetFullPath(args[0]);
var packageDirectory = Path.GetFullPath(args[1]);
var channel = args[2];
var targetVersion = args[3];

if (Directory.Exists(packageDirectory))
{
    Directory.Delete(packageDirectory, recursive: true);
}
Directory.CreateDirectory(packageDirectory);

var locator = new TestVelopackLocator(
    appId: "com.yangyuxuan.DraftBook",
    version: "0.0.1",
    packagesDir: packageDirectory);
var options = new UpdateOptions { ExplicitChannel = channel };
var manager = new UpdateManager(new SimpleFileSource(new DirectoryInfo(feedDirectory)), options, locator);
var update = await manager.CheckForUpdatesAsync()
    ?? throw new InvalidOperationException($"Expected update {targetVersion} in {channel}.");

if (!string.Equals(update.TargetFullRelease.Version.ToString(), targetVersion, StringComparison.Ordinal))
{
    throw new InvalidOperationException(
        $"Expected update {targetVersion}, found {update.TargetFullRelease.Version} in {channel}.");
}

await manager.DownloadUpdatesAsync(update);
var downloadedPackages = Directory.GetFiles(packageDirectory, "*.nupkg", SearchOption.AllDirectories);
if (downloadedPackages.Length != 1)
{
    throw new InvalidOperationException(
        $"Expected one verified package for {channel}, found {downloadedPackages.Length}.");
}

Console.WriteLine($"Verified {channel} update {targetVersion}: {Path.GetFileName(downloadedPackages[0])}");
