using System.Collections.Generic;
using System.Collections.Specialized;
using System.ComponentModel;
using System.Diagnostics;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Notepad.Core;
using Windows.Foundation;

namespace IntelligentNotepad;

// D01 T01 §3: the tab strip. Renders TabModel through a WinUI TabView with one
// manually built TabViewItem per Tab (Tag holds the model tab), so the
// container mapping is exact. Every gesture below was recorded live from
// Notepad 11.2607.14.0 (2026-09-14): Ctrl+T new tab; Ctrl+W close (selection
// falls to the neighbor); Ctrl+Tab / Ctrl+Shift+Tab cycle sequentially (not
// MRU); Ctrl+1..8 positional, Ctrl+9 last tab; Ctrl+Shift+T reopens (empty
// untitled and Don't-save closes never restore); right-click menu holds New
// tab / Close tab / Close other tabs / Close tabs to the right; middle-click
// closes; overflow shrinks tab widths with no scroll UI; drag does NOT
// reorder (three negative probes), so CanReorderTabs stays off as parity.
public sealed partial class TabBar : UserControl
{
    public static readonly DependencyProperty ModelProperty =
        DependencyProperty.Register(nameof(Model), typeof(TabModel), typeof(TabBar), new PropertyMetadata(null, OnModelChanged));

    public TabModel? Model
    {
        get => (TabModel?)GetValue(ModelProperty);
        set => SetValue(ModelProperty, value);
    }

    // Per-tab content boxes. §3 scaffolding: the TextBox stands in for the
    // D02 T01 editor so switching, dirty tracking, and the close prompt are
    // drivable now. D02 replaces ContentFor callers with the real editor.
    readonly Dictionary<Guid, TextBox> boxes = new();

    // Header parts per tab, refreshed on Tab.PropertyChanged.
    readonly Dictionary<Guid, (FrameworkElement Dot, TextBlock Name)> headers = new();

    readonly HashSet<Guid> hovered = new();

    bool syncingSelection;

    public TabBar()
    {
        InitializeComponent();
        Tabs.AddTabButtonCommand = new RelayCommand(_ => Model?.NewTab());
        Tabs.RightTapped += Tabs_RightTapped;
        Tabs.LayoutUpdated += (_, _) => SyncAddButtonMargin();
    }

    // Shrink-to-fit, owned here because this TabView generation never
    // shrinks on its own: past ~3 tabs it virtualizes into an unlabeled
    // scroll strip, while probed stock Notepad squeezes every tab into view
    // (narrow window, 25 tabs: widths 3..128px, no scroll UI, selected widest
    // at ~29% of the strip). So when the even share drops below the natural
    // cap the bar clamps MaxWidth itself: the selected tab keeps up to 35% of
    // the strip, the rest split the remainder down to a 2-DIP floor (stock
    // squeezes to 3px). Past the floor the strip scrolls; no probe covers
    // that, and the middle-tab distribution between min and max is one more
    // unprobed shape the uniform split approximates.
    internal void ShrinkTabsToFit()
    {
        const double NaturalTabWidth = 134;
        const double MinTabWidth = 2;
        int count = Tabs.TabItems.Count;
        if (count == 0 || Tabs.ActualWidth <= 0)
        {
            return;
        }

        double button = NaturalTabWidth / 3;
        if (Tabs.FindName("AddButton") is FrameworkElement add && add.ActualWidth > 0)
        {
            button = add.ActualWidth;
        }

        double available = Tabs.ActualWidth - button - 8;
        if (available <= 0)
        {
            return;
        }

        if (available / count >= NaturalTabWidth)
        {
            ClampAll(NaturalTabWidth);
            return;
        }

        double selectedWidth = Math.Min(NaturalTabWidth, available * 0.35);
        double rest = count > 1 ? (available - selectedWidth) / (count - 1) : selectedWidth;
        if (rest < MinTabWidth)
        {
            rest = MinTabWidth;
            selectedWidth = Math.Max(MinTabWidth, available - (rest * (count - 1)));
        }

        foreach (object? entry in Tabs.TabItems)
        {
            if (entry is TabViewItem item)
            {
                double target = ReferenceEquals(item.Tag, Model?.ActiveTab) ? selectedWidth : rest;
                item.MinWidth = 0;
                if (Math.Abs(item.MaxWidth - target) > 0.5)
                {
                    item.MaxWidth = target;
                }
            }
        }
    }

    void ClampAll(double maxWidth)
    {
        foreach (object? entry in Tabs.TabItems)
        {
            if (entry is TabViewItem item)
            {
                item.MinWidth = 0;
                if (Math.Abs(item.MaxWidth - maxWidth) > 0.5)
                {
                    item.MaxWidth = maxWidth;
                }
            }
        }
    }

    // Caption inset, in DIP: the TabView ends where the system caption
    // buttons begin, so a full strip parks the add button left of minimize
    // instead of under maximize (12 probed tabs put the add center 67 DIP
    // inside the caption zone). Shrink-to-fit and TabStripContentRight both
    // read the narrowed TabView, so no other math changes. MainWindow feeds
    // this from AppWindow.TitleBar.RightInset on every layout.
    double lastCaptionInset = -1;

    internal void SetCaptionInset(double dip)
    {
        double inset = Math.Max(0, dip);
        if (Math.Abs(inset - lastCaptionInset) < 0.5)
        {
            return;
        }

        lastCaptionInset = inset;
        Tabs.Margin = new Thickness(0, 0, inset, 0);
    }

    // Add-button vertical placement, per layout. With tabs the button
    // hugs the strip bottom beside the bottom-hugged tab items (stock's
    // add glyph centers 25.5 DIP with its text at 26.5). With no tabs the
    // strip row collapses and the template parks the button top-hugged
    // (probed 36px tall at strip top), so it is re-margined to the strip
    // middle; stock has no zero-tab state (last close quits), so centered
    // is the target by construction. Idempotent: steady state recomputes
    // the same values and skips the sets, so the per-layout call cannot
    // loop. Kept out of ShrinkTabsToFit (widths only) deliberately.
    Thickness? addButtonMargin;

    bool zeroTabMarginApplied;

    bool syncPending;

    // Template-part lookup by visual walk: Tabs.FindName cannot see the
    // add button (template namescope), so match its x:Name instead. (The
    // UIA AutomationId reads AddButton too, but that comes from the peer,
    // not the attached property.) Breadth-first, returns the first hit.
    Button? FindAddButton()
    {
        Queue<DependencyObject> queue = new();
        queue.Enqueue(Tabs);
        while (queue.Count > 0)
        {
            DependencyObject current = queue.Dequeue();
            int count = VisualTreeHelper.GetChildrenCount(current);
            for (int i = 0; i < count; i++)
            {
                DependencyObject child = VisualTreeHelper.GetChild(current, i);
                if (child is Button candidate && candidate.Name == "AddButton")
                {
                    return candidate;
                }

                queue.Enqueue(child);
            }
        }

        return null;
    }

    // LayoutUpdated entry: never touch the template part synchronously.
    // Setting its alignment or margin inside layout dispatch reenters
    // the TabView mid-transition (last-tab close) and dies native
    // 0xC000027B, so the apply runs one dispatch later. The pending
    // flag collapses a layout storm into one apply; the apply is
    // idempotent, so the re-layout it triggers settles.
    void SyncAddButtonMargin()
    {
        if (syncPending)
        {
            return;
        }

        syncPending = true;
        if (!DispatcherQueue.TryEnqueue(() =>
        {
            syncPending = false;
            ApplyAddButtonPlacement();
        }))
        {
            syncPending = false;
        }
    }

    void ApplyAddButtonPlacement()
    {
        // Template-part touches stow native 0xC000027B while the strip
        // is mid-transition (last-tab close), so both this walk and the
        // transform below catch the stowed COMException, not just the
        // managed disconnect InvalidOperationException.
        Button? found;
        try
        {
            found = FindAddButton();
        }
        catch (Exception ex) when (ex is InvalidOperationException or System.Runtime.InteropServices.COMException)
        {
            return;
        }

        if (found is not Button add)
        {
            return;
        }

        if (Tabs.TabItems.Count != 0)
        {
            if (add.VerticalAlignment != VerticalAlignment.Bottom)
            {
                add.VerticalAlignment = VerticalAlignment.Bottom;
            }

            if (zeroTabMarginApplied && addButtonMargin.HasValue)
            {
                add.Margin = addButtonMargin.Value;
                zeroTabMarginApplied = false;
            }

            return;
        }

        if (add.ActualHeight <= 0 || Tabs.ActualHeight <= 0)
        {
            return;
        }

        if (add.VerticalAlignment != VerticalAlignment.Center)
        {
            add.VerticalAlignment = VerticalAlignment.Center;
        }

        addButtonMargin ??= add.Margin;
        double offsetY;
        try
        {
            offsetY = add.TransformToVisual(Tabs).TransformPoint(new Point(0, 0)).Y - add.Margin.Top;
        }
        catch (Exception ex) when (ex is InvalidOperationException or System.Runtime.InteropServices.COMException)
        {
            return;
        }

        double top = Math.Max(0, (Tabs.ActualHeight - add.ActualHeight) / 2 - offsetY);
        Thickness next = new(addButtonMargin.Value.Left, top, addButtonMargin.Value.Right, addButtonMargin.Value.Bottom);
        if (!next.Equals(add.Margin))
        {
            add.Margin = next;
        }

        zeroTabMarginApplied = true;
    }

    // Right edge, in DIP, of the interactive strip (tabs plus the add
    // button). MainWindow drags the window from everything right of here.
    internal double TabStripContentRight()
    {
        double right = 0;
        try
        {
            foreach (object? entry in Tabs.TabItems)
            {
                if (entry is TabViewItem item)
                {
                    Rect bounds = item.TransformToVisual(this).TransformBounds(new Rect(0, 0, item.ActualWidth, item.ActualHeight));
                    right = Math.Max(right, bounds.Right);
                }
            }

            if (Tabs.FindName("AddButton") is FrameworkElement add)
            {
                Rect bounds = add.TransformToVisual(this).TransformBounds(new Rect(0, 0, add.ActualWidth, add.ActualHeight));
                right = Math.Max(right, bounds.Right);
            }
            else
            {
                right += 40;
            }
        }
        catch (InvalidOperationException)
        {
            // Visuals disconnecting mid-pass (teardown, container recycle):
            // keep the last good edge; the next pass recomputes.
        }

        return right;
    }

    // Top, in DIP and TabView-relative, of the highest strip content
    // (tab items or the add button). Bottom-hugged content leaves a drag
    // band above it; MainWindow covers that band with a second drag rect
    // so no dead clicks appear. Zero when nothing is found (no band, the
    // safe fallback).
    internal double TabStripContentTop()
    {
        double top = 0;
        bool found = false;
        try
        {
            foreach (object? entry in Tabs.TabItems)
            {
                if (entry is TabViewItem item)
                {
                    Rect bounds = item.TransformToVisual(Tabs).TransformBounds(new Rect(0, 0, item.ActualWidth, item.ActualHeight));
                    top = found ? Math.Min(top, bounds.Top) : bounds.Top;
                    found = true;
                }
            }

            if (FindAddButton() is Button add)
            {
                Rect bounds = add.TransformToVisual(Tabs).TransformBounds(new Rect(0, 0, add.ActualWidth, add.ActualHeight));
                top = found ? Math.Min(top, bounds.Top) : bounds.Top;
                found = true;
            }
        }
        catch (Exception ex) when (ex is InvalidOperationException or System.Runtime.InteropServices.COMException)
        {
        }

        return found ? Math.Max(0, top) : 0;
    }

    // Raised on every content-box edit, including keystrokes that change
    // neither FirstLine nor IsDirty (same first line, already dirty): the
    // model events skip those, but the §7 crash checkpoint must see them.
    // MainWindow forwards to the App debounce; restore-time programmatic
    // sets may or may not fire (pre-show boxes are unreliable raisers)
    // and need no checkpoint anyway (restored state is already filed).
    public event EventHandler? TabsEdited;

    // The box MainWindow shows in the editor region for the active tab.
    public TextBox ContentFor(Tab tab)
    {
        ArgumentNullException.ThrowIfNull(tab);
        if (!boxes.TryGetValue(tab.Id, out TextBox? box))
        {
            box = new TextBox
            {
                AcceptsReturn = true,
                TextWrapping = TextWrapping.NoWrap,
                BorderThickness = new Thickness(0),
                HorizontalAlignment = HorizontalAlignment.Stretch,
                VerticalAlignment = VerticalAlignment.Stretch,
            };
            AutomationProperties.SetAutomationId(box, "TabContentBox");
            box.TextChanged += (_, _) =>
            {
                tab.NotifyEdited(box.Text);
                TabsEdited?.Invoke(this, EventArgs.Empty);
            };
            boxes[tab.Id] = box;
        }

        return box;
    }

    public void NewTab() => Model?.NewTab();

    public void CycleNext() => Cycle(1);

    public void CyclePrevious() => Cycle(-1);

    // Ctrl+1..8 select positionally; Ctrl+9 selects the last tab (probed).
    // Out-of-range numbers are no-ops.
    public void GotoNumber(int number)
    {
        if (Model is not TabModel model || model.Tabs.Count == 0)
        {
            return;
        }

        int index = number >= 9 ? model.Tabs.Count - 1 : number - 1;
        if (index >= 0 && index < model.Tabs.Count)
        {
            model.ActiveTab = model.Tabs[index];
        }
    }

    public void ReopenLast()
    {
        if (Model is not TabModel model)
        {
            return;
        }

        model.Closed.TryPeek(out ClosedTab? peek);
        Tab? tab = model.ReopenLast();
        if (tab is null || peek is null)
        {
            return;
        }

        TextBox box = ContentFor(tab);
        if (peek.Contents is not null)
        {
            // Re-fires NotifyEdited with the same content the model already
            // recorded; the tab state is unchanged by the duplicate call.
            box.Text = peek.Contents;
            box.SelectionStart = Math.Min(peek.CaretOffset, box.Text.Length);
        }
        // Clean saved tabs reopen contentless until §4 wires file loading;
        // the tab shows its file name with an empty box.
    }

    public void RequestCloseActive()
    {
        if (Model?.ActiveTab is Tab active)
        {
            _ = RequestCloseAsync(active);
        }
    }

    // True unless the user cancelled; batch closes (others/right) abort on Cancel.
    // Cancel-aborts-everything is a default: multi-dirty batch behavior is
    // unprobed. Cost of changing: the loop below plus its drive.
    public async Task<bool> RequestCloseAsync(Tab tab)
    {
        ArgumentNullException.ThrowIfNull(tab);
        if (Model is not TabModel model || !model.Tabs.Contains(tab))
        {
            return true;
        }

        if (!tab.IsDirty)
        {
            CloseClean(tab, model);
            return true;
        }

        switch (await AskSaveAsync(tab).ConfigureAwait(true))
        {
            case SaveAnswer.Save:
                return TrySaveAndClose(tab, model);
            case SaveAnswer.DontSave:
                boxes.Remove(tab.Id);
                model.CloseTab(tab, null, 0, discardUnsaved: true);
                return true;
            case SaveAnswer.Cancel:
            default:
                return false;
        }
    }

    // Save half of the §7 answer matrix. Pathed tabs save in place via
    // the §5 engine and close; untitled tabs stay open because stock
    // answers with the Save As dialog, which lands with D01 T02 §1
    // (the keep-open cancel-outcome, probed, loses nothing). Redirects
    // (locked/read-only need the same dialog) and failures (reported
    // at T02 §1-time) also keep the tab open. Every keep-open path
    // returns true: the user vetoed nothing, so batch closes continue
    // past them instead of aborting.
    bool TrySaveAndClose(Tab tab, TabModel model)
    {
        if (tab.FilePath is null)
        {
            return true;
        }

        string text = boxes.TryGetValue(tab.Id, out TextBox? box) ? box.Text ?? string.Empty : string.Empty;
        var spec = new SaveSpec(tab.Encoding, tab.HasBom, tab.LineEnding);
        switch (FileSave.SaveFile(tab.FilePath, text, spec))
        {
            case SaveSuccess:
                tab.ApplySave(tab.FilePath, spec);
                CloseClean(tab, model);
                return true;
            case SaveRedirect redirect:
                Debug.WriteLine($"Save redirected to Save As, tab kept: {redirect.Detail}");
                return true;
            case SaveFailed failed:
                Debug.WriteLine($"Save failed, tab kept: {failed.Detail}");
                return true;
            default:
                return true;
        }
    }

    public async Task CloseOthersAsync(Tab keep)
    {
        ArgumentNullException.ThrowIfNull(keep);
        if (Model is not TabModel model)
        {
            return;
        }

        foreach (Tab tab in model.Tabs.Where(tab => !ReferenceEquals(tab, keep)).ToList())
        {
            if (!await RequestCloseAsync(tab).ConfigureAwait(true))
            {
                return;
            }
        }
    }

    public async Task CloseRightAsync(Tab keep)
    {
        ArgumentNullException.ThrowIfNull(keep);
        if (Model is not TabModel model)
        {
            return;
        }

        int index = model.Tabs.IndexOf(keep);
        if (index < 0)
        {
            return;
        }

        foreach (Tab tab in model.Tabs.Skip(index + 1).ToList())
        {
            if (!await RequestCloseAsync(tab).ConfigureAwait(true))
            {
                return;
            }
        }
    }

    static void OnModelChanged(DependencyObject d, DependencyPropertyChangedEventArgs e)
    {
        var bar = (TabBar)d;
        if (e.OldValue is TabModel oldModel)
        {
            oldModel.PropertyChanged -= bar.Model_PropertyChanged;
            oldModel.Tabs.CollectionChanged -= bar.Model_CollectionChanged;
            foreach (Tab dead in oldModel.Tabs)
            {
                dead.PropertyChanged -= bar.Tab_PropertyChanged;
            }
        }

        bar.Tabs.TabItems.Clear();
        bar.headers.Clear();
        bar.hovered.Clear();
        bar.boxes.Clear();
        if (e.NewValue is TabModel newModel)
        {
            newModel.PropertyChanged += bar.Model_PropertyChanged;
            newModel.Tabs.CollectionChanged += bar.Model_CollectionChanged;
            for (int i = 0; i < newModel.Tabs.Count; i++)
            {
                bar.InsertContainer(i, newModel.Tabs[i]);
            }

            bar.SyncSelectionFromModel();
        }
    }

    void Model_CollectionChanged(object? sender, NotifyCollectionChangedEventArgs e)
    {
        switch (e.Action)
        {
            case NotifyCollectionChangedAction.Add:
                for (int i = 0; i < e.NewItems!.Count; i++)
                {
                    InsertContainer(e.NewStartingIndex + i, (Tab)e.NewItems[i]!);
                }

                break;
            case NotifyCollectionChangedAction.Remove:
                foreach (Tab tab in e.OldItems!)
                {
                    RemoveContainer(tab);
                }

                break;
            case NotifyCollectionChangedAction.Reset:
                Tabs.TabItems.Clear();
                headers.Clear();
                if (Model is not null)
                {
                    for (int i = 0; i < Model.Tabs.Count; i++)
                    {
                        InsertContainer(i, Model.Tabs[i]);
                    }
                }

                break;
        }

        ShrinkTabsToFit();
    }

    void Model_PropertyChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName == nameof(TabModel.ActiveTab))
        {
            SyncSelectionFromModel();
        }
    }

    void InsertContainer(int index, Tab tab)
    {
        // Grid, not StackPanel: the panel measures children unconstrained and
        // would block the strip's shrink-to-fit (probed stock behavior is
        // shrink with no scroll UI, down to single-digit widths). The star
        // column lets the name trim; ellipsis-vs-clip when squeezed is
        // unprobed, ellipsis is the default. The dot trails the name on the
        // right: stock shows it where the X was (D01 T01 §2 recon).
        // 6-DIP solid ellipse, not a bullet glyph: stock's dot measures
        // 10-11px at 150% (about 7 DIP with anti-aliasing) while U+2022
        // rendered 5px. The fill is primary text at 55% opacity, which
        // lands stock's sampled 154 gray on the tab background (secondary
        // maxes out at 140, too dark even at full opacity). The brush
        // still tracks the theme where a fixed gray would not.
        Brush dotFill = Application.Current.Resources.TryGetValue("TextFillColorPrimaryBrush", out object? found) && found is Brush themed
            ? themed
            : new SolidColorBrush(Microsoft.UI.Colors.Gray);
        var dot = new Microsoft.UI.Xaml.Shapes.Ellipse { Width = 6, Height = 6, Fill = dotFill, Opacity = 0.55, VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(6, 0, 0, 0) };
        AutomationProperties.SetName(dot, "\u2022");
        var name = new TextBlock { VerticalAlignment = VerticalAlignment.Center, TextTrimming = TextTrimming.CharacterEllipsis };
        var header = new Grid();
        header.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        header.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        Grid.SetColumn(name, 0);
        Grid.SetColumn(dot, 1);
        header.Children.Add(name);
        header.Children.Add(dot);
        // The cap reproduces stock's ~201px normal width (134 DIP at the
        // 150% probe density). Long-name widths are unprobed; the cap is the
        // default. Cost of changing: this constant plus the overflow drive.
        // Bottom-hugged items, not stretched: stock's tabs sit at the
        // strip bottom (tab bottom edge 42, text center 26.5 DIP), while
        // stretched items center 3-4 DIP too high here. MinHeight 34
        // releases the template default (at least the strip height, so
        // Bottom alone is a no-op); items then hug at content height
        // (~58px) with text 2.5px above stock, X aligned with text. Local
        // values, not an ItemContainerStyle, so the default item template
        // keeps applying (a bare style would replace it and unrender
        // the tabs).
        var item = new TabViewItem { Header = header, Tag = tab, MaxWidth = 134, MinHeight = 34, VerticalAlignment = VerticalAlignment.Bottom };
        headers[tab.Id] = (dot, name);
        AutomationProperties.SetName(item, tab.DisplayName);
        // Stock hides the X on dirty tabs until hover (D01 T01 §2 recon), so
        // closability tracks dirty-or-hovered. Keyboard, menu, and middle
        // closes bypass the glyph and work regardless.
        item.PointerEntered += (_, _) =>
        {
            hovered.Add(tab.Id);
            item.IsClosable = true;
        };
        item.PointerExited += (_, _) =>
        {
            hovered.Remove(tab.Id);
            item.IsClosable = !tab.IsDirty;
        };
        // RefreshHeader cannot reach the container before insert, so a tab
        // that arrives dirty (content reopen) would keep the default X.
        item.IsClosable = !tab.IsDirty;
        RefreshHeader(tab);
        Tabs.TabItems.Insert(Math.Min(index, Tabs.TabItems.Count), item);
        tab.PropertyChanged += Tab_PropertyChanged;
    }

    void RemoveContainer(Tab tab)
    {
        tab.PropertyChanged -= Tab_PropertyChanged;
        headers.Remove(tab.Id);
        hovered.Remove(tab.Id);
        for (int i = 0; i < Tabs.TabItems.Count; i++)
        {
            if (Tabs.TabItems[i] is TabViewItem item && ReferenceEquals(item.Tag, tab))
            {
                Tabs.TabItems.RemoveAt(i);
                return;
            }
        }
    }

    void Tab_PropertyChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (sender is Tab tab && e.PropertyName is nameof(Tab.DisplayName) or nameof(Tab.IsDirty))
        {
            RefreshHeader(tab);
        }
    }

    void RefreshHeader(Tab tab)
    {
        if (headers.TryGetValue(tab.Id, out (FrameworkElement Dot, TextBlock Name) parts))
        {
            parts.Dot.Visibility = tab.IsDirty ? Visibility.Visible : Visibility.Collapsed;
            parts.Name.Text = tab.DisplayName;
        }

        if (ContainerFor(tab) is TabViewItem item)
        {
            AutomationProperties.SetName(item, tab.DisplayName);
            item.IsClosable = hovered.Contains(tab.Id) || !tab.IsDirty;
        }
    }

    TabViewItem? ContainerFor(Tab tab)
    {
        foreach (object? entry in Tabs.TabItems)
        {
            if (entry is TabViewItem item && ReferenceEquals(item.Tag, tab))
            {
                return item;
            }
        }

        return null;
    }

    void SyncSelectionFromModel()
    {
        syncingSelection = true;
        try
        {
            Tabs.SelectedItem = Model?.ActiveTab is Tab active ? ContainerFor(active) : null;
        }
        finally
        {
            syncingSelection = false;
        }
    }

    void Tabs_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (syncingSelection || Model is null)
        {
            return;
        }

        if (Tabs.SelectedItem is TabViewItem item && item.Tag is Tab tab)
        {
            Model.ActiveTab = tab;
        }

        ShrinkTabsToFit();
    }

    void Cycle(int step)
    {
        if (Model is not TabModel model || model.ActiveTab is not Tab active)
        {
            return;
        }

        int index = model.Tabs.IndexOf(active);
        if (index < 0 || model.Tabs.Count < 2)
        {
            return;
        }

        model.ActiveTab = model.Tabs[(index + step + model.Tabs.Count) % model.Tabs.Count];
    }

    void CloseClean(Tab tab, TabModel model)
    {
        int caret = boxes.TryGetValue(tab.Id, out TextBox? box) ? box.SelectionStart : 0;
        boxes.Remove(tab.Id);
        model.CloseTab(tab, null, caret, discardUnsaved: false);
    }

    // The prompt names a saved tab by its FULL PATH (probed 2026-09-15:
    // the message carries "C:\...\file.txt", capture
    // `notepad-save-prompt-path-n11.2607.14.0-win25h2.png`) and an
    // untitled tab by "{tab-name}.txt" (double-confirmed: §3 FIRST to
    // FIRST.txt plus the §7 FIRSTLINE7 probe).
    static string PromptName(Tab tab) => tab.IsUntitled ? tab.DisplayName + ".txt" : tab.FilePath!;

    async Task<SaveAnswer> AskSaveAsync(Tab tab)
    {
        if (XamlRoot is null)
        {
            return SaveAnswer.Cancel;
        }

        var dialog = new SavePromptDialog(PromptName(tab)) { XamlRoot = XamlRoot };
        return await dialog.ShowAsync() switch
        {
            ContentDialogResult.Primary => SaveAnswer.Save,
            ContentDialogResult.Secondary => SaveAnswer.DontSave,
            _ => SaveAnswer.Cancel,
        };
    }

    void Tabs_TabCloseRequested(TabView sender, TabViewTabCloseRequestedEventArgs args)
    {
        if (args.Tab?.Tag is Tab tab)
        {
            _ = RequestCloseAsync(tab);
        }
    }

    // Middle-click hit-test for MiddleClickHook: the hook owns detection
    // (XAML never sees middle presses), this maps the DIP point in window
    // coordinates onto a tab container. The hook also caches these bounds
    // for its own callback; the live re-test here covers layout drift. The
    // close itself is queued instead of running inline: showing the dirty
    // prompt synchronously inside input dispatch reenters XAML and stows a
    // crash.
    internal bool TryCloseTabAt(Point point)
    {
        if (XamlRoot?.Content is not UIElement root)
        {
            return false;
        }

        try
        {
            foreach (object? entry in Tabs.TabItems)
            {
                if (entry is TabViewItem item && item.Tag is Tab tab)
                {
                    Rect bounds = item.TransformToVisual(root).TransformBounds(new Rect(0, 0, item.ActualWidth, item.ActualHeight));
                    if (bounds.Contains(point))
                    {
                        if (Microsoft.UI.Dispatching.DispatcherQueue.GetForCurrentThread() is { } queue)
                        {
                            queue.TryEnqueue(() => _ = RequestCloseAsync(tab));
                        }
                        else
                        {
                            _ = RequestCloseAsync(tab);
                        }

                        return true;
                    }
                }
            }
        }
        catch (InvalidOperationException)
        {
            // A disconnected visual mid-click: miss the close rather than
            // throw out of the window proc, which stows a fatal crash.
        }

        return false;
    }

    // Tab bounds in window DIP for the hook's cache. Same mapping as
    // TryCloseTabAt; disconnects mid-pass yield no bounds, never a throw.
    internal IReadOnlyList<Rect> TabHitRects()
    {
        var rects = new List<Rect>();
        if (XamlRoot?.Content is not UIElement root)
        {
            return rects;
        }

        try
        {
            foreach (object? entry in Tabs.TabItems)
            {
                if (entry is TabViewItem item)
                {
                    rects.Add(item.TransformToVisual(root).TransformBounds(new Rect(0, 0, item.ActualWidth, item.ActualHeight)));
                }
            }
        }
        catch (InvalidOperationException)
        {
            rects.Clear();
        }

        return rects;
    }

    // Right-click acts on the clicked tab without changing selection, and the
    // items match live Notepad exactly. Whether stock also selects on
    // right-click is unprobed; the browser convention (no select) is the
    // default. Cost of changing: one line plus its drive.
    void Tabs_RightTapped(object sender, RightTappedRoutedEventArgs e)
    {
        if (e.OriginalSource is not DependencyObject source
            || FindAncestor<TabViewItem>(source) is not TabViewItem item
            || item.Tag is not Tab tab
            || Model is null)
        {
            return;
        }

        var flyout = new MenuFlyout();
        flyout.Items.Add(FlyoutItem("New tab", NewTab));
        flyout.Items.Add(FlyoutItem("Close tab", () => _ = RequestCloseAsync(tab)));
        flyout.Items.Add(FlyoutItem("Close other tabs", () => _ = CloseOthersAsync(tab)));
        flyout.Items.Add(FlyoutItem("Close tabs to the right", () => _ = CloseRightAsync(tab)));
        flyout.ShowAt(item);
    }

    static MenuFlyoutItem FlyoutItem(string text, Action action)
    {
        var item = new MenuFlyoutItem { Text = text };
        item.Click += (_, _) => action();
        return item;
    }

    static T? FindAncestor<T>(DependencyObject? node)
        where T : DependencyObject
    {
        while (node is not null)
        {
            if (node is T match)
            {
                return match;
            }

            node = VisualTreeHelper.GetParent(node);
        }

        return null;
    }

    enum SaveAnswer
    {
        Save,
        DontSave,
        Cancel,
    }
}
