using System.Text.RegularExpressions;
using System.Xml.Linq;
using Microsoft.CodeAnalysis;
using Microsoft.CodeAnalysis.CSharp;
using Microsoft.CodeAnalysis.CSharp.Syntax;

namespace UI;

// Binding manifest guard (D00 T02 §21): the accelerator inventory is
// derived from source, not typed by hand, and checked against the
// audit table in docs/ui-input-audit.md. Every declared binding needs
// exactly one audit row; a covered row names tests whose bodies press
// that chord (semantic validation, so a wrong-key mutation fails); an
// exempt row carries a taxonomy class, an approver, and an owner that
// still owes the chord test; duplicates, OS-reserved chords, and
// access-key collisions surface as conflicts. Every check is a pure
// function over text so planted mutations prove each rule without an
// app launch.
internal static class BindingManifest
{
    // Key handling lives in exactly these two places (the §12 sweep);
    // anything else in src/ is an undeclared binding surface.
    internal const string MenuXamlPath = "src/ScratchPad/MenuBar.xaml";
    internal const string TabSourcePath = "src/ScratchPad/MainWindow.xaml.cs";

    internal static readonly string[] Classes = ["covered", "disabled", "owner-owed", "duplicate"];

    // Declared before OsReserved: static initializers run in order,
    // and OsReserved canonicalizes through Chord, which reads this.
    static readonly string[] ModifierOrder = ["Ctrl", "Shift", "Alt"];

    // Chords the OS or shell owns: an app binding on one either never
    // fires or steals a system gesture. Win-key chords cannot be
    // declared through KeyboardAccelerator modifiers we parse, so the
    // list is the Ctrl/Alt/Shift/function-key set.
    // Written as people say them, canonicalized through Chord exactly
    // like declarations, so Alt+Shift+Tab and Escape spellings match.
    internal static readonly HashSet<string> OsReserved = new[]
    {
        "Alt+F4", "Alt+Tab", "Alt+Shift+Tab", "Alt+Esc", "Alt+Space", "Ctrl+Esc",
        "Ctrl+Alt+Delete", "Ctrl+Shift+Esc", "Ctrl+Alt+Tab", "F1", "F10", "Shift+F10",
    }.Select(ParseChord).ToHashSet(StringComparer.Ordinal);

    // "Ctrl+Shift+Esc" -> the canonical chord string.
    internal static string ParseChord(string text)
    {
        string[] parts = text.Split('+');
        return Chord(parts[..^1], parts[^1]);
    }

    internal sealed record Declaration(string Chord, string Command, string Source, bool XamlEnabled, string? AccessKey);

    internal sealed record AuditRow(string Chord, string Command, string Class, string Detail, string Approver, string Owner, int Line, string Label = "");

    // The accessible text XAML declares for a bound item (D00 T02 §28
    // item 8): UIA Name is AutomationProperties.Name when set, else the
    // item's Text; HelpText is AutomationProperties.HelpText or empty.
    internal sealed record ItemText(string Name, string HelpText);

    // One live read of a bound item's enablement in a named app state
    // (D00 T02 §28 item 9).
    internal sealed record StateObservation(string State, string Command, bool Enabled);

    // The representative states every disabled exemption is read in.
    internal static readonly string[] EnablementStates = ["fresh window", "file open", "selection present"];

    internal sealed record MenuAccessKey(string Menu, string Key);

    // ---- chord canonicalization ------------------------------------

    internal static string Chord(IEnumerable<string> modifiers, string key)
    {
        var mods = new HashSet<string>(modifiers.Select(NormalizeModifier), StringComparer.Ordinal);
        var parts = ModifierOrder.Where(mods.Contains).ToList();
        parts.Add(NormalizeKey(key));
        return string.Join('+', parts);
    }

    static string NormalizeModifier(string m) => m.Trim() switch
    {
        "Control" or "Ctrl" or "CONTROL" => "Ctrl",
        "Shift" or "SHIFT" => "Shift",
        "Menu" or "Alt" or "ALT" => "Alt",
        var other => throw new ArgumentException($"unknown modifier '{other}'"),
    };

    static string NormalizeKey(string key)
    {
        string k = key.Trim();
        if (k.StartsWith("KEY_", StringComparison.Ordinal))
        {
            k = k[4..];
        }

        return k switch
        {
            "Add" or "OEM_PLUS" => "Plus",
            "Subtract" or "OEM_MINUS" => "Minus",
            "TAB" => "Tab",
            "DELETE" => "Delete",
            "Escape" or "ESCAPE" or "ESC" or "Esc" => "Esc",
            "SPACE" or "Space" => "Space",
            _ when k.StartsWith("Number", StringComparison.Ordinal) && k.Length == 7 => k[6..],
            _ when Regex.IsMatch(k, "^F[0-9]{1,2}$") => k,
            _ when k.Length == 1 => k.ToUpperInvariant(),
            _ => k,
        };
    }

    // The label WinUI derives from a KeyboardAccelerator when no text
    // override exists (probed on the live menu: Ctrl++ and Ctrl+-).
    internal static string ExpectedLabel(string chord)
    {
        string[] parts = chord.Split('+');
        string key = parts[^1] switch
        {
            "Plus" => "+",
            "Minus" => "-",
            var other => other,
        };
        return string.Join('+', parts[..^1].Append(key));
    }

    // ---- declarations ----------------------------------------------

    internal static List<Declaration> ParseMenuXaml(string xaml, out List<MenuAccessKey> accessKeys, out List<string> problems)
    {
        problems = [];
        accessKeys = [];
        var decls = new List<Declaration>();
        XDocument doc = XDocument.Parse(xaml);
        foreach (XElement el in doc.Descendants())
        {
            string local = el.Name.LocalName;
            if (local == "MenuBarItem" && el.Attribute("AccessKey") is XAttribute ak)
            {
                accessKeys.Add(new MenuAccessKey(AutomationId(el) ?? local, ak.Value));
            }

            if (local == "KeyboardAccelerator")
            {
                XElement? owner = el.Parent?.Parent;
                string? id = owner is null ? null : AutomationId(owner);
                if (id is null)
                {
                    problems.Add($"{MenuXamlPath}: a KeyboardAccelerator sits on an element without an AutomationId");
                    continue;
                }

                string mods = el.Attribute("Modifiers")?.Value ?? string.Empty;
                string key = el.Attribute("Key")?.Value ?? string.Empty;
                bool enabled = !string.Equals(owner!.Attribute("IsEnabled")?.Value, "False", StringComparison.Ordinal);
                decls.Add(new Declaration(
                    Chord(mods.Split(',', StringSplitOptions.RemoveEmptyEntries), key), id, MenuXamlPath, enabled, null));
                // D00 T02 §28 item 1: a bound item's Click handler is the
                // one its id names (MenuFileNewTab -> OnFileNewTab), so a
                // chord re-wired to another command's handler fails here
                // before any covering test runs.
                if (owner.Attribute("Click")?.Value is string handler && id.StartsWith("Menu", StringComparison.Ordinal)
                    && !string.Equals(handler, "On" + id["Menu".Length..], StringComparison.Ordinal))
                {
                    problems.Add($"{MenuXamlPath}: {id} is wired to handler {handler}, not On{id["Menu".Length..]}; a chord must run the command it is declared on");
                }

                if (owner.Attribute("KeyboardAcceleratorTextOverride") is not null)
                {
                    problems.Add($"{MenuXamlPath}: {id} overrides its accelerator text; the label check cannot derive it");
                }
            }
        }

        return decls;
    }

    // Accessible text for every menu element carrying an AutomationId.
    internal static Dictionary<string, ItemText> ParseMenuItemText(string xaml)
    {
        var map = new Dictionary<string, ItemText>(StringComparer.Ordinal);
        foreach (XElement el in XDocument.Parse(xaml).Descendants())
        {
            if (AutomationId(el) is string id && el.Attribute("Text") is XAttribute text)
            {
                string? name = el.Attributes().FirstOrDefault(a => a.Name.LocalName == "AutomationProperties.Name")?.Value;
                string help = el.Attributes().FirstOrDefault(a => a.Name.LocalName == "AutomationProperties.HelpText")?.Value ?? string.Empty;
                map[id] = new ItemText(name ?? text.Value, help);
            }
        }

        return map;
    }

    // Assistive-technology text versus the declaration: a bound item
    // never read, or read with another name or description, is a problem.
    internal static List<string> AccessibleTextMismatches(IEnumerable<string> boundIds, Dictionary<string, ItemText> declared, Dictionary<string, ItemText> seen)
    {
        var problems = new List<string>();
        foreach (string id in boundIds.Distinct(StringComparer.Ordinal).Order(StringComparer.Ordinal))
        {
            if (!declared.TryGetValue(id, out ItemText? want))
            {
                problems.Add($"{id}: bound but declares no Text, so it has no accessible name");
            }
            else if (!seen.TryGetValue(id, out ItemText? got))
            {
                problems.Add($"{id}: bound but never read on the rendered menu");
            }
            else
            {
                if (!string.Equals(got.Name, want.Name, StringComparison.Ordinal))
                {
                    problems.Add($"{id}: accessible name '{got.Name}', declared '{want.Name}'");
                }

                if (!string.Equals(got.HelpText, want.HelpText, StringComparison.Ordinal))
                {
                    problems.Add($"{id}: accessible description '{got.HelpText}', declared '{want.HelpText}'");
                }
            }
        }

        return problems;
    }

    // D00 T02 §28 item 9: a disabled exemption holds only while its
    // command is unusable in every representative state. Enabled in any
    // state, or never read in one, fails before the owner closes.
    internal static List<string> EnablementProblems(IEnumerable<AuditRow> rows, IEnumerable<StateObservation> observations)
    {
        var problems = new List<string>();
        var seen = observations.ToList();
        foreach (AuditRow row in rows.Where(r => r.Class == "disabled"))
        {
            foreach (string state in EnablementStates)
            {
                var reads = seen.Where(o => o.Command == row.Command && o.State == state).ToList();
                if (reads.Count == 0)
                {
                    problems.Add($"{row.Chord} -> {row.Command}: disabled exemption never read in state '{state}'");
                }
                else if (reads.Any(o => o.Enabled))
                {
                    problems.Add($"{row.Chord} -> {row.Command}: exempt as disabled but enabled in state '{state}'; cover the chord or move the row to owner-owed");
                }
            }
        }

        return problems;
    }

    static string? AutomationId(XElement el) =>
        el.Attributes().FirstOrDefault(a => a.Name.LocalName == "AutomationProperties.AutomationId")?.Value;

    // Tab accelerators are programmatic (MainWindow.AddTabAccelerators):
    // each AddAccel call is one binding, and the number loop expands
    // to its declared bounds.
    internal static List<Declaration> ParseTabAccelerators(string source, out List<string> problems)
    {
        problems = [];
        var decls = new List<Declaration>();
        SyntaxNode root = CSharpSyntaxTree.ParseText(source).GetRoot();
        MethodDeclarationSyntax? method = root.DescendantNodes().OfType<MethodDeclarationSyntax>()
            .FirstOrDefault(m => m.Identifier.Text == "AddTabAccelerators");
        if (method is null)
        {
            problems.Add($"{TabSourcePath}: AddTabAccelerators is gone; the programmatic bindings cannot be derived");
            return decls;
        }

        foreach (InvocationExpressionSyntax call in method.DescendantNodes().OfType<InvocationExpressionSyntax>())
        {
            if (call.Expression is not IdentifierNameSyntax { Identifier.Text: "AddAccel" } || call.ArgumentList.Arguments.Count != 4)
            {
                continue;
            }

            ExpressionSyntax keyExpr = call.ArgumentList.Arguments[1].Expression;
            var mods = call.ArgumentList.Arguments[2].Expression.DescendantNodesAndSelf().OfType<MemberAccessExpressionSyntax>()
                .Where(m => m.Expression.ToString() == "VirtualKeyModifiers").Select(m => m.Name.Identifier.Text).ToList();
            string command = CommandName(call.ArgumentList.Arguments[3].Expression);
            if (keyExpr is MemberAccessExpressionSyntax { Expression: IdentifierNameSyntax { Identifier.Text: "VirtualKey" } } vk)
            {
                decls.Add(new Declaration(Chord(mods, vk.Name.Identifier.Text), command, TabSourcePath, true, null));
            }
            else if (keyExpr.ToString().Replace(" ", string.Empty, StringComparison.Ordinal) == "(VirtualKey)(0x30+captured)"
                && call.Ancestors().OfType<ForStatementSyntax>().FirstOrDefault() is ForStatementSyntax loop
                && LoopBounds(loop) is (int lo, int hi))
            {
                for (int n = lo; n <= hi; n++)
                {
                    decls.Add(new Declaration(Chord(mods, n.ToString(System.Globalization.CultureInfo.InvariantCulture)),
                        command.Replace("captured", n.ToString(System.Globalization.CultureInfo.InvariantCulture), StringComparison.Ordinal),
                        TabSourcePath, true, null));
                }
            }
            else
            {
                problems.Add($"{TabSourcePath}: AddAccel key '{keyExpr}' is not a shape the manifest can derive");
            }
        }

        return decls;
    }

    static string CommandName(ExpressionSyntax action) => action switch
    {
        MemberAccessExpressionSyntax m => $"Tabs.{m.Name.Identifier.Text}",
        ParenthesizedLambdaExpressionSyntax { Body: InvocationExpressionSyntax inv } =>
            $"Tabs.{(inv.Expression as MemberAccessExpressionSyntax)?.Name.Identifier.Text}({string.Join(',', inv.ArgumentList.Arguments)})",
        _ => action.ToString(),
    };

    static (int, int)? LoopBounds(ForStatementSyntax loop)
    {
        if (loop.Declaration?.Variables.FirstOrDefault()?.Initializer?.Value is LiteralExpressionSyntax lo
            && loop.Condition is BinaryExpressionSyntax { RawKind: (int)SyntaxKind.LessThanOrEqualExpression, Right: LiteralExpressionSyntax hi })
        {
            return ((int)lo.Token.Value!, (int)hi.Token.Value!);
        }

        return null;
    }

    // Commands a live section flips on at runtime (MenuCommands).
    internal static HashSet<string> RuntimeEnabled(IEnumerable<string> sources)
    {
        var ids = new HashSet<string>(StringComparer.Ordinal);
        foreach (string src in sources)
        {
            foreach (Match m in Regex.Matches(src, "SetEnabled\\(\"(\\w+)\",\\s*true\\)"))
            {
                ids.Add(m.Groups[1].Value);
            }
        }

        return ids;
    }

    // Key handling outside the two declared homes is an undeclared
    // binding surface (context routing the matrix cannot see).
    internal static List<string> UndeclaredKeyHandling(string relPath, string text)
    {
        var found = new List<string>();
        if (relPath == MenuXamlPath)
        {
            return found;
        }

        string scan = text;
        if (relPath == TabSourcePath)
        {
            // Only the AddAccel helper may touch KeyboardAccelerator, only
            // in its sanctioned shape (built from its own parameters), and
            // only AddTabAccelerators may call it: a direct Add inside
            // AddTabAccelerators, a literal key in the helper, or a call
            // from anywhere else would bind a chord the inventory never sees.
            found.AddRange(TabHomeProblems(text));
            scan = StripMethod(text, "AddAccel");
        }
        else if (Regex.IsMatch(text, "\\bAddAccel\\b"))
        {
            // R4-F1: the helper is private to MainWindow's partials, so a
            // reference from any other file (another partial included) is
            // a binding path the inventory never derives.
            found.Add($"{relPath}: references AddAccel outside {TabSourcePath}; only direct calls in AddTabAccelerators are derived");
        }

        foreach (string token in new[] { "KeyboardAccelerator", "KeyDown", "KeyUp", "PreviewKey", "AccessKey=", "ProcessKeyboardAccelerators", "CharacterReceived" })
        {
            foreach (string line in scan.Split('\n'))
            {
                string code = line.Split("//", 2)[0];
                if (code.Contains(token, StringComparison.Ordinal))
                {
                    found.Add($"{relPath}: undeclared key handling ({token}) outside the menu bar and AddTabAccelerators: {code.Trim()}");
                }
            }
        }

        return found;
    }

    internal const string SanctionedHelperBody =
        "{varaccel=newKeyboardAccelerator{Key=key,Modifiers=modifiers};accel.Invoked+=(_,args)=>{action();args.Handled=true;};scope.KeyboardAccelerators.Add(accel);}";

    static List<string> TabHomeProblems(string source)
    {
        var found = new List<string>();
        SyntaxNode root = CSharpSyntaxTree.ParseText(source).GetRoot();
        var methods = root.DescendantNodes().OfType<MethodDeclarationSyntax>().ToList();
        MethodDeclarationSyntax? helper = methods.FirstOrDefault(m => m.Identifier.Text == "AddAccel");
        if (helper is null)
        {
            found.Add($"{TabSourcePath}: the AddAccel helper is gone; the programmatic bindings cannot be derived");
            return found;
        }

        // R4-F1: the helper body must be exactly the sanctioned text
        // (whitespace aside), so no statement can re-key or re-modify the
        // accelerator after construction or add a second one.
        string body = new string((helper.Body?.ToString() ?? string.Empty).Where(c => !char.IsWhiteSpace(c)).ToArray());
        if (body != SanctionedHelperBody)
        {
            found.Add($"{TabSourcePath}: AddAccel no longer builds exactly one accelerator from its own key and modifiers parameters");
        }

        // Every reference to the helper's name counts, whatever its shape:
        // a plain call, a qualified call (MainWindow.AddAccel, this.AddAccel),
        // a method group handed to a delegate, or nameof. Only the calls in
        // AddTabAccelerators are derived, so any other reference is a way
        // to bind a chord the inventory never sees.
        foreach (IdentifierNameSyntax name in root.DescendantNodes().OfType<IdentifierNameSyntax>()
            .Where(n => n.Identifier.Text == "AddAccel"))
        {
            string? caller = name.Ancestors().OfType<MethodDeclarationSyntax>().FirstOrDefault()?.Identifier.Text;
            bool derived = caller == "AddTabAccelerators"
                && name.Parent is InvocationExpressionSyntax inv && inv.Expression == name;
            if (!derived)
            {
                found.Add($"{TabSourcePath}: AddAccel is referenced from {caller ?? "outside a method"} as `{name.Parent}`; only direct calls in AddTabAccelerators are derived");
            }
        }

        return found;
    }

    static string StripMethod(string source, params string[] names)
    {
        SyntaxNode root = CSharpSyntaxTree.ParseText(source).GetRoot();
        var spans = root.DescendantNodes().OfType<MethodDeclarationSyntax>()
            .Where(m => names.Contains(m.Identifier.Text)).Select(m => m.FullSpan).OrderByDescending(s => s.Start).ToList();
        string text = source;
        foreach (var span in spans)
        {
            text = text.Remove(span.Start, span.Length);
        }

        return text;
    }

    // ---- audit table -----------------------------------------------

    internal static List<AuditRow> ParseAudit(string markdown, out List<string> problems)
    {
        problems = [];
        var rows = new List<AuditRow>();
        string[] lines = markdown.Replace("\r\n", "\n", StringComparison.Ordinal).Split('\n');
        int start = Array.FindIndex(lines, l => l.StartsWith("## Accelerator binding sweep", StringComparison.Ordinal));
        if (start < 0)
        {
            problems.Add("docs/ui-input-audit.md: the Accelerator binding sweep section is missing");
            return rows;
        }

        int header = Array.FindIndex(lines, start, l => l.StartsWith("| Binding |", StringComparison.Ordinal));
        if (header < 0)
        {
            problems.Add("docs/ui-input-audit.md: the binding table is missing");
            return rows;
        }

        for (int i = header + 2; i < lines.Length && lines[i].StartsWith('|'); i++)
        {
            string[] cells = lines[i].Trim().Trim('|').Split('|').Select(c => c.Trim()).ToArray();
            if (cells.Length != 6)
            {
                problems.Add($"docs/ui-input-audit.md:{i + 1}: a binding row needs 6 cells (Binding, Command, Class, Coverage or reason, Approver, Owner), found {cells.Length}");
                continue;
            }

            Match id = Regex.Match(cells[1], "`([^`]+)`");
            if (!id.Success)
            {
                problems.Add($"docs/ui-input-audit.md:{i + 1}: the Command cell names no backticked command id");
                continue;
            }

            string label = Regex.Replace(cells[1], "\\s*\\(`[^`]+`\\)\\s*$", string.Empty).Replace(": ", " > ", StringComparison.Ordinal);
            rows.Add(new AuditRow(cells[0], id.Groups[1].Value, cells[2], cells[3], cells[4], cells[5], i + 1, label));
        }

        return rows;
    }

    // ---- test-body semantics ---------------------------------------

    // Chords a test method presses through UiInput.Press, including a
    // Theory's key parameter expanded from its InlineData rows.
    // R5-F1: a covering method must be one xUnit discovers: an attribute
    // whose name ends in Fact or Theory (Fact, Theory, InteractiveFact,
    // InteractiveTheory, PrimaryFact, HookFact, and the like).
    internal static bool IsDiscoverableTest(string source, string method) =>
        CSharpSyntaxTree.ParseText(source).GetRoot().DescendantNodes().OfType<MethodDeclarationSyntax>()
            .Where(m => m.Identifier.Text == method)
            .Any(m => m.AttributeLists.SelectMany(l => l.Attributes)
                .Select(a => a.Name.ToString().Split('.')[^1])
                .Any(n => n.EndsWith("Fact", StringComparison.Ordinal) || n.EndsWith("Theory", StringComparison.Ordinal)
                    || n.EndsWith("FactAttribute", StringComparison.Ordinal) || n.EndsWith("TheoryAttribute", StringComparison.Ordinal)));

    internal static HashSet<string> PressedChords(string source, string method)
    {
        var chords = new HashSet<string>(StringComparer.Ordinal);
        SyntaxNode root = CSharpSyntaxTree.ParseText(source).GetRoot();
        foreach (MethodDeclarationSyntax m in root.DescendantNodes().OfType<MethodDeclarationSyntax>().Where(m => m.Identifier.Text == method))
        {
            foreach (InvocationExpressionSyntax call in m.DescendantNodes().OfType<InvocationExpressionSyntax>())
            {
                if (call.Expression.ToString() != "UiInput.Press")
                {
                    continue;
                }

                var args = call.ArgumentList.Arguments;
                if (args.Count < 2)
                {
                    continue;
                }

                var mods = new List<string>();
                for (int a = 2; a < args.Count; a++)
                {
                    string name = args[a].NameColon?.Name.Identifier.Text ?? (a == 2 ? "withControl" : a == 3 ? "withShift" : "withAlt");
                    if (args[a].Expression.ToString() == "true")
                    {
                        mods.Add(name switch { "withControl" => "Ctrl", "withShift" => "Shift", _ => "Alt" });
                    }
                }

                string keyText = args[1].Expression.ToString();
                int param = m.ParameterList.Parameters.IndexOf(p => p.Identifier.Text == keyText);
                if (keyText.StartsWith("VirtualKeyShort.", StringComparison.Ordinal))
                {
                    chords.Add(Chord(mods, keyText["VirtualKeyShort.".Length..]));
                }
                else if (param >= 0)
                {
                    // A Theory key: bind each InlineData row's argument at the
                    // pressed parameter's position, never any key in the row.
                    foreach (AttributeSyntax attr in m.AttributeLists.SelectMany(l => l.Attributes).Where(a => a.Name.ToString() == "InlineData"))
                    {
                        var rowArgs = attr.ArgumentList?.Arguments ?? default;
                        string v = param < rowArgs.Count ? rowArgs[param].Expression.ToString() : string.Empty;
                        chords.Add(v.StartsWith("VirtualKeyShort.", StringComparison.Ordinal)
                            ? Chord(mods, v["VirtualKeyShort.".Length..])
                            : $"?unresolved:{keyText}");
                    }
                }
                else
                {
                    // A local, field, or computed key the manifest cannot
                    // read: it credits nothing, so the row fails loud.
                    chords.Add($"?unresolved:{keyText}");
                }
            }
        }

        return chords;
    }

    // D00 T02 §28 item 1: a covering test asserts an observable outcome
    // after it presses the chord. A press followed by no assertion (an
    // Assert call, directly or inside a lambda) proves the key went out,
    // not that the command ran.
    internal static bool AssertsAfterPress(string source, string method, string chord)
    {
        SyntaxNode root = CSharpSyntaxTree.ParseText(source).GetRoot();
        foreach (MethodDeclarationSyntax m in root.DescendantNodes().OfType<MethodDeclarationSyntax>().Where(m => m.Identifier.Text == method))
        {
            var presses = m.DescendantNodes().OfType<InvocationExpressionSyntax>()
                .Where(c => c.Expression.ToString() == "UiInput.Press" && PressedChords(PressOnly(m, c), method).Contains(chord)).ToList();
            if (presses.Count == 0)
            {
                continue;
            }

            int after = presses.Max(c => c.SpanStart);
            if (m.DescendantNodes().OfType<InvocationExpressionSyntax>()
                .Any(c => c.SpanStart > after && c.Expression.ToString().StartsWith("Assert.", StringComparison.Ordinal)))
            {
                return true;
            }
        }

        return false;
    }

    // The method with only one press kept, so PressedChords reads the
    // chord of that single call (Theory rows included).
    static string PressOnly(MethodDeclarationSyntax m, InvocationExpressionSyntax keep)
    {
        var others = m.DescendantNodes().OfType<InvocationExpressionSyntax>()
            .Where(c => c.Expression.ToString() == "UiInput.Press" && c != keep)
            .Select(c => c.Parent).OfType<ExpressionStatementSyntax>().ToList();
        MethodDeclarationSyntax pruned = m.RemoveNodes(others, SyntaxRemoveOptions.KeepNoTrivia) ?? m;
        return "class P { " + pruned.ToFullString() + " }";
    }

    // D00 T02 §28 item 10: an owner that owes a live command's chord test
    // must not still claim the command ships disabled. A claim line is
    // one naming the menu label beside "disabled"; it is tolerated only
    // while the owner carries an open checklist item owing the
    // reconciliation (naming "ships disabled"). Backticked spans quote
    // the note rather than claim it.
    internal static List<string> StaleDisabledClaims(string sectionBody, string label)
    {
        var lines = sectionBody.Replace("\r\n", "\n", StringComparison.Ordinal).Split('\n');
        bool reconciliationOwed = lines.Any(l => l.StartsWith("- [ ] ", StringComparison.Ordinal) && l.Contains("ships disabled", StringComparison.Ordinal));
        if (reconciliationOwed || label.Length == 0)
        {
            return [];
        }

        return lines.Where(l => l.Contains(label, StringComparison.Ordinal)
                && Regex.IsMatch(Regex.Replace(l, "`[^`]*`", string.Empty), "\\bdisabled\\b")
                && !l.Contains("enabled at runtime", StringComparison.Ordinal))
            .Select(l => l.Length > 120 ? l[..120] + "..." : l)
            .ToList();
    }

    // ---- owners ----------------------------------------------------

    // The obligation must be a checklist item naming the chord and this
    // rule; an XREF or prose mention is not an owed test.
    internal static bool OwesChordTest(string sectionBody, string chord) =>
        sectionBody.Replace("\r\n", "\n", StringComparison.Ordinal).Split('\n')
            .Any(l => (l.StartsWith("- [ ] ", StringComparison.Ordinal) || l.StartsWith("- [x] ", StringComparison.Ordinal))
                && l.Contains(chord, StringComparison.Ordinal)
                && l.Contains("D00 T02 §21", StringComparison.Ordinal));

    // Resolves `DNN TNN §N` to the section body plus its open/closed
    // row, reading the TODO tree the way todo-graph does.
    internal static (bool Found, bool Open, string Body) ReadSection(string repoRoot, string reference)
    {
        Match m = Regex.Match(reference, "^D(\\d{2}) T(\\d{2}) §(\\d+)$");
        if (!m.Success)
        {
            return (false, false, string.Empty);
        }

        string? dir = Directory.EnumerateDirectories(Path.Combine(repoRoot, "todo"), m.Groups[1].Value + "-*").FirstOrDefault();
        string? file = dir is null ? null : Directory.EnumerateFiles(dir, $"TODO-{m.Groups[2].Value}-*.md").FirstOrDefault();
        if (file is null)
        {
            return (false, false, string.Empty);
        }

        string text = File.ReadAllText(file).Replace("\r\n", "\n", StringComparison.Ordinal);
        string n = m.Groups[3].Value;
        Match row = Regex.Match(text, $"^\\|\\s*\\d+\\s*\\|\\s*§{n}\\s*\\|.*\\|\\s*\\[( |x)\\]\\s*\\|\\s*$", RegexOptions.Multiline);
        Match head = Regex.Match(text, $"^## {n}\\. .*$", RegexOptions.Multiline);
        if (!row.Success || !head.Success)
        {
            return (false, false, string.Empty);
        }

        int end = text.IndexOf("\n## ", head.Index + head.Length, StringComparison.Ordinal);
        string body = end < 0 ? text[head.Index..] : text[head.Index..end];
        return (true, row.Groups[1].Value == " ", body);
    }

    // ---- the check -------------------------------------------------

    internal sealed record Inputs(
        List<Declaration> Declarations,
        List<MenuAccessKey> AccessKeys,
        HashSet<string> RuntimeEnabled,
        List<AuditRow> Rows,
        Func<string, string?> TestSource,
        Func<string, (bool Found, bool Open, string Body)> Section);

    internal static List<string> Check(Inputs inp)
    {
        var problems = new List<string>();
        var declByKey = inp.Declarations.GroupBy(d => (d.Chord, d.Command)).ToDictionary(g => g.Key, g => g.First());
        var rowsByKey = inp.Rows.GroupBy(r => (r.Chord, r.Command)).ToDictionary(g => g.Key, g => g.ToList());

        foreach (var key in declByKey.Keys.Where(k => !rowsByKey.ContainsKey(k)))
        {
            problems.Add($"manifest: {key.Chord} -> {key.Command} is declared but has no audit row");
        }

        foreach (var (key, list) in rowsByKey)
        {
            if (!declByKey.ContainsKey(key))
            {
                problems.Add($"docs/ui-input-audit.md:{list[0].Line}: {key.Chord} -> {key.Command} has an audit row but no declaration");
            }

            if (list.Count > 1)
            {
                problems.Add($"docs/ui-input-audit.md:{list[1].Line}: {key.Chord} -> {key.Command} has {list.Count} audit rows");
            }
        }

        foreach (AuditRow row in inp.Rows)
        {
            declByKey.TryGetValue((row.Chord, row.Command), out Declaration? decl);
            bool live = decl is not null && (decl.XamlEnabled || inp.RuntimeEnabled.Contains(decl.Command));
            string at = $"docs/ui-input-audit.md:{row.Line}: {row.Chord} -> {row.Command}";
            if (!Classes.Contains(row.Class))
            {
                problems.Add($"{at}: class '{row.Class}' is outside the taxonomy ({string.Join(", ", Classes)})");
                continue;
            }

            if (row.Class == "covered")
            {
                var tests = Regex.Matches(row.Detail, "`(\\w+)\\.(\\w+)`").Select(t => (t.Groups[1].Value, t.Groups[2].Value)).ToList();
                if (tests.Count == 0)
                {
                    problems.Add($"{at}: covered names no `Class.Method` test");
                }

                foreach (var (cls, method) in tests)
                {
                    string? src = inp.TestSource(cls);
                    if (src is null)
                    {
                        problems.Add($"{at}: covering class {cls} does not exist in tests/UI");
                        continue;
                    }

                    if (!IsDiscoverableTest(src, method))
                    {
                        problems.Add($"{at}: {cls}.{method} carries no test attribute (Fact or Theory family), so it never runs and covers nothing");
                    }

                    var pressed = PressedChords(src, method);
                    if (!pressed.Contains(row.Chord))
                    {
                        problems.Add($"{at}: {cls}.{method} does not press {row.Chord} (presses {(pressed.Count == 0 ? "nothing" : string.Join(", ", pressed.OrderBy(p => p, StringComparer.Ordinal)))})");
                    }
                    else if (!AssertsAfterPress(src, method, row.Chord))
                    {
                        problems.Add($"{at}: {cls}.{method} presses {row.Chord} but asserts nothing after it, so a wrong handler would pass");
                    }
                }

                continue;
            }

            // Every exemption is approved and owned (the taxonomy rule).
            if (string.IsNullOrWhiteSpace(row.Approver) || row.Approver == "-")
            {
                problems.Add($"{at}: exemption class {row.Class} names no approver");
            }

            if (row.Class == "duplicate")
            {
                var same = inp.Declarations.Where(d => d.Chord == row.Chord && d.Command != row.Command).ToList();
                if (same.Count == 0)
                {
                    problems.Add($"{at}: duplicate, but no other command declares {row.Chord}");
                }

                if (!inp.Section(row.Owner).Found)
                {
                    problems.Add($"{at}: duplicate names owner '{row.Owner}', which does not resolve to a TODO section");
                }

                continue;
            }

            if (row.Class == "disabled" && live)
            {
                problems.Add($"{at}: exempt as disabled but the command is enabled (XAML or a runtime SetEnabled); cover the chord or move the row to owner-owed");
            }

            if (row.Class == "owner-owed" && !live)
            {
                problems.Add($"{at}: owner-owed but the command is disabled; the row is class disabled");
            }

            var (found, open, body) = inp.Section(row.Owner);
            if (!found)
            {
                problems.Add($"{at}: owner '{row.Owner}' does not resolve to a TODO section");
            }
            else if (!open)
            {
                problems.Add($"{at}: owner {row.Owner} is stamped, so it no longer owes the chord test; cover the chord");
            }
            else if (!OwesChordTest(body, row.Chord))
            {
                problems.Add($"{at}: owner {row.Owner}'s checklist does not owe the {row.Chord} chord test (it must name the chord and D00 T02 §21)");
            }

            if (found && row.Class == "owner-owed" && live)
            {
                foreach (string claim in StaleDisabledClaims(body, row.Label))
                {
                    problems.Add($"{at}: live, but owner {row.Owner} still claims {row.Label} ships disabled with no open reconciliation item: {claim}");
                }
            }
        }

        problems.AddRange(Conflicts(inp.Declarations, inp.AccessKeys, inp.Rows));
        return problems;
    }

    // The conflict matrix: one chord, one live command. A second
    // declaration of a chord is legal only as an audited duplicate
    // row; OS-reserved chords and access-key collisions never are.
    internal static List<string> Conflicts(List<Declaration> decls, List<MenuAccessKey> accessKeys, List<AuditRow> rows)
    {
        var problems = new List<string>();
        var dupRows = rows.Where(r => r.Class == "duplicate").Select(r => (r.Chord, r.Command)).ToHashSet();
        foreach (var group in decls.GroupBy(d => d.Chord).Where(g => g.Count() > 1))
        {
            var primaries = group.Where(d => !dupRows.Contains((d.Chord, d.Command))).ToList();
            if (primaries.Count != 1)
            {
                problems.Add($"conflict: {group.Key} is declared by {string.Join(", ", group.Select(d => $"{d.Command} ({d.Source})"))} with {primaries.Count} unaudited owners; exactly one may own it and the rest need duplicate rows");
            }
        }

        foreach (Declaration d in decls.Where(d => OsReserved.Contains(d.Chord)))
        {
            problems.Add($"conflict: {d.Chord} ({d.Command}) is OS-reserved");
        }

        foreach (var group in accessKeys.GroupBy(a => a.Key.ToUpperInvariant()).Where(g => g.Count() > 1))
        {
            problems.Add($"conflict: access key {group.Key} is shared by {string.Join(", ", group.Select(a => a.Menu))}");
        }

        foreach (MenuAccessKey ak in accessKeys)
        {
            string alt = Chord(["Alt"], ak.Key);
            foreach (Declaration d in decls.Where(d => d.Chord == alt))
            {
                problems.Add($"conflict: {alt} ({d.Command}) collides with the {ak.Menu} access key");
            }
        }

        return problems;
    }

    // Matrix rows for the report: every chord with its declarations.
    internal static IEnumerable<string> Matrix(List<Declaration> decls) =>
        decls.GroupBy(d => d.Chord).OrderBy(g => g.Key, StringComparer.Ordinal)
            .Select(g => $"{g.Key}: {string.Join(" | ", g.Select(d => $"{d.Command} [{(d.Source == MenuXamlPath ? "menu bar, window-global" : "root, window-global")}]"))}");
}
