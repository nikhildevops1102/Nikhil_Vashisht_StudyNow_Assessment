# Part 2 — Disaster Recovery and Production Operations

## 1. First Two Weeks — Audit and Lockdown Sequence

The first two weeks should establish ownership, reduce the largest operational risks, and prove that recovery works before adding more infrastructure.

### Days 1–2: Access and ownership
- Inventory Linode, DigitalOcean, Cloudflare, GitHub, DNS, domain, TLS, MongoDB, object storage, CI/CD, monitoring and backup access.
- Confirm named owners and emergency access paths.
- Remove former vendor access where no longer required.
- Review privileged accounts and enable MFA.
- Confirm SSH key ownership and remove stale keys.
- Review GitHub Actions secrets and runner permissions.

### Days 3–4: Internet and application exposure
- Confirm only the required public entry points are exposed.
- Keep MongoDB private and reachable only from the application network.
- Review Cloudflare DNS, TLS mode, WAF rules, rate limits and caching.
- Confirm origin access is restricted where practical.
- Review application and Nginx logs for unexpected traffic.

### Days 5–7: Secrets and CI/CD
- Confirm production secrets are outside Git.
- Rotate credentials that may have been shared historically.
- Review GitHub Actions permissions and deployment credentials.
- Ensure deployment targets the exact commit being released.
- Test blue/green deployment and rollback.

### Week 2: Backup and recovery
- Verify MongoDB backups run hourly and are encrypted before off-site storage.
- Confirm backup objects are stored outside the primary hosting provider.
- Restore a real backup into a controlled environment.
- Record measured restore time and observed recovery-point boundary.
- Define retention and recovery procedures for uploaded student documents.
- Run a tabletop regional-failure exercise.

The priority is to establish a repeatable recovery process before adding Kubernetes, complex observability stacks, or active-active infrastructure.

---

## 2. 3-2-1 Backup Strategy — MongoDB and Student Documents

The target is **RPO ≤ 1 hour** and **RTO ≤ 4 hours**.

### MongoDB

The production design should maintain:

1. **Primary copy:** live MongoDB database in the primary hosting environment.
2. **Backup copy:** encrypted hourly MongoDB archives stored in Cloudflare R2.
3. **Third copy:** a second geographically/provider-separated recovery copy, for example replicated encrypted archives in DigitalOcean object storage or a second backup host.

The assessment implementation already proves the first two layers: hourly `mongodump`, GPG AES-256 encryption, private Cloudflare R2 storage, upload verification, and a tested restore procedure.

For production, backup retention should include short-term hourly backups plus longer daily/weekly retention.

### Uploaded student documents

Student documents should not depend on the application server filesystem as the only copy.

The production design should use:
- Primary encrypted object storage.
- Object versioning or equivalent protection against accidental deletion.
- A separate recovery copy in another account/provider/region.
- Encryption at rest and in transit.
- Documented restore procedures.
- Periodic recovery tests.

The assessment application does not contain the complete student-document upload subsystem, so this is a production design recommendation rather than an implemented claim.

### Rough monthly cost

Pricing is an estimate and depends on region, workload, storage volume and retention.

For a small production starting point:

| Component | Rough monthly assumption |
|---|---:|
| Primary Linode VM, ~4 GB | ~$30–35 |
| DigitalOcean recovery VM, ~4 GB, warm standby | ~$24 |
| Cloudflare R2, ~100 GB Standard | ~$1.35 after the 10 GB free storage allowance |
| Cloudflare DNS/basic edge features | $0 assumption |
| Additional backup/transfer allowance | ~$0–5 |
| **Estimated infrastructure total** | **~$55–65/month** |

DigitalOcean currently lists a Basic 4 GiB / 2 vCPU Droplet at $24/month. Cloudflare R2 Standard storage is $0.015/GB-month with 10 GB-month free, and R2 egress is free. Linode/Akamai pricing varies by region; its published regional pricing should be checked for the selected production region before procurement. citeturn2search0turn0search1turn3search0

This estimate deliberately avoids pricing a full active-active secondary environment. A continuously running duplicate production stack would cost more, but may be justified if the business later requires a materially lower RTO than four hours.

---

## 3. Linode Regional Failure — 09:00 UK

Assume the primary Linode region becomes unavailable at 09:00 UK.

The objective during the first four hours is restoration of a usable service, not rebuilding the entire platform perfectly.

### 09:00–09:15 — Confirm and declare
- Confirm the issue is regional rather than an application-only failure.
- Check Linode status and the primary infrastructure.
- Freeze unnecessary production changes.
- Declare the incident and establish an incident owner.
- Confirm access to the secondary DigitalOcean environment.
- Confirm the latest usable MongoDB backup.

### 09:15–10:00 — Activate secondary infrastructure
- Start/provision the prepared DigitalOcean recovery environment.
- Deploy the application and Nginx configuration.
- Restore required secrets through the approved secret-management process.
- Apply firewall/network controls.
- Confirm the secondary origin is reachable privately and publicly as required.

### 10:00–11:00 — Restore data
- Download the latest valid encrypted MongoDB backup.
- Decrypt it using the controlled recovery key/passphrase.
- Restore MongoDB.
- Verify MongoDB authentication and application connectivity.
- Restore the protected student-document recovery copy.
- Validate representative application records and documents.

### 11:00–12:00 — Restore public service
- Start application containers.
- Verify `/health`, API functionality and critical user flows.
- Confirm TLS and origin configuration.
- Update the Cloudflare origin/DNS configuration to point traffic to the secondary environment.
- Verify external access through the normal public hostname.
- Monitor errors, latency and application logs.
- Keep the incident open until service stability is confirmed.

### Recovery principle

Cloudflare should remain the stable public entry point. The incident should be an **origin switch**, not a DNS redesign. The recovery procedure should already contain the exact origin, TLS, WAF and DNS changes required.

---

## 4. Month-One Cloudflare and DNS Changes

During the first month:

- Keep the public hostname behind Cloudflare rather than exposing provider-specific origins directly.
- Review DNS records and remove stale records.
- Document the primary and secondary origins securely.
- Use an operationally appropriate DNS TTL for planned recovery exercises.
- Review TLS mode and certificate coverage.
- Review WAF rules and rate limiting.
- Confirm sensitive application paths are not unintentionally cached.
- Document cache behavior for HTML/API/document routes.
- Restrict origin access to reduce direct-origin bypass where practical.
- Test a controlled origin switch before relying on it for a real incident.
- Record the exact Cloudflare/DNS change required for regional recovery.

The goal is to make failover a controlled change of origin while keeping the user-facing hostname stable.

---

## 5. Evidence From the Assessment Implementation

The assessment environment provides measurable evidence for the recovery design:

- Hourly encrypted MongoDB backups are running.
- Backups are uploaded to a private Cloudflare R2 bucket.
- Backup uploads are verified.
- A reusable MongoDB restore script was created.
- A destructive restore drill was completed successfully.
- The measured assessment restore time was approximately **22 seconds** from recorded recovery start to application health verification.
- The selected backup was approximately 17 minutes 30 seconds older than the deliberately created recovery test record; the record was absent after restore, demonstrating the recovery-point boundary.
- Blue/green deployment and deliberate rollback were tested.
- Application and MongoDB health checks are running on a five-minute schedule.

The measured 22-second restore result is an assessment-environment measurement, not a guarantee of production RTO. The production four-hour RTO remains a business recovery objective that must be validated against the complete secondary-environment recovery sequence.
