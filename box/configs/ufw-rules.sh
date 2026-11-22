#!/usr/bin/env bash
set -euo pipefail

ufw --force reset
ufw default deny incoming
ufw default allow outgoing

ufw allow 22/tcp comment 'SSH administration'
ufw allow 445/tcp comment 'Samba read-only share'
ufw allow 8080/tcp comment 'Nginx PHP diagnostics panel'

ufw --force enable
ufw status verbose
