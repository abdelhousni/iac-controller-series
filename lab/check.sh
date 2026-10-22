#!/usr/bin/env bash
# ok and ko always succeed, so "test && ok || ko" never runs both.
# shellcheck disable=SC2015
# Reports what the examples need and whether this machine has it. Run it from
# anywhere, before the first run.sh. It changes nothing.
set -uo pipefail
cd "$(dirname "$0")" || exit 1
missing=0
ok() { printf '  ok       %s\n' "$1"; }
ko() { printf '  MISSING  %s: %s\n' "$1" "$2"; missing=1; }

echo "Tools:"
if command -v docker >/dev/null && docker info >/dev/null 2>&1; then
  ok "Docker Engine $(docker version --format '{{.Server.Version}}')"
else
  ko "Docker Engine, running" "install Docker Engine and start the daemon"
fi
docker compose version >/dev/null 2>&1 && ok "Docker Compose $(docker compose version --short)" \
  || ko "Docker Compose v2" "install the docker-compose-plugin package"
for t in curl jq openssl; do
  command -v $t >/dev/null && ok "$t" || ko "$t" "install your distribution's $t package"
done

echo "Images (pulled by lab/up.sh if missing):"
while read -r i; do
  docker image inspect "$i" >/dev/null 2>&1 && ok "$i" || ko "$i" "docker pull $i"
done < <(sed -n 's/^ *image: //p' compose.yml)

echo "Lab services (lab/up.sh starts them):"
curl -fs -o /dev/null http://127.0.0.1:8929/users/sign_in && ok "GitLab on http://127.0.0.1:8929" \
  || ko "GitLab on http://127.0.0.1:8929" "lab/up.sh"
token=$(sed -n 's/^GITLAB_TOKEN=//p' .env 2>/dev/null)
if [ -n "$token" ] && curl -fs -H "PRIVATE-TOKEN: $token" 'http://127.0.0.1:8929/api/v4/runners/all?status=online' \
  | jq -e 'map(select(.description == "lab-docker")) | length == 1' >/dev/null 2>&1; then
  ok "runner lab-docker online"
else
  ko "runner lab-docker online" "lab/up.sh"
fi
curl -fs -o /dev/null http://127.0.0.1:3000/api/ping && ok "Semaphore UI on http://127.0.0.1:3000" \
  || ko "Semaphore UI on http://127.0.0.1:3000" "lab/up.sh"
exit "$missing"
