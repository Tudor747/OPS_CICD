#!/usr/bin/env bash
set -Eeuo pipefail
set -a
source /etc/hosting/hosting.env
set +a
: "${PUBLIC_URL:?Set PUBLIC_URL in /etc/hosting/hosting.env}"
exec python3 /usr/local/lib/hosting/monitor.py
