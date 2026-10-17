#!/usr/bin/env bash
set -Eeuo pipefail
[[ $EUID -eq 0 ]] || { echo 'Run with sudo' >&2; exit 1; }
cd "$(dirname "$0")"
for command in docker restic python3 systemctl flock curl; do
  command -v "$command" >/dev/null || { echo "Missing prerequisite: $command" >&2; exit 1; }
done
install -d -m 700 /etc/hosting /var/lib/hosting
install -d -m 755 /usr/local/lib/hosting
if [[ ! -e /etc/hosting/hosting.env ]]; then
  install -m 600 hosting.env.example /etc/hosting/hosting.env
fi
install -m 755 backup.sh monitor.sh monitor.py /usr/local/lib/hosting/
install -m 644 systemd/*.service systemd/*.timer /etc/systemd/system/
systemctl daemon-reload
echo 'Installed. Fill /etc/hosting/hosting.env, initialize restic, then follow ops/README.md to activate.'
