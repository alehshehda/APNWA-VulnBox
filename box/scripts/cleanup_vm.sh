#!/usr/bin/env bash
# VulnBox pre-export hygiene and state sanitization script before creating VulnBox.ova.
set -euo pipefail

if [ "${EUID}" -ne 0 ]; then
    echo "Error: cleanup_vm.sh must be executed as root (sudo)." >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOX_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "[1/5] Resetting /home/dev/.ssh/authorized_keys..."
install -d -m 0700 -o dev -g dev /home/dev/.ssh
: > /home/dev/.ssh/authorized_keys
chown dev:dev /home/dev/.ssh/authorized_keys
chmod 0600 /home/dev/.ssh/authorized_keys

echo "[2/5] Restoring default administrative scripts in /opt/admin..."
if [ -f "${BOX_ROOT}/src/admin/hooks/pre_backup.sh" ]; then
    install -m 0775 -o root -g dev "${BOX_ROOT}/src/admin/hooks/pre_backup.sh" /opt/admin/hooks/pre_backup.sh
fi
if [ -f "${BOX_ROOT}/src/admin/status_helper.py" ]; then
    install -m 0664 -o root -g dev "${BOX_ROOT}/src/admin/status_helper.py" /opt/admin/status_helper.py
fi

echo "[3/5] Cleaning temporary directories and verification logs..."
rm -f /var/log/vulnbox-backup.log
find /tmp -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>/dev/null || true
find /var/tmp -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>/dev/null || true

echo "[4/5] Cleaning APT cache and vacuuming systemd journal..."
apt-get clean
journalctl --rotate || true
journalctl --vacuum-time=1s || true

echo "[5/5] Clearing shell history for root and dev..."
rm -f /root/.bash_history /home/dev/.bash_history
history -c || true

echo "VulnBox cleanup complete. Shut down the VM ('sudo poweroff') to export VulnBox.ova."
