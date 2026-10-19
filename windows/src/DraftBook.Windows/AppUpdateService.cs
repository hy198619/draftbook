using System.Reflection;
using Velopack;
using Velopack.Sources;

namespace DraftBook.Windows;

internal sealed class AppUpdateService
{
    internal const string RepositoryUrl = "https://github.com/hy198619/draftbook";
    internal const string ReleasesUrl = RepositoryUrl + "/releases";

    private readonly UpdateManager manager;

    public AppUpdateService()
    {
        var source = new GithubSource(RepositoryUrl, accessToken: null, prerelease: true);
        manager = new UpdateManager(source);
    }

    public bool CanUpdate => manager.IsInstalled && !manager.IsPortable;

    public string CurrentVersion => manager.CurrentVersion?.ToString() ?? AssemblyVersion();

    public Task<UpdateInfo?> CheckAsync() => manager.CheckForUpdatesAsync();

    public Task DownloadAsync(UpdateInfo update, Action<int> progress, CancellationToken cancellationToken = default) =>
        manager.DownloadUpdatesAsync(update, progress, cancellationToken);

    public void ApplyAndRestart(UpdateInfo update) =>
        manager.ApplyUpdatesAndRestart(update.TargetFullRelease);

    private static string AssemblyVersion()
    {
        var informational = Assembly.GetExecutingAssembly()
            .GetCustomAttribute<AssemblyInformationalVersionAttribute>()?
            .InformationalVersion;
        return string.IsNullOrWhiteSpace(informational)
            ? "0.9.6-preview.2"
            : informational.Split('+', 2)[0];
    }
}
