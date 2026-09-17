using System.Windows.Input;

namespace ScratchPad;

// Minimal ICommand for TabView's AddTabButtonCommand. No MVVM toolkit in this
// project; a shared helper would be overkill for one binding.
internal sealed class RelayCommand(Action<object?> execute) : ICommand
{
#pragma warning disable CS0067 // Never raised: the add button is always enabled.
    public event EventHandler? CanExecuteChanged;
#pragma warning restore CS0067

    public bool CanExecute(object? parameter) => true;

    public void Execute(object? parameter) => execute(parameter);
}
