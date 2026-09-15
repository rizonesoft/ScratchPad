using Xunit;

namespace Unit;

// Discovery-time Windows gate: read-only attributes are enforced by Windows
// while POSIX permission bits are root-overridable, so attribute tests run
// on Windows and report Skipped elsewhere.
sealed class WindowsOnlyFactAttribute : FactAttribute
{
    public WindowsOnlyFactAttribute()
    {
        if (!OperatingSystem.IsWindows())
        {
            Skip = "Read-only attributes are enforced by Windows; POSIX bits are root-overridable.";
        }
    }
}
