#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
[[ $EUID -eq 0 ]] || { echo 'Run as root' >&2; exit 1; }
set -a
source /etc/hosting/hosting.env
set +a
: "${HOSTING_PROJECT:?}" "${RESTIC_REPOSITORY:?}" "${RESTIC_PASSWORD_FILE:?}"
exec 9>/run/lock/hosting-backup.lock
flock -n 9 || exit 1
# Check repository access before stopping Jenkins. Initialize it separately.
restic snapshots >/dev/null
install -d -m 700 /var/backups/hosting /var/lib/hosting
cd "$HOSTING_PROJECT"
jenkins=$(docker compose -f jenkins/compose.yaml ps -aq jenkins)
[[ -n "$jenkins" ]] || { echo 'Jenkins container does not exist' >&2; exit 1; }
running=$(docker inspect --format '{{.State.Running}}' "$jenkins")
restart=false
cleanup() {
  if [[ "$restart" == true ]]; then docker start "$jenkins" >/dev/null; fi
}
trap cleanup EXIT
trap 'exit 143' TERM
trap 'exit 130' INT
if [[ "$running" == true ]]; then
  restart=true
  docker stop --time 120 "$jenkins" >/dev/null
fi
# A stopped controller produces a consistent archive. App traffic stays up.
docker cp "$jenkins:/var/jenkins_home/." - > /var/backups/hosting/jenkins-home.tar.tmp
mv /var/backups/hosting/jenkins-home.tar.tmp /var/backups/hosting/jenkins-home.tar
if [[ "$restart" == true ]]; then
  docker start "$jenkins" >/dev/null
  restart=false
fi
paths=(/var/backups/hosting/jenkins-home.tar /etc/hosting /etc/apache2 /etc/ssh /etc/apt/apt.conf.d /etc/systemd/system "$HOSTING_PROJECT")
[[ ! -d /etc/letsencrypt ]] || paths+=(/etc/letsencrypt)
[[ ! -d /etc/ufw ]] || paths+=(/etc/ufw)
restic backup --tag hosting --exclude '**/node_modules' --exclude '**/.git' --exclude '**/.npm-cache' "${paths[@]}"
restic check
date +%s > /var/lib/hosting/last-backup
echo 'Backup and repository check succeeded'
