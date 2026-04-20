#!/usr/bin/env bash
# Smoke test for the pi-coding-agent container image.
#
# Exercises the supported launch paths — `docker compose run` and the `pie`
# wrapper — rather than reconstructing a parallel `docker run` invocation, so
# regressions in the real launch paths (lost `:ro` on the skills mount, a
# missing `HOME=/home/node`, broken `HOST_UID/HOST_GID` wiring, etc.) surface
# here instead of in production.
#
# Verifies:
#   1. The image exists (or can be built) and starts.
#   2. Core toolchain is installed and runnable: pi, uv, gh, git, node.
#   3. /workspace is writable by the mapped host user.
#   4. The skills mount is present and read-only (writes fail).
#   5. /home/node/.pi is writable (persistent data dir).
#   6. The container runs as the requested HOST_UID:HOST_GID.
#   7. HOME=/home/node inside the container.
#   8. `pie --version` launches pi end-to-end through the wrapper.
#
# Dependency-light: bash, docker, coreutils. Safe for local and CI use.
#
# Usage:
#   scripts/smoke-test.sh            # uses local/pi-coding-agent:latest
#   IMAGE=foo/bar:tag scripts/smoke-test.sh
#   BUILD=1 scripts/smoke-test.sh    # force a `docker compose build` first

set -euo pipefail

IMAGE="${IMAGE:-local/pi-coding-agent:latest}"
SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -P "$SCRIPT_DIR/.." && pwd)"
PIE="$REPO_ROOT/pie"

# docker-compose.yml reads HOST_UID/HOST_GID from the environment. `make
# smoke-test` exports them, but direct invocations of this script must not
# rely on that — export the caller's real UID/GID so the mapping check
# exercises the same wiring that production uses.
export HOST_UID="${HOST_UID:-$(id -u)}"
export HOST_GID="${HOST_GID:-$(id -g)}"

# Ensure bind-mount sources exist before compose runs, so Docker doesn't
# auto-create them as root on platforms where that applies.
mkdir -p "$REPO_ROOT/.pi-data"

TMPDIRS=()
cleanup() {
  if [ "${#TMPDIRS[@]}" -gt 0 ]; then
    rm -rf "${TMPDIRS[@]}"
  fi
}
trap cleanup EXIT

# If the caller hasn't configured SKILLS_DIR and the default doesn't exist,
# point it at an ephemeral dir so compose's `${SKILLS_DIR:-~/.agents/skills}`
# mount doesn't silently autovivify a root-owned directory on the host.
if [ -z "${SKILLS_DIR:-}" ] && [ ! -d "$HOME/.agents/skills" ]; then
  SKILLS_DIR="$(mktemp -d)"
  chmod 0755 "$SKILLS_DIR"
  TMPDIRS+=("$SKILLS_DIR")
  export SKILLS_DIR
fi

pass=0
fail=0
results=()

if [ -t 1 ]; then
  C_INFO=$'\033[1;34m'; C_OK=$'\033[1;32m'; C_BAD=$'\033[1;31m'; C_RST=$'\033[0m'
else
  C_INFO=""; C_OK=""; C_BAD=""; C_RST=""
fi

log()  { printf '%s[smoke]%s %s\n' "$C_INFO" "$C_RST" "$*"; }
ok()   { printf '  %sPASS%s %s\n' "$C_OK"  "$C_RST" "$*"; pass=$((pass+1)); results+=("PASS: $*"); }
bad()  { printf '  %sFAIL%s %s\n' "$C_BAD" "$C_RST" "$*"; fail=$((fail+1)); results+=("FAIL: $*"); }

ensure_image() {
  if [ "${BUILD:-0}" = "1" ] || ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
    log "Building image $IMAGE (docker compose build)..."
    ( cd "$REPO_ROOT" && docker compose build )
  else
    log "Using existing image $IMAGE"
  fi
}

# Run a command through `docker compose run --rm`, overriding the entrypoint
# so arbitrary binaries can be exercised. Going through compose is deliberate:
# checks fail if docker-compose.yml regresses (user mapping, mount specs,
# HOME, read-only flags, etc.) instead of silently staying green.
compose_run() {
  local entrypoint="$1"; shift
  ( cd "$REPO_ROOT" && docker compose run --rm --no-TTY --entrypoint "$entrypoint" pi-agent "$@" )
}

check_tool_compose() {
  local tool="$1"; shift
  local out
  if out=$(compose_run "$tool" "$@" 2>&1); then
    ok "[compose] $tool available ($(printf '%s' "$out" | head -n1))"
  else
    bad "[compose] $tool not runnable: $(printf '%s' "$out" | head -n1)"
  fi
}

check_workspace_writable_compose() {
  if compose_run sh -c 'f=/workspace/.smoke-test-$$; touch "$f" && rm "$f"' >/dev/null 2>&1; then
    ok "[compose] /workspace writable as $HOST_UID:$HOST_GID"
  else
    bad "[compose] /workspace NOT writable as $HOST_UID:$HOST_GID"
  fi
}

check_skills_readonly_compose() {
  if ! compose_run sh -c 'test -d /home/node/.agents/skills' >/dev/null 2>&1; then
    bad "[compose] /home/node/.agents/skills is not mounted"
    return
  fi
  # A 0 exit from the write is the failure case (mount isn't read-only).
  if compose_run sh -c 'touch /home/node/.agents/skills/.smoke-test' >/dev/null 2>&1; then
    bad "[compose] skills mount is writable (expected read-only)"
    compose_run sh -c 'rm -f /home/node/.agents/skills/.smoke-test' >/dev/null 2>&1 || true
  else
    ok "[compose] skills mount is read-only"
  fi
}

check_pi_data_writable_compose() {
  if compose_run sh -c 'f=/home/node/.pi/.smoke-test-$$; touch "$f" && rm "$f"' >/dev/null 2>&1; then
    ok "[compose] /home/node/.pi writable"
  else
    bad "[compose] /home/node/.pi NOT writable"
  fi
}

check_user_mapping_compose() {
  local uid gid
  uid=$(compose_run id -u 2>/dev/null | tr -d '[:space:]') || true
  gid=$(compose_run id -g 2>/dev/null | tr -d '[:space:]') || true
  if [ "$uid" = "$HOST_UID" ] && [ "$gid" = "$HOST_GID" ]; then
    ok "[compose] container runs as $uid:$gid (matches $HOST_UID:$HOST_GID)"
  else
    bad "[compose] uid:gid = $uid:$gid, expected $HOST_UID:$HOST_GID"
  fi
}

check_home_compose() {
  local home
  home=$(compose_run sh -c 'printf %s "$HOME"' 2>/dev/null | tr -d '[:space:]') || true
  if [ "$home" = "/home/node" ]; then
    ok "[compose] HOME=/home/node"
  else
    bad "[compose] HOME=$home, expected /home/node"
  fi
}

check_pie_version() {
  # pie's entrypoint is `pi`, so we can't override it without rewriting the
  # wrapper. A successful `pie --version` still verifies end-to-end that
  # pie's actual `docker run` invocation is syntactically valid, the mapped
  # UID can reach HOME/.pi, and pi can start — which is exactly the parity
  # guarantee this check exists to protect.
  if (cd "$REPO_ROOT" && "$PIE" --version </dev/null >/dev/null 2>&1); then
    ok "[pie] --version works"
  else
    local out
    out=$(cd "$REPO_ROOT" && "$PIE" --version </dev/null 2>&1) || true
    bad "[pie] --version failed: $(printf '%s' "$out" | head -n1)"
  fi
}

main() {
  ensure_image

  log "Checking toolchain availability (docker compose run)..."
  check_tool_compose pi --version
  check_tool_compose uv --version
  check_tool_compose gh --version
  check_tool_compose git --version
  check_tool_compose node --version

  log "Checking mount semantics (docker compose run)..."
  check_workspace_writable_compose
  check_skills_readonly_compose
  check_pi_data_writable_compose

  log "Checking environment (docker compose run)..."
  check_user_mapping_compose
  check_home_compose

  log "Checking pie launcher (end-to-end)..."
  check_pie_version

  echo
  log "Summary: $pass passed, $fail failed"
  for r in "${results[@]}"; do printf '  %s\n' "$r"; done

  [ "$fail" -eq 0 ]
}

main "$@"
