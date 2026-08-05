#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEFAULT_ISO="$ROOT_DIR/out/hydro-desk-os-amd64.iso"

usage() {
  cat <<USAGE
Usage: sudo $0 /dev/sdX [path/to/hydro-desk-os-amd64.iso]

Write the live ISO to a USB drive. WARNING: this erases the target device.
Examples:
  lsblk
  sudo $0 /dev/sdb
  sudo $0 /dev/sdb out/hydro-desk-os-amd64.iso
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" || $# -lt 1 || $# -gt 2 ]]; then
  usage
  exit 0
fi

DEVICE="$1"
ISO="${2:-$DEFAULT_ISO}"

if [[ $EUID -ne 0 ]]; then
  echo "Run as root: sudo $0 $DEVICE ${2:-}" >&2
  exit 1
fi

if [[ ! -f "$ISO" ]]; then
  echo "ISO not found: $ISO" >&2
  exit 1
fi

if [[ ! -b "$DEVICE" ]]; then
  echo "Target is not a block device: $DEVICE" >&2
  exit 1
fi

if [[ ! "$DEVICE" =~ ^/dev/(sd[a-z]|vd[a-z]|hd[a-z]|nvme[0-9]+n[0-9]+|mmcblk[0-9]+)$ ]]; then
  echo "Refusing unusual device path: $DEVICE" >&2
  exit 1
fi

ROOT_SOURCE="$(findmnt -n -o SOURCE / || true)"
if [[ -n "$ROOT_SOURCE" && "$ROOT_SOURCE" == "$DEVICE"* ]]; then
  echo "Refusing to overwrite the current root disk: $DEVICE" >&2
  exit 1
fi

echo "About to erase and write: $DEVICE"
echo "ISO: $ISO"
lsblk "$DEVICE"
read -r -p "Type YES to continue: " CONFIRM
if [[ "$CONFIRM" != "YES" ]]; then
  echo "Cancelled."
  exit 1
fi

# Unmount mounted partitions from the selected drive.
while read -r mountpoint; do
  [[ -n "$mountpoint" ]] && umount "$mountpoint"
done < <(lsblk -nrpo MOUNTPOINT "$DEVICE" | awk 'NF')

sync
dd if="$ISO" of="$DEVICE" bs=4M status=progress oflag=sync
sync

echo "USB is ready for live boot: $DEVICE"
