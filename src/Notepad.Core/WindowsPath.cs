namespace Notepad.Core;

// Windows-path handling with identical behavior on every OS, owned by
// D00 T02 §6 (track A). RULE: neutral code never calls System.IO.Path for
// Windows-path strings: Path follows the RUNNING OS, so IsPathFullyQualified,
// GetFileName, and GetFullPath answer differently on Linux CI than on the
// Windows host, and tests green at stamp time go red in CI (16 Unit failures
// since 511c99a). These helpers implement Windows BCL semantics textually:
// drive-absolute and UNC paths are rooted, joining uses backslash, and
// normalization flips slashes, collapses repeats, and resolves dot segments
// the way GetFullPath does. Real local paths (app-data dirs, temp files)
// still use System.IO.Path: those ARE platform paths. Callers with a
// Windows-path string use this; callers with a machine path use Path.
public static class WindowsPath
{
    // Path.IsPathFullyQualified on Windows, textually: drive-absolute
    // (C:\ or C:/) or UNC (\\ or // prefix). Drive-relative (\x) and bare
    // /x are NOT rooted, matching the BCL. Null or empty is not rooted.
    public static bool IsRooted(string? path)
    {
        if (string.IsNullOrEmpty(path))
        {
            return false;
        }

        if (path.StartsWith(@"\\", StringComparison.Ordinal) || path.StartsWith("//", StringComparison.Ordinal))
        {
            return true;
        }

        return path.Length >= 3
            && char.IsAsciiLetter(path[0])
            && path[1] == ':'
            && (path[2] == '\\' || path[2] == '/');
    }

    // Path.GetFileName on Windows, textually: the span after the last
    // separator of either kind. A trailing separator yields empty and a
    // bare name yields itself, matching the BCL.
    public static string GetFileName(string path)
    {
        ArgumentNullException.ThrowIfNull(path);
        int cut = path.LastIndexOfAny(['\\', '/']);
        return cut < 0 ? path : path[(cut + 1)..];
    }

    // Path.Combine plus GetFullPath on Windows, textually, for a rooted
    // Windows directory plus a relative segment. A rooted rel wins
    // unchanged (normalized); a drive-relative rel (\x) resolves against
    // the directory's drive; anything else joins under the directory.
    public static string Combine(string directory, string rel)
    {
        ArgumentException.ThrowIfNullOrEmpty(directory);
        ArgumentException.ThrowIfNullOrEmpty(rel);
        if (IsRooted(rel))
        {
            return Normalize(rel);
        }

        if (rel[0] == '\\' || rel[0] == '/')
        {
            return DriveOf(directory) + '\\' + Normalize(rel);
        }

        return Normalize(directory.TrimEnd('\\', '/') + '\\' + rel);
    }

    // GetFullPath normalization on Windows, textually: forward slashes
    // flip, repeat separators collapse (the UNC prefix pair survives),
    // single dots drop, and double dots pop (clamped at the root, as the
    // BCL clamps C:\..\x to C:\x).
    public static string Normalize(string path)
    {
        ArgumentException.ThrowIfNullOrEmpty(path);
        string flipped = path.Replace('/', '\\');
        bool unc = flipped.StartsWith(@"\\", StringComparison.Ordinal);
        string[] parts = flipped.Split('\\');
        var kept = new List<string>();
        foreach (string part in parts)
        {
            if (part.Length == 0 || part == ".")
            {
                continue;
            }

            if (part == "..")
            {
                // Never pop the drive/UNC root itself: the first kept
                // segment of a rooted path (C: or the UNC server) stays.
                bool atRoot = kept.Count == 0
                    || (kept.Count == 1 && IsRooted(path))
                    || (unc && kept.Count == 2);
                if (!atRoot)
                {
                    kept.RemoveAt(kept.Count - 1);
                }

                continue;
            }

            kept.Add(part);
        }

        string joined = string.Join('\\', kept);
        if (unc)
        {
            return @"\\" + joined;
        }

        // A bare drive is drive-relative; the BCL keeps the root slash.
        if (joined.Length == 2 && joined[1] == ':')
        {
            return joined + '\\';
        }

        return joined;
    }

    static string DriveOf(string directory)
    {
        int colon = directory.IndexOf(':', StringComparison.Ordinal);
        return colon >= 0 ? directory[..(colon + 1)] : string.Empty;
    }
}
