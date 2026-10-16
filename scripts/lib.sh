# Shared helpers for the migration and DR drill scripts.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE=(docker compose -f "$ROOT/onprem/docker-compose.yml")

tf_out() { terraform -chdir="$ROOT/terraform" output -raw "$1"; }

# Run a shell script on an EC2 instance through Systems Manager Run Command (no SSH) and print its output.
run_on() {
  local region=$1 instance=$2 script=$3 id status
  id=$(aws ssm send-command --region "$region" --instance-ids "$instance" \
    --document-name AWS-RunShellScript --comment "hybrid-migration-dr" \
    --parameters "$(python3 -c 'import json,sys; print(json.dumps({"commands":[sys.argv[1]],"executionTimeout":["1800"]}))' "$script")" \
    --query Command.CommandId --output text)
  while :; do
    status=$(aws ssm get-command-invocation --region "$region" --command-id "$id" --instance-id "$instance" \
      --query Status --output text 2>/dev/null || echo Pending)
    case $status in Success|Failed|Cancelled|TimedOut) break ;; esac
    sleep 3
  done
  aws ssm get-command-invocation --region "$region" --command-id "$id" --instance-id "$instance" \
    --query StandardOutputContent --output text
  if [[ $status != Success ]]; then
    aws ssm get-command-invocation --region "$region" --command-id "$id" --instance-id "$instance" \
      --query StandardErrorContent --output text >&2
    return 1
  fi
}

# Wait until an instance has registered with Systems Manager and finished its boot script.
wait_for_app() {
  local url=$1
  until curl -fsS --max-time 5 "$url/health" >/dev/null 2>&1; do sleep 5; done
}

now() { date -u +%Y-%m-%dT%H:%M:%SZ; }
