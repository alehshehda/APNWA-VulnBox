#!/usr/bin/env bash
# VulnBox periodic maintenance task invoked by /etc/cron.d/vulnbox-maintenance
set -euo pipefail

HOOK_SCRIPT="/opt/admin/hooks/pre_backup.sh"
STAMP_FILE="/var/log/vulnbox-backup.log"

if [ -x "${HOOK_SCRIPT}" ]; then
    "${HOOK_SCRIPT}"
fi

if [ -w "/var/log" ] || [ -w "${STAMP_FILE}" ]; then
    printf '[%s] VulnBox backup verification completed.\n' "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" >> "${STAMP_FILE}" 2>/dev/null || true
fi
