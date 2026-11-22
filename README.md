# VulnBox - Project Documentation

[![View PDF](https://img.shields.io/badge/View-PDF-blue?style=for-the-badge&logo=adobeacrobatreader&logoColor=white)](https://alehshehda.github.io/APNWA-VulnBox/APNWA-VulnBox.pdf)
[![Download PDF](https://img.shields.io/badge/Download-PDF-success?style=for-the-badge&logo=github&logoColor=white)](https://github.com/alehshehda/APNWA-VulnBox/releases/download/latest/APNWA-VulnBox.pdf)
[![Build PDF](https://img.shields.io/github/actions/workflow/status/alehshehda/APNWA-VulnBox/compile.yml?style=for-the-badge&logo=latex&label=Report%20PDF)](https://github.com/alehshehda/APNWA-VulnBox/actions/workflows/compile.yml)
[![Box CI](https://img.shields.io/github/actions/workflow/status/alehshehda/APNWA-VulnBox/box-ci.yml?style=for-the-badge&logo=linux&label=Box%20CI)](https://github.com/alehshehda/APNWA-VulnBox/actions/workflows/box-ci.yml)

Technical documentation and reproducible configuration artifacts for **VulnBox** (`vulnbox`, exported as `VulnBox.ova`) - a lightweight, isolated Ubuntu Server 26.04.1 LTS VirtualBox laboratory machine built without a GUI for network and web application security testing classes.

---

## Key Highlights

- **Headless Ubuntu Server 26.04.1 LTS Base:** Zero desktop environment (`multi-user.target`), wildcard Netplan DHCP (`en*` / `eth*`, `optional: true`, `dhcp-identifier: mac`), and password-protected GRUB2 bootloader with `--unrestricted` normal boot.
- **Network Access Control:** UFW host firewall permitting only TCP ports `22` (SSH), `445` (Samba), and `8080` (Nginx), combined with `fail2ban` protection on SSH.
- **Multi-Layer Service Architecture:**
  - **Network Discovery (`Samba :445`, `nobody`):** Read-only anonymous share exposing deployment notes.
  - **Web Diagnostics (`Nginx + PHP-FPM :8080`, `www-data`):** Lightweight PHP diagnostics panel without a database backend.
  - **Loopback Service (`Python Flask 127.0.0.1:5000`, `dev`):** Managed via `systemd`, reachable after local port forwarding, protecting `/home/dev/user.txt`.
  - **Administrative Tasks (`root`):** Scheduled `cron` maintenance job and `sudoers.d` Python task delegation guarding `/root/root.txt`.
- **Hybrid Build & Automated E2E Audit:** Step-by-step manual setup guide (`box/SETUP.md`), idempotent `provision_vm.sh`, end-to-end compliance checker `verify_vm.sh`, and OVA pre-export cleaner `cleanup_vm.sh`.

---

## Course & Authors

Project developed for the **Advanced Penetration Testing of Networks and Web Applications** (*Zaawansowane Testy Penetracyjne Sieci i Aplikacji Web* - APNWA, `04CBE0-25S302W05194G`) course at **Wrocław University of Science and Technology** (WUST / PWr), Faculty of Information and Communication Technology (Cybersecurity), Group 1 (Thursday, 11:15 - 14:00).

| Author | Student ID | Role |
| :--- | :--- | :--- |
| **Aleh Shehda** | `272277` | Architecture design, VM automation (`box/scripts/`), CI/CD, LaTeX documentation |
| **Aliaksei Lapachuk** | `276711` | Network & system hardening (Netplan, GRUB2, UFW, `fail2ban`), verification tests |
| **Karyna Zahorskaya** | `272302` | Service layer implementation (Samba, Nginx/PHP-FPM, Flask), E2E documentation |

**Project Supervisor:** mgr inż. Bartłomiej Balcerek

---

## Repository Structure

```text
├── .github/workflows/
│   ├── compile.yml                     # Automated LaTeX compilation, GitHub Pages & Release latest
│   └── box-ci.yml                      # Shellcheck, Python/PHP/YAML/sudoers lints & E2E probes
├── box/
│   ├── SETUP.md                        # Step-by-step manual & automated Ubuntu 26.04.1 VM build guide
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
│   └── images/                         # TikZ vector diagrams, Affinity icons, and screenshot slots
└── README.md                           # Project overview
```

---

## Compilation & Local Validation

The report is automatically compiled to **`APNWA-VulnBox.pdf`** and published to GitHub Releases and GitHub Pages on every push to `main`.

To compile the documentation locally:

```bash
cd report
pdflatex -interaction=nonstopmode -halt-on-error main.tex
bibtex main
pdflatex -interaction=nonstopmode -halt-on-error main.tex
pdflatex -interaction=nonstopmode -halt-on-error main.tex
```
