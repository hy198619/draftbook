using System.Threading;
using System.Windows;

namespace DraftBook.Windows;

public partial class App : Application
{
    private Mutex? singleInstance;
    private bool ownsSingleInstance;

    protected override void OnStartup(StartupEventArgs e)
    {
        singleInstance = new Mutex(true, "Local\\DraftBook.Windows", out var isFirstInstance);
        ownsSingleInstance = isFirstInstance;
        if (!isFirstInstance)
        {
            MessageBox.Show("草稿本已经在运行。", "草稿本", MessageBoxButton.OK, MessageBoxImage.Information);
            Shutdown();
            return;
        }

        DispatcherUnhandledException += (_, args) =>
        {
            MessageBox.Show($"程序遇到未处理错误：\n{args.Exception.Message}", "草稿本",
                MessageBoxButton.OK, MessageBoxImage.Error);
            args.Handled = true;
            Shutdown(-1);
        };
        base.OnStartup(e);
    }

    protected override void OnExit(ExitEventArgs e)
    {
        if (ownsSingleInstance)
        {
            singleInstance?.ReleaseMutex();
        }
        singleInstance?.Dispose();
        base.OnExit(e);
    }
}
