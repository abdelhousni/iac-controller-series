#!/usr/bin/env bash
# Starts the lab and makes it usable: GitLab CE with a root access token, a
# GitLab Runner registered with the Docker executor, and Semaphore UI.
# Passwords and tokens go to lab/.env (not committed), which Compose reads,
# so plain docker compose commands work afterwards. Safe to run again.
set -euo pipefail
cd "$(dirname "$0")"
secrets=.env
touch "$secrets" && chmod 600 "$secrets"
get() { sed -n "s/^$1=//p" "$secrets"; }
put() { grep -q "^$1=" "$secrets" || echo "$1=$2" >> "$secrets"; }
put GITLAB_ROOT_PASSWORD "$(openssl rand -hex 16)"
put SEMAPHORE_ADMIN_PASSWORD "$(openssl rand -hex 16)"


docker compose up -d --quiet-pull
echo "Waiting for GitLab (the first start takes several minutes)..."
# /-/readiness answers only from the monitoring allowlist (127.0.0.1 inside
# the container), so wait for the sign-in page instead.
until [ "$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8929/users/sign_in)" = 200 ]; do sleep 5; done

# A personal access token for root, created once from the Rails console.
if [ -z "$(get GITLAB_TOKEN)" ]; then
  token=glpat-lab-$(openssl rand -hex 12)
  docker compose exec -T gitlab gitlab-rails runner "
    t = User.find_by_username('root').personal_access_tokens.create!(
      name: 'lab', scopes: [:api], expires_at: 30.days.from_now)
    t.set_token('$token'); t.save!" >/dev/null
  put GITLAB_TOKEN "$token"
fi
api() { curl -fsS -H "PRIVATE-TOKEN: $(get GITLAB_TOKEN)" "$@"; }

# The job image, pulled once here: with the runner's default pull policy
# (always), every job asks Docker Hub again and soon hits its anonymous rate
# limit, so the runner below uses if-not-present.
for i in 1 2 3 4 5; do docker pull -q alpine:3.22 >/dev/null && break; sleep $((i * 20)); done

# An instance runner: created through the API (GitLab 16 and later), then
# registered with the authentication token the API returns.
if ! docker compose exec -T runner test -s /etc/gitlab-runner/config.toml; then
  runner_token=$(api -X POST http://127.0.0.1:8929/api/v4/user/runners \
    --data runner_type=instance_type --data description=lab-docker \
    --data run_untagged=true | jq -r .token)
  docker compose exec -T runner gitlab-runner register --non-interactive \
    --url http://gitlab --token "$runner_token" --name lab-docker \
    --executor docker --docker-image alpine:3.22 \
    --docker-pull-policy if-not-present --docker-network-mode iac-lab --clone-url http://gitlab >/dev/null 2>&1
fi

echo "Waiting for Semaphore UI..."
until curl -fs -o /dev/null http://127.0.0.1:3000/api/ping; do sleep 2; done
echo "Lab up: GitLab http://127.0.0.1:8929 (root), Semaphore http://127.0.0.1:3000 (admin); passwords in lab/.env"
