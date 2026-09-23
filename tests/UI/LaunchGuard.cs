using Microsoft.CodeAnalysis;
using Microsoft.CodeAnalysis.CSharp;
using Microsoft.CodeAnalysis.CSharp.Syntax;

namespace UI;

// Repository guard (D00 T02 §18 item 6): every app launch in the UI
// suite routes through UiLaunch, enforced by syntax plus alias
// resolution rather than by text search. One file is home
// (UiLaunch.cs); every other tests/UI source fails the guard when it
// defines a launch helper, invokes a launcher, reaches one through
// reflection, or imports a process-creating entry point:
// aliases (using X = ...Process), wrappers and renamed helpers (the
// invocation is flagged wherever it sits), Process-typed locals
// (tracked from declarations plus new-initializers), static
// usings, reflective lookup and invocation members (GetMethod,
// InvokeMember, CreateInstance, GetType, Invoke-with-arguments),
// the dynamic keyword, and DllImport entry points all trip it.
// Member-name choke points close fully dynamic reflection too: a
// method name built at runtime still passes through GetMethod or
// Invoke to run. Read-only enumeration (GetTypes, GetMethods,
// attribute reads) stays allowed: the nightly-partition and
// quiet-hours meta-tests pin suite shape that way.
internal static class LaunchGuard
{
    static readonly StringComparer Ordinal = StringComparer.Ordinal;

    static readonly HashSet<string> ProcessCreationEntries = new(StringComparer.OrdinalIgnoreCase)
    {
        "CreateProcess",
        "CreateProcessA",
        "CreateProcessW",
        "CreateProcessAsUser",
        "CreateProcessAsUserA",
        "CreateProcessAsUserW",
        "ShellExecute",
        "ShellExecuteA",
        "ShellExecuteW",
        "ShellExecuteEx",
        "WinExec",
        "NtCreateProcess",
        "NtCreateProcessEx",
        "ZwCreateProcess",
        "ZwCreateProcessEx",
    };


    internal static IReadOnlyList<string> FindViolations(string source, string fileName)
    {
        // Exact sanctioned-path exemption (D00 T02 §18 R1-F1): only
        // the central helper's own relative path skips the scan. A
        // suffix match would exempt MyUiLaunch.cs or a nested
        // same-name file, and separators normalize so no caller
        // spelling slips past. Fail-closed: anything else scans.
        if (fileName.Replace('\\', '/').Equals("tests/UI/UiLaunch.cs", StringComparison.Ordinal))
        {
            return [];
        }

        var tree = CSharpSyntaxTree.ParseText(source);
        SyntaxNode root = tree.GetRoot();
        var violations = new List<string>();
        string At(SyntaxNode node, string rule, string detail) =>
            $"{fileName}:{tree.GetLineSpan(node.Span).StartLinePosition.Line + 1} {rule}: {detail}";

        var processAliases = new HashSet<string>(Ordinal);
        var appAliases = new HashSet<string>(Ordinal);
        var namespaceAliases = new Dictionary<string, string>(Ordinal);
        bool staticProcess = false;
        bool staticApplication = false;
        foreach (UsingDirectiveSyntax directive in root.DescendantNodes().OfType<UsingDirectiveSyntax>())
        {
            string target = directive.Name?.ToString() ?? string.Empty;
            if (directive.Alias is null)
            {
                if (directive.StaticKeyword != default)
                {
                    if (target is "Process" || target.EndsWith(".Process", StringComparison.Ordinal))
                    {
                        staticProcess = true;
                    }

                    if (target is "Application" || target.EndsWith(".Application", StringComparison.Ordinal))
                    {
                        staticApplication = true;
                    }
                }

                continue;
            }

            string alias = directive.Alias.Name.Identifier.Text;
            if (target is "Process" || target.EndsWith(".Process", StringComparison.Ordinal))
            {
                processAliases.Add(alias);
            }
            else if (target is "Application" || target.EndsWith(".Application", StringComparison.Ordinal))
            {
                appAliases.Add(alias);
            }
            else
            {
                namespaceAliases[alias] = target;
            }
        }

        string Expand(string receiver)
        {
            int dot = receiver.IndexOf('.', StringComparison.Ordinal);
            string head = dot < 0 ? receiver : receiver[..dot];
            if (namespaceAliases.TryGetValue(head, out string? expanded))
            {
                return dot < 0 ? expanded : expanded + receiver[dot..];
            }

            return receiver;
        }

        bool IsProcessReceiver(string receiver)
        {
            string expanded = Expand(receiver);
            return expanded is "Process"
                || expanded.EndsWith(".Process", StringComparison.Ordinal)
                || processAliases.Contains(expanded)
                || ProcessNames(root).Contains(expanded);
        }

        bool IsApplicationReceiver(string receiver)
        {
            string expanded = Expand(receiver);
            return expanded is "Application"
                || expanded.EndsWith(".Application", StringComparison.Ordinal)
                || appAliases.Contains(expanded);
        }

        foreach (InvocationExpressionSyntax invocation in root.DescendantNodes().OfType<InvocationExpressionSyntax>())
        {
            if (invocation.Expression is MemberAccessExpressionSyntax access)
            {
                string receiver = access.Expression.ToString();
                string name = access.Name.Identifier.Text;
                if (name == "Start" && IsProcessReceiver(receiver))
                {
                    violations.Add(At(invocation, "direct-launch", $"{receiver}.Start launches outside UiLaunch"));
                }
                else if (name == "Start"
                    && access.Expression is ObjectCreationExpressionSyntax creation
                    && IsProcessType(creation.Type))
                {
                    // Inline construction (D00 T02 §18 R1-F4): new
                    // Process().Start() has no declared name for the
                    // ProcessNames check, so the creation type trips it.
                    violations.Add(At(invocation, "direct-launch", "new Process().Start launches outside UiLaunch"));
                }
                else if (name == "Launch" && IsApplicationReceiver(receiver))
                {
                    violations.Add(At(invocation, "direct-launch", $"{receiver}.Launch launches outside UiLaunch"));
                }
                else if (name is "GetMethod" or "InvokeMember" or "CreateInstance")
                {
                    violations.Add(At(invocation, "reflection-surface", $"reflective {name} has no UI test use"));
                }
                else if (receiver is "Type" && name == "GetType")
                {
                    violations.Add(At(invocation, "reflection-surface", "Type.GetType has no UI test use"));
                }
                else if (name == "Invoke" && (invocation.ArgumentList?.Arguments.Count ?? 0) >= 1)
                {
                    // MethodInfo/ConstructorInfo.Invoke takes target
                    // plus arguments; the only legitimate UI-test
                    // Invoke (FlaUI buttons) takes none.
                    violations.Add(At(invocation, "reflection-surface", $"{receiver}.Invoke has no UI test use"));
                }
            }
            else if (invocation.Expression is IdentifierNameSyntax bare)
            {
                string name = bare.Identifier.Text;
                if (name == "Start" && staticProcess)
                {
                    violations.Add(At(invocation, "direct-launch", "bare Start resolves to Process.Start"));
                }
                else if (name == "Launch" && staticApplication)
                {
                    violations.Add(At(invocation, "direct-launch", "bare Launch resolves to Application.Launch"));
                }
            }
        }

        foreach (MemberDeclarationSyntax member in root.DescendantNodes().OfType<MemberDeclarationSyntax>())
        {
            string? name = member switch
            {
                MethodDeclarationSyntax m => m.Identifier.Text,
                PropertyDeclarationSyntax p => p.Identifier.Text,
                _ => null,
            };
            if (name is not null
                && (name.StartsWith("LaunchApp", StringComparison.Ordinal)
                    || name.StartsWith("SeedSettings", StringComparison.Ordinal))
                && !IsTestMethod(member))
            {
                violations.Add(At(member, "per-file-helper", $"{name} is defined outside UiLaunch"));
            }

            foreach (AttributeListSyntax attributes in member.AttributeLists)
            {
                foreach (AttributeSyntax attribute in attributes.Attributes)
                {
                    string attributeName = attribute.Name.ToString();
                    if (attributeName is not "DllImport" && !attributeName.EndsWith(".DllImport", StringComparison.Ordinal))
                    {
                        continue;
                    }

                    string? entry = null;
                    foreach (AttributeArgumentSyntax argument in attribute.ArgumentList?.Arguments ?? [])
                    {
                        if (argument.NameEquals?.Name.Identifier.Text == "EntryPoint"
                            && argument.Expression is LiteralExpressionSyntax literal
                            && literal.Token.Value is string text)
                        {
                            entry = text;
                        }
                    }

                    entry ??= (member as MethodDeclarationSyntax)?.Identifier.Text;
                    if (entry is not null && ProcessCreationEntries.Contains(entry))
                    {
                        violations.Add(At(attribute, "process-pinvoke", $"{entry} creates processes outside UiLaunch"));
                    }
                }
            }
        }

        foreach (IdentifierNameSyntax identifier in root.DescendantNodes().OfType<IdentifierNameSyntax>())
        {
            if (identifier.Identifier.Text == "dynamic")
            {
                violations.Add(At(identifier, "reflection-surface", "dynamic dispatch has no UI test use"));
            }
        }

        foreach (LocalFunctionStatementSyntax local in root.DescendantNodes().OfType<LocalFunctionStatementSyntax>())
        {
            string name = local.Identifier.Text;
            if (name.StartsWith("LaunchApp", StringComparison.Ordinal)
                || name.StartsWith("SeedSettings", StringComparison.Ordinal))
            {
                violations.Add(At(local, "per-file-helper", $"{name} is defined outside UiLaunch"));
            }
        }

        return violations;
    }

    // Test methods ([Fact] and kin) may carry launch-family names for
    // what they pin; their bodies still scan, so a helper hiding
    // behind [Fact] trips the invocation rules instead.
    static bool IsTestMethod(MemberDeclarationSyntax member)
    {
        foreach (AttributeListSyntax attributes in member.AttributeLists)
        {
            foreach (AttributeSyntax attribute in attributes.Attributes)
            {
                string attributeName = attribute.Name.ToString();
                if (attributeName is "Theory"
                    || attributeName.EndsWith("Fact", StringComparison.Ordinal))
                {
                    return true;
                }
            }
        }

        return false;
    }

    // Names declared Process-typed in this file (locals, parameters,
    // fields), so instance Starts on them trip the direct-launch
    // rule. Scope-blind by design: a second type sharing the name in
    // one file is rarer than the bypass it would hide.
    static HashSet<string> ProcessNames(SyntaxNode root)
    {
        var names = new HashSet<string>(Ordinal);
        foreach (VariableDeclaratorSyntax declarator in root.DescendantNodes().OfType<VariableDeclaratorSyntax>())
        {
            if (declarator.Parent is VariableDeclarationSyntax declaration
                && (IsProcessType(declaration.Type) || IsProcessCreation(declarator.Initializer?.Value)))
            {
                names.Add(declarator.Identifier.Text);
            }
        }

        foreach (ParameterSyntax parameter in root.DescendantNodes().OfType<ParameterSyntax>())
        {
            if (parameter.Type is not null && IsProcessType(parameter.Type))
            {
                names.Add(parameter.Identifier.Text);
            }
        }

        foreach (BaseFieldDeclarationSyntax field in root.DescendantNodes().OfType<BaseFieldDeclarationSyntax>())
        {
            if (IsProcessType(field.Declaration.Type))
            {
                foreach (VariableDeclaratorSyntax declarator in field.Declaration.Variables)
                {
                    names.Add(declarator.Identifier.Text);
                }
            }
        }

        // Assignment aliases (D00 T02 §18 R2-F3): `var alias = p;`
        // carries the Process-ness of p. Iterate to a fixpoint so
        // chains (alias-of-alias) resolve; the loop is bounded by
        // the declarator count. Coalesce, ternary, and field flows
        // stay outside the syntax-plus-alias boundary by design.
        bool added;
        do
        {
            added = false;
            foreach (VariableDeclaratorSyntax declarator in root.DescendantNodes().OfType<VariableDeclaratorSyntax>())
            {
                if (declarator.Initializer?.Value is IdentifierNameSyntax source
                    && names.Contains(source.Identifier.Text)
                    && names.Add(declarator.Identifier.Text))
                {
                    added = true;
                }
            }
        }
        while (added);

        return names;
    }

    static bool IsProcessCreation(ExpressionSyntax? value) =>
        value is ObjectCreationExpressionSyntax creation && IsProcessType(creation.Type);

    static bool IsProcessType(TypeSyntax? type)
    {
        string text = type?.ToString() ?? string.Empty;
        return text is "Process"
            || text is "Process?"
            || text.EndsWith(".Process", StringComparison.Ordinal)
            || text.EndsWith(".Process?", StringComparison.Ordinal);
    }
}
