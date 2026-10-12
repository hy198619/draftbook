using System.Text.RegularExpressions;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Documents;
using System.Windows.Input;
using System.Windows.Media;
using Markdig;
using Markdig.Syntax;
using Markdig.Syntax.Inlines;
using MarkdownBlock = Markdig.Syntax.Block;
using WpfInline = System.Windows.Documents.Inline;

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

    private FlowDocument Render(string source)
    {
        var document = new FlowDocument
        {
            PagePadding = new Thickness(0),
            FontFamily = new FontFamily("Segoe UI, Microsoft YaHei UI"),
            FontSize = 14,
            Foreground = new SolidColorBrush(Color.FromRgb(38, 38, 38)),
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
                    var section = new Section { Margin = new Thickness(10, 3, 0, 7), Foreground = Brushes.DimGray };
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
                    Background = new SolidColorBrush(Color.FromArgb(35, 0, 0, 0)),
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
        Background = new SolidColorBrush(Color.FromRgb(244, 244, 244)),
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
                switch (child)
                {
                    case ParagraphBlock paragraph:
                        listItem.Blocks.Add(ParagraphFor(paragraph.Inline));
                        break;
                    case ListBlock nested:
                        listItem.Blocks.Add(RenderList(nested));
                        break;
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

    private WpfInline RenderInline(Markdig.Syntax.Inlines.Inline inline)
    {
        switch (inline)
        {
            case LiteralInline literal:
                return RenderTextWithBareLinks(literal.Content.ToString());
            case CodeInline code:
                return new Run(code.Content) { FontFamily = new FontFamily("Cascadia Mono, Consolas"), Background = Brushes.Gainsboro };
            case LineBreakInline lineBreak:
                return lineBreak.IsHard ? new LineBreak() : new Run(" ");
            case EmphasisInline emphasis:
                {
                    var span = new Span();
                    if (emphasis.DelimiterCount >= 2)
                    {
                        span.FontWeight = FontWeights.SemiBold;
                    }
                    else
                    {
                        span.FontStyle = FontStyles.Italic;
                    }
                    AddChildren(span, emphasis);
                    return span;
                }
            case LinkInline link when !link.IsImage:
                {
                    var hyperlink = new Hyperlink { NavigateUri = LinkLauncher.TryNormalize(link.Url, out var uri) ? uri : null };
                    AddChildren(hyperlink, link);
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
            case LinkInline image:
                return new Run(image.FirstChild?.ToString() ?? image.Url ?? "[图片]") { Foreground = Brushes.DimGray };
            case ContainerInline container:
                {
                    var span = new Span();
                    AddChildren(span, container);
                    return span;
                }
            default:
                return new Run(inline.ToString());
        }
    }

    private void AddChildren(Span target, ContainerInline container)
    {
        foreach (var child in container)
        {
            target.Inlines.Add(RenderInline(child));
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
            var hyperlink = new Hyperlink(new Run(raw)) { NavigateUri = uri };
            hyperlink.RequestNavigate += (_, args) =>
            {
                args.Handled = true;
                if (Keyboard.Modifiers.HasFlag(ModifierKeys.Control) && args.Uri is not null)
                {
                    LinkOpenRequested?.Invoke(this, args.Uri);
                }
            };
            span.Inlines.Add(hyperlink);
            cursor = match.Index + raw.Length;
        }
        if (cursor < text.Length)
        {
            span.Inlines.Add(new Run(text[cursor..]));
        }
        return span;
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
