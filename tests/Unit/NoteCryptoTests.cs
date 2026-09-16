using System.Text;
using Notepad.Core;
using Xunit;

namespace Unit;

// D01 T01 §19: lock/unlock round-trips across encodings, loud failures with
// no partial output, and the documented test vector pinned byte-exact.
public sealed class NoteCryptoTests
{
    public static TheoryData<string, bool, string> Encodings() => new()
    {
        { FileOpen.Utf8Name, false, LineEndings.Crlf },
        { FileOpen.Utf8BomName, true, LineEndings.Lf },
        { FileOpen.Utf16LeName, false, LineEndings.Crlf },
        { FileOpen.Utf16BeName, false, LineEndings.Lf },
        { FileOpen.AnsiName, false, LineEndings.Crlf },
    };

    [Theory]
    [MemberData(nameof(Encodings))]
    public void LockUnlockRestoresExactBytes(string encoding, bool hasBom, string lineEnding)
    {
        byte[] plain = FileSave.Encode("Secret body\r\nsecond line\r\n", encoding, hasBom, lineEnding);
        byte[] locked = NoteCrypto.Lock(plain, "correct-19");
        Assert.True(NoteCrypto.IsLocked(locked));
        Assert.False(ContainsSequence(locked, plain));
        Assert.Equal(plain, NoteCrypto.Unlock(locked, "correct-19"));
    }

    [Fact]
    public void PlaintextIsNotLocked()
    {
        Assert.False(NoteCrypto.IsLocked("just text\n"u8.ToArray()));
        Assert.False(NoteCrypto.IsLocked([]));
    }

    [Fact]
    public void WrongPasswordFailsLoud()
    {
        byte[] locked = NoteCrypto.Lock("data"u8.ToArray(), "right-19");
        var wrong = Assert.Throws<WrongPasswordException>(() => NoteCrypto.Unlock(locked, "wrong-19"));
        Assert.Equal("Wrong password.", wrong.Message);
    }

    [Fact]
    public void TamperedCiphertextFailsLikeWrongPassword()
    {
        byte[] locked = NoteCrypto.Lock("data"u8.ToArray(), "tamper-19");
        locked[^1] ^= 0xFF;
        Assert.Throws<WrongPasswordException>(() => NoteCrypto.Unlock(locked, "tamper-19"));
    }

    [Fact]
    public void TamperedHeaderFailsLoud()
    {
        byte[] locked = NoteCrypto.Lock("data"u8.ToArray(), "header-19");
        int headerEnd = Array.IndexOf(locked, (byte)'\n', NoteCrypto.Magic.Length + 1);
        locked[headerEnd - 2] ^= 0xFF;
        Assert.ThrowsAny<Exception>(() => NoteCrypto.Unlock(locked, "header-19"));
    }

    [Fact]
    public void TruncatedAndForeignBytesFailLoud()
    {
        byte[] locked = NoteCrypto.Lock("data"u8.ToArray(), "trunc-19");
        Assert.Throws<InvalidDataException>(() => NoteCrypto.Unlock(locked[..(locked.Length - 20)], "trunc-19"));
        Assert.Throws<InvalidDataException>(() => NoteCrypto.Unlock("INENC1 impostor"u8.ToArray(), "trunc-19"));
        Assert.Throws<InvalidDataException>(() => NoteCrypto.Unlock(Encoding.ASCII.GetBytes("IntelligentNotepad-Encrypted-1\n"), "trunc-19"));
    }

    [Fact]
    public void DocumentedVectorPinsCiphertext()
    {
        byte[] salt = Convert.FromHexString("00112233445566778899AABBCCDDEEFF");
        byte[] nonce = Convert.FromHexString("102030405060708090A0B0C0");
        byte[] locked = NoteCrypto.LockWith("vector plaintext"u8.ToArray(), "vector-password-19", salt, nonce);
        string body = Convert.ToHexString(locked.AsSpan(IndexOfBody(locked)));
        Assert.Equal(VectorCiphertextHex(), body);
    }

    [Fact]
    public void SaveBytesCommitsAtomically()
    {
        string dir = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(dir);
        try
        {
            string path = Path.Combine(dir, "locked.bin");
            byte[] payload = [0x00, 0xFF, 0x42];
            Assert.IsType<SaveSuccess>(FileSave.SaveBytes(path, payload));
            Assert.Equal(payload, File.ReadAllBytes(path));
            Assert.Single(Directory.GetFiles(dir));
        }
        finally
        {
            Directory.Delete(dir, recursive: true);
        }
    }

    [Fact]
    public void SaveBytesMissingDirectoryFails()
    {
        string path = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString("N"), "nope.bin");
        Assert.IsType<SaveFailed>(FileSave.SaveBytes(path, [0x01]));
    }

    [Fact]
    public void RelockMarksTabLockedAndClean()
    {
        string dir = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(dir);
        try
        {
            string path = Path.Combine(dir, "note.txt");
            File.WriteAllText(path, "plain");
            var tab = new Tab { FilePath = path };
            tab.NotifyEdited("plain");
            Assert.IsType<SaveSuccess>(NoteCrypto.Relock(tab, "plain", "relock-19"));
            Assert.True(tab.IsLocked);
            Assert.False(tab.IsDirty);
            byte[] locked = File.ReadAllBytes(path);
            Assert.True(NoteCrypto.IsLocked(locked));
            Assert.Equal(FileSave.Encode("plain", tab.Encoding, tab.HasBom, tab.LineEnding), NoteCrypto.Unlock(locked, "relock-19"));
        }
        finally
        {
            Directory.Delete(dir, recursive: true);
        }
    }

    [Fact]
    public void RelockOrThrowSurfacesFailureDetail()
    {
        var tab = new Tab { FilePath = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString("N"), "nope.txt") };
        IOException thrown = Assert.Throws<IOException>(() => NoteCrypto.RelockOrThrow(tab, "plain", "relock-19"));
        Assert.Contains("Lock failed", thrown.Message, StringComparison.Ordinal);
    }

    [Fact]
    public void RelockFailureMarksNothing()
    {
        var tab = new Tab { FilePath = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString("N"), "nope.txt") };
        tab.NotifyEdited("plain");
        Assert.IsType<SaveFailed>(NoteCrypto.Relock(tab, "plain", "relock-19"));
        Assert.False(tab.IsLocked);
        Assert.True(tab.IsDirty);
    }

    static bool ContainsSequence(byte[] haystack, byte[] needle)
    {
        for (int i = 0; i + needle.Length <= haystack.Length; i++)
        {
            if (haystack.AsSpan(i, needle.Length).SequenceEqual(needle))
            {
                return true;
            }
        }

        return false;
    }

    static int IndexOfBody(byte[] locked)
    {
        int headerEnd = Array.IndexOf(locked, (byte)'\n', NoteCrypto.Magic.Length + 1);
        return headerEnd + 1;
    }

    static string VectorCiphertextHex() => "8C05C9B2E3BAE1786170D06421DAB2C6ECCA8A5DC0F1B60CE0DF589A9BF67788";
}
