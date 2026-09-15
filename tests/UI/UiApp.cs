using FlaUI.Core;
using FlaUI.Core.AutomationElements;
using FlaUI.UIA3;

namespace UI;

// Single attach funnel for every UI test. GetMainWindow used to sit
// outside try, so an attach failure leaked the launched process, and one
// leaked primary turns every later launch into a redirected window (the
// app is single-instance) while their own attaches fail: the 2026-09-16
// gate cascade (58 failures, ~60 windows, one process). Attach reaps the
// launched process on any attach failure and rethrows, so a failing test
// can never poison the suite behind it.
internal static class UiApp
{
    [System.Diagnostics.CodeAnalysis.SuppressMessage("Design", "CA1031:Do not catch general exception types", Justification = "FlaUI reports a lost process as plain System.Exception; the catch only reaps the launched process and rethrows.")]
    internal static Window? Attach(Application app, UIA3Automation automation, TimeSpan timeout)
    {
        ArgumentNullException.ThrowIfNull(app);
        try
        {
            return app.GetMainWindow(automation, timeout);
        }
        catch (Exception)
        {
            try
            {
                if (!app.HasExited)
                {
                    app.Kill();
                }
            }
            catch (Exception ex) when (ex is InvalidOperationException or System.ComponentModel.Win32Exception)
            {
                // Reap is best-effort; the gate post-sweep is the backstop.
            }

            throw;
        }
    }
}
