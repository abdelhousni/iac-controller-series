#!/usr/bin/env bash
# Semaphore UI runs a playbook kept in GitLab: pushes repo/ to a private
# GitLab project, gives Semaphore a read-only project access token, creates
# the Semaphore project, repository, inventory and template through its API,
# runs the template and prints what the task reports. Needs the lab
# (lab/up.sh). CI compares the output with expected.txt.
set -euo pipefail
cd "$(dirname "$0")"
env=../lab/.env
gl=http://127.0.0.1:8929/api/v4
sem=http://127.0.0.1:3000/api
glapi() { curl -fsS -H "PRIVATE-TOKEN: $(sed -n 's/^GITLAB_TOKEN=//p' "$env")" "$@"; }
json() { curl -fsS -H 'Content-Type: application/json' "$@"; }

# 1. The playbook in a private GitLab project, as the commit on main.
pid=$(glapi "$gl/projects/root%2Fctl-02" 2>/dev/null | jq -r .id 2>/dev/null) \
  || pid=$(glapi -X POST "$gl/projects" --data name=ctl-02 --data visibility=private \
    --data initialize_with_readme=true | jq -r .id)
actions=$(for f in repo/*; do
  name=${f#repo/}
  if glapi "$gl/projects/$pid/repository/files/$name?ref=main" >/dev/null 2>&1; then a=update; else a=create; fi
  jq -n --arg a "$a" --arg p "$name" --rawfile c "$f" '{action:$a, file_path:$p, content:$c}'
done | jq -s .)
glapi -X POST -H 'Content-Type: application/json' "$gl/projects/$pid/repository/commits" \
  -d "$(jq -n --argjson a "$actions" '{branch:"main", commit_message:"site.yml for Semaphore UI", actions:$a}')" \
  >/dev/null 2>&1 || true   # no change since the last run is fine

# 2. A read-only credential for Semaphore: a project access token
#    (role Reporter, scope read_repository), valid one day. The previous
#    run's token is revoked first.
for old in $(glapi "$gl/projects/$pid/access_tokens" | jq -r '.[] | select(.name == "semaphore" and .active) | .id'); do
  glapi -X DELETE "$gl/projects/$pid/access_tokens/$old"
done
token=$(glapi -X POST -H 'Content-Type: application/json' "$gl/projects/$pid/access_tokens" \
  -d "{\"name\":\"semaphore\",\"scopes\":[\"read_repository\"],\"access_level\":20,
       \"expires_at\":\"$(date -u -d tomorrow +%F)\"}" | jq -r .token)

# 3. Semaphore: log in, then a fresh project with everything a template needs.
cookie=$(mktemp)
trap 'rm -f "$cookie"' EXIT
json -c "$cookie" -o /dev/null "$sem/auth/login" \
  -d "$(jq -n --arg p "$(sed -n 's/^SEMAPHORE_ADMIN_PASSWORD=//p' "$env")" '{auth:"admin", password:$p}')"
s() { json -b "$cookie" "$@"; }
old=$(s "$sem/projects" | jq -r '.[] | select(.name == "ctl-02") | .id')
[ -n "$old" ] && s -X DELETE "$sem/project/$old" >/dev/null
p=$(s "$sem/projects" -d '{"name":"ctl-02"}' | jq -r .id)
none=$(s "$sem/project/$p/keys" -d "{\"project_id\":$p,\"name\":\"none\",\"type\":\"none\"}" | jq -r .id)
git=$(s "$sem/project/$p/keys" -d "$(jq -n --argjson p "$p" --arg t "$token" \
  '{project_id:$p, name:"gitlab read token", type:"login_password",
    login_password:{login:"semaphore", password:$t}}')" | jq -r .id)
repo=$(s "$sem/project/$p/repositories" -d "$(jq -n --argjson p "$p" --argjson k "$git" \
  '{project_id:$p, name:"ctl-02", git_url:"http://gitlab/root/ctl-02.git", git_branch:"main", ssh_key_id:$k}')" | jq -r .id)
inv=$(s "$sem/project/$p/inventory" -d "$(jq -n --argjson p "$p" --argjson k "$none" \
  '{project_id:$p, name:"local", type:"static", ssh_key_id:$k,
    inventory:"semaphore-container"}')" | jq -r .id)
# The connection variable lives in the variable group, not on the host line.
envid=$(s "$sem/project/$p/environment" -d "$(jq -n --argjson p "$p" \
  '{project_id:$p, name:"local", json:({ansible_connection:"local"} | tojson), env:"{}"}')" | jq -r .id)
tpl=$(s "$sem/project/$p/templates" -d "$(jq -n --argjson p "$p" --argjson r "$repo" --argjson i "$inv" --argjson e "$envid" \
  '{project_id:$p, name:"site", app:"ansible", playbook:"site.yml",
    repository_id:$r, inventory_id:$i, environment_id:$e}')" | jq -r .id)

# 4. Run it and wait.
task=$(s "$sem/project/$p/tasks" -d "{\"template_id\":$tpl}" | jq -r .id)
until status=$(s "$sem/project/$p/tasks/$task" | jq -r .status); \
  case $status in success|error|stopped) true ;; *) false ;; esac; do sleep 2; done

# The task can report its status before its last log lines are stored, so
# wait (up to 60 s) for the play recap to appear in the log.
for _ in $(seq 30); do
  s "$sem/project/$p/tasks/$task/output" | jq -r '.[].output' | grep -q ' ok=' && break
  sleep 2
done

echo "Semaphore task: $status"
echo "Commit run: $(s "$sem/project/$p/tasks/$task" | jq -r .commit_message)"
s "$sem/project/$p/tasks/$task/output" | jq -r '.[].output' | sed 's/\x1b\[[0-9;]*m//g' \
  | grep -E '^Cloning Repository|galaxy install|^ *msg:|ok=' | sed 's/^ *//; s/ \{2,\}/ /g; s/ *$//' \
  | sed -E 's#/tmp/semaphore/[^ ]*/repository_[0-9_a-z]*/#<repo>/#' | awk '!seen[$0]++'
