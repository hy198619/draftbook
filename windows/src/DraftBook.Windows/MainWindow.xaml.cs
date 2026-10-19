using System.ComponentModel;
using System.IO;
using System.Text;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Threading;
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
    private readonly DispatcherTimer statusTimer = new() { Interval = TimeSpan.FromSeconds(3) };
    private readonly DispatcherTimer topmostHintTimer = new() { Interval = TimeSpan.FromSeconds(8) };
    private bool closingCompleted;
    private bool initializing = true;
    private string currentSection = "active";

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
            {
                if (error is null)
                {
                    HideStatus();
                }
                else
                {
                    ShowStatus(error, persistent: true);
                }
            });
        }

        Topmost = settings.Topmost;
        PinButton.IsChecked = Topmost;
        ComposerBox.Text = state.Composer;
        UpdateComposerPlaceholder();
        PopulateColorFilter();
        UpdateSectionChrome();
        RefreshDrafts();
        initializing = false;
        SourceInitialized += (_, _) => WindowPlacementService.Restore(this, settings);
        statusTimer.Tick += (_, _) => HideStatus();
        topmostHintTimer.Tick += (_, _) =>
        {
            topmostHintTimer.Stop();
            TopmostHintPopup.IsOpen = false;
        };
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
            if (!settings.HasShownTopmostHint)
            {
                settings.HasShownTopmostHint = true;
                Dispatcher.BeginInvoke(() =>
                {
                    TopmostHintPopup.IsOpen = true;
                    topmostHintTimer.Start();
                }, DispatcherPriority.ContextIdle);
            }
            if (load.Warning is not null)
            {
                MessageBox.Show(this, load.Warning, "已恢复备份", MessageBoxButton.OK, MessageBoxImage.Warning);
            }
        };
        Closing += OnClosing;
    }

    private string CurrentSection => currentSection;

    private DraftColor? CurrentColor => (ColorPicker.SelectedItem as ComboBoxItem)?.Tag as DraftColor?;

    private void PopulateColorFilter()
    {
        ColorPicker.Items.Clear();
        ColorPicker.Items.Add(new ComboBoxItem { Content = "全部标签", IsSelected = true });
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
            DraftPanel.Children.Add(BuildEmptyState(section, query, color));
        }
        UpdateSectionCounts();
    }

    private void Composer_TextChanged(object sender, TextChangedEventArgs e)
    {
        UpdateComposerPlaceholder();
        if (!initializing)
        {
            state.Composer = ComposerBox.Text;
        }
    }

    private void Composer_CommitRequested(object? sender, EventArgs e) => SealComposer();

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
        if (ClearSearchButton is not null)
        {
            ClearSearchButton.Visibility = string.IsNullOrEmpty(SearchBox?.Text)
                ? Visibility.Collapsed
                : Visibility.Visible;
        }
        if (!initializing)
        {
            RefreshDrafts();
        }
    }

    private void SectionButton_Click(object sender, RoutedEventArgs e) => OpenContextMenu(SectionButton);

    private void MoreButton_Click(object sender, RoutedEventArgs e) => OpenContextMenu(MoreButton);

    private static void OpenContextMenu(Button button)
    {
        if (button.ContextMenu is not { } menu)
        {
            return;
        }
        menu.PlacementTarget = button;
        menu.Placement = PlacementMode.Bottom;
        menu.IsOpen = true;
    }

    private void SectionMenuItem_Click(object sender, RoutedEventArgs e)
    {
        if (sender is not MenuItem { Tag: string section })
        {
            return;
        }
        currentSection = section;
        UpdateSectionChrome();
        RefreshDrafts();
        if (section == "active" && SearchHost.Visibility != Visibility.Visible)
        {
            ComposerBox.Focus();
        }
    }

    private void UpdateSectionChrome()
    {
        SectionTitle.Text = currentSection switch
        {
            "due" => "清理台",
            "archived" => "存档区",
            "trash" => "回收站",
            _ => "草稿区",
        };
        ComposerHost.Visibility = currentSection == "active" ? Visibility.Visible : Visibility.Collapsed;
    }

    private void UpdateSectionCounts()
    {
        var dueCount = state.DueDrafts(DateTimeOffset.Now).Count;
        var trashCount = state.TrashedDrafts.Count;
        DueMenuItem.Header = dueCount == 0 ? "清理台" : $"清理台（{dueCount}）";
        TrashMenuItem.Header = trashCount == 0 ? "回收站" : $"回收站（{trashCount}）";

        var filtering = !string.IsNullOrWhiteSpace(SearchBox.Text) || CurrentColor is not null;
        ComposerHost.Visibility = currentSection == "active" && !filtering
            ? Visibility.Visible
            : Visibility.Collapsed;
    }

    private UIElement BuildEmptyState(string section, string query, DraftColor? color)
    {
        var filtering = !string.IsNullOrWhiteSpace(query) || color is not null;
        var (title, detail) = filtering
            ? ("没有找到相关草稿", "可以清除搜索文字或标签筛选")
            : section switch
            {
                "due" => ("暂时没有需要处理的草稿", $"新草稿会在最后修改 {state.DefaultReviewDays} 天后进入这里"),
                "archived" => ("存档区是空的", "需要长期保留的草稿可以存放在这里"),
                "trash" => ("回收站是空的", "删除的草稿会先保存在这里"),
                _ => ("从这里写下第一条草稿", "写完一条，按 Ctrl+Enter 划定"),
            };

        var panel = new StackPanel
        {
            Margin = new Thickness(8, 40, 8, 8),
            HorizontalAlignment = HorizontalAlignment.Center,
        };
        panel.Children.Add(new TextBlock
        {
            Text = title,
            FontSize = 12,
            HorizontalAlignment = HorizontalAlignment.Center,
            Foreground = SystemColors.GrayTextBrush,
        });
        panel.Children.Add(new TextBlock
        {
            Text = detail,
            FontSize = 11,
            Margin = new Thickness(0, 7, 0, 0),
            HorizontalAlignment = HorizontalAlignment.Center,
            TextAlignment = TextAlignment.Center,
            Foreground = SystemColors.GrayTextBrush,
            Opacity = 0.72,
        });
        return panel;
    }

    private void SearchButton_Click(object sender, RoutedEventArgs e) =>
        SetSearchVisible(SearchButton.IsChecked == true);

    private void Search_Executed(object sender, ExecutedRoutedEventArgs e)
    {
        SearchButton.IsChecked = true;
        SetSearchVisible(true);
        e.Handled = true;
    }

    private void SetSearchVisible(bool visible)
    {
        SearchHost.Visibility = visible ? Visibility.Visible : Visibility.Collapsed;
        if (visible)
        {
            SearchBox.Focus();
            SearchBox.SelectAll();
            return;
        }

        initializing = true;
        SearchBox.Clear();
        if (ColorPicker.Items.Count > 0)
        {
            ColorPicker.SelectedIndex = 0;
        }
        initializing = false;
        RefreshDrafts();
        if (currentSection == "active")
        {
            ComposerBox.Focus();
        }
    }

    private void SearchBox_PreviewKeyDown(object sender, KeyEventArgs e)
    {
        if (e.Key != Key.Escape)
        {
            return;
        }
        SearchButton.IsChecked = false;
        SetSearchVisible(false);
        e.Handled = true;
    }

    private void ClearSearchButton_Click(object sender, RoutedEventArgs e)
    {
        SearchBox.Clear();
        SearchBox.Focus();
    }

    private void PinButton_Click(object sender, RoutedEventArgs e)
    {
        Topmost = PinButton.IsChecked == true;
        settings.Topmost = Topmost;
        TopmostHintPopup.IsOpen = false;
        topmostHintTimer.Stop();
    }

    private void ResetWindowPlacement_Click(object sender, RoutedEventArgs e)
    {
        settings.WindowWidth = 420;
        settings.WindowHeight = 680;
        settings.WindowLeftPixels = null;
        settings.WindowTopPixels = null;
        settings.WindowMaximized = false;
        WindowState = WindowState.Normal;
        WindowPlacementService.Restore(this, settings);
        ShowStatus("已恢复默认窗口大小和位置");
    }

    private void UpdateComposerPlaceholder() =>
        ComposerPlaceholder.Visibility = string.IsNullOrEmpty(ComposerBox.Text)
            ? Visibility.Visible
            : Visibility.Collapsed;

    private void ShowStatus(string message, bool persistent = false)
    {
        statusTimer.Stop();
        StatusText.Text = message;
        StatusToast.Background = (Brush)FindResource(persistent ? "ErrorBrush" : "HintSurfaceBrush");
        StatusToast.Visibility = Visibility.Visible;
        if (!persistent)
        {
            statusTimer.Start();
        }
    }

    private void HideStatus()
    {
        statusTimer.Stop();
        StatusToast.Visibility = Visibility.Collapsed;
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
        PinButton.IsChecked = Topmost;
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
            ShowStatus("完整备份已导出");
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
            ShowStatus("备份已恢复");
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
            ShowStatus("已导出");
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
            WindowPlacementService.Capture(this, settings);
            settings.Topmost = Topmost;
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
