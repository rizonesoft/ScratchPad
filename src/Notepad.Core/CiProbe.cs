namespace Notepad.Core;

// PROBE: deliberately violates CS0169 (compiler) and CA1822 (analysis) for
// the §4 red-run check. Removed by the revert immediately after CI goes red.
public class CiProbe
{
    private int _unused;

    public int Answer() => 42;
}
