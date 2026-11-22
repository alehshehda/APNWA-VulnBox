"""
VulnBox status helper module loaded by /opt/admin/maintenance.py.
Group ownership in VM: root:dev (mode 0664) - intentionally writable by group 'dev'.
"""

import platform
import socket


def collect_system_summary() -> dict:
    return {
        "host": "VulnBox",
        "hostname": socket.gethostname(),
        "platform": platform.system(),
        "release": platform.release(),
        "status": "operational",
    }
