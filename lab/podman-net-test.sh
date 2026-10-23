#!/usr/bin/env bash
# Checks whether rootless Podman networking works on this kernel, the way the
# lab needs it: a container finds another on the same network by name, and
# reaches the internet. Tries each netavark firewall driver in turn. Changes
# nothing outside its own network and containers, which it removes.
set -uo pipefail
image=docker.io/library/alpine:3.22
net=lab-podman-test
conf=$(mktemp)
trap 'podman rm -f web >/dev/null 2>&1; podman network rm -f "$net" >/dev/null 2>&1; rm -f "$conf"' EXIT

echo "Kernel $(uname -r), $(podman --version), rootless=$(podman info --format '{{.Host.Security.Rootless}}' 2>/dev/null)"
podman pull -q "$image" >/dev/null
podman network exists "$net" || podman network create "$net" >/dev/null

for driver in nftables iptables none; do
  echo "== firewall_driver = $driver"
  printf '[network]\nfirewall_driver = "%s"\n' "$driver" > "$conf"
  export CONTAINERS_CONF_OVERRIDE=$conf
  podman rm -f web >/dev/null 2>&1
  if ! err=$(podman run -d --rm --name web --network "$net" "$image" \
      sh -c 'echo hi > /i; httpd -f -p 80 -h /' 2>&1 >/dev/null); then
    echo "  start    FAIL: $(grep -v 'shared mount' <<<"$err" | tail -1)"
    continue
  fi
  sleep 2
  podman run --rm --network "$net" "$image" sh -c '
    getent hosts web >/dev/null && echo "  dns      ok" || echo "  dns      FAIL"
    wget -qO- -T 5 http://web/i >/dev/null 2>&1 && echo "  by name  ok" || echo "  by name  FAIL"
    wget -qO- -T 8 https://gitlab.com/ >/dev/null 2>&1 && echo "  outbound ok" || echo "  outbound FAIL"
  ' 2>&1 | grep -v 'shared mount'
done
