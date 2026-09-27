using System.Text.RegularExpressions;
using FlaUI.Core.AutomationElements;
using FlaUI.Core.Definitions;
using FlaUI.Core.Tools;
using FlaUI.UIA3;
using Notepad.Core;
using Xunit;

namespace UI;

// D01 T02 §6: docs/menu-audit.md is the menu's completeness contract, and
// these tests keep it true. The live menu must match the table item for
// item (id, label, order, enablement by status); every working row names
// a test whose source drives that item; every pending or owner-owed owner
// is still an open plan row (an owner that shipped and left its item dead
// fails here); and the in-window working items are invoked through the
// real menu, focus-free. A newly dead item fails the run.
[Collection("UI tests")]
public sealed partial class MenuAuditTests
{
    internal sealed record AuditRow(int Line, string Menu, string Label, string Id, string Status, string Proof);

    static readonly string[] Statuses = ["working", "container", "owner-owed", "pending"];

    [Fact]
    public void MenuAuditTableIsWellFormed()
    {
        var rows = LoadRows();
        Assert.NotEmpty(rows);
        var problems = new List<string>();
        foreach (var dup in rows.GroupBy(r => r.Id).Where(g => g.Count() > 1))
        {
            problems.Add($"{dup.Key}: {dup.Count()} rows");
        }

        foreach (var row in rows)
        {
            string at = $"docs/menu-audit.md:{row.Line}: {row.Id}";
            if (!Statuses.Contains(row.Status))
            {
                problems.Add($"{at}: status '{row.Status}' is not one of {string.Join(", ", Statuses)}");
            }
            else if (row.Status == "working" && !ProofRef().IsMatch(row.Proof))
            {
                problems.Add($"{at}: a working row names its proof as `Class.Method`, found '{row.Proof}'");
            }
            else if (row.Status is "pending" or "owner-owed" && !OwnerRef().IsMatch(row.Proof))
            {
                problems.Add($"{at}: a {row.Status} row names its owner as `DNN TNN §N`, found '{row.Proof}'");
            }
            else if (row.Status == "container" && row.Proof != "-")
            {
                problems.Add($"{at}: a container row carries '-', found '{row.Proof}'");
            }
        }

        Assert.True(problems.Count == 0, string.Join(Environment.NewLine, problems));
    }

    [Fact]
    public void WorkingProofsDriveTheirItems()
    {
        string root = BindingManifestTests.RepoRoot();
        var problems = new List<string>();
        foreach (var row in LoadRows().Where(r => r.Status == "working"))
        {
            string at = $"docs/menu-audit.md:{row.Line}: {row.Id}";
            var m = ProofRef().Match(row.Proof);
            if (!m.Success)
            {
                problems.Add($"{at}: unparseable proof '{row.Proof}'");
                continue;
            }

            string cls = m.Groups[1].Value;
            string method = m.Groups[2].Value;
            var type = typeof(MenuAuditTests).Assembly.GetType($"UI.{cls}");
            var info = type?.GetMethod(method);
            if (info is null)
            {
                problems.Add($"{at}: proof {cls}.{method} does not exist in the UI suite");
                continue;
            }

            if (info.GetCustomAttributes(typeof(FactAttribute), inherit: true).Length == 0)
            {
                problems.Add($"{at}: proof {cls}.{method} is not a test");
                continue;
            }

            string file = Path.Combine(root, "tests", "UI", cls + ".cs");
            if (!File.Exists(file) || !ProofNamesItem(File.ReadAllLines(file), method, row.Id))
            {
                problems.Add($"{at}: proof {cls}.{method} never names {row.Id} (in its body, its attributes, or a same-class helper it calls)");
            }
        }

        Assert.True(problems.Count == 0, string.Join(Environment.NewLine, problems));
    }

    [Fact]
    public void OwnersAreOpenPlanRows()
    {
        string plan = File.ReadAllText(Path.Combine(BindingManifestTests.RepoRoot(), "todo", "implementation-plan.md"));
        var problems = new List<string>();
        foreach (var row in LoadRows().Where(r => r.Status is "pending" or "owner-owed"))
        {
            string at = $"docs/menu-audit.md:{row.Line}: {row.Id} -> {row.Proof}";
            var m = Regex.Match(plan, @"\|\s*\[(?<box>[ x])\]\s*\|\s*`" + Regex.Escape(row.Proof) + "`");
            if (!m.Success)
            {
                problems.Add($"{at}: the owner has no row in todo/implementation-plan.md");
            }
            else if (m.Groups["box"].Value == "x")
            {
                problems.Add($"{at}: the owner shipped, so the item must be working now (enable it and name its proof)");
            }
        }

        Assert.True(problems.Count == 0, string.Join(Environment.NewLine, problems));
    }

    [Fact]
    public void LiveMenuMatchesTheAudit()
    {
        var rows = LoadRows();
        UiLaunch.SeedSettings(new ShellSettings { WhatsNewSeen = true });
        try
        {
            nint fgBefore = UiForeground.Capture();
            using var app = UiLaunch.LaunchApp();
            using var automation = new UIA3Automation();
            var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
            UiForeground.Background(window, fgBefore);
            Assert.NotNull(window);
            try
            {
                var problems = new List<string>();

                // Every top-level menu on the live bar, audited or not: an
                // unaudited menu is walked too, so its items read as extra.
                var bar = window.FindFirstDescendant(cf => cf.ByAutomationId("MenuRegion"));
                Assert.NotNull(bar);
                var barElements = bar.FindAllChildren(cf => cf.ByControlType(ControlType.MenuItem)).ToList();
                var tops = barElements
                    .Select(t => new LiveItem(KeyOf(t.Properties.AutomationId.ValueOrDefault, t.Name), t.Name, t.IsEnabled))
                    .ToList();
                var expectedTops = rows.Select(r => r.Menu).Distinct().ToList();
                if (!tops.Select(t => t.Id).SequenceEqual(expectedTops.Select(m => "Menu" + m)))
                {
                    problems.Add($"menu bar: live [{string.Join(", ", tops.Select(t => t.Id))}] differs from the audit's menus [{string.Join(", ", expectedTops.Select(m => "Menu" + m))}]");
                }

                foreach (var top in tops.Where(t => expectedTops.Contains(t.Id["Menu".Length..]) && t.Label != t.Id["Menu".Length..]))
                {
                    problems.Add($"menu bar: {top.Id} reads '{top.Label}'");
                }

                foreach (var top in tops)
                {
                    string topId = top.Id;
                    var expected = rows.Where(r => "Menu" + r.Menu == topId).ToList();
                    string menu = topId;
                    var live = WalkMenu(window, topId, expected.Where(r => r.Status == "container").Select(r => r.Id).ToHashSet(), barElements);
                    var liveIds = live.Select(i => i.Id).ToList();
                    var expectedIds = expected.Select(r => r.Id).ToList();
                    if (!liveIds.SequenceEqual(expectedIds))
                    {
                        problems.Add($"{menu}: live order [{string.Join(", ", liveIds)}] differs from the audit [{string.Join(", ", expectedIds)}]");
                    }

                    foreach (var extra in live.Where(i => expected.All(r => r.Id != i.Id)))
                    {
                        problems.Add($"{menu}: live item {extra.Id} ('{extra.Label}') has no audit row");
                    }

                    foreach (var row in expected)
                    {
                        var item = live.FirstOrDefault(i => i.Id == row.Id);
                        string at = $"docs/menu-audit.md:{row.Line}: {row.Id}";
                        if (item is null)
                        {
                            problems.Add($"{at}: not in the live menu");
                            continue;
                        }

                        if (item.Label != row.Label)
                        {
                            problems.Add($"{at}: live label '{item.Label}', audit '{row.Label}'");
                        }

                        bool wantEnabled = row.Status != "pending";
                        if (item.Enabled != wantEnabled)
                        {
                            problems.Add(wantEnabled
                                ? $"{at}: {row.Status} but disabled (a dead item)"
                                : $"{at}: pending on {row.Proof} but enabled (move the row to working with its proof)");
                        }
                    }
                }

                Assert.True(problems.Count == 0, string.Join(Environment.NewLine, problems));
            }
            finally
            {
                MenuBarTests.CloseApp(app, window);
            }
        }
        finally
        {
            SessionData.Delete();
        }
    }

    // The working items whose effect stays inside the window run here
    // through the real menu; items that open OS dialogs, spawn windows or
    // processes, or end the app are driven by the proofs their rows name.
    [Fact]
    public void InWindowItemsInvokeThroughTheMenu()
    {
        string dir = MenuBarTests.NewTempDir();
        UiLaunch.SeedSettings(new ShellSettings { WhatsNewSeen = true });
        try
        {
            string file = MenuBarTests.SeedFile(dir, "audit.txt", "audit body here");
            nint fgBefore = UiForeground.Capture();
            using var app = UiLaunch.LaunchAppWithArgs($"\"{file}\"");
            using var automation = new UIA3Automation();
            var window = UiApp.Attach(app, automation, TimeSpan.FromSeconds(30));
            UiForeground.Background(window, fgBefore);
            Assert.NotNull(window);
            try
            {
                Assert.Equal(2, MenuBarTests.WaitForTabCount(window, 2));

                MenuBarTests.ClickMenuItem(window, "MenuFile", "MenuFileNewTab");
                Assert.Equal(3, MenuBarTests.WaitForTabCount(window, 3));
                MenuBarTests.ClickMenuItem(window, "MenuFile", "MenuFileCloseTab");
                Assert.Equal(2, MenuBarTests.WaitForTabCount(window, 2));

                ToggleStatusBar(window, expectVisible: false);
                ToggleStatusBar(window, expectVisible: true);

                MenuBarTests.OpenMenu(window, "MenuEdit");
                var font = Retry.WhileNull(
                    () => window.FindFirstDescendant(cf => cf.ByAutomationId("MenuEditFont")),
                    TimeSpan.FromSeconds(5),
                    TimeSpan.FromMilliseconds(250)).Result;
                Assert.NotNull(font);
                font.Patterns.Invoke.Pattern.Invoke();
                var back = Retry.WhileNull(
                    () => window.FindFirstDescendant(cf => cf.ByAutomationId("SettingsBackButton")),
                    TimeSpan.FromSeconds(10),
                    TimeSpan.FromMilliseconds(250)).Result;
                Assert.NotNull(back);
                back.Patterns.Invoke.Pattern.Invoke();
                Assert.True(
                    Retry.WhileTrue(
                        () => window.FindFirstDescendant(cf => cf.ByAutomationId("SettingsBackButton")) is not null,
                        TimeSpan.FromSeconds(10),
                        TimeSpan.FromMilliseconds(250)).Success,
                    "Settings did not close after Back");

                MenuBarTests.SelectTab(window, 1);
                MenuBarTests.SetBoxText(window, "audit edited");
                MenuBarTests.ClickMenuItem(window, "MenuFile", "MenuFileSaveAll");
                Assert.Equal("audit edited", Retry.While(
                    () =>
                    {
                        try
                        {
                            return File.ReadAllText(file);
                        }
                        catch (IOException)
                        {
                            return string.Empty;
                        }
                    },
                    text => text != "audit edited",
                    TimeSpan.FromSeconds(10),
                    TimeSpan.FromMilliseconds(250),
                    lastValueOnTimeout: true).Result);

                foreach (var (itemId, dialogId) in new[]
                {
                    ("MenuToolsStats", "StatsDialog"),
                    ("MenuToolsSnapshots", "SnapshotsDialog"),
                    ("MenuToolsTemplates", "TemplatesDialog"),
                    ("MenuToolsExport", "ExportDialog"),
                    ("MenuToolsLock", "LockDialog"),
                })
                {
                    MenuBarTests.ClickMenuItem(window, "MenuTools", itemId);
                    var dialog = Retry.WhileNull(
                        () => window.FindFirstDescendant(cf => cf.ByAutomationId(dialogId)),
                        TimeSpan.FromSeconds(10),
                        TimeSpan.FromMilliseconds(250)).Result;
                    Assert.True(dialog is not null, $"{itemId} opened no {dialogId}");
                    var close = dialog!.FindFirstDescendant(cf => cf.ByName("Close"))?.AsButton()
                        ?? dialog.FindFirstDescendant(cf => cf.ByName("Cancel"))?.AsButton();
                    Assert.True(close is not null, $"{dialogId} has no Close or Cancel");
                    close!.Invoke();
                    Assert.True(
                        Retry.WhileTrue(
                            () => window.FindFirstDescendant(cf => cf.ByAutomationId(dialogId)) is not null,
                            TimeSpan.FromSeconds(10),
                            TimeSpan.FromMilliseconds(250)).Success,
                        $"{dialogId} did not close");
                }
            }
            finally
            {
                MenuBarTests.CloseApp(app, window);
            }
        }
        finally
        {
            SessionData.Delete();
            try
            {
                Directory.Delete(dir, recursive: true);
            }
            catch (IOException)
            {
            }
        }
    }

    static void ToggleStatusBar(Window window, bool expectVisible)
    {
        MenuBarTests.OpenMenu(window, "MenuView");
        var toggle = window.FindFirstDescendant(cf => cf.ByAutomationId("MenuViewStatusBar"));
        Assert.NotNull(toggle);
        toggle.Patterns.Toggle.Pattern.Toggle();
        MenuBarTests.DismissMenu(window, "MenuView");
        bool settled = Retry.WhileFalse(
            () => (window.FindFirstDescendant(cf => cf.ByAutomationId("StatusRegion")) is { IsOffscreen: false }) == expectVisible,
            TimeSpan.FromSeconds(10),
            TimeSpan.FromMilliseconds(250)).Success;
        Assert.True(settled, $"Status bar toggle never left the strip {(expectVisible ? "visible" : "hidden")}");
    }

    internal sealed record LiveItem(string Id, string Label, bool Enabled);

    static List<LiveItem> WalkMenu(Window window, string topId, HashSet<string> containers, List<AutomationElement> bar)
    {
        MenuBarTests.OpenMenu(window, topId);
        var top = Onscreen(window, bar);
        MenuBarTests.DismissMenu(window, topId);
        var result = new List<LiveItem>();
        foreach (var (_, item) in top)
        {
            result.Add(item);
            if (containers.Contains(item.Id))
            {
                // A submenu's children are the elements that newly appear
                // on screen when it expands, compared by element identity,
                // so a child reusing a visible item's id still counts.
                MenuBarTests.OpenMenu(window, topId);
                var before = Onscreen(window, bar).Select(e => e.Element).ToList();
                MenuBarTests.OpenSubmenu(window, item.Id);
                result.AddRange(Onscreen(window, bar)
                    .Where(e => !before.Any(b => b.Equals(e.Element)))
                    .Select(e => e.Item));
                MenuBarTests.DismissMenu(window, topId);
                MenuBarTests.DismissMenu(window, topId);
            }
        }

        return result;
    }

    // Every on-screen menu item in the window except the bar's own top
    // items and the OS title-bar System menu, both excluded by element
    // identity, never by id: an item with a foreign, empty, or reused id
    // (even a top menu's) still counts. Expanded children render in a
    // separate popup, so the search is window-wide.
    static List<(AutomationElement Element, LiveItem Item)> Onscreen(Window window, List<AutomationElement> bar)
    {
        var excluded = window.FindAllDescendants(cf => cf.ByControlType(ControlType.TitleBar))
            .SelectMany(t => t.FindAllDescendants(cf => cf.ByControlType(ControlType.MenuItem)))
            .Concat(bar)
            .ToList();
        var items = new List<(AutomationElement, LiveItem)>();
        foreach (var m in window.FindAllDescendants(cf => cf.ByControlType(ControlType.MenuItem)))
        {
            try
            {
                if (m.IsOffscreen || excluded.Any(c => c.Equals(m)))
                {
                    continue;
                }

                items.Add((m, new LiveItem(KeyOf(m.Properties.AutomationId.ValueOrDefault, m.Name), m.Name, m.IsEnabled)));
            }
            catch (Exception ex) when (ex is InvalidOperationException or FlaUI.Core.Exceptions.FlaUIException)
            {
            }
        }

        return items;
    }

    static string KeyOf(string? automationId, string name) =>
        string.IsNullOrEmpty(automationId) ? $"<no AutomationId: {name}>" : automationId;

    internal static List<AuditRow> LoadRows()
    {
        string[] lines = File.ReadAllLines(Path.Combine(BindingManifestTests.RepoRoot(), "docs", "menu-audit.md"));
        int start = Array.FindIndex(lines, l => l.Trim() == "## Items");
        Assert.True(start >= 0, "docs/menu-audit.md: the Items section is missing");
        var rows = new List<AuditRow>();
        for (int i = start + 1; i < lines.Length && !lines[i].StartsWith("## ", StringComparison.Ordinal); i++)
        {
            string line = lines[i].Trim();
            if (!line.StartsWith('|') || line.StartsWith("| Menu ", StringComparison.Ordinal) || line.StartsWith("| ---", StringComparison.Ordinal))
            {
                continue;
            }

            string[] cells = line.Trim('|').Split('|').Select(c => c.Trim()).ToArray();
            Assert.True(cells.Length == 6, $"docs/menu-audit.md:{i + 1}: an item row needs 6 cells, found {cells.Length}");
            rows.Add(new AuditRow(i + 1, cells[0], cells[1], cells[2].Trim('`'), cells[4], cells[5].Trim('`')));
        }

        return rows;
    }

    // The method's region is its attribute block plus its body (one line
    // for an expression body); a same-class helper it calls counts once.
    internal static bool ProofNamesItem(string[] source, string method, string id)
    {
        string quoted = $"\"{id}\"";
        string? region = Region(source, method);
        if (region is null)
        {
            return false;
        }

        if (region.Contains(quoted, StringComparison.Ordinal))
        {
            return true;
        }

        foreach (Match call in Regex.Matches(region, @"\b([A-Z][A-Za-z0-9_]*)\("))
        {
            string name = call.Groups[1].Value;
            if (name != method && Region(source, name) is { } helper && helper.Contains(quoted, StringComparison.Ordinal))
            {
                return true;
            }
        }

        return false;
    }

    static string? Region(string[] source, string method)
    {
        var sig = new Regex(@"^\s{4}(?:public |internal |private )?(?:static )?(?:void|bool|int|string|[A-Z][A-Za-z<>\[\]?]*) " + Regex.Escape(method) + @"\(");
        int i = Array.FindIndex(source, l => sig.IsMatch(l));
        if (i < 0)
        {
            return null;
        }

        int start = i;
        while (start > 0 && (source[start - 1].TrimStart().StartsWith('[') || source[start - 1].TrimStart().StartsWith("//", StringComparison.Ordinal)))
        {
            start--;
        }

        int end = i;
        if (source[i].Contains("=>", StringComparison.Ordinal))
        {
            while (end < source.Length - 1 && !source[end].TrimEnd().EndsWith(';'))
            {
                end++;
            }
        }
        else
        {
            while (end < source.Length - 1 && source[end] != "    }")
            {
                end++;
            }
        }

        return string.Join('\n', source[start..(end + 1)]);
    }

    [GeneratedRegex(@"^([A-Z][A-Za-z0-9]*)\.([A-Z][A-Za-z0-9_]*)$")]
    private static partial Regex ProofRef();

    [GeneratedRegex(@"^D\d{2} T\d{2} §\d+$")]
    private static partial Regex OwnerRef();
}
