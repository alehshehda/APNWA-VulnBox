# VulnBox Virtual Machine Setup & Export Guide (`VulnBox.ova`)

This guide covers building, hardening, validating, and exporting the **VulnBox** virtual machine (`VulnBox.ova`) using either **automated provisioning** or **manual step-by-step installation**.

For the post-export analyst verification walkthrough (`0-knowledge` to `root`), see [WALKTHROUGH.md](WALKTHROUGH.md).

---

## 1. Base Virtual Machine Specification (VirtualBox)

| Parameter | Value |
| :--- | :--- |
| **VM Name** | `VulnBox` |
| **Hostname** | `vulnbox` |
| **Operating System** | Ubuntu Server 26.04.1 LTS (64-bit, Server install image without GUI) |
| **CPU / RAM / Disk** | 1 vCPU, 2 GB RAM, 12 GB dynamically allocated VDI |
| **Adapter 1 (NAT)** | Enabled only during OS/package installation (disabled or detached before `.ova` export) |
| **Adapter 2 (Host-Only)** | `vboxnet0` (`192.168.56.0/24`), VM IP via DHCP |
| **Export Target** | `VulnBox.ova` (Open Virtualization Format 2.0) |

> **VirtualBox Host-Only DHCP Check:** Before booting the exported lab image, verify in VirtualBox (`Tools -> Network -> Host-only Networks -> vboxnet0 -> DHCP Server`) that the built-in DHCP server is enabled for `192.168.56.0/24` (typically assigning `192.168.56.101` upward). Because `01-netcfg.yaml` sets `optional: true`, an interface without an active DHCP server will not block boot, but will have no IPv4 address.

---

## 2. Option A: Automated Provisioning

After installing a clean Ubuntu Server 26.04.1 LTS system and copying the repository (or `box/` directory) to the virtual machine (for example, `/tmp/APNWA-VulnBox/box`):

```bash
# 1. Provision all packages, accounts, services, and configurations
sudo bash /tmp/APNWA-VulnBox/box/scripts/provision_vm.sh

# 2. Run the automated E2E self-test and configuration audit (must pass 31/31)
sudo bash /tmp/APNWA-VulnBox/box/scripts/verify_vm.sh

# 3. Clean temporary artifacts, logs, and shell histories before export
sudo bash /tmp/APNWA-VulnBox/box/scripts/cleanup_vm.sh
sudo poweroff
```

> **Execution Order Matters:** Always run `verify_vm.sh` **before** `cleanup_vm.sh`, and run `sudo poweroff` immediately afterward. Running `cleanup_vm.sh` stops logging services and deletes `/tmp/APNWA-VulnBox`, whereas running `verify_vm.sh` afterwards would re-create HTTP access logs right before export.

---

## 3. Option B: Manual Step-by-Step Installation

Every step below mirrors the exact actions automated in [provision_vm.sh](scripts/provision_vm.sh). Run these commands from the root of the copied repository directory (containing `box/`).

### Step 3.1. Hostname and Package Installation

Set the local hostname to `vulnbox`, map `127.0.1.1` in `/etc/hosts`, and install the minimal service footprint (without recommended GUI bloat):

```bash
sudo hostnamectl set-hostname vulnbox
sudo sed -i 's/^127\.0\.1\.1[[:space:]].*/127.0.1.1\tvulnbox/' /etc/hosts
grep -qE '^127\.0\.1\.1[[:space:]]' /etc/hosts || printf '127.0.1.1\tvulnbox\n' | sudo tee -a /etc/hosts >/dev/null

sudo apt-get update
sudo apt-get install -y --no-install-recommends \
    openssh-server ufw fail2ban python3-systemd samba nginx \
    php-fpm python3 python3-flask cron curl
```

### Step 3.2. User Account `dev` and Verification Flags

Create the unprivileged `dev` account and lock its password (`passwd -l dev`) so password-based SSH authentication is disabled while public-key SSH authentication remains permitted. Create `/home/dev/.ssh/authorized_keys` (`0600`) and place both 32-character verification flags with strict `0600` permissions:

```bash
sudo useradd -m -s /bin/bash dev
sudo passwd -l dev
sudo install -d -m 0700 -o dev -g dev /home/dev/.ssh
sudo install -m 0600 -o dev -g dev /dev/null /home/dev/.ssh/authorized_keys

printf '%s\n' 'FLAG{Us3r_Sh3ll!7xK9#mP2@vQ4_d3v%8nR1}' | sudo tee /home/dev/user.txt >/dev/null
sudo chown dev:dev /home/dev/user.txt
sudo chmod 0600 /home/dev/user.txt

printf '%s\n' 'FLAG{R00t_Pwn3d!9zW6@kL3#bT8_sys%4mX2}' | sudo tee /root/root.txt >/dev/null
sudo chown root:root /root/root.txt
sudo chmod 0600 /root/root.txt
```

### Step 3.3. Network Configuration (Netplan) and GRUB2 Protection

1. Disable `cloud-init` network overrides (if `cloud-init` is present) so it does not regenerate `50-cloud-init.yaml` after reboot, remove installer Netplan files that pin the original MAC/interface name, and deploy `box/configs/01-netcfg.yaml` (`0600`). Running `netplan generate` prepares the config without breaking an active installer SSH session mid-setup (it takes effect automatically on reboot).
2. Deploy `box/configs/40_custom_grub` (`PBKDF2-SHA512` superuser password), disable recovery mode entries (`GRUB_DISABLE_RECOVERY="true"`), and add `--unrestricted` to normal Linux menu entries in `/etc/grub.d/10_linux` so normal boot remains unattended while editing kernel parameters (`e`) or entering the GRUB shell (`c`) requires authentication:

```bash
if [ -d /etc/cloud/cloud.cfg.d ] \
    && [ ! -f /etc/cloud/cloud-init.disabled ] \
    && [ ! -f /etc/cloud/cloud.cfg.d/00-subiquity-disable-cloudinit-networking.cfg ]; then
    printf 'network: {config: disabled}\n' | sudo tee /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg >/dev/null
fi
sudo rm -f /etc/netplan/00-installer-config.yaml /etc/netplan/50-cloud-init.yaml
sudo install -m 0600 -o root -g root box/configs/01-netcfg.yaml /etc/netplan/01-netcfg.yaml
sudo netplan generate

sudo install -m 0755 -o root -g root box/configs/40_custom_grub /etc/grub.d/40_custom
if grep -q '^#*GRUB_DISABLE_RECOVERY=' /etc/default/grub; then
    sudo sed -i 's/^#*GRUB_DISABLE_RECOVERY=.*/GRUB_DISABLE_RECOVERY="true"/' /etc/default/grub
else
    printf 'GRUB_DISABLE_RECOVERY="true"\n' | sudo tee -a /etc/default/grub >/dev/null
fi
sudo sed -i '/^CLASS="--class gnu-linux/ { /--unrestricted/! s/"$/ --unrestricted"/ }' /etc/grub.d/10_linux
sudo update-grub
```

### Step 3.4. Perimeter Defense (UFW and Fail2Ban)

Install `box/configs/jail.local` (`sshd` protection via `systemd` journal backend) and run `box/configs/ufw-rules.sh` to enforce `default deny incoming` while allowing only `22/tcp`, `445/tcp`, and `8080/tcp` (`127.0.0.1:5000` stays unreachable externally).

> **Note if provisioning over SSH:** `ufw-rules.sh` runs `ufw --force reset` briefly before enabling `22/tcp`, which takes under a second locally but is safest on the VirtualBox console.

```bash
sudo install -m 0644 -o root -g root box/configs/jail.local /etc/fail2ban/jail.local
sudo bash box/configs/ufw-rules.sh
```

### Step 3.5. Stage 1 Service: Samba Anonymous Share (`:445`)

Deploy `/etc/samba/smb.conf` (`map to guest = Bad User`, `[public]` with `guest ok = yes`, `guest only = yes`, `read only = yes`) and copy `deployment-notes.txt` to `/srv/samba/public/`:

```bash
sudo install -d -m 0755 -o nobody -g nogroup /srv/samba/public
sudo install -m 0644 -o nobody -g nogroup box/src/public/deployment-notes.txt /srv/samba/public/deployment-notes.txt
sudo install -m 0644 -o root -g root box/configs/smb.conf /etc/samba/smb.conf
sudo testparm -s
```

### Step 3.6. Stage 2 Service: Nginx + PHP-FPM Diagnostics Portal (`:8080`)

Deploy `/var/www/vulnbox/index.php`, create the baseline log `/var/log/webapp/app.log`, and configure `/etc/nginx/sites-available/vulnbox.conf` pointing to `/run/php/php-fpm.sock`:

```bash
sudo install -d -m 0755 -o www-data -g www-data /var/www/vulnbox /var/log/webapp
sudo install -m 0644 -o www-data -g www-data box/src/web/index.php /var/www/vulnbox/index.php
printf '[%s] VulnBox web portal initialized on port 8080.\n' "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" | sudo tee /var/log/webapp/app.log >/dev/null
sudo chown www-data:www-data /var/log/webapp/app.log
sudo chmod 0644 /var/log/webapp/app.log

sudo install -m 0644 -o root -g root box/configs/nginx-site.conf /etc/nginx/sites-available/vulnbox.conf
sudo rm -f /etc/nginx/sites-enabled/default
sudo ln -sfn /etc/nginx/sites-available/vulnbox.conf /etc/nginx/sites-enabled/vulnbox.conf
sudo nginx -t
```

### Step 3.7. Stage 3 Service: Internal Management API (`127.0.0.1:5000`)

Deploy `/opt/internal_api/app.py`, `/opt/internal_api/config.ini` (`0640 root:www-data`), and `flask-internal.service`. Notice that `flask-internal.service` runs under `User=dev` so it can append keys to `/home/dev/.ssh/authorized_keys`, while also setting `SupplementaryGroups=www-data` so both the Flask service and Nginx/PHP (`www-data`) can read `config.ini`:

```bash
sudo install -d -m 0755 -o root -g www-data /opt/internal_api
sudo install -m 0755 -o root -g root box/src/internal_api/app.py /opt/internal_api/app.py
sudo install -m 0640 -o root -g www-data box/src/internal_api/config.ini /opt/internal_api/config.ini
sudo install -m 0644 -o root -g root box/configs/flask-internal.service /etc/systemd/system/flask-internal.service
```

### Step 3.8. Stage 4 & 5 Services: Scheduled Cron Task and Sudoers Policy

Deploy `/opt/admin/` scripts (`pre_backup.sh` with `0775 root:dev` and `status_helper.py` with `0664 root:dev`), `/etc/cron.d/vulnbox-maintenance` (`0644 root:root`), and `/etc/sudoers.d/90-dev-admin` (`0440 root:root`):

```bash
sudo install -d -m 0755 -o root -g dev /opt/admin
sudo install -d -m 0775 -o root -g dev /opt/admin/hooks
sudo install -m 0755 -o root -g root box/src/admin/backup_check.sh /opt/admin/backup_check.sh
sudo install -m 0775 -o root -g dev box/src/admin/hooks/pre_backup.sh /opt/admin/hooks/pre_backup.sh
sudo install -m 0755 -o root -g root box/src/admin/maintenance.py /opt/admin/maintenance.py
sudo install -m 0664 -o root -g dev box/src/admin/status_helper.py /opt/admin/status_helper.py

sudo install -m 0644 -o root -g root box/configs/vulnbox-maintenance.cron /etc/cron.d/vulnbox-maintenance
sudo install -m 0440 -o root -g root box/configs/90-dev-admin.sudoers /etc/sudoers.d/90-dev-admin
sudo visudo -cf /etc/sudoers.d/90-dev-admin
```

### Step 3.9. Enabling Services

Start `php*-fpm` before restarting `nginx` so `/run/php/php-fpm.sock` exists immediately, handle both `ssh.socket` and `ssh` activation cleanly, and enable all remaining services:

```bash
sudo systemctl daemon-reload
PHP_FPM_UNIT="$(systemctl list-unit-files 'php*-fpm.service' --no-legend | awk '{print $1}' | head -n 1)"
if [ -n "${PHP_FPM_UNIT}" ]; then
    sudo systemctl enable --now "${PHP_FPM_UNIT}"
    sudo systemctl restart "${PHP_FPM_UNIT}"
fi

if systemctl is-enabled --quiet ssh.socket 2>/dev/null; then
    sudo systemctl start ssh.socket
else
    sudo systemctl enable --now ssh
    sudo systemctl restart ssh
fi

sudo systemctl enable --now fail2ban smbd nginx flask-internal cron
sudo systemctl restart fail2ban smbd nginx flask-internal cron
```

---

## 4. Pre-Export Automated Audit (`verify_vm.sh`)

Before cleaning and exporting the image, run the local verification suite inside the VM:

```bash
sudo bash box/scripts/verify_vm.sh
```

The script validates **31 conditions** (`31 passed, 0 failed`), including hostname, `dev` account, Netplan (`0600` without cloud-init overrides), GRUB2 `PBKDF2` + `--unrestricted`, UFW rules (`22/tcp`, `445/tcp`, `8080/tcp`), active systemd units, SSH `StrictModes` + `PubkeyAuthentication`, listening sockets (`:445`, `127.0.0.1:5000`), PHP-FPM socket presence, live `:8080` status, `?log=` traversal, `?proxy_path=` bridge to `:5000`, `visudo`, cron mode/hook permissions, live `su dev` + `sudo PYTHONPATH=... /usr/bin/python3 /opt/admin/maintenance.py` override, and `0600` ownership on both flags.

After the build passes `31 passed, 0 failed`, follow [WALKTHROUGH.md](WALKTHROUGH.md) from your analyst host if you also want to verify the full external flow against the running VM.

---

## 5. Exporting `VulnBox.ova`

1. Reset test keys/logs, restore `/opt/admin/` defaults, clear histories, and compact free disk blocks inside the VM:
   ```bash
   sudo bash box/scripts/cleanup_vm.sh
   sudo poweroff
   ```
2. In VirtualBox, disable **Adapter 1 (NAT)** (leave **Adapter 2** on `vboxnet0` / Host-Only enabled) and detach any installation ISO image.
3. Export the appliance as **`VulnBox.ova`** (`File -> Export Appliance -> OVF 2.0`) or via CLI:
   ```bash
   VBoxManage export "VulnBox" --output "VulnBox.ova" --ovf20 --vsys 0 \
       --product "VulnBox Educational Appliance" \
       --description "APNWA Project: Vulnerable Virtual Machine (Ubuntu Server 26.04.1 LTS)"
   ```
4. Import `VulnBox.ova` into a clean VirtualBox profile (with MAC address reinitialization enabled) and verify every stage end-to-end using [WALKTHROUGH.md](WALKTHROUGH.md).
