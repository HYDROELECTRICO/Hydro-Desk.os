#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_DIR="$ROOT_DIR/live-build-config"
WORK_DIR="$ROOT_DIR/.build/live-build"
OUT_DIR="$ROOT_DIR/out"
ISO_NAME="hydro-desk-os-amd64.iso"
DIAG_DIR="$ROOT_DIR/diag-output"

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

# Diagnostic helper: collect logs and push to debug branch for retrieval
collect_and_push_diagnostics() {
  local exit_code=${1:-1}
  echo "=== Collecting diagnostics (exit code $exit_code) ===" >&2
  set +e
  mkdir -p "$DIAG_DIR"
  echo "=== system info ===" > "$DIAG_DIR/preflight.txt" 2>&1
  lsb_release -a >> "$DIAG_DIR/preflight.txt" 2>&1 || cat /etc/os-release >> "$DIAG_DIR/preflight.txt" 2>&1 || true
  uname -a >> "$DIAG_DIR/preflight.txt" 2>&1 || true
  df -h >> "$DIAG_DIR/preflight.txt" 2>&1 || true
  echo "=== auto/config ===" >> "$DIAG_DIR/preflight.txt" 2>&1
  cat "$CONFIG_DIR/auto/config" >> "$DIAG_DIR/preflight.txt" 2>&1 || true
  echo "=== live-build help ===" >> "$DIAG_DIR/preflight.txt" 2>&1
  lb config --help >> "$DIAG_DIR/preflight.txt" 2>&1 || true
  echo "=== lb config help mirror grep ===" >> "$DIAG_DIR/preflight.txt" 2>&1
  lb config --help 2>&1 | grep -Ei "mirror|security|updates|binary-images" >> "$DIAG_DIR/preflight.txt" 2>&1 || true
  echo "=== package list ===" >> "$DIAG_DIR/preflight.txt" 2>&1
  cat "$CONFIG_DIR/config/package-lists/hydro-desk.list.chroot" >> "$DIAG_DIR/preflight.txt" 2>&1 || true
  echo "=== archives ===" >> "$DIAG_DIR/preflight.txt" 2>&1
  ls -la "$CONFIG_DIR/config/archives/" >> "$DIAG_DIR/preflight.txt" 2>&1 || true
  cat "$CONFIG_DIR/config/archives/"* >> "$DIAG_DIR/preflight.txt" 2>&1 || true
  echo "=== hooks ===" >> "$DIAG_DIR/preflight.txt" 2>&1
  ls -la "$CONFIG_DIR/config/hooks/normal/" >> "$DIAG_DIR/preflight.txt" 2>&1 || true

  # Copy recent build logs if they exist
  for f in "$WORK_DIR/config/binary" "$WORK_DIR/config/bootstrap" "$WORK_DIR/config/chroot" "$WORK_DIR/config/common" "$WORK_DIR/config/source"; do
    if [[ -f "$f" ]]; then
      mkdir -p "$DIAG_DIR/config"
      cp "$f" "$DIAG_DIR/config/" 2>/dev/null || true
    fi
  done
  # List work dir
  ls -la "$WORK_DIR" > "$DIAG_DIR/workdir-list.txt" 2>&1 || true
  if [[ -f "$WORK_DIR/build.log" ]]; then cp "$WORK_DIR/build.log" "$DIAG_DIR/" 2>/dev/null || true; fi

  # Try to push diagnostics to a debug branch (requires GITHUB_TOKEN in CI)
  if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
    echo "=== Attempting to push diagnostics to debug-live-build-logs branch ===" >&2
    # Ensure git is configured
    git config user.name "hydro-debug-bot" 2>&1 || true
    git config user.email "hydro-debug@example.com" 2>&1 || true
    # Unshallow if needed
    git fetch --unshallow 2>&1 | head -n 20 || true
    git fetch origin --prune 2>&1 | head -n 20 || true
    # Stage diagnostics
    git add -f diag-output 2>&1 || true
    git add -f "$DIAG_DIR" 2>&1 || true
    # Also add any log files we created
    git status 2>&1 | head -n 50 || true
    if ! git diff --cached --quiet 2>&1; then
      git commit -m "diagnostics: live-build failure $(date -u +%Y%m%d-%H%M%S) exit $exit_code [skip ci]" 2>&1 || true
      # Push to debug branch; use origin with token already configured by checkout
      git push origin HEAD:debug-live-build-logs 2>&1 | head -n 100 || {
        echo "git push HEAD:debug-live-build-logs failed, trying with --force" >&2
        git push --force origin HEAD:debug-live-build-logs 2>&1 | head -n 100 || true
      }
    else
      echo "No diagnostic changes to commit" >&2
    fi
  else
    echo "Not in GitHub Actions, skipping git push" >&2
  fi
  set -e
}

# Ensure diag dir exists early
mkdir -p "$DIAG_DIR"

if [[ "$INSTALL_DEPS" -eq 1 ]]; then
  sudo apt-get update 2>&1 | tee "$DIAG_DIR/apt-update.log" || true
  sudo apt-get install -y --no-install-recommends live-build xorriso isolinux syslinux syslinux-common syslinux-utils squashfs-tools grub-pc-bin grub-efi-amd64-bin mtools dosfstools 2>&1 | tee "$DIAG_DIR/apt-install.log" || {
    echo "apt install failed, collecting diagnostics" >&2
    collect_and_push_diagnostics 1
    exit 1
  }
  # Verify isohybrid is available (from syslinux-utils)
  which isohybrid 2>&1 | tee -a "$DIAG_DIR/apt-install.log" || echo "isohybrid not found after install" | tee -a "$DIAG_DIR/apt-install.log"
  ls -l /usr/bin/isohybrid 2>&1 | tee -a "$DIAG_DIR/apt-install.log" || true
fi

if ! command -v lb >/dev/null 2>&1; then
  echo "live-build is not installed. Re-run with --install-deps or install package 'live-build'." >&2
  collect_and_push_diagnostics 1
  exit 1
fi

# Patch live-build for bookworm Contents path bug (old live-build 3.0~a57 expects Contents at dists/<dist>/Contents- but bookworm moved to dists/<dist>/main/Contents-)
{
  echo "=== Patching live-build Contents path bug for bookworm ==="
  # Show current file before patch
  for f in /usr/lib/live/build/lb_chroot_linux-image /usr/share/live/build/lb_chroot_linux-image /usr/lib/live/build/chroot_linux-image /usr/share/live/build/chroot_linux-image; do
    if [[ -f "$f" ]]; then
      echo "--- Found $f ---"
      grep -n "Contents" "$f" | head -n 20 || true
    fi
  done
  # Patch all files that contain the old Contents path
  for base in /usr/lib/live/build /usr/share/live/build; do
    if [[ -d "$base" ]]; then
      for f in "$base"/*; do
        if [[ -f "$f" ]] && grep -q "Contents-" "$f" 2>/dev/null; then
          echo "Patching $f"
          # Replace /dists/<dist>/Contents- with /dists/<dist>/main/Contents- (handle both LB_DISTRIBUTION and LB_PARENT_DISTRIBUTION)
          sudo sed -i 's|/dists/${LB_PARENT_DISTRIBUTION}/Contents-|/dists/${LB_PARENT_DISTRIBUTION}/main/Contents-|g' "$f" 2>&1 || true
          sudo sed -i 's|/dists/${LB_DISTRIBUTION}/Contents-|/dists/${LB_DISTRIBUTION}/main/Contents-|g' "$f" 2>&1 || true
          # Generic fallback: any /dists/<something>/Contents- -> /dists/<something>/main/Contents- if not already containing /main/
          # Use a more generic pattern to catch any remaining
          if grep -q "/dists/.*/Contents-" "$f" 2>/dev/null; then
            # Use perl to avoid double-patching already patched lines
            sudo perl -pi -e 's|(/dists/[^/]+)/Contents-|$1/main/Contents-|g unless m|/main/Contents-|' "$f" 2>&1 || true
          fi
          echo "After patch grep:"
          grep -n "Contents" "$f" | head -n 20 || true
        fi
      done
    fi
  done
  echo "=== Testing Contents URL fetch (should be main/Contents) ==="
  echo "--- Testing deb.debian.org bookworm main Contents ---"
  wget --spider -v http://deb.debian.org/debian/dists/bookworm/main/Contents-amd64.gz 2>&1 | head -n 30 || true
  curl -Is http://deb.debian.org/debian/dists/bookworm/main/Contents-amd64.gz 2>&1 | head -n 30 || true
  echo "--- Testing old path (should 404) ---"
  wget --spider -v http://deb.debian.org/debian/dists/bookworm/Contents-amd64.gz 2>&1 | head -n 30 || true
  curl -Is http://deb.debian.org/debian/dists/bookworm/Contents-amd64.gz 2>&1 | head -n 30 || true
  echo "=== Patching done ==="
} >> "$DIAG_DIR/preflight.txt" 2>&1 || true
cat "$DIAG_DIR/preflight.txt" | tail -n 100 || true

# Preflight diagnostic: lb help and auto/config validation
{
  echo "=== PREFLIGHT DIAGNOSTIC ==="
  echo "--- date ---"
  date -u
  echo "--- auto/config ---"
  cat "$CONFIG_DIR/auto/config"
  echo "--- lb --version ---"
  lb --version 2>&1 || true
  echo "--- lb config --help (mirror/security) ---"
  lb config --help 2>&1 | grep -Ei "mirror|security|updates|binary-images" || true
  echo "--- full lb config --help ---"
  lb config --help 2>&1 | head -n 200 || true
  echo "--- package list ---"
  cat "$CONFIG_DIR/config/package-lists/hydro-desk.list.chroot"
  echo "--- archives ---"
  ls -la "$CONFIG_DIR/config/archives/" || true
  cat "$CONFIG_DIR/config/archives/"* || true
} >> "$DIAG_DIR/preflight.txt" 2>&1 || true
cat "$DIAG_DIR/preflight.txt" || true

# Patch isohybrid path for binary iso (host has /usr/bin/isohybrid from syslinux-utils, but live-build may call isohybrid without full path)
{
  echo "=== Patching isohybrid path for binary iso ==="
  which isohybrid 2>&1 || true
  ls -l /usr/bin/isohybrid /bin/isohybrid 2>&1 | head -n 20 || true
  for base in /usr/lib/live/build /usr/share/live/build; do
    if [[ -d "$base" ]]; then
      for f in "$base"/*; do
        if [[ -f "$f" ]] && grep -q "isohybrid" "$f" 2>/dev/null; then
          echo "--- Found isohybrid in $f ---"
          grep -n "isohybrid" "$f" 2>&1 | head -n 20 || true
          echo "Patching $f to use full path"
          sudo sed -i 's|\<isohybrid\>|/usr/bin/isohybrid|g' "$f" 2>&1 || true
          # Avoid double patch
          sudo sed -i 's|/usr/bin//usr/bin/isohybrid|/usr/bin/isohybrid|g' "$f" 2>&1 || true
          grep -n "isohybrid" "$f" 2>&1 | head -n 20 || true
        fi
      done
    fi
  done
  # Also ensure isohybrid is in PATH for sudo
  sudo ln -sf /usr/bin/isohybrid /bin/isohybrid 2>&1 || true
  sudo ln -sf /usr/bin/isohybrid /usr/local/bin/isohybrid 2>&1 || true
  echo "=== isohybrid patch done ==="
} >> "$DIAG_DIR/preflight.txt" 2>&1 || true
cat "$DIAG_DIR/preflight.txt" | tail -n 80 || true

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

# Run lb config with logging
echo "=== Running lb config ==="
pushd "$WORK_DIR" >/dev/null
set +e
lb config 2>&1 | tee "$DIAG_DIR/lb-config.log"
LB_CONFIG_EXIT=${PIPESTATUS[0]}
set -e
if [[ "$LB_CONFIG_EXIT" -ne 0 ]]; then
  echo "lb config failed with exit $LB_CONFIG_EXIT" >&2
  cat "$DIAG_DIR/lb-config.log" >&2 || true
  echo "--- config files after failure ---" >&2
  ls -la config/ 2>&1 | head -n 100 >&2 || true
  cat "$DIAG_DIR/lb-config.log" || true
  collect_and_push_diagnostics "$LB_CONFIG_EXIT"
  popd >/dev/null
  exit "$LB_CONFIG_EXIT"
fi
echo "lb config succeeded"
cat "$DIAG_DIR/lb-config.log" || true
echo "--- generated config ---"
ls -la config/ 2>&1 | head -n 50 || true
cat config/binary 2>&1 | head -n 100 || true
cat config/common 2>&1 | head -n 100 || true

# Run lb build with logging and timeout handling
echo "=== Running lb build (this may take a long time) ==="
set +e
# Use timeout 170 minutes to stay within workflow 180m limit, but still capture logs
sudo lb build 2>&1 | tee "$DIAG_DIR/lb-build.log"
LB_BUILD_EXIT=${PIPESTATUS[0]}
set -e
echo "lb build exit code: $LB_BUILD_EXIT" | tee -a "$DIAG_DIR/lb-build.log"
if [[ "$LB_BUILD_EXIT" -ne 0 ]]; then
  echo "lb build failed with exit $LB_BUILD_EXIT" >&2
  echo "--- tail of build log ---" >&2
  tail -n 500 "$DIAG_DIR/lb-build.log" >&2 || true
  echo "--- grep errors ---" >&2
  grep -i -E "error|failed|E:" "$DIAG_DIR/lb-build.log" | head -n 200 >&2 || true
  collect_and_push_diagnostics "$LB_BUILD_EXIT"
  popd >/dev/null
  exit "$LB_BUILD_EXIT"
fi
popd >/dev/null

ISO_PATH="$(find "$WORK_DIR" -maxdepth 1 -type f -name '*.iso' | head -n 1)"
if [[ -z "${ISO_PATH:-}" ]]; then
  echo "Build finished but no ISO was found in $WORK_DIR" >&2
  ls -la "$WORK_DIR" >&2 || true
  cat "$DIAG_DIR/lb-build.log" >&2 | tail -n 200 || true
  collect_and_push_diagnostics 1
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
# Also save success diagnostic
mkdir -p "$DIAG_DIR"
echo "BUILD SUCCESS $(date -u)" > "$DIAG_DIR/success.txt" 2>&1 || true
