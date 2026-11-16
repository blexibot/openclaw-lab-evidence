#!/usr/bin/env bash
# bench (lab-linux / Incus): one small CLI so the worker never has to learn the toolchain.
#   bench new <image> [name] [--vm]     e.g. bench new ubuntu/24.04 t1   (images: remote "images:")
#   bench openclaw <name> <version>     install Node (official tarball, SHA-checked) + openclaw@<version> in the bench
#   bench snap <name> <snapshot>        bench reset <name> <snapshot>
#   bench exec <name> -- <cmd...>       bench list        bench destroy <name>
# Every action is appended to ~/bench/log.tsv (UTC time, action, name, args). Benches live in the caller's own Incus
# project; NAT egress only (the lab egress fence still applies). Never use a bench for anything but throwaway test work.
set -euo pipefail
NODE_V="${BENCH_NODE_VERSION:-v24.22.3}"
mkdir -p "$HOME/bench"; log() { printf '%s\t%s\n' "$(date -u +%FT%TZ)" "$*" >> "$HOME/bench/log.tsv"; }
cmd="${1:-}"; shift || true
case "$cmd" in
  new)
    img="$1"; name="${2:-bench-$(date +%H%M%S)}"; vm=""; [ "${3:-}" = "--vm" ] && vm="--vm"
    # security.nesting: newer systemd (Debian 13, Ubuntu 26.04) does not boot in a restricted project without it
    incus launch "images:$img" "$name" $vm -c security.nesting=true >/dev/null
    for i in $(seq 1 60); do incus exec "$name" -- true 2>/dev/null && break; sleep 2; done
    for i in $(seq 1 30); do incus exec "$name" -- getent hosts nodejs.org >/dev/null 2>&1 && break; sleep 2; done
    log new "$name" "$img" $vm; echo "$name" ;;
  openclaw)
    name="$1"; ver="$2"
    incus exec "$name" -- sh -ec "
      { command -v curl && command -v xz; } >/dev/null || { (apt-get -qq update && DEBIAN_FRONTEND=noninteractive apt-get -qq install -y curl xz-utils ca-certificates) >/dev/null 2>&1 || dnf -q -y install curl xz >/dev/null 2>&1; }
      a=\$(uname -m); case \$a in x86_64) a=x64;; aarch64) a=arm64;; esac
      f=node-$NODE_V-linux-\$a.tar.xz; cd /tmp
      curl -fsSLO https://nodejs.org/dist/$NODE_V/\$f; curl -fsSLO https://nodejs.org/dist/$NODE_V/SHASUMS256.txt
      grep \" \$f\\\$\" SHASUMS256.txt | sha256sum -c - >/dev/null
      tar -xJf \$f -C /usr/local --strip-components=1
      npm install -g openclaw@$ver --no-fund --no-audit >/dev/null 2>&1
      openclaw --version"
    log openclaw "$name" "$ver" ;;
  snap)    incus snapshot create "$1" "$2"; log snap "$1" "$2" ;;
  reset)   incus snapshot restore "$1" "$2"; log reset "$1" "$2" ;;
  exec)    name="$1"; shift; [ "${1:-}" = "--" ] && shift; incus exec "$name" -- "$@" ;;
  list)    incus list -f csv -c ns4 ;;
  destroy) incus delete -f "$1"; log destroy "$1" ;;
  *) sed -n '2,8p' "$0"; exit 2 ;;
esac
