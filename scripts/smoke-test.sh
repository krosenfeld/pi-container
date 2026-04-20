#!/usr/bin/env bash
# Smoke test for the pi-coding-agent container image.
#
# Verifies basic runtime expectations of the built image:
#   1. The image exists (or can be built) and starts.
#   2. Core toolchain is installed and runnable: pi, uv, gh, git, node.
#   3. /workspace is writable by the container user.
#   4. The skills mount is read-only (writes must fail).
#   5. The container runs as the requested host UID:GID (not root, not the
#      baked-in 1000:1000 when a different UID/GID is supplied).
#   6. /home/node/.pi is writable (bind-mounted persistent data dir).
#
# The script is intentionally dependency-light: it only requires bash, docker,
# and coreutils. It is safe to run locally or from CI.
#
# Usage:
#   scripts/smoke-test.sh            # uses local/pi-coding-agent:latest
#   IMAGE=foo/bar:tag scripts/smoke-test.sh
#   BUILD=1 scripts/smoke-test.sh    # force a `docker compose build` first

set -euo pipefail

IMAGE="${IMAGE:-local/pi-coding-agent:latest}"
SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -P "$SCRIPT_DIR/.." && pwd)"

# Use a UID/GID that is *not* the node user's default 1000:1000 when possible,
# so we actually exercise the host-UID mapping. Fall back to the caller's
# UID/GID when running as root (e.g. in some CI runners).
HOST_UID="$(id -u)"
HOST_GID="$(id -g)"
if [ "$HOST_UID" = "0" ]; then
  # Pick an arbitrary non-root, non-1000 uid/gid to exercise the mapping.
  HOST_UID=4242
  HOST_GID=4242
fi

pass=0
fail=0
results=()

log()  { printf '\033[1;34m[smoke]\033[0m %s\n' "$*"; }
ok()   { printf '  \033[1;32mPASS\033[0m %s\n' "$*"; pass=$((pass+1)); results+=("PASS: $*"); }
bad()  { printf '  \033[1;31mFAIL\033[0m %s\n' "$*"; fail=$((fail+1)); results+=("FAIL: $*"); }

ensure_image() {
  if [ "${BUILD:-0}" = "1" ] || ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
    log "Building image $IMAGE (docker compose build)..."
    ( cd "$REPO_ROOT" && docker compose build )
  else
    log "Using existing image $IMAGE"
  fi
}

# Run a command inside the image, overriding the entrypoint so we can invoke
# arbitrary binaries (the default entrypoint is `pi`).
run_in_image() {
  # Args: <extra docker args...> -- <cmd> [args...]
  local docker_args=()
  while [ "$#" -gt 0 ] && [ "$1" != "--" ]; do
    docker_args+=("$1"); shift
  done
  shift  # drop the --
  docker run --rm --entrypoint "" \
    "${docker_args[@]}" \
    "$IMAGE" "$@"
}

check_tool() {
  local tool="$1"; shift
  local out
  if out=$(run_in_image -- "$tool" "$@" 2>&1); then
    ok "$tool available ($(printf '%s' "$out" | head -n1))"
  else
    bad "$tool not runnable: $out"
  fi
}

check_workspace_writable() {
  # Mount a temp dir at /workspace and try to write to it as the host user.
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  if run_in_image \
       -v "$tmp:/workspace" \
       --user "$HOST_UID:$HOST_GID" \
       -- sh -c 'echo hello > /workspace/smoke.txt && cat /workspace/smoke.txt' \
       | grep -q '^hello$'; then
    ok "/workspace is writable as $HOST_UID:$HOST_GID"
  else
    bad "/workspace is NOT writable as $HOST_UID:$HOST_GID"
  fi
}

check_skills_readonly() {
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  # Mount read-only and assert writes fail.
  if run_in_image \
       -v "$tmp:/home/node/.agents/skills:ro" \
       --user "$HOST_UID:$HOST_GID" \
       -- sh -c 'echo x > /home/node/.agents/skills/should-fail 2>/dev/null' ; then
    bad "skills mount is writable (expected read-only)"
  else
    ok "skills mount is read-only"
  fi
}

check_user_mapping() {
  local actual_uid actual_gid
  actual_uid=$(run_in_image --user "$HOST_UID:$HOST_GID" -- id -u)
  actual_gid=$(run_in_image --user "$HOST_UID:$HOST_GID" -- id -g)
  if [ "$actual_uid" = "$HOST_UID" ] && [ "$actual_gid" = "$HOST_GID" ]; then
    ok "container runs as $actual_uid:$actual_gid (matches requested $HOST_UID:$HOST_GID)"
  else
    bad "container uid:gid = $actual_uid:$actual_gid, expected $HOST_UID:$HOST_GID"
  fi
}

check_pi_data_writable() {
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  if run_in_image \
       -v "$tmp:/home/node/.pi" \
       --user "$HOST_UID:$HOST_GID" \
       -- sh -c 'echo ok > /home/node/.pi/smoke && cat /home/node/.pi/smoke' \
       | grep -q '^ok$'; then
    ok "/home/node/.pi is writable as $HOST_UID:$HOST_GID"
  else
    bad "/home/node/.pi is NOT writable as $HOST_UID:$HOST_GID"
  fi
}

main() {
  ensure_image

  log "Checking toolchain availability..."
  check_tool pi --version
  check_tool uv --version
  check_tool gh --version
  check_tool git --version
  check_tool node --version

  log "Checking mount semantics..."
  check_workspace_writable
  check_skills_readonly
  check_pi_data_writable

  log "Checking user mapping..."
  check_user_mapping

  echo
  log "Summary: $pass passed, $fail failed"
  for r in "${results[@]}"; do printf '  %s\n' "$r"; done

  [ "$fail" -eq 0 ]
}

main "$@"
