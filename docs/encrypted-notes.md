# Encrypted notes (D01 T01 §19)

Some notes need a password. A locked file carries its parameters in a stated header, so a reader implements decrypt from this document alone; a wrong password fails loud instead of producing garbage, and the password never persists (the key lives in memory only, cleared after use).

## Algorithm

- Data: AES-256-GCM (via .NET `AesGcm`, which uses CNG on Windows). Nonce 12 bytes, tag 16 bytes, key 32 bytes.
- Key: PBKDF2-HMAC-SHA256, 600,000 iterations (OWASP password-storage guidance), 16-byte salt.
- Associated data: the exact JSON header-line bytes (below), binding the parameters to the ciphertext. Tampered parameters fail authentication exactly like a wrong password: one loud failure, no oracle detail.

## File layout

1. Magic line: `ScratchPad-Encrypted-1` plus LF (`0x0A`).
2. Header line: one JSON object plus LF, no spaces: `{"Alg":"AES-256-GCM","Kdf":"PBKDF2-SHA256","Iter":600000,"Salt":"<base64>","Nonce":"<base64>"}`.
3. Body: raw ciphertext bytes plus the raw 16-byte tag.

Readers accept any positive `Iter` (the AAD binding makes weakened parameters fail loud); writers always use 600,000. Salt must decode to 16 bytes, nonce to 12. Unknown `Alg`/`Kdf`, corrupt JSON, short bodies, and authentication failures all fail loud with no partial output.

## Decrypt (normative)

1. Split the file at the first two LF bytes; verify the magic line.
2. Parse the header JSON; reject unknown algorithms, non-positive iterations, and wrong salt/nonce lengths.
3. Derive 32 key bytes with PBKDF2-HMAC-SHA256 over the password (UTF-8), salt, and the header's iteration count.
4. AES-GCM-decrypt the body with the header nonce, the header-line bytes as associated data, and a 16-byte tag split off the body's end.
5. Feed the resulting bytes through the normal open path (encoding detection); they are the exact pre-lock bytes.

## Test vector

Password `vector-password-19`, plaintext `vector plaintext` (UTF-8, 16 bytes), salt `00112233445566778899AABBCCDDEEFF`, nonce `102030405060708090A0B0C0`. Header line: `{"Alg":"AES-256-GCM","Kdf":"PBKDF2-SHA256","Iter":600000,"Salt":"ABEiM0RVZneImaq7zN3u/w==","Nonce":"ECAwQFBgcICQoLDA"}`. Body (ciphertext plus tag) hex: `8C05C9B2E3BAE1786170D06421DAB2C6ECCA8A5DC0F1B60CE0DF589A9BF67788`. Pinned by `NoteCryptoTests.DocumentedVectorPinsCiphertext` and cross-checked with an independent Python implementation.

## Residues (D01 T01 §30)

Locked tabs persist path-only: snapshot takes are refused, and session plus crash-checkpoint entries omit locked buffers, so a locked tab restores as a ghost and any unsaved edits at persist time are dropped (the locked file on disk keeps its last saved ciphertext; unlock the tab to resume editing). Residues written before §30 shipped are left in place, never wiped: snapshot sidecars (`<file>.snapshots/`) taken while the tab was unlocked, and session files holding buffers persisted before the path-only rule. Delete those sidecars and session files by hand to clear them.
