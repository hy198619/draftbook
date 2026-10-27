using System.Runtime.ExceptionServices;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Documents;
using System.Windows.Input;
using DraftBook.Core;
using DraftBook.Windows;

namespace DraftBook.Windows.Tests;

public sealed class MarkdownPreviewTests
{
    [Fact]
    public void PlainTextPreservesEnteredLineBreaksAndSpaces()
    {
        RunOnSta(() =>
        {
            var preview = new MarkdownPreview("第一行\n第二  行\n\n第四行");
            var paragraphs = preview.Document.Blocks.OfType<Paragraph>().ToList();

            Assert.Equal(2, paragraphs.Count);
            Assert.Single(paragraphs[0].Inlines.OfType<LineBreak>());
            Assert.Contains(paragraphs[0].Inlines.OfType<Run>(), run => run.Text == "第二  行");
            Assert.Contains(paragraphs[1].Inlines.OfType<Run>(), run => run.Text == "第四行");
        });
    }

    [Theory]
    [InlineData("https://example.com")]
    [InlineData("前缀 https://example.com/path?q=1 后缀")]
    [InlineData("[官网](https://example.com)")]
    [InlineData("[https://example.com](https://example.com)")]
    [InlineData("[**https://example.com**](https://example.com)")]
    public void WebLinksRenderAsOneNonNestedHyperlink(string source)
    {
        RunOnSta(() =>
        {
            var preview = new MarkdownPreview(source);
            var hyperlinks = InlineDescendants(preview.Document).OfType<Hyperlink>().ToList();

            Assert.Single(hyperlinks);
            Assert.DoesNotContain(InlineDescendants(hyperlinks[0].Inlines), inline => inline is Hyperlink);
            Assert.Equal("https", hyperlinks[0].NavigateUri?.Scheme);
        });
    }

    [Fact]
    public void CommonExtendedMarkdownRemainsRenderable()
    {
        RunOnSta(() =>
        {
            const string source = "**粗体** *斜体* ~~删除线~~ `代码`\n\n- [x] 已完成\n- [ ] 未完成\n\n| 名称 | 值 |\n| --- | --- |\n| 甲 | 1 |";
            var preview = new MarkdownPreview(source);

            Assert.Contains(InlineDescendants(preview.Document), inline =>
                inline is Span span && span.TextDecorations?.Any(decoration =>
                    decoration.Location == TextDecorationLocation.Strikethrough) == true);
            Assert.Contains(InlineDescendants(preview.Document).OfType<Run>(), run => run.Text == "☑ ");
            Assert.Contains(InlineDescendants(preview.Document).OfType<Run>(), run => run.Text == "☐ ");
            Assert.Contains(preview.Document.Blocks, block => block is System.Windows.Documents.Table);
        });
    }

    [Fact]
    public void TagMenuContainsDirectLabelManagementEntry()
    {
        RunOnSta(() =>
        {
            var now = DateTimeOffset.Now;
            var draft = new Draft { Content = "测试", CreatedAt = now, UpdatedAt = now };
            var state = new DraftBookState(new DraftBookSnapshot
            {
                SchemaVersion = DraftBookSnapshot.CurrentSchemaVersion,
                Drafts = [draft],
            });
            var opened = false;
            var card = new DraftCard(state, draft, "active", () => { }, () => opened = true);
            var stack = Assert.IsType<StackPanel>(card.Child);
            var header = Assert.IsType<Grid>(stack.Children[0]);
            var tagButton = Assert.IsType<Button>(header.Children[0]);
            var menu = Assert.IsType<ContextMenu>(tagButton.ContextMenu);
            var item = Assert.IsType<MenuItem>(menu.Items[^1]);

            Assert.Equal("自定义分类名称…", item.Header);
            item.RaiseEvent(new RoutedEventArgs(MenuItem.ClickEvent));
            Assert.True(opened);
        });
    }

    [Fact]
    public void MouseWheelOverPreviewIsForwardedOnceToOuterScrollViewer()
    {
        RunOnSta(() =>
        {
            var preview = new MarkdownPreview("一条用于滚动测试的合成草稿");
            var outerViewer = new ScrollViewer { Content = preview };
            var forwardedCount = 0;
            outerViewer.AddHandler(
                UIElement.MouseWheelEvent,
                new MouseWheelEventHandler((_, _) => forwardedCount++),
                handledEventsToo: true);

            var wheel = new MouseWheelEventArgs(Mouse.PrimaryDevice, Environment.TickCount, -120)
            {
                RoutedEvent = UIElement.PreviewMouseWheelEvent,
            };
            preview.RaiseEvent(wheel);

            Assert.True(wheel.Handled);
            Assert.Equal(1, forwardedCount);
        });
    }

    private static IEnumerable<Inline> InlineDescendants(FlowDocument document)
    {
        foreach (var paragraph in Blocks(document.Blocks).OfType<Paragraph>())
        {
            foreach (var inline in InlineDescendants(paragraph.Inlines))
            {
                yield return inline;
            }
        }
    }

    private static IEnumerable<Block> Blocks(BlockCollection blocks)
    {
        foreach (var block in blocks)
        {
            yield return block;
            switch (block)
            {
                case Section section:
                    foreach (var child in Blocks(section.Blocks)) yield return child;
                    break;
                case System.Windows.Documents.List list:
                    foreach (var item in list.ListItems)
                    {
                        foreach (var child in Blocks(item.Blocks))
                        {
                            yield return child;
                        }
                    }
                    break;
                case System.Windows.Documents.Table table:
                    foreach (var group in table.RowGroups)
                    {
                        foreach (var row in group.Rows)
                        {
                            foreach (var cell in row.Cells)
                            {
                                foreach (var child in Blocks(cell.Blocks))
                                {
                                    yield return child;
                                }
                            }
                        }
                    }
                    break;
            }
        }
    }

    private static IEnumerable<Inline> InlineDescendants(InlineCollection inlines)
    {
        foreach (var inline in inlines)
        {
            yield return inline;
            if (inline is Span span)
            {
                foreach (var child in InlineDescendants(span.Inlines))
                {
                    yield return child;
                }
            }
        }
    }

    private static void RunOnSta(Action action)
    {
        Exception? failure = null;
        var thread = new Thread(() =>
        {
            try
            {
                action();
            }
            catch (Exception exception)
            {
                failure = exception;
            }
        });
        thread.SetApartmentState(ApartmentState.STA);
        thread.Start();
        thread.Join();
        if (failure is not null)
        {
            ExceptionDispatchInfo.Capture(failure).Throw();
        }
    }
}
