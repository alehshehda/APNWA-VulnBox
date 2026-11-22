#!/usr/bin/env bash
# VulnBox automated provisioning script for Ubuntu Server 26.04.1 LTS (no GUI).
# Mirrors the manual step-by-step configuration described in box/SETUP.md.
set -euo pipefail

if [ "${EUID}" -ne 0 ]; then
    echo "Error: provision_vm.sh must be executed with root privileges (sudo)." >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOX_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "[1/10] Configuring hostname 'vulnbox'..."
hostnamectl set-hostname vulnbox || echo "vulnbox" > /etc/hostname
if ! grep -q "vulnbox" /etc/hosts; then
    printf '127.0.1.1\tvulnbox\n' >> /etc/hosts
fi

echo "[2/10] Installing required packages..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y \
    ufw \
    fail2ban \
    samba \
    smbclient \
    nginx \
    php-fpm \
    php-cli \
    python3 \
    python3-flask \
    openssh-server \
    cron \
    curl

echo "[3/10] Creating user account 'dev' and verification flags..."
if ! id -u dev >/dev/null 2>&1; then
    useradd -m -s /bin/bash dev
fi
passwd -l dev >/dev/null 2>&1 || true

install -d -m 0700 -o dev -g dev /home/dev/.ssh
touch /home/dev/.ssh/authorized_keys
chown dev:dev /home/dev/.ssh/authorized_keys
chmod 0600 /home/dev/.ssh/authorized_keys

if [ ! -f /home/dev/user.txt ]; then
    printf 'FLAG{vulnbox_user_stage_verified_272277_276711_272302}\n' > /home/dev/user.txt
fi
chown dev:dev /home/dev/user.txt
chmod 0600 /home/dev/user.txt

if [ ! -f /root/root.txt ]; then
    printf 'FLAG{vulnbox_root_stage_verified_272277_276711_272302}\n' > /root/root.txt
fi
chown root:root /root/root.txt
chmod 0600 /root/root.txt

echo "[4/10] Deploying Netplan and GRUB2 configurations..."
install -m 0600 -o root -g root "${BOX_ROOT}/configs/01-netcfg.yaml" /etc/netplan/01-netcfg.yaml
install -m 0755 -o root -g root "${BOX_ROOT}/configs/40_custom_grub" /etc/grub.d/40_custom
if command -v update-grub >/dev/null 2>&1; then
    update-grub || true
fi

echo "[5/10] Deploying Fail2Ban and UFW firewall policy..."
install -m 0644 -o root -g root "${BOX_ROOT}/configs/jail.local" /etc/fail2ban/jail.local
bash "${BOX_ROOT}/configs/ufw-rules.sh"

echo "[6/10] Deploying Samba guest share (/srv/samba/public)..."
install -d -m 0755 -o nobody -g nogroup /srv/samba/public
install -m 0644 -o nobody -g nogroup "${BOX_ROOT}/src/public/deployment-notes.txt" /srv/samba/public/deployment-notes.txt
install -m 0644 -o root -g root "${BOX_ROOT}/configs/smb.conf" /etc/samba/smb.conf
testparm -s >/dev/null

echo "[7/10] Deploying Nginx + PHP-FPM web diagnostics portal (:8080)..."
install -d -m 0755 -o www-data -g www-data /var/www/vulnbox
install -d -m 0755 -o www-data -g www-data /var/log/webapp
install -m 0644 -o www-data -g www-data "${BOX_ROOT}/src/web/index.php" /var/www/vulnbox/index.php
printf '[%s] VulnBox web portal initialized on port 8080.\n' "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" > /var/log/webapp/app.log
chown www-data:www-data /var/log/webapp/app.log
chmod 0644 /var/log/webapp/app.log

install -m 0644 -o root -g root "${BOX_ROOT}/configs/nginx-site.conf" /etc/nginx/sites-available/vulnbox.conf
rm -f /etc/nginx/sites-enabled/default
ln -sfn /etc/nginx/sites-available/vulnbox.conf /etc/nginx/sites-enabled/vulnbox.conf
nginx -t

echo "[8/10] Deploying Internal Management API (127.0.0.1:5000)..."
install -d -m 0755 -o root -g www-data /opt/internal_api
install -m 0755 -o root -g root "${BOX_ROOT}/src/internal_api/app.py" /opt/internal_api/app.py
install -m 0640 -o root -g www-data "${BOX_ROOT}/src/internal_api/config.ini" /opt/internal_api/config.ini
install -m 0644 -o root -g root "${BOX_ROOT}/configs/flask-internal.service" /etc/systemd/system/flask-internal.service

echo "[9/10] Deploying administrative scripts, cron job, and sudoers policy..."
install -d -m 0755 -o root -g dev /opt/admin
install -d -m 0775 -o root -g dev /opt/admin/hooks
install -m 0755 -o root -g root "${BOX_ROOT}/src/admin/backup_check.sh" /opt/admin/backup_check.sh
install -m 0775 -o root -g dev "${BOX_ROOT}/src/admin/hooks/pre_backup.sh" /opt/admin/hooks/pre_backup.sh
install -m 0755 -o root -g root "${BOX_ROOT}/src/admin/maintenance.py" /opt/admin/maintenance.py
install -m 0664 -o root -g dev "${BOX_ROOT}/src/admin/status_helper.py" /opt/admin/status_helper.py

install -m 0644 -o root -g root "${BOX_ROOT}/configs/vulnbox-maintenance.cron" /etc/cron.d/vulnbox-maintenance
install -m 0440 -o root -g root "${BOX_ROOT}/configs/90-dev-admin.sudoers" /etc/sudoers.d/90-dev-admin
visudo -cf /etc/sudoers.d/90-dev-admin

echo "[10/10] Enabling and starting system services..."
systemctl daemon-reload
PHP_FPM_UNIT="$(systemctl list-unit-files 'php*-fpm.service' --no-legend | awk '{print $1}' | head -n 1)"
if [ -n "${PHP_FPM_UNIT}" ]; then
    systemctl enable --now "${PHP_FPM_UNIT}"
    systemctl restart "${PHP_FPM_UNIT}"
fi

for svc in ssh fail2ban smbd nginx flask-internal cron; do
    systemctl enable --now "${svc}"
    systemctl restart "${svc}"
done

echo "VulnBox provisioning finished. Run 'sudo bash ${SCRIPT_DIR}/verify_vm.sh' to verify."
