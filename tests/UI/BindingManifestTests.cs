using System.Text.RegularExpressions;
using Xunit;
using Xunit.Abstractions;

namespace UI;

// D00 T02 §21: the binding manifest guard over the live tree, plus one
// planted mutation per rule proving the rule can fail: an undeclared
// binding, a wrong-key covering test, an unaudited conflict, an
// OS-reserved chord, an access-key collision, an enabled command riding
// a disabled exemption, an owner that no longer owes the chord, an
// exemption without an approver, key handling outside the two homes,
// and a mismatched menu label. Pure text in, problems out: no launch.
public sealed class BindingManifestTests(ITestOutputHelper output)
{
    [Fact]
    public void LiveTreeManifestIsClean()
    {
        var (inputs, parse) = LiveInputs();
        Assert.Empty(parse);
        var problems = BindingManifest.Check(inputs);
        foreach (string line in BindingManifest.Matrix(inputs.Declarations))
        {
            output.WriteLine(line);
        }

        Assert.Empty(problems);
    }

    [Fact]
    public void LiveTreeDeclaresFortyFourBindings()
    {
        // 31 menu-bar accelerators plus 13 programmatic tab bindings
        // (the §12 sweep's census); a change here is a new or dropped
        // binding, which the audit table must follow.
        var (inputs, _) = LiveInputs();
        Assert.Equal(31, inputs.Declarations.Count(d => d.Source == BindingManifest.MenuXamlPath));
        Assert.Equal(13, inputs.Declarations.Count(d => d.Source == BindingManifest.TabSourcePath));
    }

    [Fact]
    public void CtrlEDuplicateSurfacesInTheMatrix()
    {
        var (inputs, _) = LiveInputs();
        string row = Assert.Single(BindingManifest.Matrix(inputs.Declarations), l => l.StartsWith("Ctrl+E:", StringComparison.Ordinal));
        Assert.Contains("MenuEditSearchBing", row, StringComparison.Ordinal);
        Assert.Contains("MenuEditDefineBing", row, StringComparison.Ordinal);
    }

    [Fact]
    public void PlantedUndeclaredBindingFails()
    {
        var (inputs, _) = LiveInputs(xaml => xaml.Replace(
            "<MenuFlyoutItem x:Name=\"MenuFileExit\" Text=\"Exit\" AutomationProperties.AutomationId=\"MenuFileExit\" Click=\"OnFileExit\" />",
            "<MenuFlyoutItem x:Name=\"MenuFileExit\" Text=\"Exit\" AutomationProperties.AutomationId=\"MenuFileExit\" Click=\"OnFileExit\"><MenuFlyoutItem.KeyboardAccelerators><KeyboardAccelerator Modifiers=\"Control\" Key=\"Q\" /></MenuFlyoutItem.KeyboardAccelerators></MenuFlyoutItem>",
            StringComparison.Ordinal));
        Assert.Contains(BindingManifest.Check(inputs), p => p.Contains("Ctrl+Q -> MenuFileExit is declared but has no audit row", StringComparison.Ordinal));
    }

    [Fact]
    public void WrongKeyMutationFailsTheGate()
    {
        var (inputs, _) = LiveInputs(testSource: (cls, src) => cls == "AcceleratorTests"
            ? src.Replace("VirtualKeyShort.KEY_G, withControl: true, withShift: true", "VirtualKeyShort.KEY_F, withControl: true, withShift: true", StringComparison.Ordinal)
            : src);
        Assert.Contains(BindingManifest.Check(inputs), p => p.Contains("AcceleratorTests.ChordCtrlShiftGOpensStats does not press Ctrl+Shift+G", StringComparison.Ordinal));
    }

    [Fact]
    public void CoveringMethodThatNeverRunsFails()
    {
        // R5-F1: strip the gate attribute from the G chord test; the press
        // is still in its body, but nothing discovers the method.
        var (inputs, _) = LiveInputs(testSource: (cls, src) => cls == "AcceleratorTests"
            ? src.Replace("    [InteractiveFact]\r\n    [Trait(\"Category\", \"Interactive\")]\r\n    public void ChordCtrlShiftGOpensStats()", "    public void ChordCtrlShiftGOpensStats()", StringComparison.Ordinal)
                .Replace("    [InteractiveFact]\n    [Trait(\"Category\", \"Interactive\")]\n    public void ChordCtrlShiftGOpensStats()", "    public void ChordCtrlShiftGOpensStats()", StringComparison.Ordinal)
            : src);
        Assert.Contains(BindingManifest.Check(inputs), p => p.Contains("AcceleratorTests.ChordCtrlShiftGOpensStats carries no test attribute", StringComparison.Ordinal));
    }

    [Fact]
    public void PlantedConflictFails()
    {
        var (inputs, _) = LiveInputs(tabSource: src => src.Replace(
            "AddAccel(scope, VirtualKey.T, VirtualKeyModifiers.Control, bar.NewTab);",
            "AddAccel(scope, VirtualKey.T, VirtualKeyModifiers.Control, bar.NewTab);\n        AddAccel(scope, VirtualKey.N, VirtualKeyModifiers.Control, bar.NewTab);",
            StringComparison.Ordinal));
        var problems = BindingManifest.Check(inputs);
        Assert.Contains(problems, p => p.StartsWith("conflict: Ctrl+N is declared by", StringComparison.Ordinal));
        Assert.DoesNotContain(problems, p => p.StartsWith("conflict: Ctrl+E", StringComparison.Ordinal));
    }

    [Fact]
    public void PlantedOsReservedChordFails()
    {
        var (inputs, _) = LiveInputs(xaml => xaml.Replace("Modifiers=\"Control,Shift\" Key=\"L\"", "Modifiers=\"Menu\" Key=\"F4\"", StringComparison.Ordinal));
        Assert.Contains(BindingManifest.Check(inputs), p => p == "conflict: Alt+F4 (MenuToolsLock) is OS-reserved");
    }

    [Fact]
    public void PlantedAccessKeyCollisionFails()
    {
        var (inputs, _) = LiveInputs(xaml => xaml.Replace("Title=\"Tools\" AccessKey=\"T\"", "Title=\"Tools\" AccessKey=\"F\"", StringComparison.Ordinal));
        Assert.Contains(BindingManifest.Check(inputs), p => p.StartsWith("conflict: access key F is shared by", StringComparison.Ordinal));
        var (alt, _) = LiveInputs(xaml => xaml.Replace("Modifiers=\"Control,Shift\" Key=\"L\"", "Modifiers=\"Menu\" Key=\"V\"", StringComparison.Ordinal));
        Assert.Contains(BindingManifest.Check(alt), p => p.StartsWith("conflict: Alt+V (MenuToolsLock) collides with the MenuView access key", StringComparison.Ordinal));
    }

    // D00 T02 §28 item 1: a chord re-wired to another command's handler
    // fails the manifest before any test runs.
    [Fact]
    public void PlantedHandlerSwapFails()
    {
        var (_, parse) = LiveInputs(xaml: x => x.Replace("Click=\"OnFileNewTab\"", "Click=\"OnFileOpen\"", StringComparison.Ordinal));
        Assert.Contains(parse, p => p.Contains("MenuFileNewTab is wired to handler OnFileOpen, not OnFileNewTab", StringComparison.Ordinal));
    }

    // D00 T02 §28 item 1: a covering test that presses the chord but
    // asserts nothing after it cannot tell the right command from a
    // wrong one, so it covers nothing.
    [Fact]
    public void CoveringTestWithoutAnOutcomeAssertionFails()
    {
        var (inputs, _) = LiveInputs(testSource: (cls, src) =>
        {
            if (cls != "AcceleratorTests")
            {
                return src;
            }

            int a = src.IndexOf("public void ChordCtrlShiftGOpensStats()", StringComparison.Ordinal);
            int b = src.IndexOf("[InteractiveFact]", a, StringComparison.Ordinal);
            return src[..a] + src[a..b].Replace("Assert.", "Skip.", StringComparison.Ordinal) + src[b..];
        });
        Assert.Contains(BindingManifest.Check(inputs), p => p.Contains("AcceleratorTests.ChordCtrlShiftGOpensStats presses Ctrl+Shift+G but asserts nothing after it", StringComparison.Ordinal));
    }

    [Fact]
    public void LiveCoveringTestsAssertAfterTheirPress()
    {
        var (inputs, _) = LiveInputs();
        Assert.DoesNotContain(BindingManifest.Check(inputs), p => p.Contains("asserts nothing after it", StringComparison.Ordinal));
    }

    // D00 T02 §28 item 8: assistive-technology text is checked against
    // the declaration for every bound item.
    [Fact]
    public void AccessibleTextMismatchFails()
    {
        string xaml = File.ReadAllText(Path.Combine(RepoRoot(), BindingManifest.MenuXamlPath));
        var declared = BindingManifest.ParseMenuItemText(xaml);
        Assert.Equal(new BindingManifest.ItemText("New tab", string.Empty), declared["MenuFileNewTab"]);
        var seen = new Dictionary<string, BindingManifest.ItemText>(StringComparer.Ordinal)
        {
            ["MenuFileNewTab"] = new("New tab", string.Empty),
            ["MenuFileOpen"] = new("Open file", string.Empty),
            ["MenuFileSave"] = new("Save", "Saves"),
        };
        Assert.Equal(
            [
                "MenuFileOpen: accessible name 'Open file', declared 'Open'",
                "MenuFileSave: accessible description 'Saves', declared ''",
                "MenuFileSaveAs: bound but never read on the rendered menu",
            ],
            BindingManifest.AccessibleTextMismatches(["MenuFileNewTab", "MenuFileOpen", "MenuFileSave", "MenuFileSaveAs"], declared, seen));
    }

    // D00 T02 §28 item 9: a disabled exemption enabled in one state (a
    // selection present) fails, and a state never read fails too.
    [Fact]
    public void StateConditionalEnablementPlantFails()
    {
        var (inputs, _) = LiveInputs();
        var disabled = inputs.Rows.Where(r => r.Class == "disabled").ToList();
        Assert.NotEmpty(disabled);
        var all = disabled.SelectMany(r => BindingManifest.EnablementStates.Select(st => new BindingManifest.StateObservation(st, r.Command, false))).ToList();
        Assert.Empty(BindingManifest.EnablementProblems(inputs.Rows, all));
        var planted = all.Select(o => o.Command == "MenuEditCopy" && o.State == "selection present" ? o with { Enabled = true } : o).ToList();
        Assert.Contains(BindingManifest.EnablementProblems(inputs.Rows, planted), p => p.Contains("MenuEditCopy: exempt as disabled but enabled in state 'selection present'", StringComparison.Ordinal));
        var unread = all.Where(o => !(o.Command == "MenuEditCopy" && o.State == "file open")).ToList();
        Assert.Contains(BindingManifest.EnablementProblems(inputs.Rows, unread), p => p.Contains("MenuEditCopy: disabled exemption never read in state 'file open'", StringComparison.Ordinal));
    }

    // D00 T02 §28 item 10: the Ctrl+P owner-owed row and D01 T02 §5
    // agree. While §5 owes its enablement reconciliation the historical
    // "ships disabled" note stands; once that item closes (or is
    // dropped) with the note uncorrected, the guard fails.
    [Fact]
    public void OwnerStillClaimingTheLiveCommandShipsDisabledFails()
    {
        var (live, _) = LiveInputs();
        Assert.Contains(live.Rows, r => r.Command == "MenuFilePrint" && r.Class == "owner-owed" && r.Label == "File > Print");
        Assert.DoesNotContain(BindingManifest.Check(live), p => p.Contains("still claims", StringComparison.Ordinal));
        var (closed, _) = LiveInputs(section: (reference, s) => reference == "D01 T02 §5"
            ? (s.Found, s.Open, s.Body.Replace("- [ ] The section text reconciles with the tree", "- [x] The section text reconciles with the tree", StringComparison.Ordinal))
            : s);
        Assert.Contains(BindingManifest.Check(closed), p => p.Contains("MenuFilePrint: live, but owner D01 T02 §5 still claims File > Print ships disabled", StringComparison.Ordinal));
        var (corrected, _) = LiveInputs(section: (reference, s) => reference == "D01 T02 §5"
            ? (s.Found, s.Open, s.Body.Replace("- [ ] The section text reconciles with the tree", "- [x] The section text reconciles with the tree", StringComparison.Ordinal)
                .Replace("ships File > Print and File > Page setup disabled", "ships File > Print and File > Page setup enabled at runtime", StringComparison.Ordinal))
            : s);
        Assert.DoesNotContain(BindingManifest.Check(corrected), p => p.Contains("still claims", StringComparison.Ordinal));
    }

    [Fact]
    public void PlantedEnabledButExemptCommandFails()
    {
        var (inputs, _) = LiveInputs(runtime: src => src + "\nMenuRegion.SetEnabled(\"MenuEditUndo\", true);\n");
        Assert.Contains(BindingManifest.Check(inputs), p => p.Contains("Ctrl+Z -> MenuEditUndo: exempt as disabled but the command is enabled", StringComparison.Ordinal));
    }

    [Fact]
    public void OwnerThatNoLongerOwesTheChordFails()
    {
        var (inputs, _) = LiveInputs(section: (reference, s) => reference == "D02 T01 §4" ? (s.Found, s.Open, s.Body.Replace("Ctrl+Z", "Ctrl-Z", StringComparison.Ordinal)) : s);
        Assert.Contains(BindingManifest.Check(inputs), p => p.Contains("owner D02 T01 §4's checklist does not owe the Ctrl+Z chord test", StringComparison.Ordinal));
        var (stamped, _) = LiveInputs(section: (reference, s) => reference == "D02 T01 §4" ? (s.Found, false, s.Body) : s);
        Assert.Contains(BindingManifest.Check(stamped), p => p.Contains("owner D02 T01 §4 is stamped", StringComparison.Ordinal));
    }

    [Fact]
    public void ExemptionWithoutApproverOrKnownClassFails()
    {
        var (inputs, _) = LiveInputs(audit: md => Regex.Replace(md, "\\| disabled \\| (.*?) \\| operator \\| D02 T01 §4 \\|", "| disabled | $1 | - | D02 T01 §4 |"));
        Assert.Contains(BindingManifest.Check(inputs), p => p.Contains("Ctrl+Z -> MenuEditUndo: exemption class disabled names no approver", StringComparison.Ordinal));
        var (cls, _) = LiveInputs(audit: md => md.Replace("| duplicate |", "| shrug |", StringComparison.Ordinal));
        Assert.Contains(BindingManifest.Check(cls), p => p.Contains("class 'shrug' is outside the taxonomy", StringComparison.Ordinal));
    }

    [Fact]
    public void ReservedChordsMatchWhateverSpellingTheyAreDeclaredIn()
    {
        var (shiftTab, _) = LiveInputs(xaml => xaml.Replace("Modifiers=\"Control,Shift\" Key=\"L\"", "Modifiers=\"Menu,Shift\" Key=\"Tab\"", StringComparison.Ordinal));
        Assert.Contains(BindingManifest.Check(shiftTab), p => p == "conflict: Shift+Alt+Tab (MenuToolsLock) is OS-reserved");
        var (esc, _) = LiveInputs(xaml => xaml.Replace("Modifiers=\"Control,Shift\" Key=\"L\"", "Modifiers=\"Control\" Key=\"Escape\"", StringComparison.Ordinal));
        Assert.Contains(BindingManifest.Check(esc), p => p == "conflict: Ctrl+Esc (MenuToolsLock) is OS-reserved");
    }

    [Fact]
    public void DuplicateWithAnUnresolvedOwnerFails()
    {
        var (inputs, _) = LiveInputs(audit: md => md.Replace("| operator | D01 T02 §1 |", "| operator | D98 T07 §41 |", StringComparison.Ordinal));
        Assert.Contains(BindingManifest.Check(inputs), p => p.Contains("Ctrl+E -> MenuEditDefineBing: duplicate names owner 'D98 T07 §41'", StringComparison.Ordinal));
    }

    [Fact]
    public void AnXrefAloneDoesNotOweTheChordTest()
    {
        var (inputs, _) = LiveInputs(section: (reference, s) => reference == "D02 T01 §4"
            ? (s.Found, s.Open, string.Join('\n', s.Body.Replace("\r\n", "\n", StringComparison.Ordinal).Split('\n')
                .Where(l => !(l.StartsWith("- [ ] ", StringComparison.Ordinal) && l.Contains("D00 T02 §21", StringComparison.Ordinal)))))
            : s);
        Assert.Contains(BindingManifest.Check(inputs), p => p.Contains("owner D02 T01 §4's checklist does not owe the Ctrl+Z chord test", StringComparison.Ordinal));
    }

    [Fact]
    public void AKeyTheManifestCannotBindCreditsNothing()
    {
        var (inputs, _) = LiveInputs(testSource: (cls, src) => cls == "TabBarTests"
            ? src.Replace("UiInput.Press(window, key, withControl: true);", "var pressed = VirtualKeyShort.KEY_3;\n            UiInput.Press(window, pressed, withControl: true);", StringComparison.Ordinal)
            : src);
        var problems = BindingManifest.Check(inputs);
        Assert.Contains(problems, p => p.Contains("TabBarTests.NumberShortcutsCoverMiddlePositions does not press Ctrl+2 (presses ?unresolved:pressed)", StringComparison.Ordinal));
        Assert.Equal(["Ctrl+2", "Ctrl+4", "Ctrl+5", "Ctrl+6", "Ctrl+7", "Ctrl+8"],
            BindingManifest.PressedChords(File.ReadAllText(Path.Combine(RepoRoot(), "tests", "UI", "TabBarTests.cs")), "NumberShortcutsCoverMiddlePositions").Order(StringComparer.Ordinal));
    }

    [Fact]
    public void KeyHandlingOutsideTheTwoHomesFails()
    {
        Assert.NotEmpty(BindingManifest.UndeclaredKeyHandling("src/ScratchPad/ExportDialog.cs", "class D { void M() { box.KeyDown += OnKey; } }"));
        Assert.NotEmpty(BindingManifest.UndeclaredKeyHandling("src/ScratchPad/MainWindow.xaml.cs", "class W { void Other() { root.KeyboardAccelerators.Add(a); } }"));
        const string Helper = "static void AddAccel(UIElement scope, VirtualKey key, VirtualKeyModifiers modifiers, Action action) { var accel = new KeyboardAccelerator { Key = key, Modifiers = modifiers }; accel.Invoked += (_, args) => { action(); args.Handled = true; }; scope.KeyboardAccelerators.Add(accel); }";
        const string Tab = BindingManifest.TabSourcePath;
        Assert.Empty(BindingManifest.UndeclaredKeyHandling(Tab,
            "class W { static void AddTabAccelerators(UIElement scope) { AddAccel(scope, VirtualKey.T, VirtualKeyModifiers.Control, N); } " + Helper + " }"));

        // R2-F1: a direct Add inside AddTabAccelerators, a helper with a
        // literal key, and an AddAccel call from elsewhere all bypass the
        // inventory, so each fails.
        Assert.Contains(BindingManifest.UndeclaredKeyHandling(Tab,
            "class W { static void AddTabAccelerators(UIElement scope) { scope.KeyboardAccelerators.Add(new KeyboardAccelerator { Key = VirtualKey.Q }); } " + Helper + " }"),
            p => p.Contains("undeclared key handling (KeyboardAccelerator)", StringComparison.Ordinal));
        Assert.Contains(BindingManifest.UndeclaredKeyHandling(Tab,
            "class W { static void AddTabAccelerators(UIElement scope) { } static void AddAccel(UIElement scope, VirtualKey key, VirtualKeyModifiers modifiers, Action action) { var accel = new KeyboardAccelerator { Key = VirtualKey.Q, Modifiers = modifiers }; scope.KeyboardAccelerators.Add(accel); } }"),
            p => p.Contains("AddAccel no longer builds exactly one accelerator", StringComparison.Ordinal));
        Assert.Contains(BindingManifest.UndeclaredKeyHandling(Tab,
            "class W { static void AddTabAccelerators(UIElement scope) { } void Other(UIElement scope) { AddAccel(scope, VirtualKey.Q, VirtualKeyModifiers.Control, N); } " + Helper + " }"),
            p => p.Contains("AddAccel is referenced from Other", StringComparison.Ordinal));

        // R3-F1 family sweep: every reference shape outside a direct call
        // in AddTabAccelerators fails: qualified calls elsewhere, a method
        // group handed to a delegate, and a qualified call inside the home
        // (the parser only derives direct calls, so it would go unseen).
        Assert.Contains(BindingManifest.UndeclaredKeyHandling(Tab,
            "class MainWindow { static void AddTabAccelerators(UIElement scope) { } void Other(UIElement scope) { MainWindow.AddAccel(scope, VirtualKey.Q, VirtualKeyModifiers.Control, N); } " + Helper + " }"),
            p => p.Contains("AddAccel is referenced from Other as `MainWindow.AddAccel`", StringComparison.Ordinal));
        Assert.Contains(BindingManifest.UndeclaredKeyHandling(Tab,
            "class MainWindow { static void AddTabAccelerators(UIElement scope) { } void Other() { Action<UIElement, VirtualKey, VirtualKeyModifiers, Action> f = AddAccel; } " + Helper + " }"),
            p => p.Contains("AddAccel is referenced from Other", StringComparison.Ordinal));
        Assert.Contains(BindingManifest.UndeclaredKeyHandling(Tab,
            "class MainWindow { static void AddTabAccelerators(UIElement scope) { MainWindow.AddAccel(scope, VirtualKey.Q, VirtualKeyModifiers.Control, N); } " + Helper + " }"),
            p => p.Contains("AddAccel is referenced from AddTabAccelerators as `MainWindow.AddAccel`", StringComparison.Ordinal));

        // R4-F1: a reference from another MainWindow partial, and a helper
        // that re-keys the accelerator after construction, both fail.
        Assert.Contains(BindingManifest.UndeclaredKeyHandling("src/ScratchPad/MainWindow.Menu.cs",
            "partial class MainWindow { void Wire(UIElement root) { AddAccel(root, VirtualKey.Q, VirtualKeyModifiers.Control, N); } }"),
            p => p.Contains("references AddAccel outside", StringComparison.Ordinal));
        Assert.Contains(BindingManifest.UndeclaredKeyHandling(Tab,
            "class W { static void AddTabAccelerators(UIElement scope) { } " + Helper.Replace("scope.KeyboardAccelerators.Add(accel);", "accel.Key = VirtualKey.Q; scope.KeyboardAccelerators.Add(accel);", StringComparison.Ordinal) + " }"),
            p => p.Contains("AddAccel no longer builds exactly one accelerator", StringComparison.Ordinal));
    }

    [Fact]
    public void LiveSourceHasNoUndeclaredKeyHandling()
    {
        string root = RepoRoot();
        var found = new List<string>();
        foreach (string file in Directory.EnumerateFiles(Path.Combine(root, "src"), "*.*", SearchOption.AllDirectories)
            .Where(f => (f.EndsWith(".cs", StringComparison.Ordinal) || f.EndsWith(".xaml", StringComparison.Ordinal))
                && !f.Contains($"{Path.DirectorySeparatorChar}obj{Path.DirectorySeparatorChar}", StringComparison.Ordinal)))
        {
            string rel = Path.GetRelativePath(root, file).Replace(Path.DirectorySeparatorChar, '/');
            found.AddRange(BindingManifest.UndeclaredKeyHandling(rel, File.ReadAllText(file)));
        }

        Assert.Empty(found);
    }

    [Fact]
    public void MismatchedMenuLabelFails()
    {
        var expected = new Dictionary<string, string>(StringComparer.Ordinal) { ["MenuFileSave"] = "Ctrl+S", ["MenuViewZoomIn"] = BindingManifest.ExpectedLabel("Ctrl+Plus") };
        Assert.Empty(LabelMismatches(expected, new Dictionary<string, string>(StringComparer.Ordinal) { ["MenuFileSave"] = "Ctrl+S", ["MenuViewZoomIn"] = "Ctrl++" }));
        Assert.Equal(
            ["MenuFileSave: displays 'Ctrl+Shift+S', manifest says 'Ctrl+S'"],
            LabelMismatches(expected, new Dictionary<string, string>(StringComparer.Ordinal) { ["MenuFileSave"] = "Ctrl+Shift+S", ["MenuViewZoomIn"] = "Ctrl++" }));
    }

    internal static List<string> LabelMismatches(Dictionary<string, string> expected, Dictionary<string, string> seen) =>
        expected.Where(e => seen.TryGetValue(e.Key, out string? s) && !string.Equals(s, e.Value, StringComparison.Ordinal))
            .Select(e => $"{e.Key}: displays '{seen[e.Key]}', manifest says '{e.Value}'")
            .OrderBy(s => s, StringComparer.Ordinal)
            .ToList();

    internal static string RepoRoot()
    {
        string? dir = AppContext.BaseDirectory;
        while (dir is not null && !Directory.Exists(Path.Combine(dir, "tests", "UI")))
        {
            dir = Path.GetDirectoryName(dir);
        }

        Assert.NotNull(dir);
        return dir!;
    }

    // The live inputs, each source optionally mutated for a plant.
    static (BindingManifest.Inputs Inputs, List<string> Parse) LiveInputs(
        Func<string, string>? xaml = null,
        Func<string, string>? tabSource = null,
        Func<string, string>? runtime = null,
        Func<string, string>? audit = null,
        Func<string, string, string>? testSource = null,
        Func<string, (bool Found, bool Open, string Body), (bool Found, bool Open, string Body)>? section = null)
    {
        string root = RepoRoot();
        string xamlText = File.ReadAllText(Path.Combine(root, BindingManifest.MenuXamlPath));
        string tabText = File.ReadAllText(Path.Combine(root, BindingManifest.TabSourcePath));
        xamlText = xaml?.Invoke(xamlText) ?? xamlText;
        tabText = tabSource?.Invoke(tabText) ?? tabText;
        var parse = new List<string>();
        var decls = BindingManifest.ParseMenuXaml(xamlText, out var accessKeys, out var p1);
        parse.AddRange(p1);
        decls.AddRange(BindingManifest.ParseTabAccelerators(tabText, out var p2));
        parse.AddRange(p2);
        var sources = Directory.EnumerateFiles(Path.Combine(root, "src"), "*.cs", SearchOption.AllDirectories)
            .Where(f => !f.Contains($"{Path.DirectorySeparatorChar}obj{Path.DirectorySeparatorChar}", StringComparison.Ordinal))
            .Select(File.ReadAllText).ToList();
        string joined = string.Join("\n", sources);
        var enabled = BindingManifest.RuntimeEnabled([runtime?.Invoke(joined) ?? joined]);
        string auditText = File.ReadAllText(Path.Combine(root, "docs", "ui-input-audit.md"));
        auditText = audit?.Invoke(auditText) ?? auditText;
        var rows = BindingManifest.ParseAudit(auditText, out var p3);
        parse.AddRange(p3);
        var byClass = new Dictionary<string, string>(StringComparer.Ordinal);
        foreach (string file in Directory.EnumerateFiles(Path.Combine(root, "tests", "UI"), "*.cs"))
        {
            string text = File.ReadAllText(file);
            foreach (Match m in Regex.Matches(text, "\\bclass (\\w+)"))
            {
                byClass.TryAdd(m.Groups[1].Value, text);
            }
        }

        return (new BindingManifest.Inputs(
            decls,
            accessKeys,
            enabled,
            rows,
            cls => byClass.TryGetValue(cls, out string? src) ? (testSource?.Invoke(cls, src) ?? src) : null,
            reference =>
            {
                var s = BindingManifest.ReadSection(root, reference);
                return section?.Invoke(reference, s) ?? s;
            }), parse);
    }
}
