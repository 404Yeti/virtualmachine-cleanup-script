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
  --no-zero-fill       Skip zero-filling (or fstrim) of free space
  -h, --help           Show this help
USAGE
}

# Require root (script expects sudo/root)
if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  echo "Please run as root (e.g., sudo $0 ...)" >&2
  exit 1
fi

# Detect invoking user's home when run via sudo (fallback to root)
INVOKER_HOME="${HOME}"
if [[ -n "${SUDO_USER:-}" ]] && [[ "${SUDO_USER}" != "root" ]]; then
  INVOKER_HOME="$(getent passwd "${SUDO_USER}" | cut -d: -f6 || echo "/home/${SUDO_USER}")"
fi

# Parse flags
while [[ $# -gt 0 ]]; do
  case "$1" in
    --logs-days)
      LOG_DAYS="${2:-7}"
      [[ "${LOG_DAYS}" =~ ^[0-9]+$ ]] || { echo "ERROR: --logs-days expects an integer" >&2; exit 1; }
      shift 2
      ;;
    --include-docker) DOCKER_PRUNE=true; shift ;;
    --include-snap) SNAP_PRUNE=true; shift ;;
    --include-flatpak) FLATPAK_PRUNE=true; shift ;;
    --no-zero-fill) ZERO_FILL=false; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

need_cmd() { command -v "$1" >/dev/null 2>&1; }

export DEBIAN_FRONTEND=noninteractive

echo "=== VM Cleanup starting ==="
echo "Keeping journal logs for: ${LOG_DAYS}d"
echo "Docker prune: ${DOCKER_PRUNE}"
echo "Snap prune:   ${SNAP_PRUNE}"
echo "Flatpak prune:${FLATPAK_PRUNE}"
echo "Zero-fill:    ${ZERO_FILL}"
echo

echo "[1/12] Disk usage BEFORE:"
df -h || true
echo

echo "[2/12] APT cleanup (autoremove/autoclean/clean)…"
apt-get -y update >/dev/null || true
apt-get -y autoremove --purge || true
apt-get -y autoclean || true
apt-get -y clean || true

echo "[3/12] Remove Chromium (packages + user cache) if present…"
apt-get -y remove --purge chromium chromium-common chromium-browser >/dev/null 2>&1 || true
shopt -s nullglob
rm -rf "${INVOKER_HOME}/.config/chromium" "${INVOKER_HOME}/.cache/chromium" 2>/dev/null || true

echo "[4/12] Trim Brave cache (keeps profile/bookmarks)…"
rm -rf "${INVOKER_HOME}/.cache/BraveSoftware/Brave-Browser/"* 2>/dev/null || true

echo "[5/12] Clear /tmp and user caches…"
rm -rf /tmp/* 2>/dev/null || true
rm -rf "${INVOKER_HOME}/.cache/"* 2>/dev/null || true
shopt -u nullglob

echo "[6/12] Journal and log rotation cleanup…"
if need_cmd journalctl; then
  journalctl --vacuum-time="${LOG_DAYS}d" || true
fi
# Remove rotated/compressed logs and truncate common *.log, but keep some auth/last logs intact
find /var/log -xdev -type f -name "*.gz" -delete 2>/dev/null || true
find /var/log -xdev -type f -regextype posix-extended -regex '.*/.*\.[0-9]+' -delete 2>/dev/null || true
find /var/log -xdev -type f -name "*.log" \
  ! -name "lastlog" ! -name "wtmp" ! -name "btmp" \
  -exec truncate -s 0 {} \; 2>/dev/null || true

echo "[7/12] Clean apt list residue (will re-generate on next apt update)…"
rm -rf /var/lib/apt/lists/* 2>/dev/null || true

echo "[8/12] Optional ecosystem cleanup…"
if ${DOCKER_PRUNE} && need_cmd docker; then
  echo "  • Docker system prune -a --volumes"
  docker system prune -a --volumes -f || true
else
  echo "  • Docker prune skipped (use --include-docker to enable)."
fi

if ${SNAP_PRUNE} && need_cmd snap; then
  echo "  • Snap old revision cleanup"
  snap list --all 2>/dev/null | awk '/disabled/{print $1, $3}' | while read -r snapname revision; do
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

echo "[9/12] Try removing some heavy optional desktop apps (quietly, if installed)…"
apt-get -y remove --purge libreoffice* thunderbird* hexchat* gimp* >/dev/null 2>&1 || true

echo "[10/12] Final autoremove/clean sweep…"
apt-get -y autoremove --purge || true
apt-get -y autoclean || true
apt-get -y clean || true

echo "[11/12] Disk usage AFTER cleanup (pre-trim/zero-fill):"
df -h || true
echo

if ${ZERO_FILL}; then
  if need_cmd fstrim; then
    echo "Running fstrim -av (preferred on SSD/VM backends)…"
    fstrim -av || true
  else
    echo "Zero-filling free space to help compact the disk…"
    echo "This will temporarily fill the disk; that's expected."
    sync
    dd if=/dev/zero of=/EMPTY bs=1M status=progress || true
    sync
    rm -f /EMPTY || true
    sync
    echo "Zero-fill complete."
  fi
else
  echo "Skipped fstrim/zero-fill (--no-zero-fill)."
fi

echo
echo "[12/12] Disk usage AFTER trim/zero-fill:"
df -h || true
echo
echo "=== Cleanup finished ==="
echo "NEXT: Power off the VM and compact the virtual disk on the host."
