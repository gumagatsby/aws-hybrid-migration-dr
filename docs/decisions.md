# Design decisions and trade-offs

## 1. Re-platform the database, rehost the app

The app moves to an EC2 server much as it ran in the office. The database moves to Amazon RDS instead of a self-managed PostgreSQL server, so backups, patching and cross-region copies become AWS's job. Moving to RDS is the biggest operational gain and the smallest change to the app: it only needed to read its password from Secrets Manager instead of a config file.

## 2. Dump and restore, not AWS DMS or Application Migration Service

The database is a few megabytes and the business can stop writing for a few minutes, so a native `pg_dump` and restore is the simplest method that can be checked end to end. **AWS Database Migration Service** would keep the old and new databases in sync for a near-zero-downtime cutover; it is the right tool for a large database or one that cannot stop. **AWS Application Migration Service (MGN)** copies whole servers block by block; it suits lifting many servers unchanged. Both bill for the replication servers they run, and MGN needs a real Linux machine as the source.

## 3. Prove the migration, don't assume it

Before cutover the script compares the jobs table on both sides using a row count and an MD5 hash of every row, with the time zone fixed so both servers render rows identically. Every uploaded file is checked by SHA-256: the hash is computed locally and compared with the checksum S3 stored on upload. A migration is only reported as done when every check matches.

## 4. Data moves over HTTPS, not a VPN

The dump and files go to S3 over HTTPS with IAM credentials, and the restore runs inside the VPC. A client with ongoing traffic between office and AWS would use **Site-to-Site VPN** or **Direct Connect**. Site-to-Site VPN bills per connection-hour, which a one-off copy of this size does not justify.

## 5. No SSH, no stored database password

The app server has no key pair and no port 22. The restore and the checks run through **Systems Manager Run Command**. RDS generates the database password, stores it in **Secrets Manager** and rotates it. The app reads it at connection time, so rotation needs no redeploy.

## 6. Pilot light disaster recovery in a second region

| Strategy | What runs in the DR region | Recovery time | Cost while idle |
|---|---|---|---|
| Backup and restore | Backups only | Hours | Lowest |
| **Pilot light (this project)** | Replicated data; servers built on demand by code | Minutes | Data storage and transfer only |
| Warm standby | A scaled-down copy, always running | Minutes or less | A second, smaller site |
| Active-active | Full copy serving traffic | Near zero | Two full sites |

Pilot light fits a small business: no servers run in Ireland until they are needed. Two things are copied continuously:

- The database: RDS cross-region automated backup replication sends snapshots and transaction logs to Ireland, so the database can be restored to within minutes of the failure.
- The files: S3 replication copies every uploaded file, and every app release, to the Ireland bucket.

The same Terraform module that builds London builds Ireland. Recovery is one variable: `dr_active = true`.

## 7. Measured, not claimed, recovery numbers

The drill writes to London every five seconds, stops London's app server, rebuilds in Ireland, and compares two moments: the last write London acknowledged, and the last write present after recovery. The difference is the real data loss window (RPO). The time from stopping London to Ireland serving is the real recovery time (RTO). Both are written to `docs/dr-drill-results.md` by the script.

The first drill recovered all 501 migrated jobs and had the app serving from Ireland 18 minutes 27 seconds after London went down. None of the drill's own writes survived, though: Ireland's latest restorable time ran about 13.5 minutes behind London, so more than 10 minutes of writes were lost. That is the honest data-loss window of this design, and the reason section 8 lists a read replica as the first upgrade.

## 8. What a client deployment would add

- A cross-region read replica if the business cannot lose 10 to 15 minutes of data. It stays seconds behind and is promoted rather than restored, which also shortens recovery. The cost is a second database running all the time.
- Multi-AZ for the database, so losing one data centre does not need the DR plan at all.
- Route 53 failover records with health checks, so users follow the app to Ireland automatically. Left out here because a hosted zone has a monthly charge and needs a domain.
- A load balancer and HTTPS with an ACM certificate in front of the app server.
- Private subnets with a NAT gateway, or VPC endpoints for every AWS API, so the app server has no public IP.
- Deletion protection and final snapshots on the database. Both are off here because the environment is destroyed after each run.

## 9. What it costs

Everything runs on free-tier-eligible sizes (`t4g.micro`, `db.t4g.micro`) and is destroyed after the migration and drill. Prices from the AWS Price List API on the day of the run: the app server costs $0.0094 an hour in London, the database $0.018 an hour, and each public IPv4 address $0.005 an hour. Ireland is slightly cheaper. While idle, the pilot light costs only the replicated backup storage and the replicated files.
