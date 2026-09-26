using System.Reflection;
using CaseIdentity;
using Xunit;

namespace Unit;

// D00 T02 §52 item 3: the canonical case-identity encoding. The fixture
// methods carry data attributes but no [Theory], so xunit never runs them;
// the encoder reads them exactly as it reads a real UI Theory.
#pragma warning disable xUnit1008 // data without [Theory] is the point: fixtures, not tests
public class CaseIdentityTests
{
    // Past xunit's 50-character display cut: two builds that differ only
    // here would share a cut display name.
    const string LongPrefix = "0123456789012345678901234567890123456789012345678901234567890";
    const string PastTheCut = LongPrefix + "A";

    enum Shade
    {
        Light = 1,
        Dark = 2,
    }

    sealed class Opaque
    {
    }

    static readonly object?[][] Rows =
    [
        [null, typeof(string)],
        [1.5d, new DateTime(2026, 9, 26, 1, 2, 3, DateTimeKind.Utc)],
    ];

    static readonly object?[][] OpaqueRows = [[new Opaque()]];

    static readonly int[] IntPair = [1, 2];

    static readonly object[] ObjectPair = [1, 2];

#pragma warning disable CA1814 // a multidimensional array is the shape under test
    static readonly int[,] Square = { { 1 }, { 2 } };
#pragma warning restore CA1814

    public static IEnumerable<object?[]> RowsSource => Rows;

    public static IEnumerable<object?[]> OpaqueSource => OpaqueRows;

    [InlineData(PastTheCut)]
    static void Constant(string s) => _ = s;

    [InlineData("x", 'q', true, 7, 7L, (byte)7, Shade.Dark, (Shade)9)]
    static void Kinds(string s, char c, bool b, int i, long l, byte y, Shade e, Shade u) => _ = (s, c, b, i, l, y, e, u);

    [InlineData(1.25f, 2.5d)]
    static void Floats(float f, double d) => _ = (f, d);

    [InlineData(null)]
    static void Null(string? s) => _ = s;

    [InlineData(typeof(Opaque))]
    static void Types(Type t) => _ = t;

    [InlineData(new[] { 1, 2 })]
    static void Arrays(int[] a) => _ = a;

    [InlineData("same")]
    [InlineData("same")]
    [InlineData("other")]
    static void Duplicates(string s) => _ = s;

    [MemberData(nameof(RowsSource))]
    static void Member(object? a, object? b) => _ = (a, b);

    [MemberData(nameof(OpaqueSource))]
    static void Unsupported(object o) => _ = o;

    static MethodInfo Fixture(string name) => typeof(CaseIdentityTests).GetMethod(name, BindingFlags.NonPublic | BindingFlags.Static)!;

    static string Row(string method, string args) => $"Unit.CaseIdentityTests.{method}({args})";

    [Fact]
    public void AConstantPastTheDisplayCutEncodesWhole()
    {
        Assert.Equal([Row("Constant", $"\"{PastTheCut}\"")], CaseIdentityEncoder.RowsFor(Fixture("Constant")));

        // One character past the cut is a different identity.
        Assert.NotEqual(CaseIdentityEncoder.Encode(LongPrefix + "A"), CaseIdentityEncoder.Encode(LongPrefix + "B"));
    }

    [Fact]
    public void EachKindEncodesByItsRule()
    {
        Assert.Equal(
            [Row("Kinds", "\"x\", char:\"q\", true, int32:7, int64:7, byte:7, enum:Unit.CaseIdentityTests+Shade.Dark, enum:Unit.CaseIdentityTests+Shade.9")],
            CaseIdentityEncoder.RowsFor(Fixture("Kinds")));
        Assert.Equal([Row("Floats", "single:1.25, double:2.5")], CaseIdentityEncoder.RowsFor(Fixture("Floats")));
        Assert.Equal([Row("Null", "null")], CaseIdentityEncoder.RowsFor(Fixture("Null")));
        Assert.Equal([Row("Types", "type:Unit.CaseIdentityTests+Opaque")], CaseIdentityEncoder.RowsFor(Fixture("Types")));
        Assert.Equal([Row("Arrays", "array:System.Int32[2]:[int32:1,int32:2]")], CaseIdentityEncoder.RowsFor(Fixture("Arrays")));
    }

    [Fact]
    public void CultureSensitiveValuesEncodeInvariantly()
    {
        var prior = System.Globalization.CultureInfo.CurrentCulture;
        try
        {
            System.Globalization.CultureInfo.CurrentCulture = new System.Globalization.CultureInfo("de-DE");
            Assert.Equal(
                [Row("Member", "null, type:System.String"), Row("Member", "double:1.5, datetime:2026-09-26T01:02:03.0000000Z")],
                CaseIdentityEncoder.RowsFor(Fixture("Member")));
            Assert.Equal("decimal:1.5", CaseIdentityEncoder.Encode(1.5m));
            Assert.Equal("timespan:01:02:03", CaseIdentityEncoder.Encode(new TimeSpan(1, 2, 3)));
        }
        finally
        {
            System.Globalization.CultureInfo.CurrentCulture = prior;
        }
    }

    // D00 T02 §53 (from §52 R5-C1): arrays that differ only in element type
    // or shape encode differently.
    [Fact]
    public void ArraysKeepElementTypeAndShape()
    {
        string ints = CaseIdentityEncoder.Encode(IntPair);
        string objects = CaseIdentityEncoder.Encode(ObjectPair);
        string square = CaseIdentityEncoder.Encode(Square);
        Assert.Equal("array:System.Int32[2]:[int32:1,int32:2]", ints);
        Assert.Equal("array:System.Object[2]:[int32:1,int32:2]", objects);
        Assert.Equal("array:System.Int32[2,1]:[int32:1,int32:2]", square);
        Assert.Equal(3, new HashSet<string> { ints, objects, square }.Count);
    }

    [Fact]
    public void IdenticalRowsCountByOccurrence()
    {
        Assert.Equal(
            [Row("Duplicates", "\"same\""), Row("Duplicates", "\"same\"") + "#2", Row("Duplicates", "\"other\"")],
            CaseIdentityEncoder.RowsFor(Fixture("Duplicates")));
    }

    [Fact]
    public void AnUnsupportedArgumentRefusesByName()
    {
        var ex = Assert.Throws<UnsupportedArgumentException>(() => CaseIdentityEncoder.RowsFor(Fixture("Unsupported")));
        Assert.Contains("Unit.CaseIdentityTests.Unsupported", ex.Message, StringComparison.Ordinal);
        Assert.Contains("unsupported argument type Unit.CaseIdentityTests+Opaque", ex.Message, StringComparison.Ordinal);
        Assert.Throws<UnsupportedArgumentException>(() => CaseIdentityEncoder.Encode(new Opaque()));
        Assert.Throws<UnsupportedArgumentException>(() => CaseIdentityEncoder.Encode(new object()));
    }
}
#pragma warning restore xUnit1008
