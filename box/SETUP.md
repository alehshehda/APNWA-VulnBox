# VulnBox Virtual Machine Setup & Export Guide (`VulnBox.ova`)

This guide provides both the **manual step-by-step configuration procedure** and the **automated provisioning workflow** for building, verifying, and exporting the **VulnBox** educational virtual machine (`VulnBox.ova`).

---

## 1. Base Virtual Machine Specification (VirtualBox)

| Parameter | Value |
| :--- | :--- |
| **VM Name** | `VulnBox` |
| **Hostname** | `vulnbox` |
| **Operating System** | Ubuntu Server 26.04.1 LTS (64-bit, Server install image without GUI) |
| **CPU / RAM / Disk** | 1-2 vCPU, 2048 MB RAM, 12 GB dynamically allocated VDI |
| **Adapter 1 (NAT)** | Enabled during package installation (disabled or detached before `.ova` export) |
| **Adapter 2 (Host-Only)** | `vboxnet0` (`192.168.56.0/24`), VM IP via DHCP or static `192.168.56.101/24` |
| **Export Target** | `VulnBox.ova` (Open Virtualization Format 2.0) |

---

## 2. Option A: Automated Provisioning

After installing a clean Ubuntu Server 26.04.1 LTS system and copying the `box/` directory to the virtual machine (e.g., `/tmp/APNWA-VulnBox/box`):

```bash
# 1. Provision all packages, accounts, services, and configurations
sudo bash /tmp/APNWA-VulnBox/box/scripts/provision_vm.sh

# 2. Run automated E2E self-test and configuration audit
sudo bash /tmp/APNWA-VulnBox/box/scripts/verify_vm.sh

# 3. Clean temporary artifacts and shell histories before export
sudo bash /tmp/APNWA-VulnBox/box/scripts/cleanup_vm.sh
sudo poweroff
```

---

## 3. Option B: Manual Step-by-Step Installation

Every step below corresponds directly to the actions automated in `box/scripts/provision_vm.sh`.

### Step 3.1. Hostname and Package Installation

```bash
sudo hostnamectl set-hostname vulnbox
sudo apt-get update
sudo apt-get install -y --no-install-recommends ufw fail2ban python3-systemd \
    samba nginx php-fpm python3 python3-flask cron curl
```

### Step 3.2. User Account `dev` and Verification Flags

Create the unprivileged `dev` account (with locked password so login requires SSH public-key authentication) and place the two independent 32-character stage verification flags (`user.txt` and `root.txt`) with strict `0600` permissions:

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

Remove the installer Netplan file (which pins the original MAC address), copy `box/configs/01-netcfg.yaml` to `/etc/netplan/01-netcfg.yaml` with `0600` permissions, and apply the bootloader password policy with `--unrestricted` unattended boot and disabled recovery entries:

```bash
sudo rm -f /etc/netplan/00-installer-config.yaml /etc/netplan/50-cloud-init.yaml
sudo install -m 0600 -o root -g root box/configs/01-netcfg.yaml /etc/netplan/01-netcfg.yaml
sudo netplan generate

sudo install -m 0755 -o root -g root box/configs/40_custom_grub /etc/grub.d/40_custom
sudo sed -i 's/^#*GRUB_DISABLE_RECOVERY=.*/GRUB_DISABLE_RECOVERY="true"/' /etc/default/grub
sudo sed -i '/^CLASS="--class gnu-linux/ { /--unrestricted/! s/"$/ --unrestricted"/ }' /etc/grub.d/10_linux
sudo update-grub
```

### Step 3.4. Perimeter Defense (UFW and Fail2Ban)

Install `box/configs/jail.local` and execute `box/configs/ufw-rules.sh` to enforce `default deny incoming` while allowing ports `22/tcp`, `445/tcp`, and `8080/tcp` (note that `127.0.0.1:5000` remains isolated on the loopback interface):

```bash
sudo install -m 0644 -o root -g root box/configs/jail.local /etc/fail2ban/jail.local
sudo bash box/configs/ufw-rules.sh
```

### Step 3.5. Stage 1 Service: Samba Anonymous Share (`:445`)

Deploy `/etc/samba/smb.conf` and populate `/srv/samba/public/deployment-notes.txt`:

```bash
sudo install -d -m 0755 -o nobody -g nogroup /srv/samba/public
sudo install -m 0644 -o nobody -g nogroup box/src/public/deployment-notes.txt /srv/samba/public/deployment-notes.txt
sudo install -m 0644 -o root -g root box/configs/smb.conf /etc/samba/smb.conf
sudo testparm -s
```

### Step 3.6. Stage 2 Service: Nginx + PHP-FPM Diagnostics Portal (`:8080`)

Deploy `/var/www/vulnbox/index.php` and configure `/etc/nginx/sites-available/vulnbox.conf` using the version-agnostic UNIX socket `/run/php/php-fpm.sock`:

```bash
sudo install -d -m 0755 -o www-data -g www-data /var/www/vulnbox /var/log/webapp
sudo install -m 0644 -o www-data -g www-data box/src/web/index.php /var/www/vulnbox/index.php
sudo install -m 0644 -o root -g root box/configs/nginx-site.conf /etc/nginx/sites-available/vulnbox.conf
sudo rm -f /etc/nginx/sites-enabled/default
sudo ln -sfn /etc/nginx/sites-available/vulnbox.conf /etc/nginx/sites-enabled/vulnbox.conf
sudo nginx -t
```

### Step 3.7. Stage 3 Service: Internal Management API (`127.0.0.1:5000`)

Deploy the Flask internal service and its configuration file `/opt/internal_api/config.ini` (readable by group `www-data` so the web portal can inspect it during Stage 2 verification, while running under `User=dev` so it can manage `/home/dev/.ssh/authorized_keys`):

```bash
sudo install -d -m 0755 -o root -g www-data /opt/internal_api
sudo install -m 0755 -o root -g root box/src/internal_api/app.py /opt/internal_api/app.py
sudo install -m 0640 -o root -g www-data box/src/internal_api/config.ini /opt/internal_api/config.ini
sudo install -m 0644 -o root -g root box/configs/flask-internal.service /etc/systemd/system/flask-internal.service
```

### Step 3.8. Stage 4 Services: Scheduled Cron Task and Sudoers Policy

Deploy `/opt/admin/` scripts with group ownership `root:dev` on `/opt/admin/hooks/pre_backup.sh` (`0775`) and `/opt/admin/status_helper.py` (`0664`), alongside `/etc/cron.d/vulnbox-maintenance` (`0644`) and `/etc/sudoers.d/90-dev-admin` (`0440`):

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

```bash
sudo systemctl daemon-reload
sudo systemctl start ssh.socket
sudo systemctl enable --now fail2ban smbd nginx flask-internal cron
```

---

## 4. End-to-End Verification Checklist (`0-knowledge` to `root`)

From the analyst host on the `vboxnet0` network (assuming `VulnBox` is reachable at `192.168.56.101`):

1. **Network Discovery & Samba Enumeration (`:445`)**:
   ```bash
   smbclient -N -L //192.168.56.101/
   smbclient -N //192.168.56.101/public -c "get deployment-notes.txt -"
   ```
2. **Web Diagnostics Inspection (`:8080`)**:
   ```bash
   curl -s "http://192.168.56.101:8080/?module=status"
   curl -s "http://192.168.56.101:8080/?log=....//....//....//var/www/vulnbox/index.php"
   curl -s "http://192.168.56.101:8080/?log=....//....//....//opt/internal_api/config.ini"
   ```
3. **Loopback Management API Interaction (`127.0.0.1:5000`) & SSH Access (`dev`)**:
   ```bash
   curl -s "http://192.168.56.101:8080/?proxy_path=/api/v1/info&token=vb-internal-9f8e7d6c5b4a3f2e1d0c"
   curl -s -X POST "http://192.168.56.101:8080/?proxy_path=/api/v1/ssh-key&token=vb-internal-9f8e7d6c5b4a3f2e1d0c" \
        --data-urlencode "ssh_key=$(cat ~/.ssh/id_ed25519.pub)"
   ssh dev@192.168.56.101 "id && cat /home/dev/user.txt"
   ```
4. **Administrative Privilege Verification (`dev` -> `root`)**:
   - **Path A (`cron` hook)**: Inspect `/etc/cron.d/vulnbox-maintenance` and writable `/opt/admin/hooks/pre_backup.sh` (`0775`, `root:dev`).
   - **Path B (`sudo` Python module import)**: Inspect `sudo -l` (`NOPASSWD: /usr/bin/python3 /opt/admin/maintenance.py`) and writable `/opt/admin/status_helper.py` (`0664`, `root:dev`), then verify reading `/root/root.txt`.

---

## 5. Exporting `VulnBox.ova`

1. Run `sudo bash box/scripts/cleanup_vm.sh` and `sudo poweroff`.
2. In VirtualBox, disable the NAT adapter (leave only the Host-Only / Lab network adapter enabled) and detach any installation ISO image.
3. Export the appliance as **`VulnBox.ova`** (`File -> Export Appliance -> OVF 2.0`) or via CLI:
   ```bash
   VBoxManage export "VulnBox" --output "VulnBox.ova" --ovf20 --vsys 0 \
       --product "VulnBox Educational Appliance" \
       --description "APNWA Project: Vulnerable Virtual Machine (Ubuntu Server 26.04.1 LTS)"
   ```
4. Import `VulnBox.ova` into a clean VirtualBox profile and verify that all services start automatically on boot without manual intervention.
