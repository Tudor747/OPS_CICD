# Server operations

Run these steps on Ubuntu after the root README's inspection and initial app/Jenkins
setup. These files have not configured a live server. Replace example values first.

## Domain and HTTPS

Point your domain's A record (and AAAA only if IPv6 works) at the server. Forward
80/443 if behind a router. Replace `demo.example.com` in the Apache site and enable
it as described in the root README. Review existing certificate management before
installing another client. For Ubuntu's packaged Certbot:

```bash
sudo apt update
sudo apt install certbot python3-certbot-apache
sudo apache2ctl configtest
sudo certbot --apache --redirect -d YOUR_DOMAIN
sudo certbot renew --dry-run
systemctl list-timers --all | grep certbot
curl --fail https://YOUR_DOMAIN/health
```

Certbot asks for your email and agreement to its terms. Keep renewal enabled.
[Ubuntu TLS instructions](https://ubuntu.com/server/docs/how-to/security/obtain-tls-certificates/).

## SSH and firewall

Keep your existing SSH session open. Install your public SSH key for your normal
sudo user, then verify a second connection with password authentication disabled:
`ssh -o PasswordAuthentication=no USER@SERVER`.

Inspect `sudo sshd -T` and `/etc/ssh/sshd_config.d/`. After verifying key access,
create `/etc/ssh/sshd_config.d/00-hosting.conf` containing the following settings,
provided they fit your access method (keyboard-interactive may be needed for MFA):

```text
PermitRootLogin no
PubkeyAuthentication yes
PasswordAuthentication no
KbdInteractiveAuthentication no
```

Run `sudo sshd -t`, inspect `sudo sshd -T` to confirm effective settings, then
`sudo systemctl reload ssh`. Test another new connection before closing the original.
Match blocks may require `sshd -T -C` for the actual user/address.

Inspect `sudo ss -lntp`, your provider firewall and `sudo ufw status verbose`.
If UFW is your chosen firewall, install it if needed and allow your **actual SSH
port and all existing required services** before enabling it:

```bash
sudo ufw allow YOUR_SSH_PORT/tcp
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw enable
sudo ufw status verbose
```

App port 3001 and Jenkins 8080 are bound to loopback. Keep that binding:
[Docker traffic can bypass UFW](https://docs.docker.com/engine/network/packet-filtering-firewalls/).
Verify exposure from another network, including IPv6 if configured.

## Updates and installation

```bash
sudo apt install unattended-upgrades restic python3 curl
sudo dpkg-reconfigure -plow unattended-upgrades
sudo unattended-upgrade --dry-run --debug
sudo systemctl enable docker apache2
sudo bash ops/install.sh
```

Review the existing update policy before changing it. Schedule reboots when
`/var/run/reboot-required` exists. Rebuild apps through Jenkins for base-image
updates. Review Jenkins/plugin updates and back up before rebuilding Jenkins:
`docker compose -f jenkins/compose.yaml build --pull`, followed by
`docker compose -f jenkins/compose.yaml up -d`.
Jenkins's Docker socket grants host-level control; run only trusted builds.

The installer copies scripts and systemd units; it leaves timers disabled on a
new installation until configuration is complete. Re-running it preserves your
configuration and any already enabled timers.

## Encrypted off-server backups

Edit `/etc/hosting/hosting.env` using `sudoedit`. Supply the stable project clone
path, public health URL, and an **off-server** restic destination. This root-owned
Bash environment file must stay mode 600. Never commit credentials.
For SFTP, provision root's SSH key and verify the backup host's key fingerprint;
do not disable host-key verification. Other providers may require credentials here.

Create `/etc/hosting/restic-password` with a strong unique password and mode 600.
Keep a separate secure copy of the password and repository credentials: losing
them makes backups unrecoverable. Initialize a new repository once, skipping
`init` if it already exists:

```bash
sudo bash -c 'set -a; source /etc/hosting/hosting.env; set +a; restic init'
sudo systemctl start hosting-backup.service
sudo journalctl -u hosting-backup.service -n 100 --no-pager
```

The backup briefly stops Jenkins for a consistent archive, restarts it before
uploading, and captures Apache/TLS/SSH/firewall/update configuration and project
files. Run outside builds: stopping Jenkins interrupts jobs. App traffic continues.
Keep local space for the previous and temporary Jenkins archives. Future databases
need their own consistent backup process; arbitrary Docker volumes and the entire
OS are not backed up by this script. Repository integrity is checked after backup.

Restore into a **new empty directory**, never over running services:

```bash
sudo bash -c 'set -a; source /etc/hosting/hosting.env; set +a; restic snapshots --tag hosting'
sudo bash -c 'set -a; source /etc/hosting/hosting.env; set +a; restic restore SNAPSHOT_ID --target /var/tmp/hosting-restore-test'
sudo tar -tf /var/tmp/hosting-restore-test/var/backups/hosting/jenkins-home.tar | head
```

Inspect restored configuration and test Jenkins restoration in an isolated
environment without a Docker socket or external network access: restored jobs must
not trigger production builds. With a stopped Jenkins container and empty volume,
`docker cp - CONTAINER:/var/jenkins_home < ARCHIVE` extracts the archive; restore
ownership as required by the image. Real recovery also requires reinstalling the
server packages and restoring TLS paths. Review SSH/firewall settings before
restoring them to a different host.

After a successful restore test:

```bash
sudo systemctl enable --now hosting-backup.timer
```

Daily backups run around 03:00 in the **server timezone**. Snapshots are retained
until you explicitly expire them. Periodically review storage and run restic
`forget --tag hosting --keep-daily 7 --keep-weekly 4 --keep-monthly 6 --dry-run`
with the environment loaded. Only remove `--dry-run` and add `--prune` after
reviewing the selection and verifying recovery.
[Restic documentation](https://restic.readthedocs.io/en/stable/).

## Monitoring

Set `PUBLIC_URL` to your HTTPS `/health` endpoint. Optional `ALERT_WEBHOOK` accepts
an HTTPS URL receiving JSON `{"text":"..."}`; verify your provider's payload format.
Without a webhook, failures go to the systemd journal only. Secrets belong in the
root-owned environment file. Alerts repeat every five minutes during a failure.

```bash
sudo systemctl start hosting-monitor.service
sudo journalctl -u hosting-monitor.service -n 50 --no-pager
sudo systemctl enable --now hosting-monitor.timer
systemctl list-timers 'hosting-*'
```

Checks cover Docker/Apache, local/public app health, disk space, available memory,
and backup age. Extend `/health` when adding dependencies such as a database.
Also configure an **external uptime service** against your public health URL with
your chosen notification destination: local checks cannot report a total server or
network outage. Test alert delivery with a deliberate failure. Jenkins deployment
failures are reported in Jenkins; add its notification integration when you choose
a destination.

## Deployment and rollback

Jenkins tests the HTTP routes in a Docker build stage, builds a commit-tagged image,
then runs `ops/deploy.sh`. A failed health check restores the previous image and
still marks the build failed. First deployment has no rollback target. Brief
downtime remains possible; database migration rollback is not provided.

Manual deployment of an existing image:

```bash
sudo bash ops/deploy.sh express-demo:COMMIT_SHA
```

The previous release is tagged `express-demo:previous`; the last successful one is
`express-demo:current`. To restore the previous release manually, use its immutable
image ID so retagging cannot change your selected target:

```bash
previous=$(sudo docker image inspect --format '{{.Id}}' express-demo:previous)
sudo bash ops/deploy.sh "$previous"
```

Use this script for every deployment. A named Docker container lock coordinates
Jenkins/manual runs. After a killed process or power loss, inspect the app and
confirm no deployment is running before clearing a stale lock with
`sudo docker rm express-demo-deploy-lock`. Preserve images needed for rollback.
Plain Compose defaults to the original local demo image. To recreate the last
successful release without rebuilding, run
`sudo env APP_IMAGE=express-demo:current docker compose up -d --no-build --wait`.

## Reboot verification

At a planned maintenance time, reboot and reconnect, then check:

```bash
systemctl is-active docker apache2
sudo docker compose ps
sudo docker compose -f jenkins/compose.yaml ps
systemctl list-timers 'hosting-*'
curl --fail https://YOUR_DOMAIN/health
sudo systemctl start hosting-monitor.service
```

Verify the site from another network and Jenkins through its SSH tunnel.
Container restart policies restore the deployed image after reboot.

## Local validation

```bash
node --test
bash test/deploy.test.sh
python3 -m unittest discover -s test -p 'test_*.py'
docker compose config --quiet
docker build --target test .
```

The deployment tests use a fake Docker CLI. They do not replace an Ubuntu
integration test of TLS, timers, backups and recovery.
