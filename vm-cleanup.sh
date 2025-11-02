#!/usr/bin/env bash
set -euo pipefail

# Defaults (override with flags)
LOG_DAYS=7
DOCKER_PRUNE=false
SNAP_PRUNE=false
FLATPAK_PRUNE=false
ZERO_FILL=true

usage() {
  cat <<USAGE
Usage: sudo ./vm-cleanup.sh [options]

Options:
  --logs-days N        Keep only last N days of systemd journal (default: 7)
  --include-docker     Also prune Docker images/containers/volumes
  --include-snap       Remove old Snap revisions (if snap is installed)
  --include-flatpak    Remove unused Flatpak runtimes (if flatpak is installed)
  --no-zero-fill       Skip zero-filling free space (for compacting you usually want it ON)
  -h, --help           Show this help
USAGE
}

# Parse flags
while [[ $# -gt 0 ]]; do
  case "$1" in
    --logs-days) LOG_DAYS="${2:-7}"; shift 2 ;;
    --include-docker) DOCKER_PRUNE=true; shift ;;
    --include-snap) SNAP_PRUNE=true; shift ;;
    --include-flatpak) FLATPAK_PRUNE=true; shift ;;
    --no-zero-fill) ZERO_FILL=false; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1"; usage; exit 1 ;;
  esac
done

need_cmd() { command -v "$1" >/dev/null 2>&1; }

echo "=== VM Cleanup starting ==="
echo "Keeping journal logs for: ${LOG_DAYS}d"
echo "Docker prune: ${DOCKER_PRUNE}"
echo "Snap prune:   ${SNAP_PRUNE}"
echo "Flatpak prune:${FLATPAK_PRUNE}"
echo "Zero-fill:    ${ZERO_FILL}"
echo

echo "[1/11] Disk usage BEFORE:"
df -h || true
echo

echo "[2/11] APT cleanup (clean, autoclean, autoremove --purge)…"
apt-get -y update >/dev/null || true
apt-get -y autoremove --purge || true
apt-get -y autoclean || true
apt-get -y clean || true

echo "[3/11] Remove Chromium (packages + user cache) if present…"
apt-get -y remove --purge chromium chromium-common chromium-browser >/dev/null 2>&1 || true
rm -rf "${HOME}/.config/chromium" "${HOME}/.cache/chromium" 2>/dev/null || true

echo "[4/11] Trim Brave cache (keeps your profile/bookmarks)…"
rm -rf "${HOME}/.cache/BraveSoftware" 2>/dev/null || true

echo "[5/11] Clear /tmp and user caches…"
rm -rf /tmp/* 2>/dev/null || true
rm -rf "${HOME}/.cache/"* 2>/dev/null || true

echo "[6/11] Journal and log rotation cleanup…"
if need_cmd journalctl; then
  journalctl --vacuum-time="${LOG_DAYS}d" || true
fi
# Remove rotated/compressed logs and truncate current logs
find /var/log -type f -name "*.gz" -delete 2>/dev/null || true
find /var/log -type f -regextype posix-extended -regex '.*\.[0-9]+' -delete 2>/dev/null || true
find /var/log -type f -name "*.log" -exec truncate -s 0 {} \; 2>/dev/null || true

echo "[7/11] Clean apt list residue (will re-generate on next apt update)…"
rm -rf /var/lib/apt/lists/* 2>/dev/null || true

echo "[8/11] Optional ecosystem cleanup…"
if ${DOCKER_PRUNE} && need_cmd docker; then
  echo "  • Docker system prune -a --volumes"
  docker system prune -a --volumes -f || true
else
  echo "  • Docker prune skipped (use --include-docker to enable)."
fi

if ${SNAP_PRUNE} && need_cmd snap; then
  echo "  • Snap old revision cleanup"
  snap list --all | awk '/disabled/{print $1, $3}' | while read snapname revision; do
    snap remove "$snapname" --revision="$revision" || true
  done
else
  echo "  • Snap prune skipped (use --include-snap to enable)."
fi

if ${FLATPAK_PRUNE} && need_cmd flatpak; then
  echo "  • Flatpak uninstall --unused"
  flatpak uninstall --unused -y || true
else
  echo "  • Flatpak prune skipped (use --include-flatpak to enable)."
fi

echo "[9/11] Try removing some heavy optional desktop apps (quietly, if installed)…"
apt-get -y remove --purge libreoffice* thunderbird* hexchat* gimp* >/dev/null 2>&1 || true

echo "[10/11] Final autoremove/clean sweep…"
apt-get -y autoremove --purge || true
apt-get -y autoclean || true
apt-get -y clean || true

echo "[11/11] Disk usage AFTER cleanup (before zero-fill):"
df -h || true
echo

if ${ZERO_FILL}; then
  echo "Zero-filling free space to help compact the disk…"
  echo "This will temporarily fill the disk; that's expected."
  sync
  dd if=/dev/zero of=/EMPTY bs=1M status=progress || true
  sync
  rm -f /EMPTY || true
  sync
  echo "Zero-fill complete."
else
  echo "Skipped zero-fill (--no-zero-fill)."
fi

echo
echo "Disk usage AFTER zero-fill (file removed):"
df -h || true
echo
echo "=== Cleanup finished ==="
echo "NEXT: Power off the VM and compact the virtual disk on the host."
