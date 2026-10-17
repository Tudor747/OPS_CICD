# Ubuntu Express hosting demo

For HTTPS, SSH/firewall setup, backups, monitoring, updates and release rollback,
continue with [the server operations guide](ops/README.md) after initial setup.
Fill in your own domain and backup destination when ready.

A small Express app behind your existing Apache, with Docker Compose and a private Jenkins instance. No Nginx, PostgreSQL, Certbot, UFW, or monitoring tools are installed. GitHub hosts your repository; the server runs open-source software.

```text
Browser -> Apache (demo.example.com) -> localhost:3001 -> Express container
Jenkins -> polls GitHub every two minutes -> builds and deploys Express
Your computer -> SSH tunnel -> localhost:8080 -> Jenkins
```

This repository prepares the files only. Work through one numbered step at a time and review the result before continuing. Nothing automatically changes Apache or installs server packages.

## 1. Inspect Ubuntu first

Run these over SSH on your Ubuntu server. They only inspect existing software and configuration.

```bash
cat /etc/os-release                 # Ubuntu release
uname -m                           # CPU architecture
free -h                            # RAM and swap
df -h /                            # Available disk space
docker --version                   # Docker CLI, if installed
docker compose version             # Compose plugin, if installed
git --version                      # Git, if installed
dpkg -l | grep -E 'docker|containerd|runc|jenkins|apache2'
sudo apache2ctl configtest          # Check existing Apache syntax
sudo apache2ctl -S                  # Existing virtual hosts
sudo apache2ctl -M                  # Enabled modules
sudo ss -lntp                      # Ports already in use
sudo docker ps -a                   # Existing containers, if Docker is installed
```

Stop here and review the output. If Docker, Compose, or Git is missing, choose installation instructions for the detected Ubuntu version after checking existing packages. Do not remove conflicting packages blindly. Use Docker Engine 28 or newer: older releases have a documented localhost-publishing exposure on the same network. This demo needs the Compose `--wait` option. Host Node.js and Java are unnecessary.

## 2. Clone your repository

First put these files in your own GitHub repository. Replace `YOUR_USER/YOUR_REPO` below. Check that the destination is unused; reuse an existing hosting directory's ownership policy instead of changing it.

```bash
ls -ld /opt/hosting /opt/hosting/apps /opt/hosting/apps/demo  # Inspect destinations
```

If `/opt/hosting` is new:

```bash
sudo mkdir -p /opt/hosting/apps     # Create the project parent directory
sudo chown "$USER:$(id -gn)" /opt/hosting/apps # Let your SSH user clone projects here
git clone https://github.com/YOUR_USER/YOUR_REPO.git /opt/hosting/apps/demo
cd /opt/hosting/apps/demo
```

For this small demo, the Jenkins configuration lives inside this repo's `jenkins/` folder; only one Jenkins service is needed for all projects. Its data lives in a named Docker volume. Jenkins checks out its own copy of the app when it deploys, so the original clone will not automatically update after pushes.

## 3. Run Express locally on the server

Confirm port 3001 and the Compose project name `express-demo` are unused first.

```bash
sudo docker compose up -d --build --wait # Build and start the app; wait for health
curl http://127.0.0.1:3001/               # Expected: Hello from my Ubuntu server!
curl http://127.0.0.1:3001/health         # Expected: {"status":"ok"}
sudo docker compose ps                  # Check the running container
```

The app has a 256 MB runtime limit. Builds consume additional host memory. Apache is still unchanged.

## 4. Add one Apache site

Review the existing virtual hosts from step 1 before selecting a new hostname. Edit `apache/express-demo.conf` to replace `demo.example.com` with your hostname. The sample is HTTP only; if you already manage HTTPS, integrate with that existing configuration separately. Do not use HTTP for sensitive traffic.

Verify `/etc/apache2/sites-available/express-demo.conf` does not already exist. If it does, inspect it and choose another filename rather than overwriting it.

```bash
sudo ls -l /etc/apache2/sites-available/express-demo.conf # Check destination
sudo a2enmod proxy proxy_http             # Enable reverse proxy modules if needed
sudo cp -n apache/express-demo.conf /etc/apache2/sites-available/express-demo.conf
sudo a2ensite express-demo.conf           # Enable only the new site
sudo apache2ctl configtest                # Must say Syntax OK before reloading
```

Only after the syntax check succeeds:

```bash
sudo systemctl reload apache2            # Apply the new site without stopping Apache
curl -H 'Host: demo.example.com' http://127.0.0.1/ # Use your chosen hostname here
```

DNS must point to your server for domain access. Internet access also depends on your existing router/ISP setup. Only Apache's existing public ports should be forwarded; never forward 3001 or 8080. No DNS/router changes are performed by this repository.

## 5. Start private Jenkins

Confirm port 8080 and project name `hosting-jenkins` are unused and that you do not already have Jenkins. This minimal personal-server setup runs trusted builds on the controller with access to the host Docker socket. That access is effectively root access to the Ubuntu host. Only your trusted repository/branch should run here; do not enable untrusted pull-request builds. Separate build agents are a future improvement if you need isolation.

```bash
sudo docker compose -f jenkins/compose.yaml up -d --build # Build and start Jenkins
sudo docker compose -f jenkins/compose.yaml logs --tail=50 # Check startup
sudo docker compose -f jenkins/compose.yaml exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword
```

Use the initial password locally; do not paste it into chat or commit it. If startup is still in progress, wait for the setup screen before reading it again.

On your own computer, open a second terminal and keep this SSH tunnel running:

```bash
ssh -N -L 8080:127.0.0.1:8080 YOUR_SSH_USER@YOUR_SERVER
```

Open `http://localhost:8080`. Unlock Jenkins, choose the plugin-selection option (Pipeline and Git are already included in the image), and create your administrator account. Under **Manage Jenkins -> System**, use `http://localhost:8080/` as the Jenkins URL for this tunnel-based demo. Under **Manage Jenkins -> Nodes -> Built-In Node -> Configure**, set **Number of executors** to **1** to limit builds on the 8 GB server. Leave anonymous access disabled. Jenkins has a 1.5 GB container limit and a 768 MB Java heap.

## 6. Connect GitHub and deploy

1. Create a **Pipeline** job named `express-demo`.
2. Select **Pipeline script from SCM**, then **Git**.
3. Enter your GitHub repository HTTPS URL. For a private repository, add Jenkins username/password credentials using your GitHub username and a read-only repository token as the password. Never put the token in files or the URL.
4. Set the branch to `*/main` (or your actual default branch).
5. Set **Script Path** to `Jenkinsfile`, save, and click **Build Now** once.
6. After it succeeds, edit the greeting in `app.js`, commit, and push to that branch. Jenkins checks for changes every two minutes and deploys automatically when a change is detected. No public webhook or Jenkins endpoint is needed.

The initial build registers the polling trigger. Compose uses the fixed project name `express-demo`, so Jenkins replaces the same demo container started manually. The pipeline tests HTTP routes, builds a commit-tagged image, and restores the previous image if deployment health fails. Deployment can briefly interrupt requests; it does not implement zero-downtime deployment or database migration rollback. See the operations guide for recovery details.

## Adding another project

Use another repository and `/opt/hosting/apps/another-app` folder. Copy the app files, set a unique Compose `name`, and use another localhost host port such as `127.0.0.1:3002:3000`. Create a separate Apache site with its own hostname pointing to that port, and a separate Jenkins Pipeline job. Reuse the existing Jenkins service. Do not start another copy of its Compose file. Keep deployments for each app on one trusted branch/job.

If PostgreSQL is needed later, add it to that app's Compose network with a persistent volume and no published `ports`. The app can connect to its database service name over the private Docker network.

## Basic maintenance

```bash
sudo docker compose logs --tail=100 app   # Inspect app logs
sudo docker system df                    # Inspect image/build-cache disk usage
```

Log rotation is configured, but builds accumulate images/cache over time. Review disk usage before choosing cleanup commands. Back up the Jenkins named volume and any future database volumes; do not use `docker compose down -v` unless you intend to delete that project's data. Image tags track updates and are not digest-pinned in this demo.

## Official references

- [Docker on Ubuntu](https://docs.docker.com/engine/install/ubuntu/)
- [Docker localhost port publishing](https://docs.docker.com/engine/network/port-publishing/)
- [Apache reverse proxy guide](https://httpd.apache.org/docs/2.4/howto/reverse_proxy.html)
- [Jenkins Docker installation](https://www.jenkins.io/doc/book/installing/docker/)
- [Jenkins Pipeline syntax and SCM polling](https://www.jenkins.io/doc/book/pipeline/syntax/)
