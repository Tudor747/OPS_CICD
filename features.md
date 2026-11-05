# Multi-project hosting and CI/CD

This document records the proposed setup discussed for hosting Java, JavaScript,
and Python applications on one Ubuntu server. It is a plan and learning guide;
the multi-project changes below have not yet been implemented or deployed.

## Current state

- This repository contains an Express demo, Docker Compose configuration, a
  Jenkins pipeline, an Apache HTTP site example, and operations scripts.
- The Express pipeline tests, builds a commit-tagged image, deploys it, and
  attempts to restore the previous image if deployment health checks fail.
- Jenkins is configured to listen on `127.0.0.1:8080` and use the host Docker
  engine. Its image includes the Git and Pipeline plugins.
- Deployment names, monitoring, and backup configuration currently assume one
  demo project. They need changes before managing several applications.
- The Apache example is HTTP only. Having its configuration in Git does not
  mean Apache or HTTPS is installed on the server.
- On the server `utilizator@facultativefiir`, `apache2 -v` returned
  `command not found`. Apache installation and the server's Linux distribution
  still need verification.
- Only `main` was found in the available local and saved remote branch
  references. The requested `pla` branch was not verified because the remote
  GitHub connection failed. No branch was created or switched during discussion.

## Intended architecture

Use one Apache installation, one Jenkins instance, and a separate Docker Compose
project for every application. Start with trusted personal/student projects.

```text
Visitor -> HTTPS port 443 -> Apache on Ubuntu
                              |
                              +-- demo.example.com
                              |     -> 127.0.0.1:3001 -> Express container
                              |
                              +-- student.example.com
                              |     -> 127.0.0.1:3002 -> Java container:8080
                              |
                              +-- reports.example.com
                                    -> 127.0.0.1:3003 -> Python container

GitHub <- outbound polling -- Jenkins -> host Docker engine -> application containers
Laptop -- SSH tunnel ------> private Jenkins interface
```

The hostnames are examples; replace them with domains you control. Their DNS
records point to the server's public IP. If the server is behind a router, the
router must forward the public web ports to the server, and the Internet
connection must permit inbound access.

Apache forwards requests according to the requested hostname. It supports
reverse proxying itself, so Nginx is not required. Jenkins performs builds and
deployments; it does not handle normal visitor requests.

Each application needs a unique Compose project name, host port, image name,
deployment lock, and release tags. Keep networks and persistent volumes separate
per project. Containers share the host's resources; this is not a design for
running untrusted tenants.

### Public and internal ports

| Port | Purpose | Exposure |
| --- | --- | --- |
| 443 | HTTPS through Apache | Public |
| 80 | HTTP redirect and common certificate validation | Usually public |
| 3001, 3002, 3003 | Application backends | Bind to `127.0.0.1` only |
| 8080 | Jenkins interface | Bind to `127.0.0.1`; access through SSH |
| Actual SSH port | Administration | Restrict to trusted IPs or use a VPN |
| Database ports | Application data access | Private Docker network; no public port mapping |

Several websites can share public port 443. Exactly one public **web** port is
possible, but certificate issuance and renewal must support that arrangement.
For example, DNS validation works without public port 80; Let's Encrypt HTTP-01
validation requires port 80. The initial suggested setup uses 80 and 443 for
websites, with restricted SSH access separately.

## Repository responsibilities

Keep `ubuntuStart` for shared hosting configuration, operations tooling, and
application templates. Keep each application's source and deployment files in
its own GitHub repository. Reuse the existing Jenkins instance by creating one
Pipeline job per application.

### Example Java full-stack repository

Assumption: Spring Boot and Maven, with the example project name `student-app`.

```text
student-app/
|-- pom.xml                       Dependencies and build configuration
|-- mvnw                          Maven wrapper launcher for Linux/CI
|-- mvnw.cmd                      Maven wrapper launcher for Windows
|-- .mvn/wrapper/                 Wrapper files required by the chosen version
|-- src/
|   |-- main/
|   |   |-- java/...              Backend source
|   |   `-- resources/
|   |       |-- application.yml  Configuration without committed secrets
|   |       |-- templates/       Thymeleaf pages, if used
|   |       `-- static/          CSS, browser JavaScript, images
|   `-- test/java/...            Tests
|-- Dockerfile                   Build the JAR and package its Java runtime
|-- compose.yaml                 Runtime configuration for this app
|-- Jenkinsfile                  Automated tests, build, and deployment
|-- ops/deploy.sh                Adapted deployment and rollback script
|-- .dockerignore                Exclude unnecessary files from Docker builds
`-- .gitignore                   Exclude secrets and generated output from Git
```

Commit the Maven wrapper files and keep Linux scripts compatible with Linux
line endings. Do not commit passwords, tokens, populated secret environment
files, or generated build output.

For Spring Boot with Thymeleaf, Java serves the pages and backend from one
container. For React or Vue that builds to static files, add `frontend/`, build
the frontend during the Docker build, and include the resulting files in the
Spring Boot static resources before packaging the JAR. A frontend requiring its
own server, such as an SSR application, needs a separate runtime arrangement.

The Dockerfile should use build stages to run Maven tests and produce an
executable Spring Boot JAR, then package that JAR with a compatible Java runtime.
The application starts with a command such as `java -jar app.jar`. Java and Maven
do not need to be installed directly on Ubuntu for this container build approach.

The existing Jenkins pipeline expects a Docker build stage named `test`; keep
that contract in the Java Dockerfile or change the Java pipeline accordingly.

Typical project-specific test/build commands:

| Runtime | Example commands inside build containers |
| --- | --- |
| Java with Maven | `./mvnw verify` |
| JavaScript with npm | `npm ci`, `npm test`, plus the project's build command |
| Python | Install locked dependencies, then run `pytest` |

### Example Java Compose settings

This is an illustrative fragment, not a complete deployment file:

```yaml
name: student-app
services:
  app:
    image: ${APP_IMAGE:-student-app:local}
    build: .
    restart: unless-stopped
    ports:
      - "127.0.0.1:3002:8080"
```

Here `3002` is the Ubuntu host port and `8080` is the port inside the Java
container. Configure Spring Boot to listen on the container interface, not just
the container's loopback address. Complete the file with an appropriate health
check, memory/CPU limits, and log rotation. The Java image must contain whatever
tool its health check invokes; the current Node-based check cannot be reused.

Docker runs the application in the background. Closing SSH or turning off the
developer's laptop does not stop it. With Docker enabled at boot and
`restart: unless-stopped`, containers return after a server reboot unless they
were explicitly stopped. A health check alone does not automatically restart
an unhealthy container.

## Changes needed in this repository

| File or area | Planned change |
| --- | --- |
| `jenkins/compose.yaml`, `jenkins/Dockerfile` | Reuse one Jenkins installation. Keep private access and initially run one build executor to limit resource use. |
| Root `Dockerfile` and `compose.yaml` | Retain for Express; provide Java and Python templates with suitable builds and runtime settings. |
| Root `Jenkinsfile` | Use as a template; each app's pipeline needs its own image names and test/build stages. |
| `ops/deploy.sh` | Parameterize project identity, image/release tags, and lock name; remove the Node-specific lock command assumption. Distribute the adapted script with each app. |
| `apache/express-demo.conf` | Retain the demo; add a separate site such as `apache/student-app.conf` pointing to `127.0.0.1:3002`. Configure HTTPS on the server. |
| Project inventory | Record each project's repository, deployment branch, Compose name, hostname, local port, and health URL without secrets. |
| `ops/monitor.py`, `ops/monitor.sh`, `ops/hosting.env.example` | Support all apps and their expected health responses; currently one local port and public URL are assumed. |
| `ops/backup.sh` and backup configuration | Separate shared Jenkins location from app locations; include each app's required persistent data and configuration, with database-aware backups. |
| Documentation and validation | Document onboarding, logs, rollback, recovery, and verify that deploying one app leaves the others running. |

Do not copy the existing deployment script unchanged: projects would share
`express-demo` release tags and its deployment lock. A stale lock must be
investigated before removal.

## Connect Jenkins to GitHub

### Start Jenkins once

Prerequisites: Docker and Compose are installed on Ubuntu, the repository is
checked out there, and the selected port/project name are unused. Run from the
`ubuntuStart` checkout on the **server**:

```bash
sudo docker compose -f jenkins/compose.yaml up -d --build
sudo docker compose -f jenkins/compose.yaml logs --tail=50
```

For a new installation, retrieve the initial password after startup:

```bash
sudo docker compose -f jenkins/compose.yaml exec jenkins \
  cat /var/jenkins_home/secrets/initialAdminPassword
```

Use that password privately in the setup screen. Do not commit it or paste it
into chat.

On your **laptop**, open this tunnel and leave the terminal running:

```bash
ssh -N -L 8080:127.0.0.1:8080 YOUR_USER@YOUR_SERVER
```

Open `http://localhost:8080`, complete setup, and create an administrator account.
Git and Pipeline are already included in this repository's Jenkins image. Keep
anonymous access disabled. Initially set the built-in node to one executor so
different jobs do not build simultaneously on the small server.

This demo Jenkins has access to the host Docker socket, which effectively grants
control of the host. Only run trusted repositories and branches. Do not enable
untrusted pull-request builds on this setup; isolated build infrastructure is a
later improvement.

### Create one Pipeline job per application

1. Push the application's code and deployment files to its GitHub repository.
2. In Jenkins, select **New Item**, enter `student-app`, and choose **Pipeline**.
3. Under **Pipeline**, select **Pipeline script from SCM**, then **Git**.
4. Enter the app repository URL, such as
   `https://github.com/Tudor747/student-app.git` (example repository).
5. A public repository can use no credentials. For a private repository, add a
   **Username with password** credential using your GitHub username and a token
   with read access to that repository as the password. Store it in Jenkins,
   not in the repository URL or source files.
6. Set **Branch Specifier** to `*/main`, or the actual trusted deployment branch.
7. Set **Script Path** to `Jenkinsfile`.
8. Save and click **Build Now** once. Inspect **Console Output**.

The Java repository must already have Java-compatible build and deployment
files. Jenkins does not infer how to deploy from Java source alone.

The current pipeline contains this trigger, which the Java pipeline can reuse:

```groovy
triggers {
    pollSCM('H/2 * * * *')
}
```

After an initial run registers the trigger, Jenkins checks GitHub approximately
every two minutes and builds when it detects changes. This requires outbound
access to GitHub; no public Jenkins endpoint or GitHub webhook is needed.
Builds also need outbound access to their dependency and image repositories.

## What happens after a push?

```text
Developer commits and pushes to the configured GitHub branch
    -> Jenkins detects a change and checks out the application
    -> Tests run inside a Docker build stage
    -> Docker builds an application image tagged with the commit SHA
    -> The deployment script updates that app's Compose service
    -> Compose waits for the app's health check
    -> Success: record the current release
    -> Failure: attempt to restore the previous image and fail the build
```

CI is the automated testing and building. CD here is deployment after those
checks succeed. The first deployment has no previous image to restore. Brief
downtime is possible; this setup does not provide zero-downtime deployment.

Source code is uploaded to **GitHub**. In this arrangement, Jenkins builds images
using the Ubuntu host's Docker engine, and that same engine runs them. A manual
JAR upload or Docker Hub account is not required. Jenkins checks out its own
workspace; an original manual clone is not automatically updated after pushes.

After the first successful deployment, configure the app's Apache site, DNS,
and TLS certificate. Then verify the public URL. For later changes, push to the
configured branch and inspect the new build in Jenkins.

## Database, secrets, monitoring, and recovery

- Add a database service to the application's Compose project if needed. The
  app connects using its service name, such as `db`, on the private network.
- Store database data in a named persistent volume. Do not publish its port to
  the Internet. Replacing an app container must not delete its database volume.
- Configure database health checks and readiness dependencies; also make the
  application handle connection failures appropriately.
- Supply secrets through protected deployment configuration or credentials,
  outside Git. Give each application only the credentials it needs.
- Keep consistent database backups and test restoration. The existing backup
  script does not automatically back up arbitrary Docker volumes or databases.
- Application image rollback does not undo database migrations. Plan schema
  changes so the previous application release remains compatible when possible.
- Monitor each local and public health endpoint, host disk and memory, and backup
  freshness. Add external uptime monitoring to detect a total server outage.
- Measure resource usage before adding more applications; Java builds and
  Jenkins compete with running applications for server memory and CPU.

## Next server checks: Apache command not found

`apache2: command not found` can mean Apache is absent or its executable is outside
the user's command search path. `bash apache2 -v` does not solve that: it asks Bash
to read a script named `apache2`.

Run these read-only checks on the server and review the output before installing
anything:

```bash
# Identify the Linux distribution
cat /etc/os-release

# Check the usual Ubuntu/Debian executable location
/usr/sbin/apache2 -v

# Ubuntu/Debian package inventory
dpkg -l | grep -E '^ii[[:space:]]+(apache2|nginx|httpd)'

# Look for existing services using the public web ports
sudo ss -lntp '( sport = :80 or sport = :443 )'
```

The package command applies to Ubuntu/Debian. Empty output or a missing command
is useful information; it does not justify overwriting an existing web setup.

Once Apache is available, inspect it with:

```bash
apache2 -v
sudo systemctl status apache2
sudo apache2ctl -S
sudo apache2ctl -M
sudo apache2ctl configtest
```

If the executable exists only outside the user's search path, use its full path.
Review existing virtual hosts and certificate management before adding a site.
Validate configuration before reloading Apache. Follow `README.md` and
`ops/README.md` for the repository's existing setup and operational procedures.

## First implementation milestone

1. Confirm the server distribution, installed software, available resources,
   current listeners, and existing sites.
2. Prepare the reusable per-project deployment script and a Java example.
3. Run Java alongside Express using separate Compose identities and host ports.
4. Configure its Jenkins job and verify a push triggers tests and deployment.
5. Configure the Java hostname and HTTPS in Apache.
6. Verify Java health, an intentional failed-release rollback, and that Express
   remains available throughout Java deployment testing.
7. Extend monitoring and backups, then test restoration and reboot behavior.
8. Add Python using the same approach once the second application works.

## Official references

- [Docker Compose project names](https://docs.docker.com/compose/how-tos/project-name/)
- [Compose dependency readiness](https://docs.docker.com/compose/how-tos/startup-order/)
- [Jenkins Pipeline setup](https://www.jenkins.io/doc/book/pipeline/getting-started/)
- [Jenkinsfile documentation](https://www.jenkins.io/doc/book/pipeline/jenkinsfile/)
- [Jenkins polling triggers](https://www.jenkins.io/doc/book/pipeline/syntax/#triggers)
- [Apache reverse proxy guide](https://httpd.apache.org/docs/2.4/howto/reverse_proxy.html)
- [Apache name-based virtual hosts](https://httpd.apache.org/docs/2.4/vhosts/name-based.html)
- [Apache executable options](https://httpd.apache.org/docs/2.4/programs/httpd.html)
- [Spring Boot Docker packaging](https://docs.spring.io/spring-boot/reference/packaging/container-images/dockerfiles.html)
- [Spring Boot web applications](https://docs.spring.io/spring-boot/reference/web/servlet.html)
- [Let's Encrypt validation methods](https://letsencrypt.org/docs/challenge-types/)
