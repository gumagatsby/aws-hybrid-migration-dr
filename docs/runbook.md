# Runbook

## Run the company server locally

```bash
docker compose -f onprem/docker-compose.yml up -d --build --wait
docker compose -f onprem/docker-compose.yml exec -T app python seed.py
open http://localhost:8080
```

## Migrate to AWS

1. Deploy London: `terraform -chdir=terraform apply -var allowed_cidr=<your IP>/32`.
2. Run `./scripts/migrate.sh`. It stops writes on the company server, moves the database and files, and validates both. Results go to `docs/migration-results.md`.
3. If validation reports a mismatch, do not cut over. The company server still holds the data: start it again with `docker compose -f onprem/docker-compose.yml start app` and investigate.

## London is down: fail over to Ireland

1. Check how recent Ireland's copy is:
   ```bash
   aws rds describe-db-instance-automated-backups --region eu-west-1 \
     --query 'DBInstanceAutomatedBackups[].RestoreWindow.LatestTime'
   ```
   Anything written after that time is lost.
2. Turn on the pilot light: `terraform -chdir=terraform apply -var dr_active=true`.
3. The app comes up at the `dr_url` output once the database has restored and the server has booted.
4. Tell users the new address. With a domain, a Route 53 failover record would do this automatically.

## Rehearse a failover

Run `./scripts/dr-drill.sh`. It writes to London every five seconds (10 minutes by default, `WRITE_SECONDS` to change), stops London's app server, recovers in Ireland, and records the measured recovery time and data loss in `docs/dr-drill-results.md`.

Before a drill, check that Ireland's latest restorable time has passed your last significant change (step 1 above). Right after the backup replication is first switched on, it can lag behind.

## Tear down

```bash
terraform -chdir=terraform destroy -var dr_active=true
```

The buckets are set to empty on destroy and the database skips its final snapshot, because this is a demo environment. Remove both settings for anything real.
