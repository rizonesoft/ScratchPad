using FlaUI.Core;
using FlaUI.Core.AutomationElements;
using FlaUI.Core.Tools;
using FlaUI.UIA3;
using Notepad.Core;
using Xunit;

namespace UI;

// D00 T02 §21 item 11: the shortcut text each menu item displays (its
// UIA AcceleratorKey, which WinUI derives from the KeyboardAccelerator
// when no override exists) matches the binding manifest. Read on the
// rendered menu of a background window: menus open through Invoke and
// ExpandCollapse, never focus. Stock-text parity (Del vs Delete,
// Ctrl+Plus vs Ctrl++) is D01 T02 §6's audit, not this check.
// D00 T02 §28 items 8 and 9: the same read checks each bound item's
// accessible name and description against the XAML, and reads every
// disabled exemption in three representative states (fresh window,
// file open, selection present), failing as soon as one is usable.
// Since D00 T02 §36 item 7 the states come from the audit's Enablement
// states table, where owners declare their own (read-only document,
// text edited twice).
[Collection("UI tests")]
public sealed class MenuLabelTests
{
    static readonly (string Top, string? Sub)[] Menus =
    [
        ("MenuFile", null),
        ("MenuEdit", null),
        ("MenuView", "MenuViewZoom"),
        ("MenuTools", null),
    ];

    sealed record Read(string Accelerator, BindingManifest.ItemText Text, bool Enabled);

    [Fact]
    public void DisplayedShortcutTextMatchesTheManifest()
    {
        string root = BindingManifestTests.RepoRoot();
        string xaml = File.ReadAllText(Path.Combine(root, BindingManifest.MenuXamlPath));
        var decls = BindingManifest.ParseMenuXaml(xaml, out _, out var parse);
        Assert.Empty(parse);
        var expected = decls.GroupBy(d => d.Command).ToDictionary(g => g.Key, g => BindingManifest.ExpectedLabel(g.First().Chord), StringComparer.Ordinal);
        var reads = WithApp(null, window => ReadBound(window, expected.Keys));
        var seen = reads.ToDictionary(r => r.Key, r => r.Value.Accelerator, StringComparer.Ordinal);
        Assert.Equal(expected.Keys.Order(StringComparer.Ordinal), seen.Keys.Order(StringComparer.Ordinal));
        Assert.Empty(BindingManifestTests.LabelMismatches(expected, seen));
        Assert.Empty(BindingManifest.AccessibleTextMismatches(
            expected.Keys,
            BindingManifest.ParseMenuItemText(xaml),
            reads.ToDictionary(r => r.Key, r => r.Value.Text, StringComparer.Ordinal)));
    }

    [Fact]
    public void DisabledExemptionsHoldAcrossEnablementStates()
    {
        string root = BindingManifestTests.RepoRoot();
        var rows = BindingManifest.ParseAudit(File.ReadAllText(Path.Combine(root, "docs", "ui-input-audit.md")), out var parse);
        Assert.Empty(parse);
        var ids = rows.Where(r => r.Class == "disabled").Select(r => r.Command).Distinct(StringComparer.Ordinal).ToList();
        Assert.NotEmpty(ids);
        // The states come from the audit's Enablement states table: §28's
        // three plus owner-declared ones (D00 T02 §36 item 7).
        var states = BindingManifest.SubTable(File.ReadAllText(Path.Combine(root, "docs", "ui-input-audit.md")), "Enablement states", 3, out var stateParse);
        Assert.Empty(stateParse);
        var observations = new List<BindingManifest.StateObservation>();
        foreach (string[] state in states)
        {
            Observe(observations, state[0], BuildState(state[1], window => ReadBound(window, ids)));
        }

        Assert.Empty(BindingManifest.EnablementProblems(rows, observations, states.Select(s => s[0])));
    }

    // D00 T02 §43 item 5 (R1-F2): enablement is read across a transition,
    // over every bound menu item, not only the always-disabled rows. The
    // read-only document is entered (its documented enablement: every
    // `disabled` row reads disabled) and left by closing it back to the
    // writable tab, which must read every item exactly as the writable
    // baseline in its own fresh window does; a selection is entered and
    // left in one window, which must read as it did before.
    [Fact]
    public void LeavingAStateRestoresEveryItemsEnablement()
    {
        string root = BindingManifestTests.RepoRoot();
        var rows = BindingManifest.ParseAudit(File.ReadAllText(Path.Combine(root, "docs", "ui-input-audit.md")), out var parse);
        Assert.Empty(parse);
        var disabled = rows.Where(r => r.Class == "disabled").Select(r => r.Command).Distinct(StringComparer.Ordinal).ToList();
        var all = rows.Where(r => r.Command.StartsWith("Menu", StringComparison.Ordinal)).Select(r => r.Command).Distinct(StringComparer.Ordinal).ToList();
        Assert.True(all.Count > disabled.Count, "the audit names no enabled menu command, so a transition read proves nothing");
        string writable = Path.Combine(Path.GetTempPath(), $"scratchpad-transition-w-{Guid.NewGuid():N}.txt");
        string readOnly = Path.Combine(Path.GetTempPath(), $"scratchpad-transition-r-{Guid.NewGuid():N}.txt");
        File.WriteAllText(writable, "writable" + Environment.NewLine);
        File.WriteAllText(readOnly, "read-only" + Environment.NewLine);
        File.SetAttributes(readOnly, FileAttributes.ReadOnly);
        try
        {
            var baseline = WithApp($"\"{writable}\"", window => ReadBound(window, all));
            var (inReadOnly, afterLeaving) = WithApp($"\"{writable}\" \"{readOnly}\"", window =>
            {
                Assert.Contains("scratchpad-transition-r-", window.Title, StringComparison.Ordinal);
                var ro = ReadBound(window, all);
                UiInput.InvokeMenuItem(window, "MenuFile", "MenuFileCloseTab");
                Assert.True(Retry.WhileFalse(() => window.Title.Contains("scratchpad-transition-w-", StringComparison.Ordinal), TimeSpan.FromSeconds(10), TimeSpan.FromMilliseconds(200)).Result, $"closing the read-only tab did not return to the writable one: {window.Title}");
                return (ro, ReadBound(window, all));
            });
            foreach (string id in disabled)
            {
                Assert.True(inReadOnly.TryGetValue(id, out Read? r) && !r.Enabled, $"{id} is documented disabled but reads {(r?.Enabled == true ? "enabled" : "unread")} in the read-only document");
            }

            // Every expected item is read in every state before any
            // comparison (R2-F2), so a command missing from a read never
            // escapes the check.
            foreach (var (name, reads) in new[] { ("the writable baseline", baseline), ("the read-only document", inReadOnly), ("the writable tab after leaving", afterLeaving) })
            {
                var missing = all.Where(id => !reads.ContainsKey(id)).ToList();
                Assert.True(missing.Count == 0, $"{name} did not read {missing.Count} bound item(s): {string.Join(", ", missing)}");
            }
            foreach (var (id, read) in baseline)
            {
                Assert.True(afterLeaving.TryGetValue(id, out Read? back), $"{id} was not read after leaving the read-only document");
                Assert.True(back.Enabled == read.Enabled, $"{id} reads {(back.Enabled ? "enabled" : "disabled")} after leaving the read-only document, but {(read.Enabled ? "enabled" : "disabled")} in the writable baseline");
            }

            var (before, selected, cleared) = WithApp(null, window =>
            {
                var box = ContentBox(window);
                UiInput.AppendText(box, "transition text");
                var pre = ReadBound(window, all);
                UiInput.SelectAllText(box);
                var sel = ReadBound(window, all);
                UiInput.ClearSelection(box);
                return (pre, sel, ReadBound(window, all));
            });
            foreach (var (name, reads) in new[] { ("before the selection", before), ("with the selection", selected), ("after clearing it", cleared) })
            {
                var missing = all.Where(id => !reads.ContainsKey(id)).ToList();
                Assert.True(missing.Count == 0, $"{name} did not read {missing.Count} bound item(s): {string.Join(", ", missing)}");
            }
            foreach (var (id, read) in before)
            {
                Assert.True(cleared.TryGetValue(id, out Read? back) && back.Enabled == read.Enabled, $"{id} reads {(cleared.TryGetValue(id, out Read? c) && c.Enabled ? "enabled" : "disabled")} after the selection was cleared, but {(read.Enabled ? "enabled" : "disabled")} before it was made");
            }
        }
        finally
        {
            File.SetAttributes(readOnly, FileAttributes.Normal);
            File.Delete(readOnly);
            File.Delete(writable);
        }
    }

    // Builds one named setup in a fresh app and reads the bound items there.
    static Dictionary<string, Read> BuildState(string setup, Func<Window, Dictionary<string, Read>> read)
    {
        switch (setup)
        {
            case "launch":
                return WithApp(null, read);
            case "select-text":
                return WithApp(null, window =>
                {
                    var box = ContentBox(window);
                    UiInput.AppendText(box, "selected text");
                    UiInput.SelectAllText(box);
                    Assert.False(string.IsNullOrEmpty(box.Patterns.Text.Pattern.GetSelection().FirstOrDefault()?.GetText(-1)), "the selection state has no selection");
                    return read(window);
                });
            case "edit-twice":
                return WithApp(null, window =>
                {
                    var box = ContentBox(window);
                    UiInput.AppendText(box, "first edit");
                    UiInput.AppendText(box, " second edit");
                    Assert.Equal("first edit second edit", box.Text);
                    return read(window);
                });
            case "open-file":
            case "open-read-only":
                string file = Path.Combine(Path.GetTempPath(), $"scratchpad-enablement-{Guid.NewGuid():N}.txt");
                File.WriteAllText(file, "file open state\n");
                try
                {
                    if (setup == "open-read-only")
                    {
                        File.SetAttributes(file, FileAttributes.ReadOnly);
                    }

                    return WithApp($"\"{file}\"", read);
                }
                finally
                {
                    File.SetAttributes(file, FileAttributes.Normal);
                    File.Delete(file);
                }

            default:
                Assert.Fail($"enablement setup '{setup}' has no builder");
                return [];
        }
    }

    static void Observe(List<BindingManifest.StateObservation> into, string state, Dictionary<string, Read> reads)
    {
        foreach (var (id, read) in reads)
        {
            into.Add(new BindingManifest.StateObservation(state, id, read.Enabled));
        }
    }

    static T WithApp<T>(string? args, Func<Window, T> body)
    {
        UiLaunch.SeedSettings(new ShellSettings { WhatsNewSeen = true });
        nint fgBefore = UiForeground.Capture();
        using Application app = args is null ? UiLaunch.LaunchApp() : UiLaunch.LaunchAppWithArgs(args);
        using var automation = new UIA3Automation();
        var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
        UiForeground.Background(window, fgBefore);
        Assert.NotNull(window);
        try
        {
            return body(window);
        }
        finally
        {
            try
            {
                window.Close();
            }
            catch (Exception ex) when (ex is InvalidOperationException or FlaUI.Core.Exceptions.FlaUIException)
            {
                // Already gone.
            }

            if (!app.HasExited)
            {
                app.Kill();
            }
        }
    }

    // Opens each menu (and the Zoom submenu) and reads every wanted id
    // it renders: accelerator text, accessible name and description,
    // and enablement.
    static Dictionary<string, Read> ReadBound(Window window, IEnumerable<string> wanted)
    {
        var ids = wanted.ToList();
        var seen = new Dictionary<string, Read>(StringComparer.Ordinal);
        foreach (var (top, sub) in Menus)
        {
            OpenMenu(window, top);
            if (sub is not null)
            {
                var subItem = Retry.WhileNull(
                    () => window.FindFirstDescendant(cf => cf.ByAutomationId(sub)),
                    TimeSpan.FromSeconds(5),
                    TimeSpan.FromMilliseconds(250)).Result;
                Assert.NotNull(subItem);
                subItem.Patterns.ExpandCollapse.Pattern.Expand();
                Thread.Sleep(600);
            }

            foreach (string id in ids)
            {
                var item = window.FindFirstDescendant(cf => cf.ByAutomationId(id));
                if (item is not null)
                {
                    seen[id] = new Read(
                        item.Properties.AcceleratorKey.ValueOrDefault ?? string.Empty,
                        new BindingManifest.ItemText(item.Properties.Name.ValueOrDefault ?? string.Empty, item.Properties.HelpText.ValueOrDefault ?? string.Empty),
                        item.IsEnabled);
                }
            }

            CloseMenu(window, top);
        }

        return seen;
    }

    static TextBox ContentBox(Window window)
    {
        var box = Retry.WhileNull(
            () => window.FindFirstDescendant(cf => cf.ByAutomationId("TabContentBox"))?.AsTextBox(),
            TimeSpan.FromSeconds(10),
            TimeSpan.FromMilliseconds(250)).Result;
        Assert.NotNull(box);
        return box;
    }

    static void OpenMenu(Window window, string topId)
    {
        var top = window.FindFirstDescendant(cf => cf.ByAutomationId(topId));
        Assert.NotNull(top);
        top.Patterns.Invoke.Pattern.Invoke();
        Thread.Sleep(600);
        var expand = top.Patterns.ExpandCollapse.PatternOrDefault;
        if (expand is not null && expand.ExpandCollapseState != FlaUI.Core.Definitions.ExpandCollapseState.Expanded)
        {
            top.Patterns.Invoke.Pattern.Invoke();
            Thread.Sleep(600);
        }
    }

    static void CloseMenu(Window window, string topId)
    {
        var top = window.FindFirstDescendant(cf => cf.ByAutomationId(topId));
        var expand = top?.Patterns.ExpandCollapse.PatternOrDefault;
        if (top is not null && (expand is null || expand.ExpandCollapseState == FlaUI.Core.Definitions.ExpandCollapseState.Expanded))
        {
            top.Patterns.Invoke.Pattern.Invoke();
            Thread.Sleep(400);
        }
    }
}
