#!/usr/bin/env bash
# Disaster recovery drill: keep writing to London, take London away, rebuild in Ireland,
# and measure how long recovery took (RTO) and how much data was lost (RPO).
set -euo pipefail
source "$(dirname "$0")/lib.sh"

PRIMARY_REGION=$(tf_out primary_region)
DR_REGION=$(tf_out dr_region)
URL=$(tf_out primary_url)
INSTANCE=$(tf_out primary_instance_id)
DR_BUCKET=$(tf_out dr_bucket)
WRITE_SECONDS=${WRITE_SECONDS:-600}

echo "Replicated backups in $DR_REGION:"
aws rds describe-db-instance-automated-backups --region "$DR_REGION" \
  --query 'DBInstanceAutomatedBackups[].[DBInstanceIdentifier,Status,RestoreWindow.LatestTime]' --output text

echo "1/4 Writing a heartbeat to London every 5 seconds for $WRITE_SECONDS seconds"
LAST_ID=""; LAST_AT=""
end=$(( $(date +%s) + WRITE_SECONDS ))
while (( $(date +%s) < end )); do
  if resp=$(curl -fsS --max-time 5 -X POST "$URL/heartbeat"); then
    LAST_ID=$(python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])' <<<"$resp")
    LAST_AT=$(python3 -c 'import json,sys; print(json.load(sys.stdin)["written_at"])' <<<"$resp")
  fi
  sleep 5
done
JOBS_BEFORE=$(curl -fsS "$URL/health" | python3 -c 'import json,sys; print(json.load(sys.stdin)["jobs"])')
echo "  last write London acknowledged: #$LAST_ID at $LAST_AT"

echo "2/4 Disaster: London's app server goes down"
T0=$(date +%s); T0_ISO=$(now)
aws ec2 stop-instances --region "$PRIMARY_REGION" --instance-ids "$INSTANCE" >/dev/null

echo "3/4 Recover: turn on the pilot light in $DR_REGION"
terraform -chdir="$ROOT/terraform" apply -auto-approve -input=false -var dr_active=true >/dev/null
DR_URL=$(tf_out dr_url)
wait_for_app "$DR_URL"
T1=$(date +%s); T1_ISO=$(now)

echo "4/4 Measure"
health=$(curl -fsS "$DR_URL/health")
RECOVERED_AT=$(python3 -c 'import json,sys; print(json.load(sys.stdin)["last_heartbeat"])' <<<"$health")
JOBS_AFTER=$(python3 -c 'import json,sys; print(json.load(sys.stdin)["jobs"])' <<<"$health")
# "None" means not one drill write survived: the restore point is older than the whole write window.
RPO=$(python3 -c '
import sys; from datetime import datetime
a, b = sys.argv[1:]
if b == "None":
    print("more than " + sys.argv[3])
else:
    print(max(0, round((datetime.fromisoformat(a) - datetime.fromisoformat(b)).total_seconds())))' "$LAST_AT" "$RECOVERED_AT" "$WRITE_SECONDS")
RTO=$((T1 - T0))
FILES_DR=$(aws s3api list-objects-v2 --bucket "$DR_BUCKET" --prefix uploads/ --region "$DR_REGION" --query 'length(Contents)' --output text)

echo "  RTO $RTO seconds, RPO $RPO seconds, jobs $JOBS_BEFORE -> $JOBS_AFTER, files in DR bucket $FILES_DR"
echo "  Ireland is serving at $DR_URL"

cat > "$ROOT/docs/dr-drill-results.md" <<MD
# Disaster recovery drill results

Recorded by \`scripts/dr-drill.sh\`. London's app server was stopped at $T0_ISO and the application was rebuilt in $DR_REGION from replicated backups and files.

| Measure | Result |
|---|---|
| Recovery time (RTO): outage to app serving in $DR_REGION | **$RTO seconds** |
| Data loss window (RPO): last write London acknowledged to last write recovered | **$RPO seconds** |
| Last write London acknowledged | $LAST_AT |
| Last write present after recovery | $RECOVERED_AT |
| Jobs before / after | $JOBS_BEFORE / $JOBS_AFTER |
| Uploaded files in the $DR_REGION bucket | $FILES_DR |

Recovery finished at $T1_ISO.
MD
