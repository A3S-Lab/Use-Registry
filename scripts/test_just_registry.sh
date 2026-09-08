#!/usr/bin/env bash
# First-principles gate for `just up::registry` and multi-package mock pubs.
#
# Mission: the just-started local transport (and ephemeral mock trees served
# the same way) are startable, byte-faithful, and consumable only under the
# pinned trust root — never because of the URL or just recipe name.
#
# Track J — just up::registry (committed Use-Registry tree)
#   J1 just up::registry becomes honestly ready
#   J2 smoke: served root == disk root == bootstrap pin
#   J3 consume selftest plan-install provenance == URL+root
#   J4 just down::registry clears readiness
#   J5 wrong trust-root fails closed against the just-served URL
#
# Track M — mocked multi-package publication (alpha, beta, echo, compose)
#   M1 assemble+verify four mock packages
#   M2 serve mock tree via A3S_USE_REGISTRY_DIR (same serve_local)
#   M3 smoke both skill archives + tool planning target
#   M4 plan-install alpha and beta with matching provenance
#   M5 unknown package fails plan
#   M6 wrong trust-root fails against mock URL
#   M7 stop clears mock readiness
#
# Track C — OKF + Skill + Tool + UI + MCP cooperation (a3s/mock-compose)
#   C1 catalog surfaces include tool/mcp/okf/skill/ui with skill requires
#   C2 planning target covers tool + mcp executables
#   C3 plan-install compose provenance
#   C4 skill/ui require edges present in plan catalog
#   C5 broken requires_tool (missing id) fails assemble
#
# Requires (from monorepo): just, python3, curl; A3S_USE_BIN (0.3.x+);
# A3S_USE_REGISTRY_TOOLS_BIN or a built a3s-use-registry-tools.
set -euo pipefail

REGISTRY_REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MONOREPO="$(cd "${REGISTRY_REPO}/.." && pwd)"
SERVE="${REGISTRY_REPO}/scripts/serve_local.sh"
SMOKE="${REGISTRY_REPO}/scripts/smoke_local.sh"
ASSEMBLE_MOCK="${REGISTRY_REPO}/scripts/assemble_mock_registry.sh"
COMMITTED_ROOT="${A3S_USE_REGISTRY_EXPECTED_ROOT:-sha256:068207b2a075ab53e4a633084637169deee05a2fce33eb0362a870f5462b3d8a}"

PASS=0
FAIL=0
SKIP=0

WORK="$(mktemp -d "${TMPDIR:-/tmp}/a3s-just-registry-gate.XXXXXX")"
JUST_PORT="$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()')"
MOCK_PORT="$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()')"
JUST_STATE="${WORK}/just-serve"
MOCK_STATE="${WORK}/mock-serve"
MOCK_ROOT="${WORK}/mock-pub"

cleanup() {
  (
    export A3S_USE_REGISTRY_STATE_DIR="${JUST_STATE}"
    export A3S_USE_REGISTRY_PORT="${JUST_PORT}"
    "${SERVE}" stop >/dev/null 2>&1 || true
  )
  (
    export A3S_USE_REGISTRY_STATE_DIR="${MOCK_STATE}"
    export A3S_USE_REGISTRY_PORT="${MOCK_PORT}"
    "${SERVE}" stop >/dev/null 2>&1 || true
  )
  # Prefer just down when the recipe owns the process; ignore failures.
  (
    cd "${MONOREPO}"
    export A3S_USE_REGISTRY_STATE_DIR="${JUST_STATE}"
    export A3S_USE_REGISTRY_PORT="${JUST_PORT}"
    just down::registry >/dev/null 2>&1 || true
  )
  rm -rf "${WORK}"
}
trap cleanup EXIT

pass() { PASS=$((PASS + 1)); printf 'PASS  %s\n' "$1"; }
fail() {
  FAIL=$((FAIL + 1))
  printf 'FAIL  %s\n' "$1" >&2
  [[ -n "${2:-}" ]] && printf '  %s\n' "$2" >&2
}
skip() {
  SKIP=$((SKIP + 1))
  printf 'SKIP  %s\n' "$1"
  [[ -n "${2:-}" ]] && printf '  %s\n' "$2"
}

assert_ok() {
  local label="$1"
  shift
  local out ec=0
  set +e
  out="$("$@" 2>&1)"
  ec=$?
  set -e
  if [[ "${ec}" -eq 0 ]]; then
    pass "${label}"
  else
    fail "${label}" "exit=${ec} output=${out}"
  fi
}

assert_fails() {
  local label="$1"
  shift
  local out ec=0
  set +e
  out="$("$@" 2>&1)"
  ec=$?
  set -e
  if [[ "${ec}" -ne 0 ]]; then
    pass "${label}"
  else
    fail "${label}" "expected failure, got: ${out}"
  fi
}

resolve_use_bin() {
  if [[ -n "${A3S_USE_BIN:-}" && -x "${A3S_USE_BIN}" ]]; then
    if "${A3S_USE_BIN}" registry source list --json >/dev/null 2>&1; then
      printf '%s\n' "${A3S_USE_BIN}"
      return 0
    fi
  fi
  local candidate
  for candidate in \
    "${MONOREPO}/crates/use/target/debug/a3s-use" \
    "${MONOREPO}/crates/use/target/release/a3s-use"; do
    if [[ -x "${candidate}" ]] && "${candidate}" registry source list --json >/dev/null 2>&1; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  done
  return 1
}

plan_install() {
  local home="$1" url="$2" root="$3" package="$4" source_name="$5"
  export A3S_USE_HOME="${home}"
  "${USE_BIN}" registry source add "${source_name}" \
    --url "${url}" \
    --trust-root "${root}" \
    --json >/dev/null
  "${USE_BIN}" plugin plan-install "${package}" \
    --registry-name "${source_name}" \
    --scope-kind user \
    --scope-id "user/registry-gate" \
    --json
}

check_plan_provenance() {
  local plan_json="$1" expected_url="$2" expected_root="$3" expected_pkg="$4"
  EXPECTED_URL="${expected_url}" EXPECTED_ROOT="${expected_root}" EXPECTED_PKG="${expected_pkg}" \
    PLAN_JSON="${plan_json}" python3 -c '
import json, os, sys
payload = json.loads(os.environ["PLAN_JSON"])
if not payload.get("ok"):
    raise SystemExit(f"plan failed: {payload}")
data = payload["data"]
prov = data["plan"]["packageLock"]["packages"][0]["catalog"]["provenance"]
url = prov["registryUrl"].rstrip("/") + "/"
root = prov["rootSha256"]
if not root.startswith("sha256:"):
    root = "sha256:" + root
exp_url = os.environ["EXPECTED_URL"].rstrip("/") + "/"
exp_root = os.environ["EXPECTED_ROOT"]
if not exp_root.startswith("sha256:"):
    exp_root = "sha256:" + exp_root
if url != exp_url:
    raise SystemExit(f"url mismatch {url!r} != {exp_url!r}")
if root != exp_root:
    raise SystemExit(f"root mismatch {root!r} != {exp_root!r}")
if data["packageId"] != os.environ["EXPECTED_PKG"]:
    raise SystemExit(f"package mismatch {data['packageId']!r}")
'
}

printf 'just-registry first-principles gate\n'
printf 'monorepo=%s just_port=%s mock_port=%s\n' "${MONOREPO}" "${JUST_PORT}" "${MOCK_PORT}"

# --- Track J: just up::registry ------------------------------------------------
export A3S_USE_REGISTRY_HOST=127.0.0.1
export A3S_USE_REGISTRY_PORT="${JUST_PORT}"
export A3S_USE_REGISTRY_STATE_DIR="${JUST_STATE}"
unset A3S_USE_REGISTRY_DIR || true
export A3S_USE_REGISTRY_EXPECTED_ROOT="${COMMITTED_ROOT}"

assert_fails "J4 status fails before just up" env \
  A3S_USE_REGISTRY_PORT="${JUST_PORT}" \
  A3S_USE_REGISTRY_STATE_DIR="${JUST_STATE}" \
  "${SERVE}" status

(
  cd "${MONOREPO}"
  export A3S_USE_REGISTRY_HOST=127.0.0.1
  export A3S_USE_REGISTRY_PORT="${JUST_PORT}"
  export A3S_USE_REGISTRY_STATE_DIR="${JUST_STATE}"
  just up::registry
) >/dev/null
assert_ok "J1 just up::registry status ready" env \
  A3S_USE_REGISTRY_PORT="${JUST_PORT}" \
  A3S_USE_REGISTRY_STATE_DIR="${JUST_STATE}" \
  "${SERVE}" status

JUST_URL="$(
  A3S_USE_REGISTRY_PORT="${JUST_PORT}" \
  A3S_USE_REGISTRY_STATE_DIR="${JUST_STATE}" \
  "${SERVE}" url
)"
case "${JUST_URL}" in
  http://127.0.0.1:"${JUST_PORT}"/) pass "J1 just url shape ${JUST_URL}" ;;
  *) fail "J1 just url shape" "got ${JUST_URL}" ;;
esac

assert_ok "J2 smoke committed tree via just transport" env \
  A3S_USE_REGISTRY_EXPECTED_ROOT="${COMMITTED_ROOT}" \
  A3S_USE_REGISTRY_DIR="${REGISTRY_REPO}/registry" \
  "${SMOKE}" "${JUST_URL}"

USE_BIN=""
if USE_BIN="$(resolve_use_bin)"; then
  export A3S_USE_BIN="${USE_BIN}"
  HOME_J="$(mktemp -d "${WORK}/home-just.XXXXXX")"
  set +e
  PLAN_J="$(plan_install "${HOME_J}" "${JUST_URL}" "${COMMITTED_ROOT}" "a3s/registry-selftest" "just-local" 2>&1)"
  PLAN_J_EC=$?
  set -e
  if [[ "${PLAN_J_EC}" -eq 0 ]] && check_plan_provenance "${PLAN_J}" "${JUST_URL}" "${COMMITTED_ROOT}" "a3s/registry-selftest"; then
    pass "J3 consume selftest provenance"
  else
    fail "J3 consume selftest provenance" "ec=${PLAN_J_EC} out=${PLAN_J}"
  fi

  HOME_JBAD="$(mktemp -d "${WORK}/home-just-bad.XXXXXX")"
  set +e
  BAD_J="$(plan_install "${HOME_JBAD}" "${JUST_URL}" \
    "sha256:0000000000000000000000000000000000000000000000000000000000000000" \
    "a3s/registry-selftest" "just-bad" 2>&1)"
  BAD_J_EC=$?
  set -e
  if [[ "${BAD_J_EC}" -ne 0 ]]; then
    pass "J5 wrong trust-root fails on just URL"
  else
    fail "J5 wrong trust-root fails on just URL" "${BAD_J}"
  fi
else
  skip "J3 consume selftest provenance" "set A3S_USE_BIN"
  skip "J5 wrong trust-root fails on just URL" "requires A3S_USE_BIN"
fi

(
  cd "${MONOREPO}"
  export A3S_USE_REGISTRY_PORT="${JUST_PORT}"
  export A3S_USE_REGISTRY_STATE_DIR="${JUST_STATE}"
  just down::registry
) >/dev/null
assert_fails "J4 just down::registry clears readiness" env \
  A3S_USE_REGISTRY_PORT="${JUST_PORT}" \
  A3S_USE_REGISTRY_STATE_DIR="${JUST_STATE}" \
  "${SERVE}" status

# --- Track M: mock multi-package tree ----------------------------------------
chmod +x "${ASSEMBLE_MOCK}"
MOCK_META="$("${ASSEMBLE_MOCK}" "${MOCK_ROOT}")"
MOCK_SHA="$(printf '%s\n' "${MOCK_META}" | python3 -c 'import json,sys; print(json.load(sys.stdin)["rootSha256"])')"
MOCK_DIR="$(printf '%s\n' "${MOCK_META}" | python3 -c 'import json,sys; print(json.load(sys.stdin)["registry"])')"
PKG_COUNT="$(printf '%s\n' "${MOCK_META}" | python3 -c 'import json,sys; print(len(json.load(sys.stdin)["packages"]))')"
if [[ "${PKG_COUNT}" -eq 4 && -f "${MOCK_DIR}/metadata/root.json" ]]; then
  pass "M1 assemble+verify four mock packages"
else
  fail "M1 assemble+verify four mock packages" "${MOCK_META}"
fi

export A3S_USE_REGISTRY_DIR="${MOCK_DIR}"
export A3S_USE_REGISTRY_PORT="${MOCK_PORT}"
export A3S_USE_REGISTRY_STATE_DIR="${MOCK_STATE}"
export A3S_USE_REGISTRY_EXPECTED_ROOT="${MOCK_SHA}"
export A3S_USE_REGISTRY_SMOKE_TARGET="targets/extensions/a3s/mock-alpha/0.1.0/stable/any/a3s-mock-alpha-0.1.0-any.tar.gz"

assert_ok "M2 start mock registry transport" "${SERVE}" start
MOCK_URL="$("${SERVE}" url)"

assert_ok "M3 smoke mock-alpha target" "${SMOKE}" "${MOCK_URL}"
assert_ok "M3 download mock-beta archive" curl -fsS \
  "${MOCK_URL}targets/extensions/a3s/mock-beta/0.1.0/stable/any/a3s-mock-beta-0.1.0-any.tar.gz" \
  -o "${WORK}/mock-beta.tar.gz"
assert_ok "M3 download mock-echo planning target" curl -fsS \
  "${MOCK_URL}targets/extensions/a3s/mock-echo/0.1.0/stable/any/planning-v1.json" \
  -o "${WORK}/mock-echo-planning.json"
assert_ok "C2 download mock-compose archive" curl -fsS \
  "${MOCK_URL}targets/extensions/a3s/mock-compose/0.1.0/stable/any/a3s-mock-compose-0.1.0-any.tar.gz" \
  -o "${WORK}/mock-compose.tar.gz"
assert_ok "C2 download mock-compose planning target" curl -fsS \
  "${MOCK_URL}targets/extensions/a3s/mock-compose/0.1.0/stable/any/planning-v1.json" \
  -o "${WORK}/mock-compose-planning.json"

# Planning bundle must list both executable surfaces used by Skill/UI binds.
set +e
PLANNING_CHECK="$(
  COMPOSE_PLANNING="${WORK}/mock-compose-planning.json" python3 - <<'PY'
import json, os, sys
bundle = json.load(open(os.environ["COMPOSE_PLANNING"]))
kinds = {s.get("kind") for s in bundle.get("surfaces", [])}
ids = {s.get("id") for s in bundle.get("surfaces", [])}
need_kinds = {"tool-task-native", "mcp-stdio"}
need_ids = {"echo", "context"}
missing_kinds = need_kinds - kinds
missing_ids = need_ids - ids
if missing_kinds or missing_ids:
    print(f"kinds={sorted(kinds)} missing_kinds={sorted(missing_kinds)} ids={sorted(ids)} missing_ids={sorted(missing_ids)}")
    sys.exit(1)
print("ok")
PY
)"
PLANNING_EC=$?
set -e
if [[ "${PLANNING_EC}" -eq 0 ]]; then
  pass "C2 planning covers tool+mcp executables"
else
  fail "C2 planning covers tool+mcp executables" "${PLANNING_CHECK}"
fi

if [[ -n "${USE_BIN}" ]]; then
  HOME_MA="$(mktemp -d "${WORK}/home-alpha.XXXXXX")"
  set +e
  PLAN_A="$(plan_install "${HOME_MA}" "${MOCK_URL}" "${MOCK_SHA}" "a3s/mock-alpha" "mock" 2>&1)"
  PLAN_A_EC=$?
  set -e
  if [[ "${PLAN_A_EC}" -eq 0 ]] && check_plan_provenance "${PLAN_A}" "${MOCK_URL}" "${MOCK_SHA}" "a3s/mock-alpha"; then
    pass "M4 plan-install mock-alpha provenance"
  else
    fail "M4 plan-install mock-alpha provenance" "ec=${PLAN_A_EC} out=${PLAN_A}"
  fi

  # Same home/source: second package must resolve without re-adding.
  set +e
  PLAN_B="$(
    A3S_USE_HOME="${HOME_MA}" "${USE_BIN}" plugin plan-install a3s/mock-beta \
      --registry-name mock \
      --scope-kind user \
      --scope-id user/registry-gate \
      --json 2>&1
  )"
  PLAN_B_EC=$?
  set -e
  if [[ "${PLAN_B_EC}" -eq 0 ]] && check_plan_provenance "${PLAN_B}" "${MOCK_URL}" "${MOCK_SHA}" "a3s/mock-beta"; then
    pass "M4 plan-install mock-beta provenance"
  else
    fail "M4 plan-install mock-beta provenance" "ec=${PLAN_B_EC} out=${PLAN_B}"
  fi

  set +e
  PLAN_C="$(
    A3S_USE_HOME="${HOME_MA}" "${USE_BIN}" plugin plan-install a3s/mock-compose \
      --registry-name mock \
      --scope-kind user \
      --scope-id user/registry-gate \
      --json 2>&1
  )"
  PLAN_C_EC=$?
  set -e
  if [[ "${PLAN_C_EC}" -eq 0 ]] && check_plan_provenance "${PLAN_C}" "${MOCK_URL}" "${MOCK_SHA}" "a3s/mock-compose"; then
    pass "C3 plan-install mock-compose provenance"
  else
    fail "C3 plan-install mock-compose provenance" "ec=${PLAN_C_EC} out=${PLAN_C}"
  fi

  set +e
  COMPOSE_SURFACES="$(
    PLAN_JSON="${PLAN_C}" python3 - <<'PY'
import json, os, sys
payload = json.loads(os.environ["PLAN_JSON"])
if not payload.get("ok"):
    raise SystemExit("plan not ok")
catalog = payload["data"]["plan"]["packageLock"]["packages"][0]["catalog"]
surfaces = catalog.get("surfaces") or catalog.get("record", {}).get("surfaces") or []
# catalog may be nested under record depending on lock shape
if not surfaces and isinstance(catalog, dict):
    for key in ("surfaces",):
        if key in catalog:
            surfaces = catalog[key]
kinds = {s.get("kind") for s in surfaces}
ids = {(s.get("kind"), s.get("id")) for s in surfaces}
need = {
    ("tool", "echo"),
    ("mcp", "context"),
    ("okf", "domain"),
    ("skill", "compose"),
    ("ui", "compose"),
}
missing = need - ids
if missing:
    raise SystemExit(f"missing surfaces {sorted(missing)}; have {sorted(ids)}")
skill = next(s for s in surfaces if s.get("kind") == "skill" and s.get("id") == "compose")
requires = {(r.get("kind"), r.get("id")) for r in skill.get("requires", [])}
need_req = {("tool", "echo"), ("mcp", "context"), ("okf", "domain")}
missing_req = need_req - requires
if missing_req:
    raise SystemExit(f"skill missing requires {sorted(missing_req)}; have {sorted(requires)}")
print("ok")
PY
  )"
  COMPOSE_SURFACES_EC=$?
  set -e
  if [[ "${COMPOSE_SURFACES_EC}" -eq 0 ]]; then
    pass "C1/C4 compose surfaces + skill requires"
  else
    fail "C1/C4 compose surfaces + skill requires" "${COMPOSE_SURFACES} plan=${PLAN_C}"
  fi

  set +e
  PLAN_MISS="$(
    A3S_USE_HOME="${HOME_MA}" "${USE_BIN}" plugin plan-install a3s/does-not-exist \
      --registry-name mock \
      --scope-kind user \
      --scope-id user/registry-gate \
      --json 2>&1
  )"
  PLAN_MISS_EC=$?
  set -e
  if [[ "${PLAN_MISS_EC}" -ne 0 ]]; then
    pass "M5 unknown package fails plan"
  else
    fail "M5 unknown package fails plan" "${PLAN_MISS}"
  fi

  HOME_MBAD="$(mktemp -d "${WORK}/home-mock-bad.XXXXXX")"
  set +e
  BAD_M="$(plan_install "${HOME_MBAD}" "${MOCK_URL}" \
    "sha256:0000000000000000000000000000000000000000000000000000000000000000" \
    "a3s/mock-alpha" "mock-bad" 2>&1)"
  BAD_M_EC=$?
  set -e
  if [[ "${BAD_M_EC}" -ne 0 ]]; then
    pass "M6 wrong trust-root fails on mock URL"
  else
    fail "M6 wrong trust-root fails on mock URL" "${BAD_M}"
  fi
else
  skip "M4 plan-install mock-alpha provenance" "requires A3S_USE_BIN"
  skip "M4 plan-install mock-beta provenance" "requires A3S_USE_BIN"
  skip "C3 plan-install mock-compose provenance" "requires A3S_USE_BIN"
  skip "C1/C4 compose surfaces + skill requires" "requires A3S_USE_BIN"
  skip "M5 unknown package fails plan" "requires A3S_USE_BIN"
  skip "M6 wrong trust-root fails on mock URL" "requires A3S_USE_BIN"
fi

# C5: Skill requires a tool id that does not exist in the package → assemble fails.
BROKEN="${WORK}/broken-compose"
mkdir -p "${BROKEN}/packages/broken/skills/x"
cp -R "${MOCK_ROOT}/packages/mock-compose/." "${BROKEN}/packages/broken/" 2>/dev/null || true
# Rebuild a minimal broken skill-only-requires-missing-tool package
rm -rf "${BROKEN}"
mkdir -p "${BROKEN}/packages/broken/skills/x"
cat >"${BROKEN}/packages/broken/a3s-use-extension.acl" <<'EOF'
extension "a3s/mock-broken" {
  schema_version = 3
  version        = "0.1.0"
  route          = "mock-broken"
  requires_use   = ">=0.3.0, <0.4.0"
  actions        = ["read"]

  repository {
    url      = "https://github.com/A3S-Lab/Use-Registry"
    revision = "0123456789abcdef0123456789abcdef01234567"
  }

  skill "broken" {
    path          = "skills/x/SKILL.md"
    requires_tool = ["does-not-exist"]
    requires_mcp  = []
    requires_okf  = []
    optional      = false
  }
}
EOF
echo '# broken' >"${BROKEN}/packages/broken/skills/x/SKILL.md"
echo '# broken' >"${BROKEN}/packages/broken/README.md"
cat >"${BROKEN}/admissions.acl" <<'EOF'
admission "a3s/mock-broken" {
  package_directory = "packages/broken"
  channel           = "stable"
  target            = "any"
  display_name      = "Mock Broken"
  description       = "Skill requires a missing tool id."
  license           = "Apache-2.0"
  keywords          = ["mock"]
  categories        = ["testing"]
}
EOF
TOOLS_BIN="${A3S_USE_REGISTRY_TOOLS_BIN:-}"
if [[ -z "${TOOLS_BIN}" || ! -x "${TOOLS_BIN}" ]]; then
  for candidate in \
    "${MONOREPO}/crates/use/target/release/a3s-use-registry-tools" \
    "${MONOREPO}/crates/use/target/debug/a3s-use-registry-tools"; do
    if [[ -x "${candidate}" ]]; then
      TOOLS_BIN="${candidate}"
      break
    fi
  done
fi
if [[ -n "${TOOLS_BIN}" ]]; then
  "${TOOLS_BIN}" keygen --keys-dir "${BROKEN}/keys" >/dev/null
  set +e
  BROKEN_OUT="$("${TOOLS_BIN}" assemble \
    --keys-dir "${BROKEN}/keys" \
    --admissions "${BROKEN}/admissions.acl" \
    --out-root "${BROKEN}/registry" 2>&1)"
  BROKEN_EC=$?
  set -e
  if [[ "${BROKEN_EC}" -ne 0 ]]; then
    pass "C5 broken skill requires_tool fails assemble"
  else
    fail "C5 broken skill requires_tool fails assemble" "${BROKEN_OUT}"
  fi
else
  skip "C5 broken skill requires_tool fails assemble" "registry-tools missing"
fi

assert_ok "M7 stop mock transport" "${SERVE}" stop
assert_fails "M7 status fails after mock stop" "${SERVE}" status

printf '\nsummary pass=%s fail=%s skip=%s\n' "${PASS}" "${FAIL}" "${SKIP}"
if [[ "${FAIL}" -ne 0 ]]; then
  exit 1
fi
