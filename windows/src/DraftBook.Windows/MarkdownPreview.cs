using System.Text.RegularExpressions;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Documents;
using System.Windows.Input;
using System.Windows.Media;
using Markdig;
using Markdig.Extensions.Tables;
using Markdig.Extensions.TaskLists;
using Markdig.Syntax;
using Markdig.Syntax.Inlines;
using MarkdownBlock = Markdig.Syntax.Block;
using MarkdownTable = Markdig.Extensions.Tables.Table;
using WpfInline = System.Windows.Documents.Inline;
using WpfTable = System.Windows.Documents.Table;

namespace DraftBook.Windows;

public sealed partial class MarkdownPreview : FlowDocumentScrollViewer
{
    private static readonly MarkdownPipeline Pipeline = new MarkdownPipelineBuilder()
        .UseAdvancedExtensions()
        .DisableHtml()
        .Build();

    [GeneratedRegex("(?<candidate>https?://[^\\s<>()\\[\\]{}\\\"']+|file:///[^\\r\\n<>\\\"']+|(?:[A-Za-z]:\\\\|\\\\\\\\)[^\\r\\n<>|?*]+)", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant)]
    private static partial Regex BareLinkRegex();

    public MarkdownPreview(string source)
    {
        IsToolBarVisible = false;
        VerticalScrollBarVisibility = ScrollBarVisibility.Disabled;
        HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled;
        Background = Brushes.Transparent;
        Focusable = false;
        Document = Render(source);
    }

    public event EventHandler<Uri>? LinkOpenRequested;

    protected override void OnPreviewMouseWheel(MouseWheelEventArgs e)
    {
        // FlowDocumentScrollViewer owns an internal ScrollViewer. Even though its
        // scrollbars are disabled here, that nested viewer can consume the wheel
        // event before the draft list receives it. Forward one equivalent event to
        // the outer viewer so scrolling behaves consistently over the whole card.
        if (!e.Handled && FindOuterScrollViewer() is { } outerViewer)
        {
            e.Handled = true;
            outerViewer.RaiseEvent(new MouseWheelEventArgs(e.MouseDevice, e.Timestamp, e.Delta)
            {
                RoutedEvent = UIElement.MouseWheelEvent,
            });
            return;
        }

        base.OnPreviewMouseWheel(e);
    }

    private ScrollViewer? FindOuterScrollViewer()
    {
        DependencyObject? ancestor = this;
        while (ancestor is not null)
        {
            // Before a control is fully loaded it can already have a logical
            // parent while its visual parent has not been created yet. Support
            // both trees so wheel forwarding stays deterministic in startup and
            // in the regression test.
            ancestor = VisualTreeHelper.GetParent(ancestor) ?? LogicalTreeHelper.GetParent(ancestor);
            if (ancestor is ScrollViewer viewer)
            {
                return viewer;
            }
        }

        return null;
    }

    private FlowDocument Render(string source)
    {
        var document = new FlowDocument
        {
            PagePadding = new Thickness(0),
            FontFamily = new FontFamily("Segoe UI, Microsoft YaHei UI"),
            FontSize = 14,
            Foreground = SystemColors.WindowTextBrush,
        };

        var markdown = Markdig.Markdown.Parse(source ?? string.Empty, Pipeline);
        foreach (var block in markdown)
        {
            AddBlock(document, block);
        }

        if (document.Blocks.Count == 0)
        {
            document.Blocks.Add(new Paragraph());
        }

        return document;
    }

    private void AddBlock(FlowDocument target, MarkdownBlock block)
    {
        switch (block)
        {
            case HeadingBlock heading:
                {
                    var paragraph = ParagraphFor(heading.Inline);
                    paragraph.FontWeight = FontWeights.SemiBold;
                    paragraph.FontSize = heading.Level switch { 1 => 23, 2 => 19, 3 => 16, _ => 14 };
                    paragraph.Margin = new Thickness(0, heading.Level <= 2 ? 8 : 5, 0, 4);
                    target.Blocks.Add(paragraph);
                    break;
                }
            case ParagraphBlock paragraphBlock:
                {
                    var paragraph = ParagraphFor(paragraphBlock.Inline);
                    paragraph.Margin = new Thickness(0, 2, 0, 7);
                    target.Blocks.Add(paragraph);
                    break;
                }
            case QuoteBlock quote:
                {
                    var section = new Section { Margin = new Thickness(10, 3, 0, 7), Foreground = SystemColors.GrayTextBrush };
                    foreach (var child in quote)
                    {
                        AddBlock(section, child);
                    }
                    target.Blocks.Add(section);
                    break;
                }
            case ListBlock list:
                target.Blocks.Add(RenderList(list));
                break;
            case MarkdownTable table:
                target.Blocks.Add(RenderTable(table));
                break;
            case FencedCodeBlock fenced:
                target.Blocks.Add(CodeParagraph(fenced.Lines.ToString()));
                break;
            case CodeBlock code:
                target.Blocks.Add(CodeParagraph(code.Lines.ToString()));
                break;
            case ThematicBreakBlock:
                target.Blocks.Add(new BlockUIContainer(new Border
                {
                    Height = 1,
                    Margin = new Thickness(0, 8, 0, 8),
                    Background = SystemColors.ControlDarkBrush,
                }));
                break;
            case ContainerBlock container:
                foreach (var child in container)
                {
                    AddBlock(target, child);
                }
                break;
        }
    }

    private static Paragraph CodeParagraph(string content) => new(new Run(content)
    {
        FontFamily = new FontFamily("Cascadia Mono, Consolas"),
        FontSize = 12.5,
    })
    {
        Background = SystemColors.ControlBrush,
        Padding = new Thickness(8),
        Margin = new Thickness(0, 4, 0, 8),
    };

    private System.Windows.Documents.List RenderList(ListBlock source)
    {
        var result = new System.Windows.Documents.List
        {
            MarkerStyle = source.IsOrdered ? TextMarkerStyle.Decimal : TextMarkerStyle.Disc,
            Margin = new Thickness(20, 2, 0, 7),
        };
        foreach (var item in source.OfType<ListItemBlock>())
        {
            var listItem = new ListItem();
            foreach (var child in item)
            {
                if (child is ListBlock nested)
                {
                    listItem.Blocks.Add(RenderList(nested));
                    continue;
                }

                var temporary = new FlowDocument();
                AddBlock(temporary, child);
                while (temporary.Blocks.FirstBlock is { } first)
                {
                    temporary.Blocks.Remove(first);
                    listItem.Blocks.Add(first);
                }
            }
            result.ListItems.Add(listItem);
        }
        return result;
    }

    private Paragraph ParagraphFor(ContainerInline? inline)
    {
        var paragraph = new Paragraph();
        if (inline is not null)
        {
            foreach (var child in inline)
            {
                paragraph.Inlines.Add(RenderInline(child));
            }
        }
        return paragraph;
    }

    private WpfInline RenderInline(Markdig.Syntax.Inlines.Inline inline, bool detectBareLinks = true)
    {
        switch (inline)
        {
            case LiteralInline literal:
                return detectBareLinks
                    ? RenderTextWithBareLinks(literal.Content.ToString())
                    : new Run(literal.Content.ToString());
            case CodeInline code:
                return new Run(code.Content) { FontFamily = new FontFamily("Cascadia Mono, Consolas"), Background = SystemColors.ControlBrush };
            case LineBreakInline:
                // DraftBook is a writing surface rather than a document publishing
                // tool. Preserve the line the user entered even when CommonMark
                // classifies it as a soft break.
                return new LineBreak();
            case TaskList task:
                return new Run(task.Checked ? "☑ " : "☐ ");
            case EmphasisInline emphasis:
                {
                    var span = new Span();
                    if (emphasis.DelimiterChar == '~')
                    {
                        span.TextDecorations = TextDecorations.Strikethrough;
                    }
                    else if (emphasis.DelimiterCount >= 2)
                    {
                        span.FontWeight = FontWeights.SemiBold;
                    }
                    else
                    {
                        span.FontStyle = FontStyles.Italic;
                    }
                    AddChildren(span, emphasis, detectBareLinks);
                    return span;
                }
            case LinkInline link when !link.IsImage:
                {
                    var hyperlink = CreateHyperlink(LinkLauncher.TryNormalize(link.Url, out var uri) ? uri : null);
                    // Markdig represents an automatic URL as a LinkInline whose
                    // child is the URL text. Bare-link detection inside that child
                    // would create Hyperlink inside Hyperlink, which WPF rejects.
                    AddChildren(hyperlink, link, detectBareLinks: false);
                    return hyperlink;
                }
            case LinkInline image:
                return new Run(image.FirstChild?.ToString() ?? image.Url ?? "[图片]") { Foreground = SystemColors.GrayTextBrush };
            case ContainerInline container:
                {
                    var span = new Span();
                    AddChildren(span, container, detectBareLinks);
                    return span;
                }
            default:
                return new Run(inline.ToString());
        }
    }

    private void AddChildren(Span target, ContainerInline container, bool detectBareLinks = true)
    {
        foreach (var child in container)
        {
            target.Inlines.Add(RenderInline(child, detectBareLinks));
        }
    }

    private WpfInline RenderTextWithBareLinks(string text)
    {
        var matches = BareLinkRegex().Matches(text);
        if (matches.Count == 0)
        {
            return new Run(text);
        }

        var span = new Span();
        var cursor = 0;
        foreach (Match match in matches)
        {
            if (!TryLinkPrefix(match.Groups["candidate"].Value, out var raw, out var uri))
            {
                continue;
            }
            if (match.Index > cursor)
            {
                span.Inlines.Add(new Run(text[cursor..match.Index]));
            }
            var hyperlink = CreateHyperlink(uri);
            hyperlink.Inlines.Add(new Run(raw));
            span.Inlines.Add(hyperlink);
            cursor = match.Index + raw.Length;
        }
        if (cursor < text.Length)
        {
            span.Inlines.Add(new Run(text[cursor..]));
        }
        return span;
    }

    private Hyperlink CreateHyperlink(Uri? uri)
    {
        var hyperlink = new Hyperlink { NavigateUri = uri };
        if (uri is not null)
        {
            hyperlink.ToolTip = $"Ctrl+单击打开：{uri}";
        }
        hyperlink.RequestNavigate += (_, args) =>
        {
            args.Handled = true;
            if (Keyboard.Modifiers.HasFlag(ModifierKeys.Control) && args.Uri is not null)
            {
                LinkOpenRequested?.Invoke(this, args.Uri);
            }
        };
        return hyperlink;
    }

    private WpfTable RenderTable(MarkdownTable source)
    {
        var table = new WpfTable
        {
            CellSpacing = 0,
            Margin = new Thickness(0, 4, 0, 8),
        };
        var group = new TableRowGroup();
        table.RowGroups.Add(group);

        foreach (var sourceRow in source.OfType<Markdig.Extensions.Tables.TableRow>())
        {
            var row = new System.Windows.Documents.TableRow();
            foreach (var sourceCell in sourceRow.OfType<Markdig.Extensions.Tables.TableCell>())
            {
                var cell = new System.Windows.Documents.TableCell
                {
                    BorderBrush = SystemColors.ControlLightBrush,
                    BorderThickness = new Thickness(0.5),
                    Padding = new Thickness(6, 4, 6, 4),
                    Background = sourceRow.IsHeader ? SystemColors.ControlBrush : Brushes.Transparent,
                    ColumnSpan = Math.Max(1, sourceCell.ColumnSpan),
                    RowSpan = Math.Max(1, sourceCell.RowSpan),
                };
                var temporary = new FlowDocument();
                foreach (var child in sourceCell)
                {
                    AddBlock(temporary, child);
                }
                while (temporary.Blocks.FirstBlock is { } first)
                {
                    temporary.Blocks.Remove(first);
                    if (sourceRow.IsHeader)
                    {
                        first.FontWeight = FontWeights.SemiBold;
                    }
                    first.Margin = new Thickness(0);
                    cell.Blocks.Add(first);
                }
                if (cell.Blocks.Count == 0)
                {
                    cell.Blocks.Add(new Paragraph());
                }
                row.Cells.Add(cell);
            }
            group.Rows.Add(row);
        }

        return table;
    }

    private static bool TryLinkPrefix(string candidate, out string raw, out Uri? uri)
    {
        raw = candidate.TrimEnd('.', ',', '，', '。', ';', '；', ':', '：', '!', '！', '?', '？', ')', '）');
        if (LinkLauncher.TryNormalize(raw, out uri))
        {
            return true;
        }

        // A bare Windows path may contain spaces, so the regex deliberately reads
        // through the rest of the line. Find the longest prefix that is a real file.
        for (var length = raw.Length - 1; length >= 3; length--)
        {
            var prefix = raw[..length].TrimEnd();
            if (LinkLauncher.TryNormalize(prefix, out uri))
            {
                raw = prefix;
                return true;
            }
        }

        raw = string.Empty;
        uri = null;
        return false;
    }

    private void AddBlock(Section target, MarkdownBlock block)
    {
        var temporary = new FlowDocument();
        AddBlock(temporary, block);
        while (temporary.Blocks.FirstBlock is { } first)
        {
            temporary.Blocks.Remove(first);
            target.Blocks.Add(first);
        }
    }
}
