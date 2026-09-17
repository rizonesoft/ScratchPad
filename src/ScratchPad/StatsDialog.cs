using System.Globalization;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Notepad.Core;

namespace ScratchPad;

// Document statistics panel, owned by D01 T01 §14. Code-built ContentDialog
// following SavePromptDialog (default WinUI styling): three sections over
// StatsController.Current, computed on open, re-read only through Refresh.
// The provider arrives injected (MainWindow reads the active tab's buffer)
// until D02 T01 §1 binds the real editor buffer. Tabular rows share one
// grid per section so values right-align on a common edge.
internal sealed class StatsDialog : ContentDialog
{
    // Display cap for the unbounded repetition list; the engine keeps all.
    const int MaxRepeatedRows = 50;
    // Dialog cap (DIP) plus the fallback grid width for an unknown
    // template. ValuesAlignToDialogRightEdge trips if the template ever
    // stops honoring the cap.
    const double DialogMaxWidth = 420;
    const double GridWidth = 372;

    readonly StatsController controller;
    readonly StackPanel topWords = new();
    readonly StackPanel sentences = new();
    readonly StackPanel repeated = new();

    public StatsDialog(ITextProvider provider)
    {
        ArgumentNullException.ThrowIfNull(provider);
        controller = new StatsController(provider);
        AutomationProperties.SetAutomationId(this, "StatsDialog");
        Title = "Document statistics";
        CloseButtonText = "Close";
        AutomationProperties.SetAutomationId(topWords, "StatsTopWords");
        AutomationProperties.SetAutomationId(sentences, "StatsSentences");
        AutomationProperties.SetAutomationId(repeated, "StatsRepeatedWords");
        var refresh = new Button { Content = "Refresh", Margin = new Thickness(0, 12, 0, 0) };
        AutomationProperties.SetAutomationId(refresh, "StatsRefreshButton");
        refresh.Click += (_, _) =>
        {
            controller.Refresh();
            Render(controller.Current);
        };
        // Capped dialog: the template sizes to first measure and never
        // shrinks (dump-proven at 585), so the cap bounds the blast radius
        // while the fitted viewer below does the real alignment.
        MaxWidth = DialogMaxWidth;
        Content = new StackPanel
        {
            Children = { Section("Top words", topWords), Section("Sentences", sentences), Section("Repeated words", repeated), refresh },
        };
        // Values fill the slot: the content's nearest ScrollViewer ancestor
        // is pinned to the dialog minus live chrome, so the stretching
        // grids always span exactly the available width. Measured at load
        // and on every dialog resize (a squeezed dialog from a narrow
        // window narrows the viewer too, instead of clipping the values
        // behind its right edge, real user case). No viewer found means an
        // unknown template: fall back to the fixed width, which fits every
        // dialog the cap allows.
        Loaded += (_, _) => FitViewer();
        SizeChanged += (_, _) => FitViewer();
        Render(controller.Current);
    }

    void FitViewer()
    {
        double chrome = Padding.Left + Padding.Right + BorderThickness.Left + BorderThickness.Right;
        double slot = ActualWidth - (chrome > 0 ? chrome : 2);
        DependencyObject? parent = VisualTreeHelper.GetParent(topWords);
        while (parent is not null && parent is not ScrollViewer)
        {
            parent = VisualTreeHelper.GetParent(parent);
        }

        if (parent is ScrollViewer viewer && slot > 0)
        {
            viewer.Width = slot;
            return;
        }

        foreach (Grid grid in Grids())
        {
            grid.Width = GridWidth;
        }
    }

    System.Collections.Generic.IEnumerable<Grid> Grids()
    {
        foreach (StackPanel section in new[] { topWords, sentences })
        {
            foreach (UIElement child in section.Children)
            {
                if (child is Grid grid)
                {
                    yield return grid;
                }
            }
        }
    }


    static StackPanel Section(string heading, StackPanel rows)
    {
        var header = new TextBlock { Text = heading, FontWeight = Microsoft.UI.Text.FontWeights.SemiBold, Margin = new Thickness(0, 8, 0, 4) };
        return new StackPanel { Children = { header, rows } };
    }

    // One grid per section: labels left, values on the shared right edge.
    // The label column is Star (labels ellipsize before they can squeeze
    // a value); the value column is Auto, so every value's right edge is
    // the grid's right edge. The grids stretch to the fitted viewer with
    // no pinned width of their own.
    static Grid ValueGrid(IReadOnlyList<(string Label, string Value)> rows, string? trailer = null)
    {
        var grid = new Grid { HorizontalAlignment = HorizontalAlignment.Stretch };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        int row = 0;
        foreach ((string label, string value) in rows)
        {
            grid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            var labelBlock = new TextBlock { Text = label, Margin = new Thickness(0, 0, 16, 0), TextTrimming = TextTrimming.CharacterEllipsis };
            var valueBlock = new TextBlock { Text = value, HorizontalAlignment = HorizontalAlignment.Right };
            Grid.SetRow(labelBlock, row);
            Grid.SetColumn(labelBlock, 0);
            Grid.SetRow(valueBlock, row);
            Grid.SetColumn(valueBlock, 1);
            grid.Children.Add(labelBlock);
            grid.Children.Add(valueBlock);
            row++;
        }

        if (trailer is not null)
        {
            grid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            var trailerBlock = new TextBlock { Text = trailer };
            Grid.SetRow(trailerBlock, row);
            Grid.SetColumnSpan(trailerBlock, 2);
            grid.Children.Add(trailerBlock);
        }

        return grid;
    }

    void Render(DocumentStats stats)
    {
        topWords.Children.Clear();
        topWords.Children.Add(ValueGrid(stats.TopWords.Select(word => (word.Word, word.Count.ToString(CultureInfo.InvariantCulture))).ToList()));
        sentences.Children.Clear();
        sentences.Children.Add(ValueGrid(
        [
            ("Sentences", stats.TotalSentences.ToString(CultureInfo.InvariantCulture)),
            ("Mean length", FormattableString.Invariant($"{stats.MeanSentenceLength:0.0}")),
            ("Shortest", stats.ShortestSentence.ToString(CultureInfo.InvariantCulture)),
            ("Longest", stats.LongestSentence.ToString(CultureInfo.InvariantCulture)),
            ("Short (1-10)", stats.Buckets.Small.ToString(CultureInfo.InvariantCulture)),
            ("Medium (11-25)", stats.Buckets.Medium.ToString(CultureInfo.InvariantCulture)),
            ("Long (26+)", stats.Buckets.Large.ToString(CultureInfo.InvariantCulture)),
        ]));
        repeated.Children.Clear();
        foreach (string word in stats.RepeatedWords.Take(MaxRepeatedRows))
        {
            repeated.Children.Add(new TextBlock { Text = word });
        }

        if (stats.RepeatedWords.Count > MaxRepeatedRows)
        {
            repeated.Children.Add(new TextBlock { Text = $"+{stats.RepeatedWords.Count - MaxRepeatedRows} more" });
        }
    }
}

// The §14 text seam: MainWindow injects the active tab's buffer; D02 T01 §1
// swaps this for the real editor buffer without touching the dialog.
internal sealed class ActiveTabTextProvider : ITextProvider
{
    readonly Func<string> read;

    public ActiveTabTextProvider(Func<string> read)
    {
        ArgumentNullException.ThrowIfNull(read);
        this.read = read;
    }

    public string GetText() => read();
}
