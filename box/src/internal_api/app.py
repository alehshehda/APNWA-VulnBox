#!/usr/bin/env python3
"""
VulnBox Internal Management API (127.0.0.1:5000).
Provides local health diagnostics and developer SSH key registration for lab maintenance.
"""

import configparser
import os
from pathlib import Path
from flask import Flask, jsonify, request

app = Flask(__name__)

DEFAULT_CONFIG_PATH = "/opt/internal_api/config.ini"


def load_settings() -> dict:
    config_path = os.environ.get("VULNBOX_CONFIG", DEFAULT_CONFIG_PATH)
    parser = configparser.ConfigParser()
    if os.path.isfile(config_path):
        parser.read(config_path, encoding="utf-8")

    api_token = parser.get(
        "security", "api_token", fallback="vb-internal-9f8e7d6c5b4a3f2e1d0c"
    )
    auth_keys_default = parser.get(
        "security", "authorized_keys_path", fallback="/home/dev/.ssh/authorized_keys"
    )
    auth_keys_path = os.environ.get("VULNBOX_AUTH_KEYS_FILE", auth_keys_default)
    return {
        "api_token": api_token.strip(),
        "authorized_keys_path": auth_keys_path.strip(),
        "service_name": parser.get(
            "service", "name", fallback="vulnbox-internal-api"
        ).strip(),
    }


def is_authorized(req) -> bool:
    settings = load_settings()
    provided = req.headers.get("X-Internal-Token", "").strip()
    return bool(provided) and provided == settings["api_token"]


@app.get("/health")
def health():
    settings = load_settings()
    return jsonify(
        {
            "status": "ok",
            "service": settings["service_name"],
            "host": "vulnbox",
            "bind": "127.0.0.1:5000",
        }
    )


@app.get("/api/v1/info")
def api_info():
    if not is_authorized(request):
        return jsonify({"error": "Unauthorized: valid X-Internal-Token required"}), 403

    settings = load_settings()
    return jsonify(
        {
            "service": settings["service_name"],
            "managed_account": "dev",
            "authorized_keys_path": settings["authorized_keys_path"],
            "endpoints": ["/health", "/api/v1/info", "/api/v1/ssh-key"],
        }
    )


@app.post("/api/v1/ssh-key")
def register_ssh_key():
    if not is_authorized(request):
        return jsonify({"error": "Unauthorized: valid X-Internal-Token required"}), 403

    payload = request.get_json(silent=True) or {}
    ssh_key = str(payload.get("ssh_key", "")).strip()

    if not ssh_key or not (
        ssh_key.startswith("ssh-ed25519 ")
        or ssh_key.startswith("ssh-rsa ")
        or ssh_key.startswith("ecdsa-sha2-")
    ):
        return jsonify({"error": "Invalid SSH public key format"}), 400

    if "\n" in ssh_key or "\r" in ssh_key:
        return jsonify({"error": "Single-line SSH public key required"}), 400

    settings = load_settings()
    target_file = Path(settings["authorized_keys_path"])
    try:
        target_file.parent.mkdir(parents=True, exist_ok=True)
        existing = ""
        if target_file.is_file():
            existing = target_file.read_text(encoding="utf-8")
        if ssh_key not in existing.splitlines():
            with target_file.open("a", encoding="utf-8") as handle:
                handle.write(ssh_key + "\n")
        os.chmod(target_file, 0o600)
    except OSError as exc:
        return jsonify({"error": f"Failed to update authorized_keys: {exc}"}), 500

    return jsonify(
        {
            "status": "registered",
            "account": "dev",
            "authorized_keys_path": str(target_file),
        }
    )


if __name__ == "__main__":
    app.run(host="127.0.0.1", port=5000, debug=False)
