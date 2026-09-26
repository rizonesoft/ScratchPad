using System.Reflection;
using System.Runtime.Loader;
using CaseIdentity;

// Canonical Theory case rows for a built test assembly (D00 T02 §52 item
// 3). Usage:
//   CaseIdentity <test assembly> <Namespace.Class.Method> [...]
// Prints one row per case of each named method (`<Type.Method>(<args>)`,
// occurrences numbered) and exits 0; a value no encoding rule covers, or a
// method that cannot be found, prints `REFUSE <method>: <reason>` and exits
// 1, so the population check refuses by name instead of guessing.
Console.OutputEncoding = System.Text.Encoding.UTF8;
if (args.Length < 2 || !File.Exists(args[0]))
{
    Console.WriteLine("usage: CaseIdentity <test assembly> <Namespace.Class.Method> [...]");
    return 2;
}

string path = Path.GetFullPath(args[0]);
var resolver = new AssemblyDependencyResolver(path);
var context = new AssemblyLoadContext("case-identity", isCollectible: false);
context.Resolving += (ctx, name) =>
{
    string? p = resolver.ResolveAssemblyToPath(name);
    if (p is null)
    {
        string local = Path.Combine(Path.GetDirectoryName(path)!, name.Name + ".dll");
        p = File.Exists(local) ? local : null;
    }

    return p is null ? null : ctx.LoadFromAssemblyPath(p);
};
Assembly assembly = context.LoadFromAssemblyPath(path);
Type?[] types;
try
{
    types = assembly.GetTypes();
}
catch (ReflectionTypeLoadException ex)
{
    types = ex.Types;
}

int code = 0;
foreach (string wanted in args.Skip(1))
{
    int dot = wanted.LastIndexOf('.');
    string typeName = dot > 0 ? wanted[..dot] : string.Empty;
    string methodName = dot > 0 ? wanted[(dot + 1)..] : wanted;
    MethodInfo? method = types.Where(t => t?.FullName == typeName).SelectMany(t => t!.GetMethods(BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance | BindingFlags.Static)).FirstOrDefault(m => m.Name == methodName);
    if (method is null)
    {
        Console.WriteLine($"REFUSE {wanted}: no such method in {Path.GetFileName(path)}");
        code = 1;
        continue;
    }

    try
    {
        foreach (string row in CaseIdentityEncoder.RowsFor(method))
        {
            Console.WriteLine(row);
        }
    }
    catch (UnsupportedArgumentException ex)
    {
        Console.WriteLine($"REFUSE {wanted}: {ex.Message}");
        code = 1;
    }
}

return code;
