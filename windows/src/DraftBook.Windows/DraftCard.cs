using System.Globalization;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using DraftBook.Core;

namespace DraftBook.Windows;

public sealed class DraftCard : Border
{
    private readonly DraftBookState state;
    private readonly Guid draftId;
    private readonly Action refresh;
    private readonly Grid bodyHost = new();
    private bool editing;

    public DraftCard(DraftBookState state, Draft draft, string section, Action refresh)
    {
        this.state = state;
        draftId = draft.Id;
        this.refresh = refresh;
        Background = Brushes.White;
        BorderBrush = new SolidColorBrush(Color.FromArgb(24, 0, 0, 0));
        BorderThickness = new Thickness(1);
        CornerRadius = new CornerRadius(8);
        Margin = new Thickness(0, 0, 0, 8);
        Padding = new Thickness(11, 8, 11, 9);

        var stack = new StackPanel();
        stack.Children.Add(BuildHeader(draft, section));
        if (draft.State == DraftState.Archived)
        {
            stack.Children.Add(BuildTitleEditor(draft));
        }
        stack.Children.Add(bodyHost);
        Child = stack;
        ShowPreview(draft.Content);
    }

    private UIElement BuildHeader(Draft draft, string section)
    {
        var grid = new Grid { Margin = new Thickness(0, 0, 0, 4) };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

        var tag = new ComboBox
        {
            Width = 92,
            FontSize = 11,
            Background = TagBrush(draft),
            ToolTip = $"{state.LabelName(draft.Color)}\n创建：{draft.CreatedAt.ToLocalTime():g}\n更新：{draft.UpdatedAt.ToLocalTime():g}\n" +
                      DraftTiming.CleanupDescription(draft.ReviewAt, draft.Pinned, DateTimeOffset.Now),
        };
        foreach (var color in Enum.GetValues<DraftColor>())
        {
            tag.Items.Add(new ComboBoxItem { Content = state.LabelName(color), Tag = color });
        }
        tag.SelectedIndex = (int)draft.Color;
        tag.SelectionChanged += (_, _) =>
        {
            if (tag.SelectedItem is ComboBoxItem { Tag: DraftColor selected })
            {
                state.SetColor(draftId, selected);
                tag.Background = TagBrush(draft);
            }
        };
        grid.Children.Add(tag);

        var status = new TextBlock
        {
            Text = StatusFor(draft),
            VerticalAlignment = VerticalAlignment.Center,
            Foreground = new SolidColorBrush(Color.FromRgb(120, 120, 120)),
            FontSize = 10,
            Margin = new Thickness(9, 0, 5, 0),
            TextTrimming = TextTrimming.CharacterEllipsis,
        };
        Grid.SetColumn(status, 1);
        grid.Children.Add(status);

        var actions = new StackPanel { Orientation = Orientation.Horizontal };
        AddActionButtons(actions, draft, section);
        Grid.SetColumn(actions, 2);
        grid.Children.Add(actions);
        return grid;
    }

    private UIElement BuildTitleEditor(Draft draft)
    {
        var title = new TextBox
        {
            Text = draft.DisplayTitle,
            FontSize = 13,
            FontWeight = FontWeights.SemiBold,
            BorderThickness = new Thickness(0),
            Background = Brushes.Transparent,
            Margin = new Thickness(0, 4, 0, 2),
            ToolTip = "存档标题，失去焦点时保存",
        };
        title.LostKeyboardFocus += (_, _) => state.RenameArchived(draftId, title.Text);
        return title;
    }

    private void AddActionButtons(Panel panel, Draft draft, string section)
    {
        panel.Children.Add(ActionButton("复制", () =>
        {
            if (ClipboardService.TrySetText(Window.GetWindow(this), draft.Content))
            {
                state.MarkCopied(draftId, DateTimeOffset.Now);
            }
        }));

        if (draft.State == DraftState.Active)
        {
            if (section == "due")
            {
                panel.Children.Add(ActionButton("延后", () => { state.Postpone(draftId, state.DefaultReviewDays, DateTimeOffset.Now); refresh(); }));
            }
            panel.Children.Add(ActionButton(draft.Pinned ? "取消固定" : "固定", () => { state.TogglePinned(draftId, DateTimeOffset.Now); refresh(); }));
            panel.Children.Add(ActionButton("存档", () => { state.Archive(draftId, null, null, DateTimeOffset.Now); refresh(); }));
            panel.Children.Add(ActionButton("删除", () => { state.MoveToTrash(draftId, DateTimeOffset.Now); refresh(); }));
        }
        else if (draft.State == DraftState.Archived)
        {
            panel.Children.Add(ActionButton("恢复", () => { state.RestoreFromArchive(draftId, DateTimeOffset.Now); refresh(); }));
            panel.Children.Add(ActionButton("删除", () => { state.MoveToTrash(draftId, DateTimeOffset.Now); refresh(); }));
        }
        else
        {
            panel.Children.Add(ActionButton("恢复", () => { state.RestoreFromTrash(draftId, DateTimeOffset.Now); refresh(); }));
            panel.Children.Add(ActionButton("永久删除", () =>
            {
                var owner = Window.GetWindow(this);
                var result = MessageBox.Show(owner, "这条草稿将无法恢复。确定永久删除吗？", "永久删除",
                    MessageBoxButton.YesNo, MessageBoxImage.Warning);
                if (result == MessageBoxResult.Yes)
                {
                    state.DeletePermanently(draftId);
                    refresh();
                }
            }));
        }
    }

    private static Button ActionButton(string label, Action action)
    {
        var button = new Button { Content = label, FontSize = 10, Padding = new Thickness(5, 2, 5, 2) };
        button.Click += (_, _) => action();
        return button;
    }

    private void ShowPreview(string content)
    {
        editing = false;
        bodyHost.Children.Clear();
        var preview = new MarkdownPreview(content)
        {
            Margin = new Thickness(1, 5, 1, 2),
            ToolTip = "单击编辑原文；Ctrl+单击链接打开；复制保留 Markdown 语法",
        };
        preview.LinkOpenRequested += (_, uri) => LinkLauncher.Open(Window.GetWindow(this), uri);
        preview.PreviewMouseLeftButtonDown += (_, args) =>
        {
            if (!Keyboard.Modifiers.HasFlag(ModifierKeys.Control))
            {
                args.Handled = true;
                BeginEditing();
            }
        };
        bodyHost.Children.Add(preview);
    }

    private void BeginEditing()
    {
        if (editing || state.Find(draftId) is not { } draft)
        {
            return;
        }

        editing = true;
        bodyHost.Children.Clear();
        var editor = new ImeAwareTextBox
        {
            Text = draft.Content,
            AcceptsReturn = true,
            TextWrapping = TextWrapping.Wrap,
            MinHeight = 64,
            MaxHeight = 360,
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
            BorderThickness = new Thickness(0),
            Margin = new Thickness(0, 5, 0, 2),
        };
        editor.TextChanged += (_, _) => state.UpdateContent(draftId, editor.Text, DateTimeOffset.Now);
        editor.LostKeyboardFocus += (_, _) =>
        {
            if (editing)
            {
                ShowPreview(state.Find(draftId)?.Content ?? string.Empty);
            }
        };
        bodyHost.Children.Add(editor);
        editor.Focus();
        editor.CaretIndex = editor.Text.Length;
    }

    private static string StatusFor(Draft draft)
    {
        if (draft.State == DraftState.Active && !draft.Pinned && draft.ReviewAt <= DateTimeOffset.Now)
        {
            return "待处理";
        }
        if (draft.Pinned)
        {
            return "已固定";
        }
        var culture = CultureInfo.GetCultureInfo("zh-CN");
        return draft.State switch
        {
            DraftState.Archived => $"存档于 {(draft.ArchivedAt ?? draft.UpdatedAt).ToLocalTime().ToString("g", culture)}",
            DraftState.Trash => $"删除于 {(draft.DeletedAt ?? draft.UpdatedAt).ToLocalTime().ToString("g", culture)}",
            _ => draft.CreatedAt.ToLocalTime().ToString("g", culture),
        };
    }

    private static Brush TagBrush(Draft draft)
    {
        var baseColor = draft.Color switch
        {
            DraftColor.Yellow => Color.FromRgb(244, 191, 67),
            DraftColor.Blue => Color.FromRgb(79, 147, 238),
            DraftColor.Purple => Color.FromRgb(154, 106, 221),
            DraftColor.Green => Color.FromRgb(75, 172, 114),
            DraftColor.Red => Color.FromRgb(226, 91, 91),
            _ => Color.FromRgb(183, 183, 183),
        };
        var saturation = DraftTiming.TagSaturation(draft.CreatedAt, DateTimeOffset.Now);
        const byte surface = 238;
        byte Fade(byte component) => (byte)Math.Clamp(surface + ((component - surface) * saturation), 0, 255);
        return new SolidColorBrush(Color.FromRgb(Fade(baseColor.R), Fade(baseColor.G), Fade(baseColor.B)));
    }
}
