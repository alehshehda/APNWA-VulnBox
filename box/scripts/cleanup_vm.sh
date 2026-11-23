#!/usr/bin/env bash
# VulnBox pre-export hygiene and disk compaction script before creating VulnBox.ova.
set -euo pipefail

if [ "${EUID}" -ne 0 ]; then
    echo "Error: cleanup_vm.sh must be executed as root (sudo)." >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOX_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "[1/8] Stopping logging services during cleanup..."
for svc in cron fail2ban nginx smbd flask-internal; do
    systemctl stop "${svc}" 2>/dev/null || true
done

echo "[2/8] Resetting /home/dev/.ssh/authorized_keys..."
install -d -m 0700 -o dev -g dev /home/dev/.ssh
: > /home/dev/.ssh/authorized_keys
chown dev:dev /home/dev/.ssh/authorized_keys
chmod 0600 /home/dev/.ssh/authorized_keys

echo "[3/8] Restoring default administrative scripts and clearing Python caches..."
if [ -f "${BOX_ROOT}/src/admin/hooks/pre_backup.sh" ]; then
    install -m 0775 -o root -g dev "${BOX_ROOT}/src/admin/hooks/pre_backup.sh" /opt/admin/hooks/pre_backup.sh
fi
if [ -f "${BOX_ROOT}/src/admin/status_helper.py" ]; then
    install -m 0664 -o root -g dev "${BOX_ROOT}/src/admin/status_helper.py" /opt/admin/status_helper.py
fi
rm -rf /opt/admin/__pycache__ /opt/internal_api/__pycache__

echo "[4/8] Truncating active service logs and removing rotated archives..."
rm -f /var/log/vulnbox-backup.log
for log_file in \
    /var/log/nginx/*.log \
    /var/log/fail2ban.log \
    /var/log/auth.log \
    /var/log/syslog \
    /var/log/dpkg.log \
    /var/log/alternatives.log \
    /var/log/cloud-init.log \
    /var/log/cloud-init-output.log \
    /var/log/wtmp \
    /var/log/btmp \
    /var/log/lastlog; do
    if [ -f "${log_file}" ]; then
        : > "${log_file}"
    fi
done
find /var/log/samba -type f -delete 2>/dev/null || true
find /var/log/apt -type f -delete 2>/dev/null || true
find /var/log -type f \( -name '*.gz' -o -name '*.1' -o -name '*.old' \) -delete 2>/dev/null || true

echo "[5/8] Cleaning APT caches, package lists, and systemd journal..."
apt-get autoremove --purge -y >/dev/null 2>&1 || true
apt-get clean
rm -rf /var/lib/apt/lists/*
journalctl --rotate >/dev/null 2>&1 || true
journalctl --vacuum-time=1s >/dev/null 2>&1 || true

echo "[6/8] Clearing shell histories and session artifacts for all accounts..."
rm -f /root/.bash_history /root/.lesshst /root/.viminfo /root/.wget-hsts
for home_dir in /home/*; do
    if [ -d "${home_dir}" ]; then
        rm -f "${home_dir}/.bash_history" "${home_dir}/.lesshst" "${home_dir}/.viminfo" "${home_dir}/.wget-hsts"
    fi
done

echo "[7/8] Cleaning temporary directories (/tmp and /var/tmp)..."
find /tmp -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>/dev/null || true
find /var/tmp -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>/dev/null || true

echo "[8/8] Zeroing free disk space on / (preserving 1024 MB safety buffer)..."
AVAIL_MB="$(df -m --output=avail / | tail -n 1 | tr -d '[:space:]')"
if [ -n "${AVAIL_MB}" ] && [ "${AVAIL_MB}" -gt 1024 ]; then
    ZERO_MB=$((AVAIL_MB - 1024))
    echo "Writing ${ZERO_MB} MB of zeros to /zero.fill..."
    dd if=/dev/zero of=/zero.fill bs=1M count="${ZERO_MB}" status=none || true
    sync
    rm -f /zero.fill
    sync
fi
fstrim -av >/dev/null 2>&1 || true

echo "VulnBox cleanup complete. Immediately run 'sudo poweroff' to export VulnBox.ova."
