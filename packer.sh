#!/usr/bin/env bash
# packer.sh - create self-extracting archives (encrypted by default)
# Usage: packer.sh -o <outfile.sh> [--no-password] <file/dir> [file/dir ...]
# Output: standalone executable script w/ embedded tar + compressed + base64 payload

set -euo pipefail

# ── helpers ──────────────────────────────────────────────────────────────────

usage() {
  cat >&2 <<'EOF'
Usage: packer.sh -o <outfile.sh> [--no-password] <file/dir> [file/dir ...]

Creates a standalone self-extracting script from files/directories.
Run the output script on the target machine to extract.

Options:
  -o <outfile.sh>    Path to write self-extracting script (required)
  -n, --no-password  Skip encryption; extraction won't prompt for a password
  <file/dir> ...     Files or directories to pack (required, 1+)
  -h, --help         Show this help
EOF
  exit 1
}

info()  { echo "[packer] $*" >&2; }
error() { echo "[packer] ERROR: $*" >&2; exit 1; }

# ── arg parse ────────────────────────────────────────────────────────────────

outfile=""
no_password=false
inputs=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    -o)
      [[ $# -lt 2 ]] && error "'-o' requires argument"
      outfile="$2"
      shift 2
      ;;
    -n|--no-password)
      no_password=true
      shift
      ;;
    -h|--help) usage ;;
    -*) error "Unknown option: $1" ;;
    *)  inputs+=("$1"); shift ;;
  esac
done

[[ -z "$outfile" ]]       && error "Output file required (-o <outfile.sh>)"
[[ ${#inputs[@]} -eq 0 ]] && error "At least one input required"

# ── validate ─────────────────────────────────────────────────────────────────

for cmd in tar xz base64; do
  command -v "$cmd" &>/dev/null || error "'$cmd' not found on PATH"
done
if [[ "$no_password" == false ]]; then
  command -v gpg &>/dev/null || error "'gpg' not found on PATH"
fi

for input in "${inputs[@]}"; do
  [[ -e "$input" ]] || error "Input not found: $input"
done

outdir="$(dirname "$outfile")"
[[ -w "$outdir" ]] || error "Output directory not writable: $outdir"

# ── create payload ───────────────────────────────────────────────────────────

info "Inputs:  ${inputs[*]}"
info "Output:  $outfile"
if [[ "$no_password" == true ]]; then
  info "Stages:  tar -cvf | xz -zv | base64"
  info "Password protection disabled; payload will not be encrypted."
else
  info "Stages:  tar -cvf | xz -zv | gpg --symmetric | base64"
  info "GPG will prompt for passphrase..."
fi

payload_b64=$(mktemp)
trap 'rm -f "$payload_b64"' EXIT

if [[ "$no_password" == true ]]; then
  tar -cvf - "${inputs[@]}" 2>/dev/null \
    | xz -zv \
    | base64 \
    > "$payload_b64"
else
  GPG_TTY=$(tty) 2>/dev/null || GPG_TTY=""
  export GPG_TTY
  tar -cvf - "${inputs[@]}" 2>/dev/null \
    | xz -zv \
    | gpg --symmetric \
    | base64 \
    > "$payload_b64"
fi

payload_size=$(wc -c < "$payload_b64")
info "Payload: $payload_size bytes (base64 encoded)"

# ── generate self-extractor ──────────────────────────────────────────────────

cat > "$outfile" <<'EXTRACTOR_HEADER'
#!/usr/bin/env bash
# Self-extracting archive

set -euo pipefail

echo "[extract] Self-extracting archive"
EXTRACTOR_HEADER

if [[ "$no_password" == true ]]; then
  cat >> "$outfile" <<'EXTRACTOR_PLAIN'
echo "[extract] This archive is not encrypted."
echo ""

payload_line=$(grep -n "^__PAYLOAD_START__$" "$0" 2>/dev/null | cut -d: -f1)
[[ -z "$payload_line" ]] && { echo "[extract] ERROR: Payload marker not found" >&2; exit 1; }
payload_line=$((payload_line + 1))
tail -n +$payload_line "$0" \
  | base64 -d \
  | xz -dv \
  | tar -xvf - -C .
EXTRACTOR_PLAIN
else
  cat >> "$outfile" <<'EXTRACTOR_ENCRYPTED'
GPG_TTY=$(tty) 2>/dev/null || GPG_TTY=""
export GPG_TTY

echo "[extract] Prompting for password (same one used during packing)..."
echo ""

payload_line=$(grep -n "^__PAYLOAD_START__$" "$0" 2>/dev/null | cut -d: -f1)
[[ -z "$payload_line" ]] && { echo "[extract] ERROR: Payload marker not found" >&2; exit 1; }
payload_line=$((payload_line + 1))
tail -n +$payload_line "$0" \
  | base64 -d \
  | gpg --decrypt \
  | xz -dv \
  | tar -xvf - -C .
EXTRACTOR_ENCRYPTED
fi

cat >> "$outfile" <<'EXTRACTOR_FOOTER'
echo ""
echo "[extract] Done. Extracted to current directory."
exit 0

__PAYLOAD_START__
EXTRACTOR_FOOTER

cat "$payload_b64" >> "$outfile"
chmod +x "$outfile"

size=$(du -sh "$outfile" 2>/dev/null | cut -f1)
info "Done. $outfile ($size)"
if [[ "$no_password" == true ]]; then
  info "Run: $outfile (no password required; contents are unencrypted)"
else
  info "Run: $outfile (will prompt for password)"
fi
