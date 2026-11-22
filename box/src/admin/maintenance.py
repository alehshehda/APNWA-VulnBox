#!/usr/bin/env python3
"""
VulnBox administrative diagnostic runner.
Imports status_helper from /opt/admin to collect system health metadata.
"""

import json
import sys
from pathlib import Path

CURRENT_DIR = Path(__file__).resolve().parent
if str(CURRENT_DIR) not in sys.path:
    sys.path.append(str(CURRENT_DIR))

import status_helper  # noqa: E402


def main() -> int:
    summary = status_helper.collect_system_summary()
    print(f"[VulnBox Maintenance] System summary: {json.dumps(summary)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
