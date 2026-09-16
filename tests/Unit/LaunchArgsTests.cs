using Notepad.Core;
using Xunit;

namespace Unit;

// D01 T01 §8: command-line launch parser. End-to-end honor (files opening
// per mode, verbs answering, print exiting) is driven by the UI suite;
// these pin the grammar branches.
public sealed class LaunchArgsTests
{
    const string WorkDir = "C:\\work";

    [Fact]
    public void BareLaunchRequestsNothing()
    {
        LaunchRequest request = LaunchArgs.Parse([], WorkDir);
        Assert.Empty(request.Files);
        Assert.False(request.IsPrint);
        Assert.False(request.IsVerb);
    }

    [Fact]
    public void SingleFileRootsAgainstWorkDir()
    {
        LaunchRequest request = LaunchArgs.Parse(["note.txt"], WorkDir);
        Assert.Equal([Path.Combine(WorkDir, "note.txt")], request.Files);
    }

    [Fact]
    public void AbsolutePathsPassThrough()
    {
        LaunchRequest request = LaunchArgs.Parse(["D:\\docs\\a.txt"], WorkDir);
        Assert.Equal(["D:\\docs\\a.txt"], request.Files);
    }

    [Fact]
    public void MultipleFilesKeepOrder()
    {
        LaunchRequest request = LaunchArgs.Parse(["b.txt", "a.txt"], WorkDir);
        Assert.Equal([Path.Combine(WorkDir, "b.txt"), Path.Combine(WorkDir, "a.txt")], request.Files);
    }

    [Fact]
    public void PrintFlagTakesNextFile()
    {
        LaunchRequest request = LaunchArgs.Parse(["/p", "note.txt"], WorkDir);
        Assert.True(request.IsPrint);
        Assert.Equal(Path.Combine(WorkDir, "note.txt"), request.PrintFile);
        Assert.Null(request.PrintPrinter);
        Assert.Empty(request.Files);
    }

    [Fact]
    public void PrintToFlagTakesFileAndPrinter()
    {
        LaunchRequest request = LaunchArgs.Parse(["/pt", "note.txt", "HP Laser"], WorkDir);
        Assert.True(request.IsPrint);
        Assert.Equal(Path.Combine(WorkDir, "note.txt"), request.PrintFile);
        Assert.Equal("HP Laser", request.PrintPrinter);
    }

    [Fact]
    public void FlagsAreCaseInsensitive()
    {
        Assert.True(LaunchArgs.Parse(["/P", "a.txt"], WorkDir).IsPrint);
        Assert.True(LaunchArgs.Parse(["/PT", "a.txt", "prn"], WorkDir).IsPrint);
        Assert.True(LaunchArgs.Parse(["/REGISTER-ASSOCIATIONS"], WorkDir).IsVerb);
    }

    [Fact]
    public void IncompleteFlagsAreIgnored()
    {
        Assert.False(LaunchArgs.Parse(["/p"], WorkDir).IsPrint);
        Assert.False(LaunchArgs.Parse(["/pt", "a.txt"], WorkDir).IsPrint);
        Assert.False(LaunchArgs.Parse(["/p", "/pt"], WorkDir).IsPrint);
    }

    [Fact]
    public void UnknownFlagsAreIgnored()
    {
        LaunchRequest request = LaunchArgs.Parse(["/nosuchflag", "a.txt"], WorkDir);
        Assert.Equal([Path.Combine(WorkDir, "a.txt")], request.Files);
        Assert.False(request.IsPrint);
    }

    [Fact]
    public void VerbsAreExclusive()
    {
        LaunchRequest request = LaunchArgs.Parse(["a.txt", "/register-associations", "/p", "b.txt"], WorkDir);
        Assert.True(request.RegisterAssociations);
        Assert.False(request.UnregisterAssociations);
        Assert.Empty(request.Files);
        Assert.False(request.IsPrint);
        Assert.True(LaunchArgs.Parse(["/unregister-associations"], WorkDir).UnregisterAssociations);
    }

    [Theory]
    [InlineData("/new-note")]
    [InlineData("-new-note")]
    [InlineData("/NEW-NOTE")]
    public void NewNoteFlagParses(string flag)
    {
        LaunchRequest request = LaunchArgs.Parse([flag], WorkDir);
        Assert.True(request.NewNote);
        Assert.Empty(request.Files);
        Assert.False(request.IsVerb);
    }

    [Fact]
    public void NewNoteCombinesWithFiles()
    {
        LaunchRequest request = LaunchArgs.Parse(["a.txt", "/new-note"], WorkDir);
        Assert.True(request.NewNote);
        Assert.Equal([Path.Combine(WorkDir, "a.txt")], request.Files);
    }

    [Fact]
    public void VerbsClearNewNote()
    {
        LaunchRequest request = LaunchArgs.Parse(["/new-note", "/register-associations"], WorkDir);
        Assert.True(request.RegisterAssociations);
        Assert.False(request.NewNote);
    }
}
