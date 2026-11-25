# VulnBox - Project Documentation

[![View PDF](https://img.shields.io/badge/View-PDF-blue?style=for-the-badge&logo=adobeacrobatreader&logoColor=white)](https://alehshehda.github.io/APNWA-VulnBox/APNWA-VulnBox.pdf)
[![Download PDF](https://img.shields.io/badge/Download-PDF-success?style=for-the-badge&logo=github&logoColor=white)](https://github.com/alehshehda/APNWA-VulnBox/releases/download/latest/APNWA-VulnBox.pdf)
[![Box CI](https://img.shields.io/github/actions/workflow/status/alehshehda/APNWA-VulnBox/box-ci.yml?style=for-the-badge&logo=linux&label=Box%20CI)](https://github.com/alehshehda/APNWA-VulnBox/actions/workflows/box-ci.yml)

Technical documentation and reproducible configuration artifacts for **VulnBox** - a lightweight, isolated Ubuntu Server 26.04.1 LTS VirtualBox laboratory machine built without a GUI.

---

## Key Highlights

- **Headless Ubuntu Server 26.04.1 LTS Base:** No desktop environment (`multi-user.target`), hardware-independent Netplan DHCP (`en*` / `eth*`, `optional: true`, `dhcp-identifier: mac` for seamless OVA import), and password-protected GRUB2 bootloader with `--unrestricted` unattended normal boot.
- **Network Access Control:** UFW host firewall permitting only TCP ports `22` (SSH), `445` (Samba), and `8080` (Nginx), combined with `fail2ban` brute-force protection on SSH.
- **Multi-Layer Service Architecture:**
  - **Network Discovery (`Samba :445`, `nobody`):** Read-only anonymous guest share exposing deployment notes (`CWE-538`, `CWE-200`).
  - **Web Diagnostics (`Nginx + PHP-FPM :8080`, `www-data`):** PHP diagnostics panel featuring single-pass log path sanitization (`CWE-22`) and an unrestricted internal HTTP proxy bridge (`CWE-441`, `CWE-918`) paired with group-readable API config permissions (`CWE-732`).
  - **Loopback Service (`Python Flask 127.0.0.1:5000`, `dev`):** Managed via `systemd`, reachable only locally or through the PHP bridge (`?proxy_path=`), authenticating via a static token (`CWE-798`) and managing SSH keys protecting `/home/dev/user.txt`.
  - **Administrative Tasks (`root`):** Scheduled `cron` hook (`pre_backup.sh`, `CWE-732`) and `sudoers.d` Python delegation (`maintenance.py` + `PYTHONPATH`, `CWE-427`, `CWE-732`) guarding `/root/root.txt`.
- **Documentation & Automation:** VM build and export manual ([`box/SETUP.md`](box/SETUP.md)), step-by-step E2E walkthrough ([`box/WALKTHROUGH.md`](box/WALKTHROUGH.md)), provisioning script [`provision_vm.sh`](box/scripts/provision_vm.sh), 31-check self-test suite [`verify_vm.sh`](box/scripts/verify_vm.sh), and OVA pre-export cleaner [`cleanup_vm.sh`](box/scripts/cleanup_vm.sh).

---

## Quick Start

1. **Build & Export the VM (`VulnBox.ova`):** Follow [`box/SETUP.md`](box/SETUP.md) (Automated `provision_vm.sh` or Manual Option B) on Ubuntu Server 26.04.1 LTS, verify with `verify_vm.sh`, sanitize with `cleanup_vm.sh`, and export to OVF 2.0.
2. **Verify the E2E Path (`0-knowledge` -> `root`):** Follow [`box/WALKTHROUGH.md`](box/WALKTHROUGH.md) from an analyst machine on `vboxnet0` (default target IP `192.168.56.101`).
3. **Read the Full Technical Report:** Download or view `APNWA-VulnBox.pdf` via the badges above, or compile locally from `report/`.

---

## Course & Authors

Project developed for the **Advanced Pentesting of Networks and Web Applications** course at **Wrocław University of Science and Technology**, Faculty of Information and Communication Technology (Cybersecurity), Group 1 (Thursday, 11:15 - 14:00).

**Authors:** Aleh Shehda, Aliaksei Lapachuk, Karyna Zahorskaya

**Project Supervisor:** mgr inż. Bartłomiej Balcerek

---

## Repository Structure

```text
├── .github/workflows/
│   ├── compile.yml                     # Automated LaTeX compilation, GitHub Pages & Release latest
│   └── box-ci.yml                      # Shellcheck, Python/PHP/YAML/sudoers lints & E2E probes
├── box/
│   ├── SETUP.md                        # Ubuntu 26.04.1 VM build, verify_vm.sh, and OVA export guide
│   ├── WALKTHROUGH.md                  # Step-by-step E2E walkthrough (0-knowledge to root)
│   ├── configs/                        # Netplan, GRUB2, UFW, fail2ban, Samba, Nginx, systemd, cron, sudoers
│   ├── src/                            # Service sources (public share, PHP panel, Flask API, admin scripts)
│   └── scripts/                        # provision_vm.sh, verify_vm.sh, cleanup_vm.sh
├── report/
│   ├── main.tex                        # Master LaTeX document (pdfLaTeX + BibTeX, PWr theme)
│   ├── config/                         # Document metadata, PWr colors, and section toggles
│   ├── preamble/                       # Typography, macros, tables, TikZ/Affinity styles, listings
│   ├── frontmatter/                    # Title page
│   ├── chapters/                       # Chapters 1-6 (Polish project documentation)
│   ├── bib/                            # BibTeX references (references.bib) and Polish bst style
│   └── images/                         # TikZ vector diagrams and Affinity icons
└── README.md                           # Project overview
```

---

## Compilation & Local Validation

The report is automatically compiled to **`APNWA-VulnBox.pdf`** and published to GitHub Releases and GitHub Pages on every push to `main`.
