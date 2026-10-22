#!/usr/bin/env bash
# Proves the lab end to end: creates the project lab-smoke, commits a
# one-job .gitlab-ci.yml, waits for the pipeline and prints its status and
# the job's log line. Run after lab/up.sh. Safe to run again.
set -euo pipefail
cd "$(dirname "$0")"
gl=http://127.0.0.1:8929/api/v4
api() { curl -fsS -H "PRIVATE-TOKEN: $(sed -n 's/^GITLAB_TOKEN=//p' .env)" "$@"; }

id=$(api "$gl/projects/root%2Flab-smoke" 2>/dev/null | jq -r .id) \
  || id=$(api -X POST "$gl/projects" --data name=lab-smoke --data initialize_with_readme=true | jq -r .id)
# The variables are for the job's shell, not this one.
# shellcheck disable=SC2016
ci=$(printf 'smoke:\n  script:\n    - echo "job ran on $CI_RUNNER_DESCRIPTION, cloned from $CI_SERVER_HOST"\n')
action=create
api "$gl/projects/$id/repository/files/.gitlab-ci.yml?ref=main" >/dev/null 2>&1 && action=update
sha=$(api -X POST -H 'Content-Type: application/json' "$gl/projects/$id/repository/commits" -d "$(jq -n \
  --arg a "$action" --arg c "$ci" '{branch:"main", commit_message:"smoke pipeline",
  actions:[{action:$a, file_path:".gitlab-ci.yml", content:$c}]}')" | jq -r .id)

until status=$(api "$gl/projects/$id/pipelines?sha=$sha" | jq -r '.[0].status // "pending"'); \
  case $status in success|failed|canceled) true ;; *) false ;; esac; do sleep 3; done
echo "pipeline: $status"
job=$(api "$gl/projects/$id/jobs" | jq -r --arg s "$sha" '[.[] | select(.commit.id == $s)][0].id')
api "$gl/projects/$id/jobs/$job/trace" | grep -o 'job ran on [a-z].*' | tr -d '\r'
[ "$status" = success ]
