#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_DIR="$ROOT_DIR/live-build-config"
WORK_DIR="$ROOT_DIR/.build/live-build"
OUT_DIR="$ROOT_DIR/out"
ISO_NAME="hydro-desk-os-amd64.iso"

usage() {
  cat <<USAGE
Usage: $0 [--install-deps] [--clean]

Build a bootable Hydro Desk OS live ISO.

Options:
  --install-deps  Install live-build and ISO/USB boot tooling with apt before building.
  --clean         Remove the previous live-build working tree before building.
  -h, --help      Show this help.

Output:
  $OUT_DIR/$ISO_NAME
  $OUT_DIR/$ISO_NAME.sha256
USAGE
}

INSTALL_DEPS=0
CLEAN=0
for arg in "$@"; do
  case "$arg" in
    --install-deps) INSTALL_DEPS=1 ;;
    --clean) CLEAN=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $arg" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ "$INSTALL_DEPS" -eq 1 ]]; then
  sudo apt-get update
  sudo apt-get install -y --no-install-recommends live-build xorriso isolinux syslinux-common squashfs-tools grub-pc-bin grub-efi-amd64-bin mtools dosfstools
fi

if ! command -v lb >/dev/null 2>&1; then
  echo "live-build is not installed. Re-run with --install-deps or install package 'live-build'." >&2
  exit 1
fi

if [[ "$CLEAN" -eq 1 ]]; then
  sudo rm -rf "$WORK_DIR"
fi

mkdir -p "$WORK_DIR" "$OUT_DIR"

if [[ -f "$WORK_DIR/auto/config" ]]; then
  pushd "$WORK_DIR" >/dev/null
  sudo lb clean --purge || true
  popd >/dev/null
fi

sudo rm -rf "$WORK_DIR/auto" "$WORK_DIR/config" "$WORK_DIR/local"
sudo find "$WORK_DIR" -maxdepth 1 -type f -name '*.iso' -delete 2>/dev/null || true
sudo find "$WORK_DIR" -maxdepth 1 -type f -name '*.sha256' -delete 2>/dev/null || true
(cd "$CONFIG_DIR" && tar cf - .) | (cd "$WORK_DIR" && tar xpf -)
# Ensure live-build's auto/config is executable
chmod +x "$WORK_DIR/auto/config" 2>/dev/null || true
sudo chmod +x "$WORK_DIR/auto/config" 2>/dev/null || true

pushd "$WORK_DIR" >/dev/null
lb config
sudo lb build
popd >/dev/null

ISO_PATH="$(find "$WORK_DIR" -maxdepth 1 -type f -name '*.iso' | head -n 1)"
if [[ -z "${ISO_PATH:-}" ]]; then
  echo "Build finished but no ISO was found in $WORK_DIR" >&2
  ls -la "$WORK_DIR" >&2 || true
  exit 1
fi

sudo cp "$ISO_PATH" "$OUT_DIR/$ISO_NAME"
sudo chown "$(id -u):$(id -g)" "$OUT_DIR/$ISO_NAME"
(cd "$OUT_DIR" && sha256sum "$ISO_NAME" > "$ISO_NAME.sha256")
# Verify the checksum file is valid
(cd "$OUT_DIR" && sha256sum -c "$ISO_NAME.sha256")

echo "Built: $OUT_DIR/$ISO_NAME"
echo "SHA256: $OUT_DIR/$ISO_NAME.sha256"
ls -lh "$OUT_DIR/$ISO_NAME" "$OUT_DIR/$ISO_NAME.sha256"
