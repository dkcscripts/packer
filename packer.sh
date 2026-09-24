#!/usr/bin/env bash
# packer.sh — create self-extracting encrypted archives
# Usage: packer.sh -o <outfile.sh> <file/dir> [file/dir ...]
# Output: standalone executable script w/ embedded tar + gpg + base64 payload

set -euo pipefail

GPG_TTY=$(tty) 2>/dev/null || GPG_TTY=""
export GPG_TTY

# ── helpers ──────────────────────────────────────────────────────────────────

usage() {
  cat >&2 <<'EOF'
Usage: packer.sh -o <outfile.sh> <file/dir> [file/dir ...]

Creates standalone self-extracting script from files/directories.
Run output script on target machine to decrypt and extract.

Options:
  -o <outfile.sh>  Path to write self-extracting script (required)
  <file/dir> ...   Files or directories to pack (required, 1+)
  -h, --help       Show this help
EOF
  exit 1
}

info()  { echo "[packer] $*" >&2; }
error() { echo "[packer] ERROR: $*" >&2; exit 1; }

# ── arg parse ────────────────────────────────────────────────────────────────

outfile=""
inputs=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    -o)
      [[ $# -lt 2 ]] && error "'-o' requires argument"
      outfile="$2"
      shift 2
      ;;
    -h|--help) usage ;;
    -*) error "Unknown option: $1" ;;
    *)  inputs+=("$1"); shift ;;
  esac
done

[[ -z "$outfile" ]]       && error "Output file required (-o <outfile.sh>)"
[[ ${#inputs[@]} -eq 0 ]] && error "At least one input required"

# ── validate ─────────────────────────────────────────────────────────────────

for cmd in tar gpg base64; do
  command -v "$cmd" &>/dev/null || error "'$cmd' not found on PATH"
done

for input in "${inputs[@]}"; do
  [[ -e "$input" ]] || error "Input not found: $input"
done

outdir="$(dirname "$outfile")"
[[ -w "$outdir" ]] || error "Output directory not writable: $outdir"

# ── create payload ───────────────────────────────────────────────────────────

info "Inputs:  ${inputs[*]}"
info "Output:  $outfile"
info "Stages:  tar -cvf | xz -zv | gpg --symmetric | base64"
info "GPG will prompt for passphrase..."

# Create temp file for base64 payload
payload_b64=$(mktemp)
trap "rm -f '$payload_b64'" EXIT

# Pipeline: tar | gpg | base64 -> temp file
tar -cvf - "${inputs[@]}" 2>/dev/null \
  | xz -zv \
  | gpg --symmetric \
  | base64 \
  > "$payload_b64"

payload_size=$(wc -c < "$payload_b64")
info "Payload: $payload_size bytes (base64 encoded)"

# ── generate self-extractor ──────────────────────────────────────────────────

cat > "$outfile" <<'EXTRACTOR_HEADER'
#!/usr/bin/env bash
# Self-extracting encrypted archive
# Run this script to decrypt and extract contents (prompts for password)

set -euo pipefail

GPG_TTY=$(tty) 2>/dev/null || GPG_TTY=""
export GPG_TTY

echo "[extract] Self-extracting archive"
echo "[extract] Prompting for password (same one used during packing)..."
echo ""

# Find payload start marker
payload_line=$(grep -n "^__PAYLOAD_START__$" "$0" 2>/dev/null | cut -d: -f1)
[[ -z "$payload_line" ]] && { echo "[extract] ERROR: Payload marker not found" >&2; exit 1; }

# Extract payload, skip header + marker line
payload_line=$((payload_line + 1))
tail -n +$payload_line "$0" \
  | base64 -d \
  | gpg --decrypt \
  | xz -dv \
  | tar -xvf - -C .

echo ""
echo "[extract] Done. Extracted to current directory."
exit 0

__PAYLOAD_START__
EXTRACTOR_HEADER

# Append base64 payload
cat "$payload_b64" >> "$outfile"

# Make executable
chmod +x "$outfile"

# ── done ─────────────────────────────────────────────────────────────────────

size=$(du -sh "$outfile" 2>/dev/null | cut -f1)
info "Done. $outfile ($size)"
info "Run: $outfile (will prompt for password)"
