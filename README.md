# packer.sh

Create **standalone self-extracting archives**. By default, each `.sh` embeds a tar'd, compressed, GPG-encrypted, base64-encoded payload. An optional no-password mode skips encryption and creates an archive that extracts without prompting.

Encrypted archives prompt for a password when run and extract to the current working directory. Use the unencrypted mode only when the archive contents do not need protection.

---

## Requirements

| Tool     | Purpose                                  |
|----------|------------------------------------------|
| `tar`    | Archive                                  |
| `xz`     | Compress                                 |
| `gpg`    | Symmetric encryption (default mode only) |
| `base64` | Encode/decode binary to ASCII            |
| `grep`   | Finding PAYLOAD inside script            |

All must be on `PATH`; `gpg` is only needed when creating or extracting encrypted archives.

---

## Usage

### Create self-extracting archive

```bash
./packer.sh -o archive.sh [--no-password] <file/dir> [file/dir ...]
```

| Flag | Required | Description |
|------|----------|-------------|
| `-o <outfile.sh>` | ✅ | Path to write self-extracting script |
| `-n, --no-password` | | Skip encryption and password prompts (contents are unencrypted) |
| `<file/dir> ...` | ✅ | One or more files/dirs to pack |
| `-h / --help` | | Show help |

**Example:**

```bash
# Pack single directory
./packer.sh -o backup.sh ~/projects/my-app

# Pack multiple files with encryption (default)
./packer.sh -o secrets.sh .env config.json certs/

# Pack without encryption or password prompts
./packer.sh -n -o public-data.sh ./public-data/
```

Output: executable `backup.sh` (or `secrets.sh`). Size ~33% larger than compressed binary (base64 overhead).

### Extract on target machine

```bash
./backup.sh
```

Encrypted archives prompt for the packing password, then decode the base64 payload, decrypt with GPG, and extract to the current directory. Archives created with `--no-password` skip decryption and extract directly.

No temp files left behind.

---

## Round-trip example

**On source machine:**

```bash
# Pack
./packer.sh -o my-app.sh ./my-app/
```

**Transfer (HTTP, email, chat, etc.)**

```bash
# Just a text file, safe anywhere
curl -O http://example.com/my-app.sh
chmod +x my-app.sh
```

**On target machine:**

```bash
# Extract
./my-app.sh
# Prompts: Enter passphrase for symmetric encryption: [type password]
```

---

## How it works

```
[packer.sh on source]
  ↓
  tar -cvf (archive files)
  ↓
  xz -zv (compress)
  ↓
  gpg --symmetric (encrypt w/ passphrase)
  ↓
  base64 (make ASCII-safe)
  ↓
  Embed in bash script header
  ↓
  Output: backup.sh (executable)

[backup.sh on target]
  ↓
  Extract base64 payload from self
  ↓
  base64 -d (decode)
  ↓
  gpg --decrypt (decrypt w/ prompted password)
  ↓
  xz -dv (decompress)
  ↓
  tar -xzvf (extract to CWD)
  ↓
  Done
```

---

## Key points

- **Self-contained:** single `.sh` file. No launcher + payload split. Just run it.
- **Portable:** works Linux + macOS + Git Bash (Windows). Only needs tar/xz/gpg/base64/grep.
- **Encrypted by default:** GPG symmetric encryption, passphrase-based. No key files.
- **Optional unencrypted mode:** `--no-password` avoids password prompts, but anyone with the archive can read its contents.
- **Transparent:** verbose extraction output shows what's being extracted.
- **Safe encoding:** base64 makes encrypted binary safe for any channel (HTTP, email, etc.).

---

## Troubleshooting

**"gpg: command not found"**
- `gpg` not installed or not on PATH
- Recommendation: `apt install gnupg` (Linux) / `brew install gpg` (macOS)

**"base64: command not found"**
- `base64` not installed (rare)
- Linux: `apt install coreutils`
- macOS: built-in

**"Payload marker not found"**
- Script corrupted or truncated during transfer
- Verify file integrity: `head -20 archive.sh` should show bash code, `tail -20 archive.sh` should show base64

**"gpg: decryption failed"**
- Wrong password or corrupted payload
- Password must match exactly (case-sensitive)
- Verify file wasn't corrupted: size should match what packer.sh reported

---

## Security notes

- Passphrase entered at terminal (not echoed)
- Same passphrase used for both pack + extract
- No temp files written; all in pipes
- Encrypted via GPG symmetric cipher (AES-256 default)
- Base64 encoding is NOT encryption; it's just ASCII-safe encoding

---

## Examples

**Backup home directory:**

```bash
./packer.sh -o home-backup.sh ~
# Transfer home-backup.sh to another machine
# On target: ./home-backup.sh
```

**Package confidential config:**

```bash
./packer.sh -o config.sh app.conf secrets.json certs/
# Ship config.sh to deployment server
# On server: ./config.sh
```

**Share files securely in chat:**

```bash
./packer.sh -o data.sh ./sensitive-data/
# Recipient runs: ./data.sh (encrypted, needs password)

# For non-sensitive files, skip encryption and the password prompt
./packer.sh --no-password -o public-data.sh ./public-data/
# Recipient runs: ./public-data.sh (no password; contents are unencrypted)
```

---

## Tips

- **Large files:** base64 adds ~33% size.
- **Password strength:** GPG will warn if passphrase is weak. Use a strong one.
