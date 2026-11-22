#!/usr/bin/env bash
# VulnBox automated E2E self-test and configuration audit script.
set -euo pipefail

PASS_COUNT=0
FAIL_COUNT=0

report_check() {
    local status="$1"
    local label="$2"
    if [ "${status}" = "PASS" ]; then
        printf '[PASS] %s\n' "${label}"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        printf '[FAIL] %s\n' "${label}" >&2
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
}

echo "=== VulnBox End-to-End Verification Suite ==="

# 1. Hostname and user account
CURRENT_HOST="$(hostname)"
if [ "${CURRENT_HOST}" = "vulnbox" ]; then
    report_check "PASS" "Hostname is set to 'vulnbox'"
else
    report_check "FAIL" "Hostname is '${CURRENT_HOST}' (expected 'vulnbox')"
fi

if id -u dev >/dev/null 2>&1; then
    report_check "PASS" "System account 'dev' exists"
else
    report_check "FAIL" "System account 'dev' is missing"
fi

# 2. Netplan universal DHCP configuration
NETPLAN_PERM="$(stat -c '%a' /etc/netplan/01-netcfg.yaml 2>/dev/null || true)"
if [ "${NETPLAN_PERM}" = "600" ] \
    && [ ! -f /etc/netplan/00-installer-config.yaml ] \
    && [ ! -f /etc/netplan/50-cloud-init.yaml ]; then
    report_check "PASS" "Netplan uses 01-netcfg.yaml (mode 0600) with no installer/cloud-init overrides"
else
    report_check "FAIL" "Netplan configuration mismatch (01-netcfg.yaml mode='${NETPLAN_PERM}')"
fi

# 3. GRUB2 protection
if [ -f /etc/grub.d/40_custom ] && grep -q "password_pbkdf2" /etc/grub.d/40_custom; then
    report_check "PASS" "GRUB2 custom PBKDF2 configuration present in /etc/grub.d/40_custom"
else
    report_check "FAIL" "GRUB2 custom PBKDF2 configuration missing"
fi

if [ -f /boot/grub/grub.cfg ] && grep -q "password_pbkdf2" /boot/grub/grub.cfg; then
    report_check "PASS" "Active /boot/grub/grub.cfg contains password_pbkdf2 directive"
else
    report_check "FAIL" "Active /boot/grub/grub.cfg does not contain password_pbkdf2 directive"
fi

if [ -f /boot/grub/grub.cfg ] && grep -q -- "--unrestricted" /boot/grub/grub.cfg; then
    report_check "PASS" "Active /boot/grub/grub.cfg enables --unrestricted unattended boot"
else
    report_check "FAIL" "Active /boot/grub/grub.cfg is missing --unrestricted directive"
fi

# 4. UFW and Fail2Ban
if ufw status | grep -q "Status: active"; then
    report_check "PASS" "UFW firewall is active"
else
    report_check "FAIL" "UFW firewall is inactive"
fi

for port in "22/tcp" "445/tcp" "8080/tcp"; do
    if ufw status | grep -q "${port}"; then
        report_check "PASS" "UFW rule present for ${port}"
    else
        report_check "FAIL" "UFW rule missing for ${port}"
    fi
done

# 5. Systemd service health (supporting Ubuntu ssh.socket activation)
if systemctl is-active --quiet ssh.socket || systemctl is-active --quiet ssh; then
    report_check "PASS" "OpenSSH listener (ssh.socket / ssh.service) is active"
else
    report_check "FAIL" "OpenSSH listener is NOT active"
fi

for svc in fail2ban smbd nginx flask-internal cron; do
    if systemctl is-active --quiet "${svc}"; then
        report_check "PASS" "Systemd service '${svc}' is active"
    else
        report_check "FAIL" "Systemd service '${svc}' is NOT active"
    fi
done

# 6. Samba configuration and share file
if testparm -s >/dev/null 2>&1 && [ -f /srv/samba/public/deployment-notes.txt ]; then
    report_check "PASS" "Samba configuration valid and deployment-notes.txt present"
else
    report_check "FAIL" "Samba validation or deployment-notes.txt check failed"
fi

# 7. Active HTTP probe: Nginx + PHP-FPM portal (:8080)
WEB_STATUS="$(curl -fsS "http://127.0.0.1:8080/?module=status" || true)"
if printf '%s' "${WEB_STATUS}" | grep -q "VulnBox Diagnostics Portal"; then
    report_check "PASS" "HTTP probe on 127.0.0.1:8080/?module=status returned portal status"
else
    report_check "FAIL" "HTTP probe on 127.0.0.1:8080/?module=status failed"
fi

WEB_TRAVERSAL="$(curl -fsS "http://127.0.0.1:8080/?log=....//....//....//opt/internal_api/config.ini" || true)"
if printf '%s' "${WEB_TRAVERSAL}" | grep -q "api_token"; then
    report_check "PASS" "Stage 2 path normalization check retrieved /opt/internal_api/config.ini"
else
    report_check "FAIL" "Stage 2 path normalization check failed to read config.ini"
fi

# 8. Active HTTP probe: Internal Flask API (127.0.0.1:5000)
API_HEALTH="$(curl -fsS "http://127.0.0.1:5000/health" || true)"
if printf '%s' "${API_HEALTH}" | grep -q '"status"'; then
    report_check "PASS" "Internal Flask API /health endpoint responded on 127.0.0.1:5000"
else
    report_check "FAIL" "Internal Flask API /health endpoint failed on 127.0.0.1:5000"
fi

API_TOKEN="$(awk -F '=' '/^[[:space:]]*api_token[[:space:]]*=/ {gsub(/[[:space:]]/, "", $2); print $2}' /opt/internal_api/config.ini 2>/dev/null || true)"
API_INFO="$(curl -fsS -H "X-Internal-Token: ${API_TOKEN}" "http://127.0.0.1:5000/api/v1/info" || true)"
if printf '%s' "${API_INFO}" | grep -q '"managed_account"'; then
    report_check "PASS" "Internal Flask API /api/v1/info authenticated using token from config.ini"
else
    report_check "FAIL" "Internal Flask API /api/v1/info authentication failed"
fi

# 9. Sudoers, Cron, and Administrative script permissions
if visudo -cf /etc/sudoers.d/90-dev-admin >/dev/null 2>&1; then
    report_check "PASS" "Sudoers policy /etc/sudoers.d/90-dev-admin passed visudo syntax check"
else
    report_check "FAIL" "Sudoers policy /etc/sudoers.d/90-dev-admin failed visudo check"
fi

HOOK_PERM="$(stat -c '%a:%U:%G' /opt/admin/hooks/pre_backup.sh 2>/dev/null || true)"
if [ -f /etc/cron.d/vulnbox-maintenance ] && [ "${HOOK_PERM}" = "775:root:dev" ]; then
    report_check "PASS" "Cron configuration present and pre_backup.sh permissions are 0775 (root:dev)"
else
    report_check "FAIL" "Cron configuration or pre_backup.sh permissions invalid (${HOOK_PERM})"
fi

HELPER_PERM="$(stat -c '%a:%U:%G' /opt/admin/status_helper.py 2>/dev/null || true)"
if [ "${HELPER_PERM}" = "664:root:dev" ]; then
    report_check "PASS" "Module /opt/admin/status_helper.py permissions are 0664 (root:dev)"
else
    report_check "FAIL" "Module /opt/admin/status_helper.py permissions invalid (${HELPER_PERM})"
fi

# 10. Verification flags and permissions
USER_FLAG_PERM="$(stat -c '%a:%U' /home/dev/user.txt 2>/dev/null || true)"
if [ "${USER_FLAG_PERM}" = "600:dev" ]; then
    report_check "PASS" "User flag /home/dev/user.txt exists with mode 0600 and owner dev"
else
    report_check "FAIL" "User flag /home/dev/user.txt permissions invalid (${USER_FLAG_PERM})"
fi

ROOT_FLAG_PERM="$(stat -c '%a:%U' /root/root.txt 2>/dev/null || true)"
if [ "${ROOT_FLAG_PERM}" = "600:root" ]; then
    report_check "PASS" "Root flag /root/root.txt exists with mode 0600 and owner root"
else
    report_check "FAIL" "Root flag /root/root.txt permissions invalid (${ROOT_FLAG_PERM})"
fi

printf '\n=== Summary: %d passed, %d failed ===\n' "${PASS_COUNT}" "${FAIL_COUNT}"
if [ "${FAIL_COUNT}" -gt 0 ]; then
    exit 1
fi
