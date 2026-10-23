#!/usr/bin/env bash
# Runs the lab on rootless Podman instead of Docker: starts Podman's
# Docker-compatible API service with netavark's firewall off (see
# podman/containers.conf), then runs a lab script or any command with docker
# and docker compose pointed at it.
#
#   lab/podman.sh up | check | smoke | down [--wipe]
#   lab/podman.sh 04-opentofu-gitlab-state/run.sh
#
# down also stops the API service. The lab's data stays in Podman's volumes
# unless down gets --wipe.
set -euo pipefail
lab=$(cd "$(dirname "$0")" && pwd)
dir=${XDG_RUNTIME_DIR:?needs a user session}/podman
sock=$dir/lab.sock
pidfile=$dir/lab.pid

[ $# -gt 0 ] || { sed -n '7,8s/^# *//p' "$0"; exit 2; }

ping() { curl -fs --max-time 2 --unix-socket "$sock" http://podman/_ping >/dev/null 2>&1; }

if ! ping; then
  mkdir -p "$dir"
  CONTAINERS_CONF_OVERRIDE=$lab/podman/containers.conf \
    nohup podman system service --time=0 "unix://$sock" >"$dir/lab.log" 2>&1 &
  echo $! > "$pidfile"
  for _ in $(seq 20); do ping && break; sleep 0.5; done
  ping || { echo "Podman API service did not start; see $dir/lab.log" >&2; exit 1; }
fi

export DOCKER_HOST=unix://$sock
export COMPOSE_FILE=$lab/compose.yml:$lab/compose.podman.yml

case $1 in
  up | check | smoke) cmd=$1; shift; "$lab/$cmd.sh" "$@" ;;
  down)
    shift
    "$lab/down.sh" "$@"
    [ -f "$pidfile" ] && kill "$(cat "$pidfile")" 2>/dev/null || true
    rm -f "$pidfile"
    ;;
  *) exec "$@" ;;
esac
