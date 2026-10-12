using System.ComponentModel;
using System.IO;
using System.Text;
using System.Windows;
using System.Windows.Controls;
using DraftBook.Core;
using Microsoft.Win32;

namespace DraftBook.Windows;

public partial class MainWindow : Window
{
    private readonly string dataDirectory;
    private readonly AppSettingsStore settingsStore;
    private readonly AppSettings settings;
    private readonly DraftRepository repository;
    private readonly DraftBookState state;
    private readonly AutoSaveCoordinator? autoSave;
    private bool closingCompleted;
    private bool initializing = true;

    public MainWindow()
    {
        InitializeComponent();
        dataDirectory = DraftRepository.DefaultDataDirectory();
        settingsStore = new AppSettingsStore(dataDirectory);
        settings = settingsStore.Load();
        repository = new DraftRepository(new DraftRepositoryOptions(
            dataDirectory, settings.AutomaticBackupsEnabled, settings.BackupRetentionCount));

        DraftLoadResult load;
        string? fatalLoadError = null;
        try
        {
            load = repository.Load();
        }
        catch (DraftBookDataException exception)
        {
            load = new DraftLoadResult(new DraftBookSnapshot { SchemaVersion = DraftBookSnapshot.CurrentSchemaVersion });
            fatalLoadError = $"无法读取本地草稿。为防止空白数据覆盖原文件，程序将退出，且不会写入草稿文件。\n\n{exception.Message}\n\n数据目录：{dataDirectory}";
        }

        state = new DraftBookState(load.Snapshot, settings.DefaultReviewDays);
        if (fatalLoadError is null)
        {
            autoSave = new AutoSaveCoordinator(state, repository);
            autoSave.SaveErrorChanged += (_, error) => Dispatcher.BeginInvoke(() =>
                StatusText.Text = error ?? $"已保存 {DateTime.Now:HH:mm:ss}");
        }

        Width = settings.WindowWidth;
        Height = settings.WindowHeight;
        Topmost = settings.Topmost;
        ComposerBox.Text = state.Composer;
        PopulateColorFilter();
        RefreshDrafts();
        initializing = false;
        Loaded += (_, _) =>
        {
            if (fatalLoadError is not null)
            {
                MessageBox.Show(this, fatalLoadError, "草稿读取失败", MessageBoxButton.OK, MessageBoxImage.Error);
                closingCompleted = true;
                Close();
                return;
            }
            ComposerBox.Focus();
            if (load.Warning is not null)
            {
                MessageBox.Show(this, load.Warning, "已恢复备份", MessageBoxButton.OK, MessageBoxImage.Warning);
            }
        };
        Closing += OnClosing;
    }

    private string CurrentSection => (SectionPicker.SelectedItem as ComboBoxItem)?.Tag as string ?? "active";

    private DraftColor? CurrentColor => (ColorPicker.SelectedItem as ComboBoxItem)?.Tag as DraftColor?;

    private void PopulateColorFilter()
    {
        ColorPicker.Items.Clear();
        ColorPicker.Items.Add(new ComboBoxItem { Content = "全部分类", IsSelected = true });
        foreach (var color in Enum.GetValues<DraftColor>())
        {
            ColorPicker.Items.Add(new ComboBoxItem { Content = state.LabelName(color), Tag = color });
        }
    }

    private void RefreshDrafts()
    {
        if (DraftPanel is null)
        {
            return;
        }
        var section = CurrentSection;
        var query = SearchBox?.Text ?? string.Empty;
        var color = ColorPicker is null ? null : CurrentColor;
        IReadOnlyList<Draft> drafts = section switch
        {
            "due" => state.DueDrafts(DateTimeOffset.Now, query, color),
            "archived" => state.Drafts(DraftState.Archived, query, color),
            "trash" => state.Drafts(DraftState.Trash, query, color),
            _ => state.Drafts(DraftState.Active, query, color),
        };

        DraftPanel.Children.Clear();
        foreach (var draft in drafts)
        {
            DraftPanel.Children.Add(new DraftCard(state, draft, section, RefreshDrafts));
        }
        if (drafts.Count == 0)
        {
            DraftPanel.Children.Add(new TextBlock
            {
                Text = section == "due" ? "目前没有待处理草稿。" : "这里还是空的。",
                Foreground = System.Windows.Media.Brushes.Gray,
                Margin = new Thickness(8, 24, 8, 8),
                HorizontalAlignment = HorizontalAlignment.Center,
            });
        }
        StatusText.Text = $"共 {drafts.Count} 条";
    }

    private void Composer_TextChanged(object sender, TextChangedEventArgs e)
    {
        if (!initializing)
        {
            state.Composer = ComposerBox.Text;
        }
    }

    private void Composer_CommitRequested(object? sender, EventArgs e) => SealComposer();

    private void Seal_Click(object sender, RoutedEventArgs e) => SealComposer();

    private void SealComposer()
    {
        state.Composer = ComposerBox.Text;
        if (state.SealComposer(DateTimeOffset.Now) is null)
        {
            return;
        }
        initializing = true;
        ComposerBox.Clear();
        initializing = false;
        RefreshDrafts();
        ComposerBox.Focus();
    }

    private void Filter_Changed(object sender, EventArgs e)
    {
        if (!initializing)
        {
            RefreshDrafts();
        }
    }

    private void Settings_Click(object sender, RoutedEventArgs e)
    {
        var dialog = new SettingsDialog(settings, state) { Owner = this };
        if (dialog.ShowDialog() != true)
        {
            return;
        }
        settings.Normalize();
        settingsStore.Save(settings);
        Topmost = settings.Topmost;
        repository.Configure(settings.AutomaticBackupsEnabled, settings.BackupRetentionCount);
        state.ConfigureReviewDays(settings.DefaultReviewDays);
        PopulateColorFilter();
        RefreshDrafts();
    }

    private void ExportText_Click(object sender, RoutedEventArgs e) => ExportText("DraftBook.txt", "文本文件|*.txt", state.ExportPlainText());

    private void ExportMarkdown_Click(object sender, RoutedEventArgs e) => ExportText("DraftBook.md", "Markdown|*.md", state.ExportMarkdown());

    private void ExportBackup_Click(object sender, RoutedEventArgs e)
    {
        var dialog = new SaveFileDialog { FileName = $"DraftBook-Backup-{DateTime.Now:yyyyMMdd}.json", Filter = "JSON|*.json" };
        if (dialog.ShowDialog(this) == true)
        {
            File.WriteAllBytes(dialog.FileName, repository.FullBackup(state.ToSnapshot()));
            StatusText.Text = "完整备份已导出";
        }
    }

    private void RestoreBackup_Click(object sender, RoutedEventArgs e)
    {
        var dialog = new OpenFileDialog { Filter = "DraftBook JSON|*.json|All files|*.*", CheckFileExists = true };
        if (dialog.ShowDialog(this) != true)
        {
            return;
        }
        var answer = MessageBox.Show(this,
            "恢复将用备份中的内容替换当前草稿。当前数据会先自动保留一份安全备份。继续吗？",
            "从完整备份恢复", MessageBoxButton.YesNo, MessageBoxImage.Warning);
        if (answer != MessageBoxResult.Yes)
        {
            return;
        }
        try
        {
            var snapshot = repository.RestoreFullBackup(File.ReadAllBytes(dialog.FileName), DateTimeOffset.Now);
            state.ReplaceWithSnapshot(snapshot);
            initializing = true;
            ComposerBox.Text = state.Composer;
            initializing = false;
            PopulateColorFilter();
            RefreshDrafts();
            StatusText.Text = "备份已恢复";
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException or DraftBookDataException)
        {
            MessageBox.Show(this, exception.Message, "无法恢复备份", MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }

    private void ExportText(string fileName, string filter, string content)
    {
        var dialog = new SaveFileDialog { FileName = fileName, Filter = filter };
        if (dialog.ShowDialog(this) == true)
        {
            File.WriteAllText(dialog.FileName, content, new UTF8Encoding(encoderShouldEmitUTF8Identifier: false));
            StatusText.Text = "已导出";
        }
    }

    private void InstallSamples_Click(object sender, RoutedEventArgs e)
    {
        state.InstallSampleDrafts(DateTimeOffset.Now);
        RefreshDrafts();
    }

    private void RemoveSamples_Click(object sender, RoutedEventArgs e)
    {
        state.RemoveSampleDrafts();
        RefreshDrafts();
    }

    private void Guide_Click(object sender, RoutedEventArgs e) => MessageBox.Show(this,
        "在顶部直接输入，按 Ctrl+Enter 划定。\n\n" +
        "草稿自动保存；单击正文编辑 Markdown 原文，Ctrl+单击链接打开。\n\n" +
        "到期草稿进入清理台，可延后、固定、存档或删除。",
        "功能说明", MessageBoxButton.OK, MessageBoxImage.Information);

    private void Exit_Click(object sender, RoutedEventArgs e) => Close();

    private void OnClosing(object? sender, CancelEventArgs e)
    {
        if (closingCompleted)
        {
            return;
        }
        try
        {
            settings.WindowWidth = Width;
            settings.WindowHeight = Height;
            settingsStore.Save(settings);
            if (autoSave is not null)
            {
                autoSave.FlushAsync().GetAwaiter().GetResult();
                if (autoSave.LastError is not null)
                {
                    var answer = MessageBox.Show(this,
                        $"{autoSave.LastError}\n\n草稿可能尚未写入磁盘。仍要退出吗？",
                        "未能保存", MessageBoxButton.YesNo, MessageBoxImage.Warning);
                    if (answer != MessageBoxResult.Yes)
                    {
                        e.Cancel = true;
                        return;
                    }
                }
                autoSave.DisposeAsync().AsTask().GetAwaiter().GetResult();
            }
            closingCompleted = true;
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
        {
            var answer = MessageBox.Show(this,
                $"退出前保存失败：\n{exception.Message}\n\n仍要退出吗？",
                "未能保存", MessageBoxButton.YesNo, MessageBoxImage.Warning);
            if (answer != MessageBoxResult.Yes)
            {
                e.Cancel = true;
            }
            else
            {
                closingCompleted = true;
            }
        }
    }
}
