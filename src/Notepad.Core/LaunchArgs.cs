namespace Notepad.Core;

// Command-line launch request, owned by D01 T01 §8. Stock 11.2607.14.0
// behavior (probed 2026-09-15): positional paths open as tabs in the live
// window (deduped); /p and /pt are recognized print flags (consumed, never
// treated as filenames); unknown flags are ignored (default: stock's
// unknown-flag behavior is unprobed; ignoring is the non-destructive
// reading, cost one branch). The /register-associations and
// /unregister-associations verbs are ours (no stock counterpart): the app
// answers them and exits, and D07's installer calls the same seam.
public sealed record LaunchRequest(
    IReadOnlyList<string> Files,
    string? PrintFile,
    string? PrintPrinter,
    bool RegisterAssociations,
    bool UnregisterAssociations)
{
    public bool IsPrint => PrintFile is not null;

    public bool IsVerb => RegisterAssociations || UnregisterAssociations;
}

public static class LaunchArgs
{
    public const string PrintFlag = "/p";

    public const string PrintToFlag = "/pt";

    public const string RegisterFlag = "/register-associations";

    public const string UnregisterFlag = "/unregister-associations";

    // Parses raw process args (argv without the exe). workingDirectory
    // roots relative paths; absolute paths pass through untouched.
    // Incomplete flags (/p with no file, /pt with no printer) are ignored,
    // and verbs are exclusive: with a verb present, files never open.
    public static LaunchRequest Parse(IEnumerable<string> args, string workingDirectory)
    {
        ArgumentNullException.ThrowIfNull(args);
        ArgumentException.ThrowIfNullOrEmpty(workingDirectory);
        var files = new List<string>();
        string? printFile = null;
        string? printPrinter = null;
        bool register = false;
        bool unregister = false;
        List<string> rest = new(args);
        for (int i = 0; i < rest.Count; i++)
        {
            string arg = rest[i];
            if (!IsFlag(arg))
            {
                files.Add(Root(arg, workingDirectory));
                continue;
            }

            switch (arg.ToUpperInvariant())
            {
                case "/P" or "-P" when i + 1 < rest.Count && !IsFlag(rest[i + 1]):
                    printFile = Root(rest[i + 1], workingDirectory);
                    i++;
                    break;
                case "/PT" or "-PT" when i + 2 < rest.Count && !IsFlag(rest[i + 1]) && !IsFlag(rest[i + 2]):
                    printFile = Root(rest[i + 1], workingDirectory);
                    printPrinter = rest[i + 2];
                    i += 2;
                    break;
                case "/REGISTER-ASSOCIATIONS" or "-REGISTER-ASSOCIATIONS":
                    register = true;
                    break;
                case "/UNREGISTER-ASSOCIATIONS" or "-UNREGISTER-ASSOCIATIONS":
                    unregister = true;
                    break;
                default:
                    break;
            }
        }

        if (register || unregister)
        {
            files.Clear();
            printFile = null;
            printPrinter = null;
        }

        return new LaunchRequest(files, printFile, printPrinter, register, unregister);
    }

    static bool IsFlag(string arg) => arg.StartsWith('/') || arg.StartsWith('-');

    static string Root(string path, string workingDirectory) =>
        Path.IsPathFullyQualified(path) ? path : Path.GetFullPath(Path.Combine(workingDirectory, path));
}
