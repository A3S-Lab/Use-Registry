#!/usr/bin/env bash
# Serve the committed signed registry/ tree as a local static HTTP source.
#
# Trust remains the bootstrap root digest (README). This script only provides
# a stable local transport so clients can use --url instead of --github.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REGISTRY_DIR="${ROOT_DIR}/registry"
STATE_DIR="${A3S_USE_REGISTRY_STATE_DIR:-${ROOT_DIR}/.local/serve}"
HOST="${A3S_USE_REGISTRY_HOST:-127.0.0.1}"
PORT="${A3S_USE_REGISTRY_PORT:-4873}"
PID_FILE="${STATE_DIR}/httpd.pid"
LOG_FILE="${STATE_DIR}/httpd.log"
URL_FILE="${STATE_DIR}/base.url"

usage() {
  cat <<'EOF'
Usage: scripts/serve_local.sh <start|stop|status|url|restart>

Environment:
  A3S_USE_REGISTRY_HOST       Bind address (default: 127.0.0.1)
  A3S_USE_REGISTRY_PORT       Listen port (default: 4873)
  A3S_USE_REGISTRY_STATE_DIR  PID/log directory (default: .local/serve)

The served base URL ends with / and exposes metadata/ and targets/ directly
(matching the GitHub raw registry/ layout clients expect).
EOF
}

require_registry() {
  if [[ ! -f "${REGISTRY_DIR}/metadata/root.json" ]]; then
    echo "error: missing ${REGISTRY_DIR}/metadata/root.json" >&2
    exit 1
  fi
}

base_url() {
  printf 'http://%s:%s/' "${HOST}" "${PORT}"
}

is_running() {
  if [[ ! -f "${PID_FILE}" ]]; then
    return 1
  fi
  local pid
  pid="$(cat "${PID_FILE}")"
  if ! kill -0 "${pid}" 2>/dev/null; then
    return 1
  fi
  return 0
}

cmd_start() {
  require_registry
  mkdir -p "${STATE_DIR}"

  if is_running; then
    echo "already running pid=$(cat "${PID_FILE}") url=$(base_url)"
    exit 0
  fi

  if command -v python3 >/dev/null 2>&1; then
    (
      cd "${REGISTRY_DIR}"
      # Bind explicitly; directory is registry/ so /metadata and /targets map
      # at the URL root (same relative layout as the published registry/ path).
      exec python3 -m http.server "${PORT}" --bind "${HOST}"
    ) >"${LOG_FILE}" 2>&1 &
    echo $! >"${PID_FILE}"
  else
    echo "error: python3 is required to serve the static registry tree" >&2
    exit 1
  fi

  local url
  url="$(base_url)"
  printf '%s\n' "${url}" >"${URL_FILE}"

  # Ready probe: root metadata must be reachable.
  local i
  for i in 1 2 3 4 5 6 7 8 9 10; do
    if curl -fsS "${url}metadata/root.json" >/dev/null 2>&1; then
      echo "started pid=$(cat "${PID_FILE}") url=${url}"
      return 0
    fi
    sleep 0.2
  done

  echo "error: registry started but failed readiness probe; see ${LOG_FILE}" >&2
  cmd_stop || true
  exit 1
}

cmd_stop() {
  if [[ ! -f "${PID_FILE}" ]]; then
    echo "not running"
    return 0
  fi
  local pid
  pid="$(cat "${PID_FILE}")"
  if kill -0 "${pid}" 2>/dev/null; then
    kill "${pid}" 2>/dev/null || true
    local i
    for i in 1 2 3 4 5 6 7 8 9 10; do
      if ! kill -0 "${pid}" 2>/dev/null; then
        break
      fi
      sleep 0.1
    done
    if kill -0 "${pid}" 2>/dev/null; then
      kill -9 "${pid}" 2>/dev/null || true
    fi
  fi
  rm -f "${PID_FILE}"
  echo "stopped"
}

cmd_status() {
  if is_running; then
    local url
    url="$(base_url)"
    if curl -fsS "${url}metadata/root.json" >/dev/null 2>&1; then
      echo "running pid=$(cat "${PID_FILE}") url=${url} ready=1"
      return 0
    fi
    echo "running pid=$(cat "${PID_FILE}") url=${url} ready=0" >&2
    return 1
  fi
  echo "not running"
  return 1
}

cmd_url() {
  printf '%s\n' "$(base_url)"
}

case "${1:-}" in
  start) cmd_start ;;
  stop) cmd_stop ;;
  status) cmd_status ;;
  url) cmd_url ;;
  restart)
    cmd_stop
    cmd_start
    ;;
  *)
    usage
    exit 2
    ;;
esac
