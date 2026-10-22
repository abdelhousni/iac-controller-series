#!/usr/bin/env bash
# Copies GitLab's OpenTofu CI/CD component into the lab at components/opentofu,
# with its release tag, once. A self-managed GitLab can't include components
# from gitlab.com, and the lab's GitLab has no internet access to pull-mirror
# one, so this pushes the tag from a clone. Used by examples 04 and 05.
set -euo pipefail
cd "$(dirname "$0")"
token=$(sed -n 's/^GITLAB_TOKEN=//p' .env)
gl=http://127.0.0.1:8929/api/v4
glapi() { curl -fsS -H "PRIVATE-TOKEN: $token" "$@"; }
component_version=4.9.0

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

