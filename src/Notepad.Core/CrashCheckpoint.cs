namespace Notepad.Core;

// Crash-checkpoint policy, owned by D01 T01 §7. Stock 11.2607.14.0 restores
// killed sessions silently with no offer or notice (probed 2026-09-15: kill
// with a dirty file tab plus a dirty untitled tab relaunched to both buffers
// with zero dialogs, file bytes untouched), checkpointing continuously
// (content typed seconds before the kill survived). Our session.json doubles
// as the checkpoint: the App debounces edits by Debounce, then applies
// Decide; relaunch restores through the §6 path with no new file, marker,
// or dialog. The 2 s debounce is an engineering default (cost: one
// constant); stock's exact cadence is unobservable from outside.
public static class CrashCheckpoint
{
    public static readonly TimeSpan Debounce = TimeSpan.FromSeconds(2);

    public enum Decision
    {
        // Continue mode with a nontrivial session: write the checkpoint.
        Write,

        // Continue mode with a trivial session (mirrors quit: empty quits
        // stay file-clean), or fresh mode with a stale session file left
        // from an earlier continue session (fresh quits delete; a killed
        // fresh session must not resurrect on a later flip to continue).
        Delete,

        // Fresh mode with no stale file: nothing to do.
        Skip,
    }

    public static Decision Decide(StartupMode mode, bool trivial, bool fileExists) =>
        mode == StartupMode.ContinueSession
            ? (trivial ? Decision.Delete : Decision.Write)
            : (fileExists ? Decision.Delete : Decision.Skip);
}
