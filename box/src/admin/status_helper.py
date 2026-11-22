"""
VulnBox status helper module loaded by /opt/admin/maintenance.py.
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
