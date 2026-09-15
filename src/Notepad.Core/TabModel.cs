using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Runtime.CompilerServices;

namespace Notepad.Core;

// Tab list model, owned by D01 T01 §2. UI-free: the TabView (§3) and the editor
// (D02 T01) observe it; nothing here references WinUI. Recorded live from Notepad
// 11.2607.14.0: dirty "*" prefixes the name (§1 title rule); untitled tabs take
// the first content line trimmed to 35 chars, else "Untitled"; empty untitled
// tabs and Don't-save-discarded closes never reappear on Ctrl+Shift+T, so the
// model does not stack them. The reopen stack is unbounded: no measurable cap
// exists (untitled closes yield zero reopens, saved-tab depth unprobed), which
// matches the §6/§7 session-restore semantics; if a cap is ever measured, add
// a constant plus an eviction test. Undo-to-save-point clears dirty through
// MarkClean, wired by D02 T01 §4; "only on save" in the plan means no
// spontaneous clears, per the section checkpoint.
public sealed class TabModel : INotifyPropertyChanged
{
    public event PropertyChangedEventHandler? PropertyChanged;

    public ObservableCollection<Tab> Tabs { get; } = new();

    public Stack<ClosedTab> Closed { get; } = new();

    public Tab? ActiveTab
    {
        get;
        set
        {
            if (!ReferenceEquals(field, value))
            {
                field = value;
                OnPropertyChanged();
            }
        }
    }

    public Tab NewTab()
    {
        var tab = new Tab();
        Tabs.Add(tab);
        ActiveTab = tab;
        return tab;
    }

    // Opens a detected file as a tab, owned by D01 T01 §4. An already-open
    // path focuses instead of duplicating (case-insensitive: Windows paths);
    // the focus-not-duplicate default is bedtime-confirmed against stock.
    public Tab OpenTab(string path, DetectedFile file)
    {
        ArgumentNullException.ThrowIfNull(path);
        ArgumentNullException.ThrowIfNull(file);
        Tab? existing = Tabs.FirstOrDefault(t => string.Equals(t.FilePath, path, StringComparison.OrdinalIgnoreCase));
        if (existing is not null)
        {
            ActiveTab = existing;
            return existing;
        }

        var tab = new Tab
        {
            FilePath = path,
            Encoding = file.EncodingName,
            HasBom = file.HasBom,
            LineEnding = file.LineEnding.Dominant,
        };
        tab.NotifyEdited(file.Text);
        tab.MarkSaved();
        Tabs.Add(tab);
        ActiveTab = tab;
        return tab;
    }

    // Closes a tab. Content and caret come from the editor buffer (D02 T01),
    // which is the only writer; the model snapshots what the stack needs.
    // Pass content null when the tab is clean at close (reopen reloads by path).
    // Closing a tab that is not open is a no-op, so double-close races are safe.
    public void CloseTab(Tab tab, string? content, int caretOffset, bool discardUnsaved)
    {
        ArgumentNullException.ThrowIfNull(tab);
        int index = Tabs.IndexOf(tab);
        if (index < 0)
        {
            return;
        }

        if (!discardUnsaved && (tab.FilePath is not null || !string.IsNullOrEmpty(content)))
        {
            Closed.Push(new ClosedTab(tab.FilePath, content, caretOffset, tab.Encoding, tab.LineEnding));
        }

        Tabs.Remove(tab);
        if (ReferenceEquals(ActiveTab, tab))
        {
            ActiveTab = Tabs.Count == 0 ? null : Tabs[Math.Min(index, Tabs.Count - 1)];
        }
    }

    public Tab? ReopenLast()
    {
        if (!Closed.TryPop(out ClosedTab? entry))
        {
            return null;
        }

        var tab = new Tab
        {
            FilePath = entry.FilePath,
            Encoding = entry.Encoding,
            LineEnding = entry.LineEnding,
        };
        if (entry.Contents is not null)
        {
            tab.NotifyEdited(entry.Contents);
        }

        Tabs.Add(tab);
        ActiveTab = tab;
        return tab;
    }

    void OnPropertyChanged([CallerMemberName] string? name = null)
    {
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
    }
}

public enum SaveRequestOutcome
{
    SaveToPath,
    SaveAsRequired,
}

public sealed record ClosedTab(string? FilePath, string? Contents, int CaretOffset, string Encoding, string LineEnding);

public sealed class Tab : INotifyPropertyChanged
{
    public event PropertyChangedEventHandler? PropertyChanged;

    public Guid Id { get; } = Guid.NewGuid();

    public string? FilePath
    {
        get;
        set
        {
            if (field != value)
            {
                field = value;
                OnPropertyChanged();
                OnPropertyChanged(nameof(DisplayName));
            }
        }
    }

    public bool IsUntitled => FilePath is null;

    // Untitled tabs route their save to the §5 Save As dialog; pathed tabs save in place.
    public SaveRequestOutcome SaveRequest => FilePath is null ? SaveRequestOutcome.SaveAsRequired : SaveRequestOutcome.SaveToPath;

    public bool IsDirty
    {
        get;
        private set
        {
            if (field != value)
            {
                field = value;
                OnPropertyChanged();
            }
        }
    }

    public string Encoding
    {
        get;
        set
        {
            if (field != value)
            {
                field = value;
                OnPropertyChanged();
            }
        }
    } = "UTF-8";

    // Whether the file carries a byte-order mark; preserved across saves
    // (D01 T01 §5: stock adds one to BOM-less UTF-16, we round-trip).
    public bool HasBom
    {
        get;
        set
        {
            if (field != value)
            {
                field = value;
                OnPropertyChanged();
            }
        }
    }

    public string LineEnding
    {
        get;
        set
        {
            if (field != value)
            {
                field = value;
                OnPropertyChanged();
            }
        }
    } = "CRLF";

    // Saved tabs show the file name; untitled tabs show the first content line,
    // trimmed, 35 chars max, else "Untitled". Recorded live: 34 chars show
    // fully, 36 truncate to 35 with no ellipsis, surrounding spaces strip.
    // Whitespace-only content resolving to "Untitled" is inferred from the
    // cleared-content probe (empty untitled shows "Untitled").
    public string DisplayName => FilePath is null ? TabDisplayName.FromContent(FirstLine) : Path.GetFileName(FilePath);

    public string FirstLine
    {
        get;
        private set
        {
            if (field != value)
            {
                field = value;
                OnPropertyChanged();
                OnPropertyChanged(nameof(DisplayName));
            }
        }
    } = string.Empty;

    public string WindowTitle(string appName) => Notepad.Core.WindowTitle.Format(DisplayName, IsDirty, appName);

    // The editor calls this on every content change. Untitled tabs are dirty
    // exactly when they hold content (proven: clearing flips back to clean);
    // saved tabs latch dirty until a save or an undo-to-save-point.
    public void NotifyEdited(string content)
    {
        ArgumentNullException.ThrowIfNull(content);
        FirstLine = FirstLineOf(content);
        IsDirty = IsUntitled ? content.Length != 0 : true;
    }

    public void MarkSaved()
    {
        IsDirty = false;
    }

    // Records a completed save, owned by D01 T01 §5: path (Save As moves
    // the tab), the written encoding, BOM, and EOL, and the cleared dirty
    // flag. Called only after the bytes commit; failures never reach here.
    public void ApplySave(string path, SaveSpec spec)
    {
        ArgumentNullException.ThrowIfNull(path);
        ArgumentNullException.ThrowIfNull(spec);
        FilePath = path;
        Encoding = spec.EncodingName;
        HasBom = spec.HasBom;
        LineEnding = spec.LineEnding;
        MarkSaved();
    }

    // Undo-to-save-point seam, called by the D02 T01 §4 undo stack when it pops
    // back to the saved revision. Notepad clears the dirty marker there.
    public void MarkClean()
    {
        IsDirty = false;
    }

    static string FirstLineOf(string content)
    {
        int end = content.IndexOfAny(['\r', '\n']);
        return end < 0 ? content : content[..end];
    }

    void OnPropertyChanged([CallerMemberName] string? name = null)
    {
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
    }
}

public static class TabDisplayName
{
    public const int MaxLength = 35;

    public const string Untitled = "Untitled";

    public static string FromContent(string firstLine)
    {
        ArgumentNullException.ThrowIfNull(firstLine);
        string trimmed = firstLine.Trim();
        if (trimmed.Length == 0)
        {
            return Untitled;
        }

        return trimmed.Length <= MaxLength ? trimmed : trimmed[..MaxLength];
    }
}
