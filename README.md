# Study Now — DevOps Engineer Assessment

Production-oriented deployment and operations setup for the MongoDB MERN Stack Example, prepared for the Study Now / Global Student Pathway DevOps Engineer assessment.

The focus of this implementation is reliable deployment, health verification, rollback, authenticated MongoDB access, encrypted off-host backups, restore verification, monitoring, and operational documentation.

> **Original application:** This assessment uses the MongoDB Developer MERN Stack Example as the application starting point:
> https://github.com/mongodb-developer/mern-stack-example
>
> The application code has been kept intentionally minimal. Infrastructure, deployment, backup, monitoring, and operational changes are the primary focus of this assessment.

---

## 1. Assessment Goals

The implementation addresses the core requirements of the assessment:

- Containerized MERN application
- MongoDB authentication with a least-privilege application user
- Secrets kept outside Git
- Nginx gateway
- Two application containers for blue/green deployment
- Health-checked deployment
- Automatic rollback on deployment verification failure
- GitHub Actions CI/CD using a dedicated self-hosted runner
- Hourly encrypted MongoDB backups
- Cloudflare R2 off-host backup storage
- Reusable MongoDB restore script
- Measured restore drill with RTO/RPO evidence
- Five-minute application health monitoring
- Failure notification path testing
- Operational runbook and disaster-recovery documentation

The assessment prioritizes reliable and explainable operations over adding unnecessary infrastructure or tooling.

---

## 2. Architecture

```text
                         GitHub
                           |
                           | Push to assessment
                           v
                  GitHub Actions CI/CD
                           |
                           v
                 Self-hosted Linux VM
                 github-runner user
                           |
                           v
                  Docker Compose Stack
                           |
             +-------------+-------------+
             |                           |
             v                           v
       Nginx Gateway              MongoDB 8
             |                           |
       +-----+-----+                     |
       |           |                     |
       v           v                     |
   API Blue     API Green ---------------+
       |           |
       +-----+-----+
             |
             v
        employees DB

MongoDB backup
      |
      v
GPG AES-256 encryption
      |
      v
Cloudflare R2
```

### Assessment VM

The assessment was implemented on an Ubuntu Linux VM with Docker and Docker Compose.

The assessment environment uses host port `8080` for the Nginx gateway because the VM already has another service using host port `80`.

In the production design, Nginx can be exposed through the standard HTTP/HTTPS entry point behind Cloudflare.

---

## 3. Application

The application is the MongoDB Developer MERN Stack Example.

It provides a small employee-record CRUD application and was selected so the assessment could focus on production infrastructure rather than application development.

The original application source and license are retained and credited.

Application changes were intentionally kept minimal:

- Configurable MongoDB connection through `MONGO_URI`
- `/health` endpoint for application and database health
- Production containerization

---

## 4. Containerization

The application is split into:

- React/Vite frontend
- Node/Express API
- MongoDB
- Nginx gateway

### API container

The API uses a Node 20 production image.

The container:

- installs production dependencies
- runs as the non-root `node` user
- exposes port `5050` internally
- uses `MONGO_URI` from the environment

### Frontend container

The frontend uses a multi-stage Docker build:

1. Node builds the React/Vite application.
2. Nginx serves the generated static files.

### MongoDB

MongoDB is not exposed on a host port.

It is reachable only through the internal Docker network.

---

## 5. MongoDB Security

MongoDB authentication is enabled.

A root/admin account is used only for administrative operations.

The application uses a separate user:

```text
app_user
```

The application user has only:

```text
readWrite on employees
```

The application does not use the MongoDB root account.

MongoDB health checks authenticate against the administrative database.

Secrets are supplied through the local `.env` file and are not committed to Git.

The repository contains only:

```text
.env.example
```

with placeholder values.

---

## 6. Nginx Gateway

Nginx provides:

- frontend serving
- SPA fallback
- API reverse proxy
- `/health` proxying
- blue/green backend switching

The active backend is controlled by:

```text
nginx/active-backend.conf
```

Example:

```text
server api-green:5050;
```

The active backend can therefore be switched without changing application code.

---

## 7. Blue/Green Deployment and Rollback

The deployment script is:

```text
scripts/deploy.sh
```

The deployment process:

1. Determines the currently active backend.
2. Selects the inactive backend as the deployment target.
3. Builds the target API image.
4. Starts the target API container.
5. Waits for its Docker health check.
6. Verifies the API health endpoint directly.
7. Changes the Nginx active backend.
8. Validates the Nginx configuration.
9. Reloads Nginx without stopping the gateway.
10. Verifies the public application health endpoint.
11. Leaves the previous backend available as the rollback target.

### Rollback

The deployment script uses an error trap to restore the previous Nginx backend when deployment verification fails.

A deliberate failure was introduced during testing.

The rollback drill demonstrated that the deployment:

1. Started the new backend.
2. Confirmed the new backend was healthy.
3. Switched traffic.
4. Triggered an intentional verification failure.
5. Automatically restored the previous backend.
6. Reloaded Nginx.
7. Confirmed the application remained healthy.

The temporary failure hook was removed after the drill.

---

## 8. CI/CD

GitHub Actions workflow:

```text
.github/workflows/ci-cd.yml
```

The workflow runs on the dedicated self-hosted runner.

The runner is a dedicated Linux VM user:

```text
github-runner
```

The runner has Docker access but does not have general sudo access.

### Pipeline flow

```text
Checkout
   |
   v
Environment verification
   |
   v
Docker Compose validation
   |
   v
Build application images
   |
   v
Synchronize deployment checkout to exact commit
   |
   v
Verify MongoDB health
   |
   v
Blue/green deployment
   |
   v
Application health verification
   |
   v
API endpoint verification
   |
   v
Container status
```

The deployment checkout is synchronized to the exact GitHub Actions commit SHA before deployment.

The real production `.env` remains on the assessment VM and is not stored in GitHub.

The current application sample does not provide a meaningful server-side test suite; its server `npm test` script is the default placeholder that exits with an error. The client does provide an ESLint script. This limitation is documented rather than replacing the application's test command with a fabricated test.

---

## 9. Backups

MongoDB backup script:

```text
scripts/backup-mongodb.sh
```

The backup process:

1. Reads the MongoDB administrative credential from the local environment file.
2. Runs `mongodump` from the MongoDB 8 container.
3. Creates a compressed archive.
4. Encrypts the archive using GPG AES-256.
5. Uploads the encrypted backup to Cloudflare R2.
6. Verifies the R2 object using `head-object`.
7. Removes temporary plaintext backup data.
8. Removes local encrypted backups older than seven days.

The backup schedule is:

```cron
0 * * * * root /opt/study-now/mern-stack-example/scripts/backup-mongodb.sh >> /var/log/study-now-mongodb-backup.log 2>&1
```

This runs once per hour.

### Backup destination

Cloudflare R2 bucket:

```text
study-now-mongodb-backups
```

The bucket is private.

The R2 API credentials are stored outside the Git repository and are scoped to the backup bucket.

---

## 10. Restore Drill

A reusable restore script is provided:

```text
scripts/restore-mongodb.sh
```

The script:

1. Downloads an encrypted backup from Cloudflare R2.
2. Decrypts the backup.
3. Copies the archive into the MongoDB container.
4. Performs an authenticated `mongorestore --dryRun` verification.
5. Requires explicit `RESTORE` confirmation before destructive recovery.
6. Drops the `employees` database when `--drop` is supplied.
7. Restores the MongoDB archive.
8. Verifies application health.
9. Removes temporary restore files.

A final restore drill was performed against the assessment environment.

### Restore drill evidence

Backup used:

```text
mongodb/20261002T063001Z.archive.gz.gpg
```

Recovery start:

```text
2026-10-02T06:55:39Z
```

MongoDB restore completed:

```text
2026-10-02T06:56:01.127Z
```

Application health verification completed:

```text
2026-10-02T06:56:01Z
```

Measured recovery time from the recorded recovery start to application health verification:

```text
~22 seconds
```

This is the measured RTO for this assessment restore drill on the assessment VM and dataset. It is not presented as a guaranteed production RTO.

### Restore verification

Before the restore, an `RPO_DRILL` record was deliberately created after the selected backup.

After the database was dropped and restored:

```text
RPO_DRILL documents: 0
```

This demonstrated that data created after the selected recovery point was not present after restoration.

The record contained in the backup was successfully recovered:

```text
Backup Restore Test
```

The application also returned:

```json
{"status":"healthy","database":"connected"}
```

---

## 11. RPO

The MongoDB backup job currently runs every hour.

This provides a designed backup interval aligned with the assessment's one-hour RPO target, assuming scheduled backup jobs complete successfully.

The actual data-loss window is dependent on:

- the time of the most recent successful backup
- backup job success
- availability of the backup destination
- restore availability

Therefore, the hourly schedule is documented as the **RPO design target**, not as a claim that every recovery will always have exactly one hour or less of data loss.

### Observed restore drill

The selected backup was created at approximately:

```text
2026-10-02T06:30:01Z
```

The RPO test record was created at:

```text
2026-10-02T06:47:31Z
```

The test record was therefore created approximately 17 minutes 30 seconds after the selected backup.

The record was absent after restoration, confirming the expected data-loss boundary for that recovery point.

This is an observed drill result, not a guarantee that every recovery will have the same data-loss window.

---

## 12. Health Monitoring

Application health monitoring is implemented using:

```text
scripts/health-check.sh
```

Schedule:

```text
/etc/cron.d/study-now-health-check
```

Every five minutes:

```cron
*/5 * * * * root /opt/study-now/mern-stack-example/scripts/health-check.sh >> /var/log/study-now-health-check.log 2>&1
```

The health check verifies:

```text
http://localhost:8080/health
```

If the check fails, the configured webhook is called.

The failure path was tested using a temporary local webhook receiver.

No production Slack, Discord, or email integration is claimed as part of the assessment environment; the webhook endpoint is externally configurable.

---

## 13. Security Controls

Implemented controls include:

- MongoDB authentication
- Least-privilege application database user
- MongoDB not exposed on a host port
- Application containers run without root privileges where applicable
- Secrets kept outside Git
- Private R2 bucket
- Bucket-scoped R2 credentials
- Encrypted MongoDB backups
- Off-host backup storage
- Dedicated self-hosted GitHub runner
- Runner does not have general sudo access
- Health checks
- Deployment rollback
- Explicit confirmation for destructive database restore
- Temporary restore files removed after recovery

The repository should be audited before submission to ensure no credentials or temporary files are tracked.

---

## 14. Operational Runbook

### Check application health

```bash
curl -fsS http://localhost:8080/health
```

Expected result:

```json
{"status":"healthy","database":"connected"}
```

### Check active backend

```bash
cat nginx/active-backend.conf
```

### Check containers

```bash
docker compose ps
```

### Deploy

```bash
./scripts/deploy.sh
```

### Verify API

```bash
curl -fsS http://localhost:8080/record
```

### Check backup logs

```bash
tail -n 100 /var/log/study-now-mongodb-backup.log
```

### Check health monitoring logs

```bash
tail -n 100 /var/log/study-now-health-check.log
```

### Restore

Use a known R2 backup object:

```bash
./scripts/restore-mongodb.sh mongodb/<backup-file>.archive.gz.gpg --drop
```

The restore script requires explicit confirmation before dropping the application database.

### 2am checklist

1. Check application health.
2. Check Docker container status.
3. Check active backend.
4. Check recent backup log.
5. Confirm the latest backup exists in R2.
6. Check health monitoring logs.
7. Check recent CI/CD runs.
8. If deployment is unhealthy, use the previous blue/green backend as the rollback target.
9. If data recovery is required, follow the tested restore procedure rather than improvising commands.

---

## 15. Disaster Recovery — GSP Scenario

The assessment scenario assumes:

- Linode is the primary hosting provider.
- DigitalOcean is available as the secondary provider.
- Cloudflare provides DNS, caching and WAF capabilities.
- The application contains sensitive student information and uploaded documents.
- The recovery objective is to restore service within four hours.
- The recovery point objective is one hour.

### First two weeks: priority sequence

#### 1. Establish access and ownership

Inventory:

- Linode accounts and servers
- DigitalOcean resources
- Cloudflare account and DNS zones
- DNS records
- TLS certificates
- MongoDB
- Uploaded student documents
- Application secrets
- CI/CD credentials
- Monitoring and alerting
- Backup locations

Remove former vendor access and rotate credentials where appropriate.

#### 2. Establish backup coverage

MongoDB backups should be encrypted and stored outside the primary provider.

Uploaded student documents should have equivalent protection:

- encrypted backups
- separate storage location
- access-controlled credentials
- documented restore procedure
- restore verification

#### 3. Test restoration

A backup that has never been restored should not be treated as proven.

Run regular restore tests and record:

- restore start time
- restore completion time
- application recovery time
- data recovered
- errors encountered

#### 4. Prepare secondary infrastructure

Maintain a documented DigitalOcean recovery configuration capable of running:

- application containers
- MongoDB recovery
- Nginx
- required secrets
- monitoring

The secondary environment does not need to duplicate every primary resource continuously if that is not cost-effective, but recovery dependencies should be known and tested.

---

## 16. 3-2-1 Backup Strategy

For the GSP production environment, the intended strategy is:

```text
                 Production
                     |
          +----------+----------+
          |                     |
          v                     v
     Primary copy          Backup copy
                               |
                         +-----+-----+
                         |           |
                         v           v
                     Off-site     Recovery
                     storage      copy
```

### MongoDB

- Frequent encrypted backups
- Separate backup storage
- Regular restore testing
- Retention policy appropriate to business requirements
- Restore procedure documented and tested

### Uploaded documents

- Primary object storage
- Versioned/protected backup
- Separate recovery copy
- Encryption at rest and in transit
- Documented restoration process

The final production design should verify that the selected storage configuration actually satisfies the required 3-2-1 model and one-hour RPO.

The current assessment application does not contain the full student-document upload subsystem, so uploaded-document backup is a proposed production design rather than a claim of implemented functionality in this assessment repository.

---

## 17. Linode Regional Failure — 09:00 UK

If the primary Linode region becomes unavailable, the first four hours should focus on service restoration rather than infrastructure perfection.

### Recovery sequence

```text
09:00
Regional failure detected
        |
        v
Confirm incident and stop unnecessary changes
        |
        v
Declare recovery procedure
        |
        v
Activate secondary infrastructure
        |
        v
Restore MongoDB
        |
        v
Restore uploaded documents
        |
        v
Start application
        |
        v
Verify application + database health
        |
        v
Move Cloudflare/DNS traffic
        |
        v
Verify external application access
        |
        v
Continue monitoring
```

### Detailed recovery sequence

**09:00–09:15**

- Confirm the outage is regional rather than an application-only issue.
- Confirm the primary region is unavailable.
- Freeze unnecessary production changes.
- Declare the recovery procedure.
- Establish incident ownership and communication.

**09:15–10:00**

- Activate the prepared DigitalOcean recovery environment.
- Provision or start the required application and Nginx services.
- Restore required secrets securely.
- Verify network and firewall access.

**10:00–11:00**

- Retrieve the latest valid MongoDB backup.
- Restore MongoDB.
- Verify database health and application connectivity.
- Restore the protected student-document copy.

**11:00–12:00**

- Start application containers.
- Verify application and database health.
- Validate important application paths.
- Prepare Cloudflare/DNS traffic movement.
- Move DNS/origin traffic to the secondary environment.
- Verify external access.
- Continue monitoring.

The recovery process should use the previously tested runbook rather than relying on ad-hoc commands during the incident.

---

## 18. Cloudflare / DNS Improvements

To reduce future recovery time:

- Keep DNS records documented.
- Keep origin information documented securely.
- Use a low enough DNS TTL where operationally appropriate.
- Keep the secondary origin prepared and tested.
- Use Cloudflare as the stable public entry point.
- Avoid making application users depend directly on provider-specific origin addresses.
- Document the exact Cloudflare origin/DNS change required during a regional failure.
- Test the DNS/origin failover procedure regularly.
- Keep TLS configuration ready on the secondary environment.

The goal is to make the recovery procedure a controlled origin switch rather than a complete DNS redesign during an incident.

---

## 19. Cost and Reliability Trade-offs

The recovery design should balance:

- RTO
- RPO
- availability
- backup durability
- operational complexity
- monthly infrastructure cost

A fully active-active secondary environment provides different recovery characteristics from a warm or cold standby, but also introduces additional infrastructure and operational cost.

For the GSP production scenario, the exact monthly cost should be calculated from the selected Linode, DigitalOcean, Cloudflare/R2, storage, bandwidth, monitoring and backup-retention requirements.

The final production choice should be based on the business requirement for the four-hour RTO and one-hour RPO rather than on adding infrastructure for its own sake.

---

## 20. Repository Structure

```text
.
├── .github/
│   └── workflows/
│       └── ci-cd.yml
├── docker/
│   └── mongo/
│       └── init/
├── mern/
│   ├── client/
│   │   ├── Dockerfile
│   │   └── ...
│   └── server/
│       ├── Dockerfile
│       ├── db/
│       ├── routes/
│       └── ...
├── nginx/
│   ├── nginx.conf
│   └── active-backend.conf
├── scripts/
│   ├── backup-mongodb.sh
│   ├── deploy.sh
│   ├── health-check.sh
│   └── restore-mongodb.sh
├── .env.example
├── .gitignore
├── docker-compose.yml
├── LICENSE
└── README.md
```

---

## 21. Implementation Status

### Implemented and tested

- Containerized MERN application
- MongoDB authentication
- Least-privilege application user
- Secrets outside Git
- Nginx gateway
- Blue/green deployment
- Automatic rollback
- GitHub Actions self-hosted runner
- Production checkout synchronization to exact commit
- Encrypted MongoDB backups
- Cloudflare R2 backup storage
- Backup upload verification
- Scheduled hourly backups
- Reusable MongoDB restore script
- MongoDB restore drill
- Measured assessment restore RTO
- Observed RPO/data-loss window
- Application health monitoring
- Failure notification path testing
- Operational deployment and recovery commands

### Proposed for the GSP production scenario

- Full secondary DigitalOcean recovery environment
- Complete uploaded-document backup strategy
- Production Cloudflare/DNS failover procedure
- Production-scale 3-2-1 implementation and retention policy
- Regular scheduled recovery exercises
- Production cost model based on actual workload and storage requirements

These items are kept separate because the assessment environment does not represent the complete GSP production infrastructure.

---

## 22. Original Project

Application source:

https://github.com/mongodb-developer/mern-stack-example

The original project licensing and attribution are retained in `LICENSE`.

The application was used as the starting point for this assessment; infrastructure and operational work were added around it rather than presenting the sample application as original application development.
