#!/usr/bin/env bash
# OpenTofu in a GitLab pipeline, with the state kept by GitLab: mirrors GitLab's
# OpenTofu CI/CD component into the lab, pushes repo/ to a project, runs the
# pipeline (fmt, validate, plan, then the manual apply), reads the state GitLab
# now holds, and reads it again from outside CI. Needs the lab (lab/up.sh) and
# access to gitlab.com. CI compares the output with expected.txt.
set -euo pipefail
cd "$(dirname "$0")"
env=../lab/.env
token=$(sed -n 's/^GITLAB_TOKEN=//p' "$env")
gl=http://127.0.0.1:8929/api/v4
glapi() { curl -fsS -H "PRIVATE-TOKEN: $token" "$@"; }
component_version=4.9.0

# 1. The component, at components/opentofu, as on gitlab.com. A self-managed
#    GitLab can't include components from gitlab.com, so they are copied in.
if ! glapi "$gl/projects/components%2Fopentofu/repository/tags/$component_version" >/dev/null 2>&1; then
  gid=$(glapi "$gl/groups/components" 2>/dev/null | jq -r .id 2>/dev/null) \
    || gid=$(glapi -X POST "$gl/groups" --data name=components --data path=components \
      --data visibility=public | jq -r .id)
  glapi "$gl/projects/components%2Fopentofu" >/dev/null 2>&1 \
    || glapi -X POST "$gl/projects" --data name=opentofu --data namespace_id="$gid" \
      --data visibility=public >/dev/null
  mkdir -p out
  [ -d out/opentofu-component ] || git clone -q --single-branch --branch main \
    https://gitlab.com/components/opentofu.git out/opentofu-component
  git -C out/opentofu-component fetch -q origin "refs/tags/$component_version:refs/tags/$component_version"
  # ci.skip: the component's own pipeline builds its images; not needed here.
  git -C out/opentofu-component -c push.negotiate=false \
    -c http.extraHeader="Authorization: Basic $(printf 'root:%s' "$token" | base64 -w0)" \
    push -q -o ci.skip http://127.0.0.1:8929/components/opentofu.git \
    main "refs/tags/$component_version"
fi
echo "Component: components/opentofu@$(glapi "$gl/projects/components%2Fopentofu/repository/tags/$component_version" | jq -r .name)"

# 2. The project, with repo/ as its main branch.
pid=$(glapi "$gl/projects/root%2Fctl-04" 2>/dev/null | jq -r .id 2>/dev/null) \
  || pid=$(glapi -X POST "$gl/projects" --data name=ctl-04 --data visibility=private \
    --data initialize_with_readme=true | jq -r .id)
actions=$(cd repo && for f in main.tf .gitlab-ci.yml; do
  if glapi "$gl/projects/$pid/repository/files/$(jq -rn --arg f "$f" '$f|@uri')?ref=main" >/dev/null 2>&1; then a=update; else a=create; fi
  jq -n --arg a "$a" --arg p "$f" --rawfile c "$f" '{action:$a, file_path:$p, content:$c}'
done | jq -s .)
# ci.skip here too: the pipeline is started below, once the old state is gone.
glapi -X POST -H 'Content-Type: application/json' "$gl/projects/$pid/repository/commits" \
  -d "$(jq -n --argjson a "$actions" '{branch:"main", commit_message:"OpenTofu with GitLab-managed state [ci skip]", actions:$a}')" \
  >/dev/null 2>&1 || true   # no change since the last run is fine
# Start from no state, so every run shows the same first apply.
glapi -X DELETE "$gl/projects/$pid/terraform/state/default" >/dev/null 2>&1 || true

# 3. The pipeline: fmt, validate and plan run; apply waits for a person.
pipeline=$(glapi -X POST "$gl/projects/$pid/pipeline?ref=main" | jq -r .id)
jobs() { glapi "$gl/projects/$pid/pipelines/$pipeline/jobs?per_page=50"; }
until jobs | jq -e 'map(select(.name != "apply")) | all(.status == "success" or .status == "failed")' >/dev/null \
  && jobs | jq -e '.[] | select(.name == "apply") | .status == "manual"' >/dev/null; do
  jobs | jq -e 'any(.status == "failed")' >/dev/null && break
  sleep 3
done
echo "Before apply:"
jobs | jq -r 'sort_by(.id) | .[] | "  \(.stage) / \(.name): \(.status)"'
log() { glapi "$gl/projects/$pid/jobs/$(jobs | jq -r --arg n "$1" '.[] | select(.name == $n) | .id')/trace" \
  | sed 's/\x1b\[[0-9;]*m//g; s/^[^ ]* [0-9]*[OE]+\{0,1\} //' | tr -d '\r'; }
log plan | grep -o 'Plan: .*' | head -1

# The manual apply, as a Maintainer would click it.
glapi -X POST "$gl/projects/$pid/jobs/$(jobs | jq -r '.[] | select(.name == "apply") | .id')/play" >/dev/null
until s=$(jobs | jq -r '.[] | select(.name == "apply") | .status'); [ "$s" = success ] || [ "$s" = failed ]; do sleep 3; done
echo "Apply: $s, $(log apply | grep -o 'Apply complete! .*' | head -1)"

# 4. The state GitLab keeps: one named state per project, versioned.
glapi -H 'Content-Type: application/json' "$gl/../graphql" -d "$(jq -n \
  '{query:"{ project(fullPath: \"root/ctl-04\") { terraformStates { nodes { name lockedAt latestVersion { serial job { name } } } } } }"}')" \
  | jq -r '.data.project.terraformStates.nodes[] |
    "State \(.name): serial \(.latestVersion.serial), written by job \(.latestVersion.job.name), locked: \(.lockedAt != null)"'
glapi "$gl/projects/$pid/terraform/state/default" \
  | jq -r '"Resources: \([.resources[] | "\(.type).\(.name)"] | join(", "))",
           "Output release: \(.outputs.release.value | tojson)"'

# 5. The same state from outside CI, as from an engineer's machine: the HTTP
#    backend with a personal access token instead of the job token.
docker run --rm --network iac-lab -v "$PWD/repo:/src:ro" -w /tmp \
  -e TF_HTTP_ADDRESS="http://gitlab/api/v4/projects/$pid/terraform/state/default" \
  -e TF_HTTP_USERNAME=root -e TF_HTTP_PASSWORD="$token" \
  --entrypoint sh "registry.gitlab.com/components/opentofu/gitlab-opentofu:$component_version-opentofu1.12.6-alpine" \
  -c 'cp /src/main.tf . && tofu init -input=false >/dev/null && echo "tofu output from outside CI:" && tofu output -json release'
