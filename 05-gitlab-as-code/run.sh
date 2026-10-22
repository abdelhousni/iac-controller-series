#!/usr/bin/env bash
# GitLab as code: a configuration project, root/gitlab-config, whose pipeline
# runs OpenTofu with the GitLab provider against the lab's own GitLab. It
# creates a group, a project in it, protection for its main branch, a CI/CD
# variable and a project runner, then reads them back through the API, and runs
# the pipeline again to show a plan with no changes. Needs the lab (lab/up.sh)
# and, on the first run, access to gitlab.com and the OpenTofu registry.
# CI compares the output with expected.txt.
set -euo pipefail
cd "$(dirname "$0")"
token=$(sed -n 's/^GITLAB_TOKEN=//p' ../lab/.env)
gl=http://127.0.0.1:8929/api/v4
glapi() { curl -fsS -H "PRIVATE-TOKEN: $token" "$@"; }

../lab/opentofu-component.sh

# 1. Bootstrap, by hand once: the configuration project and the credentials
#    its pipeline uses. Everything else is created by OpenTofu.
pid=$(glapi "$gl/projects/root%2Fgitlab-config" 2>/dev/null | jq -r .id 2>/dev/null) \
  || pid=$(glapi -X POST "$gl/projects" --data name=gitlab-config --data visibility=private \
    --data initialize_with_readme=true | jq -r .id)
var() {  # key value masked
  glapi -X DELETE "$gl/projects/$pid/variables/$1" >/dev/null 2>&1 || true
  glapi -X POST "$gl/projects/$pid/variables" --data key="$1" --data-urlencode value="$2" \
    --data protected=true --data masked="$3" >/dev/null
}
var GITLAB_BASE_URL "http://gitlab/api/v4/" false
var GITLAB_TOKEN "$token" true

# 2. Start from nothing: remove what a previous run created, and its state.
if gid=$(glapi "$gl/groups/platform" 2>/dev/null | jq -r .id 2>/dev/null); then
  # GitLab 19 schedules a top-level group for deletion (permanently_remove is
  # only for subgroups) and renames it platform-deletion_scheduled-<id>, which
  # frees the path for this run.
  glapi -X DELETE "$gl/groups/$gid" >/dev/null
fi
glapi -X DELETE "$gl/projects/$pid/terraform/state/default" >/dev/null 2>&1 || true

# 3. The configuration as the project's main branch.
actions=$(cd repo && for f in main.tf .terraform.lock.hcl .gitlab-ci.yml; do
  if glapi "$gl/projects/$pid/repository/files/$(jq -rn --arg f "$f" '$f|@uri')?ref=main" >/dev/null 2>&1; then a=update; else a=create; fi
  jq -n --arg a "$a" --arg p "$f" --rawfile c "$f" '{action:$a, file_path:$p, content:$c}'
done | jq -s .)
glapi -X POST -H 'Content-Type: application/json' "$gl/projects/$pid/repository/commits" \
  -d "$(jq -n --argjson a "$actions" '{branch:"main", commit_message:"GitLab as code [ci skip]", actions:$a}')" \
  >/dev/null 2>&1 || true   # no change since the last run is fine

# 4. Pipelines: wait for every job but a manual apply, then print a job's lines.
pipeline=""
jobs() { glapi "$gl/projects/$pid/pipelines/$pipeline/jobs?per_page=50"; }
run_pipeline() {
  pipeline=$(glapi -X POST "$gl/projects/$pid/pipeline?ref=main" | jq -r .id)
  until jobs | jq -e 'length > 0 and all(.status | IN("success", "failed", "manual", "skipped", "canceled"))' >/dev/null; do
    sleep 3
  done
}
log() { glapi "$gl/projects/$pid/jobs/$(jobs | jq -r --arg n "$1" '.[] | select(.name == $n) | .id')/trace" \
  | sed 's/\x1b\[[0-9;]*m//g; s/^[^ ]* [0-9]*[OE]+\{0,1\} //' | tr -d '\r'; }

run_pipeline
echo "First pipeline:"
jobs | jq -r 'sort_by(.id) | .[] | "  \(.stage) / \(.name): \(.status)"'
log plan | grep -E '^  # [a-z_.]+ will be created|^Plan: ' | sed 's/^  # /  will create: /; s/ will be created$//'
glapi -X POST "$gl/projects/$pid/jobs/$(jobs | jq -r '.[] | select(.name == "apply") | .id')/play" >/dev/null
until s=$(jobs | jq -r '.[] | select(.name == "apply") | .status'); [ "$s" = success ] || [ "$s" = failed ]; do sleep 3; done
echo "Apply: $s, $(log apply | grep -o 'Apply complete! .*' | head -1)"

# 5. What GitLab now has, read back through its API.
app=$(glapi "$gl/projects/platform%2Fapp")
aid=$(jq -r .id <<<"$app")
echo "GitLab now has:"
jq -r '"  project \(.path_with_namespace), \(.visibility), default branch \(.default_branch)"' <<<"$app"
glapi "$gl/projects/$aid/protected_branches/main" | jq -r \
  '"  branch main protected: push \(.push_access_levels[0].access_level_description), merge \(.merge_access_levels[0].access_level_description), force push \(.allow_force_push)"'
glapi "$gl/projects/$aid/variables/DEPLOY_ENV" | jq -r '"  variable \(.key)=\(.value), protected \(.protected)"'
glapi "$gl/projects/$aid/runners?type=project_type" | jq -r '.[] | "  runner \"\(.description)\", \(.runner_type)"'
glapi "$gl/projects/$pid/terraform/state/default" | jq -r \
  '"  runner token kept in the OpenTofu state: \([.resources[] | select(.type == "gitlab_user_runner") | .instances[0].attributes.token | length > 0] | first)"'

# 6. The same configuration again: nothing to do.
run_pipeline
echo "Second pipeline, plan: $(log plan | grep -o 'No changes.*' | head -1)"
