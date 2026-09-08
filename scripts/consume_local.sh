#!/usr/bin/env bash
# Prove an a3s-use package-manager client can consume the local registry.
#
# Requires a Use binary that exposes `registry` / `plugin` routes (for example
# crates/use target/debug/a3s-use 0.3.x). Homebrew a3s-use 0.1.x capability
# wrappers do not implement Registry routes.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXPECTED_ROOT="${A3S_USE_REGISTRY_EXPECTED_ROOT:-sha256:068207b2a075ab53e4a633084637169deee05a2fce33eb0362a870f5462b3d8a}"
PACKAGE_ID="${A3S_USE_REGISTRY_PACKAGE_ID:-a3s/registry-selftest}"
SOURCE_NAME="${A3S_USE_REGISTRY_SOURCE_NAME:-local}"
USE_BIN="${A3S_USE_BIN:-}"

supports_registry() {
  local bin="$1"
  [[ -x "${bin}" ]] || return 1
  "${bin}" registry source list --json >/dev/null 2>&1
}

resolve_use_bin() {
  if [[ -n "${USE_BIN}" ]]; then
    printf '%s\n' "${USE_BIN}"
    return 0
  fi
  local candidate
  for candidate in \
    "${ROOT_DIR}/../crates/use/target/debug/a3s-use" \
    "${ROOT_DIR}/../crates/use/target/release/a3s-use"; do
    if supports_registry "${candidate}"; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  done
  if command -v a3s-use >/dev/null 2>&1 && supports_registry "$(command -v a3s-use)"; then
    command -v a3s-use
    return 0
  fi
  echo "error: set A3S_USE_BIN to an a3s-use package-manager binary with registry routes" >&2
  echo "hint: from crates/use run 'cargo build -p a3s-use', then export A3S_USE_BIN=\$PWD/target/debug/a3s-use" >&2
  echo "note: Homebrew a3s-use capability wrappers (0.1.x) do not expose registry routes" >&2
  exit 1
}

USE_BIN="$(resolve_use_bin)"
if ! "${USE_BIN}" registry source list --json >/dev/null 2>&1; then
  echo "error: '${USE_BIN}' does not support 'registry source' (capability wrappers are insufficient)" >&2
  exit 1
fi

if ! "${ROOT_DIR}/scripts/serve_local.sh" status >/dev/null 2>&1; then
  "${ROOT_DIR}/scripts/serve_local.sh" start
fi
URL="$("${ROOT_DIR}/scripts/serve_local.sh" url)"

HOME_TMP=""
CLEANUP_HOME=0
if [[ "${A3S_USE_REGISTRY_KEEP_HOME:-0}" == "1" && -n "${A3S_USE_HOME:-}" ]]; then
  HOME_TMP="${A3S_USE_HOME}"
else
  HOME_TMP="$(mktemp -d "${TMPDIR:-/tmp}/a3s-use-registry-consume.XXXXXX")"
  CLEANUP_HOME=1
fi
export A3S_USE_HOME="${HOME_TMP}"

cleanup() {
  if [[ "${CLEANUP_HOME}" -eq 1 ]]; then
    rm -rf "${HOME_TMP}"
  fi
}
trap cleanup EXIT

"${USE_BIN}" registry source add "${SOURCE_NAME}" \
  --url "${URL}" \
  --trust-root "${EXPECTED_ROOT}" \
  --json >/dev/null

PLAN_OUT="$("${USE_BIN}" plugin plan-install "${PACKAGE_ID}" \
  --registry-name "${SOURCE_NAME}" \
  --json)"

echo "${PLAN_OUT}" | python3 -c '
import json, sys
payload = json.load(sys.stdin)
if not payload.get("ok"):
    raise SystemExit(f"plan-install failed: {payload}")
data = payload["data"]
lock = data["plan"]["packageLock"]["packages"][0]["catalog"]["provenance"]
url = lock["registryUrl"]
root = lock["rootSha256"]
pkg = data["packageId"]
print(f"ok consume package={pkg} registry_url={url} root={root} home={sys.argv[1]}")
' "${HOME_TMP}"
