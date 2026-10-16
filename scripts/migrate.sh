#!/usr/bin/env bash
# Move the company server's database and files into AWS London, then prove nothing changed on the way.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

REGION=$(tf_out primary_region)
BUCKET=$(tf_out primary_bucket)
INSTANCE=$(tf_out primary_instance_id)
URL=$(tf_out primary_url)
STAMP=$(date -u +%Y%m%dT%H%M%SZ)
WORK="$ROOT/onprem/.dump/$STAMP"
mkdir -p "$WORK"

echo "Waiting for the AWS app server to finish booting"
wait_for_app "$URL"

START=$(date +%s); START_ISO=$(now)
echo "1/5 Freeze writes: stop the app on the company server"
"${COMPOSE[@]}" stop app >/dev/null

echo "2/5 Dump the database and upload the dump"
"${COMPOSE[@]}" exec -T db pg_dump -U jobs -d jobs --clean --if-exists --no-owner --no-privileges | gzip > "$WORK/jobs.sql.gz"
aws s3 cp --only-show-errors "$WORK/jobs.sql.gz" "s3://$BUCKET/migration/$STAMP/jobs.sql.gz" --region "$REGION"

echo "3/5 Copy uploaded files"
docker cp "$("${COMPOSE[@]}" ps -aq app)":/data/uploads "$WORK/uploads"
aws s3 sync --only-show-errors --checksum-algorithm SHA256 "$WORK/uploads" "s3://$BUCKET/uploads/" --region "$REGION"

echo "4/5 Restore into RDS from inside the VPC (Run Command, no SSH)"
run_on "$REGION" "$INSTANCE" "set -euo pipefail; set -a; . /etc/app.env; set +a; cd /opt/app
aws s3 cp --only-show-errors s3://$BUCKET/migration/$STAMP/jobs.sql.gz - | gunzip | psql -q -v ON_ERROR_STOP=1 \"\$(venv/bin/python db.py conninfo)\" >/dev/null
echo restored" >/dev/null

echo "5/5 Validate"
SRC_DB=$("${COMPOSE[@]}" exec -T db psql -U jobs -d jobs -Atc "SET TIME ZONE 'UTC'; SELECT count(*) || ' ' || coalesce(md5(string_agg(j::text, '|' ORDER BY j.id)), '') FROM jobs j" | tail -1)
AWS_DB=$(run_on "$REGION" "$INSTANCE" "set -a; . /etc/app.env; set +a; cd /opt/app && venv/bin/python db.py fingerprint" | tr -d "\r" | awk NF | tail -1)

files=0; mismatched=0
while IFS= read -r -d '' f; do
  key="uploads/${f#"$WORK/uploads/"}"
  local_sum=$(openssl dgst -sha256 -binary "$f" | base64)
  remote_sum=$(aws s3api head-object --bucket "$BUCKET" --key "$key" --checksum-mode ENABLED --region "$REGION" --query ChecksumSHA256 --output text)
  files=$((files + 1))
  [[ $local_sum == "$remote_sum" ]] || { mismatched=$((mismatched + 1)); echo "  mismatch: $key"; }
done < <(find "$WORK/uploads" -type f -print0)
END=$(date +%s)

db_ok=$([[ $SRC_DB == "$AWS_DB" ]] && echo match || echo MISMATCH)
echo "  database  company server: $SRC_DB"
echo "  database  AWS:            $AWS_DB   ($db_ok)"
echo "  files     $files checked, $mismatched mismatched"
echo "  downtime  $((END - START)) seconds from freezing writes to validated"

cat > "$ROOT/docs/migration-results.md" <<MD
# Migration results

Recorded by \`scripts/migrate.sh\` on $START_ISO.

| Check | Company server | AWS ($REGION) | Result |
|---|---|---|---|
| Jobs table (row count, MD5 of every row) | \`$SRC_DB\` | \`$AWS_DB\` | $db_ok |
| Uploaded files (SHA-256 each) | $files files | $files files | $mismatched mismatched |

Write freeze to validated cutover: **$((END - START)) seconds**.
MD
[[ $db_ok == match && $mismatched == 0 ]] && echo "Migration validated. The app is now served from $URL"
