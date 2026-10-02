# Study Now — DevOps Engineer Assessment

Production-oriented deployment and operations setup for the MongoDB MERN Stack Example, prepared for the Study Now / Global Student Pathway DevOps Engineer assessment.

The focus of this implementation is reliable deployment, health verification, rollback, authenticated MongoDB access, encrypted off-host backups, restore verification, and operational documentation.

> **Original application:** This assessment uses the MongoDB Developer MERN Stack Example as the application starting point. The original project is available at:
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
- GitHub Actions CI/CD using a self-hosted runner
- Hourly encrypted MongoDB backups
- Cloudflare R2 off-host backup storage
- Restore drill with measured MongoDB restore duration
- Five-minute application health monitoring
- Operational runbook and disaster-recovery considerations

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
              +------------+------------+
              |                         |
              v                         v
        Nginx Gateway              MongoDB 8
        Port 8080                  Internal only
              |
              v
       Active API Backend
          /          \
         /            \
   API Blue         API Green
   :5050            :5050

          Blue/Green deployment
                 |
                 v
        Health verification
                 |
        +--------+--------+
        |                 |
      Success           Failure
        |                 |
        v                 v
   Keep new color      Automatic rollback
```

### Current state

The active backend is controlled by:

```text
nginx/active-backend.conf
```

Example:

```nginx
server api-green:5050;
```

Only the active API receives application traffic through Nginx. The inactive API remains available as the deployment target.

---

## 3. Application

The application is the MongoDB Developer MERN Stack Example:

- React/Vite frontend
- Node.js/Express REST API
- MongoDB
- Employee records CRUD functionality

The application has been modified minimally for the assessment.

### Application health endpoint

```text
GET /health
```

Example successful response:

```json
{
  "status": "healthy",
  "database": "connected"
}
```

The health endpoint verifies MongoDB connectivity rather than only confirming that the Node.js process is running.

---

## 4. Containerization

The application is containerized using Docker Compose.

Services:

```text
mongodb
api-blue
api-green
nginx
```

### API container

The API uses a Node.js 20 production image.

The container:

- installs production dependencies with `npm ci --omit=dev`
- runs as the non-root `node` user
- exposes port 5050 internally
- provides the `/health` endpoint

### Frontend / Nginx container

The frontend is built using Node.js and served by Nginx.

Nginx also acts as the gateway to the active API backend.

The assessment VM already has another service using host port 80, so the assessment gateway is exposed locally on:

```text
http://localhost:8080
```

The production design can expose Nginx on the standard HTTP/HTTPS ports behind the appropriate edge/load-balancing layer.

---

## 5. MongoDB Security

MongoDB is not exposed directly to the host.

The application uses a dedicated MongoDB user:

```text
app_user
```

The application user has:

```text
readWrite
```

on the:

```text
employees
```

database only.

The MongoDB root account is used only for administrative operations such as backup.

### Secrets

Secrets are not committed to Git.

Local environment configuration is stored in:

```text
.env
```

and is excluded by `.gitignore`.

A safe template is provided as:

```text
.env.example
```

No production passwords or R2 credentials are stored in the repository.

---

## 6. Blue/Green Deployment

Deployment is implemented in:

```text
scripts/deploy.sh
```

The deployment process is:

1. Determine the currently active backend.
2. Select the inactive color as the deployment target.
3. Build the inactive API image.
4. Start the inactive API container.
5. Wait for the Docker health check.
6. Verify the API `/health` endpoint directly.
7. Update the Nginx active backend.
8. Validate the Nginx configuration.
9. Reload Nginx.
10. Verify the public application health endpoint.
11. Keep the previous backend available as the rollback target.

The goal is to avoid taking the application offline during a normal deployment.

---

## 7. Rollback

The deployment script uses an error trap to restore the previous Nginx backend when deployment verification fails.

Rollback restores the previous:

```text
nginx/active-backend.conf
```

and reloads Nginx.

### Rollback drill

A deliberate deployment failure was introduced during testing.

The deployment:

1. Started the new backend.
2. Confirmed the new backend was healthy.
3. Switched traffic.
4. Triggered the intentional verification failure.
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

Pipeline stages:

```text
Checkout
   |
Environment verification
   |
Docker Compose validation
   |
Build application images
   |
MongoDB health verification
   |
Blue/Green deployment
   |
Application health verification
   |
API verification
   |
Active backend reporting
```

The runner is a dedicated Linux user with Docker access and does not have general sudo privileges.

### Manual deployment

The deployment can also be executed directly on the assessment VM:

```bash
./scripts/deploy.sh
```

---

## 9. MongoDB Backups

Backup implementation:

```text
scripts/backup-mongodb.sh
```

Backups run hourly using:

```text
/etc/cron.d/study-now-mongodb-backup
```

Schedule:

```cron
0 * * * * root /opt/study-now/mern-stack-example/scripts/backup-mongodb.sh
```

### Backup process

The script:

1. Reads the MongoDB administrative credential from the local environment file.
2. Runs `mongodump` from the MongoDB container.
3. Creates a compressed archive.
4. Encrypts the archive using GPG AES-256.
5. Uploads the encrypted object to Cloudflare R2.
6. Verifies the uploaded object.
7. Removes temporary plaintext backup data.
8. Removes encrypted local backups older than seven days.

The backup stored in R2 is private.

### Backup destination

```text
Cloudflare R2
Bucket: study-now-mongodb-backups
```

The R2 credentials are stored outside the Git repository and are scoped to the backup bucket.

---

## 10. Restore Drill

A restore drill was performed against the assessment environment.

The drill included:

1. Creating a test database record.
2. Taking an encrypted MongoDB backup.
3. Downloading the backup from R2.
4. Decrypting the backup.
5. Verifying the archive contents.
6. Dropping the application database.
7. Confirming the application returned no records.
8. Restoring the MongoDB archive.
9. Confirming the record was recovered.
10. Confirming the application health endpoint returned healthy.

### Measured result

Measured MongoDB restore duration:

```text
1 minute 9.44 seconds
```

This measurement represents the database restore portion of the recovery process.

It is **not claimed as the complete end-to-end application RTO**.

A final end-to-end recovery measurement should include the complete recovery sequence, including application availability verification.

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

If the check fails, the script can send a JSON notification to a configured webhook.

The failure path was tested using a temporary local webhook receiver.

No production Slack/Discord integration is claimed as part of this assessment environment.

---

## 13. Security Controls

Implemented controls include:

- MongoDB authentication
- Dedicated least-privilege application database user
- MongoDB not exposed on a host port
- Secrets excluded from Git
- Encrypted MongoDB backups
- Private R2 backup bucket
- Bucket-scoped R2 credentials
- API containers running as non-root
- Dedicated self-hosted GitHub runner user
- No general sudo access for the GitHub runner
- Health checks for deployment verification
- Automatic deployment rollback
- Backup verification after upload

---

## 14. Operational Runbook

### 2 AM deployment check

```bash
cd /opt/study-now/mern-stack-example

docker compose ps

curl -fsS http://localhost:8080/health

cat nginx/active-backend.conf
```

Expected health response:

```json
{
  "status": "healthy",
  "database": "connected"
}
```

### If deployment fails

Check:

```bash
docker compose ps
docker compose logs api-blue
docker compose logs api-green
docker compose logs nginx
```

Then verify:

```bash
cat nginx/active-backend.conf
curl -fsS http://localhost:8080/health
```

The deployment script is designed to restore the previous backend when deployment verification fails.

### Backup verification

Check the backup log:

```bash
tail -n 100 /var/log/study-now-mongodb-backup.log
```

List R2 backup objects using the configured administrative environment/profile.

### Health monitoring

Check:

```bash
tail -n 100 /var/log/study-now-health-check.log
```

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
- uploaded student documents
- application secrets
- CI/CD credentials
- monitoring and alerting
- backup locations

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
Production data
      |
      +---- Primary copy
      |
      +---- Secondary backup copy
      |
      +---- Off-provider / geographically separate copy
```

MongoDB:

- frequent encrypted backups
- separate backup storage
- regular restore testing
- retention policy appropriate to business requirements

Uploaded documents:

- primary object storage
- versioned/protected backup
- separate recovery copy
- encryption at rest and in transit
- documented restoration process

The final production design should verify that the selected storage configuration actually satisfies the required 3-2-1 model and one-hour RPO.

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

The recovery process should use the previously tested runbook rather than relying on ad-hoc commands during the incident.

---

## 18. Cloudflare / DNS Improvements

To reduce future recovery time:

- keep DNS configuration documented
- minimize unnecessary DNS TTL during planned recovery exercises
- maintain clear origin records
- document Cloudflare configuration
- document WAF rules
- document cache behavior
- document TLS configuration
- keep recovery origin information ready
- test DNS/origin changes during planned exercises

Cloudflare should remain an edge control rather than being treated as the sole recovery mechanism.

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
│   └── server/
├── nginx/
│   ├── nginx.conf
│   └── active-backend.conf
├── scripts/
│   ├── backup-mongodb.sh
│   ├── deploy.sh
│   └── health-check.sh
├── .env.example
├── .gitignore
├── docker-compose.yml
├── LICENSE
└── README.md
```

---

## 21. What Is Implemented vs. Proposed

### Implemented and tested

- Docker Compose application stack
- MongoDB authentication
- Least-privilege application user
- Nginx gateway
- Blue/green deployment
- Deployment health checks
- Automatic rollback
- GitHub Actions self-hosted runner
- Encrypted MongoDB backups
- Cloudflare R2 backup storage
- Backup upload verification
- MongoDB restore drill
- Application health monitoring
- Failure notification path testing
- Operational deployment and recovery commands

### Proposed for the GSP production scenario

- Full secondary DigitalOcean recovery environment
- Complete uploaded-document backup strategy
- Production Cloudflare/DNS failover procedure
- Full end-to-end disaster recovery measurement
- Regular scheduled recovery exercises
- Final production 3-2-1 implementation and retention policy

These items are kept separate because the assessment environment does not represent the complete GSP production infrastructure.

---

## 22. Original Project

Application source:

https://github.com/mongodb-developer/mern-stack-example

Original project licensing and attribution are retained in `LICENSE`.

The assessment work focuses primarily on infrastructure, deployment, security, backup, recovery, monitoring, and operational reliability around the sample application.
