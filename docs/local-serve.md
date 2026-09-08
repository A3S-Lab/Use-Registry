# Local registry serve

Status: development preview. This is a **local transport** for the committed
signed tree under `registry/`. It does not change the bootstrap trust root.

## Start / stop / status

From this repository root:

```bash
chmod +x scripts/serve_local.sh scripts/smoke_local.sh   # once
./scripts/serve_local.sh start
./scripts/serve_local.sh status
./scripts/smoke_local.sh
./scripts/serve_local.sh stop
```

Defaults:

| Variable | Default |
| --- | --- |
| `A3S_USE_REGISTRY_HOST` | `127.0.0.1` |
| `A3S_USE_REGISTRY_PORT` | `4873` |
| Base URL | `http://127.0.0.1:4873/` |

State (PID, log, recorded URL) lives under `.local/serve/` (gitignored).

Requires `python3` and `curl`. The process serves only the static `registry/`
directory (metadata + targets). No Docker and no a3s-box are required for this
preview transport.

## Point a client at the local source

Trust is still the bootstrap root digest from the README. Transport is the
local URL:

```bash
ROOT=sha256:068207b2a075ab53e4a633084637169deee05a2fce33eb0362a870f5462b3d8a
URL="$(./scripts/serve_local.sh url)"

a3s-use registry source add local \
  --url "${URL}" \
  --trust-root "${ROOT}" \
  --json
```

Do not treat GitHub, localhost, or any other URL as authority. Replace or
remove the local source when you are done; a redirect or hostname change never
rotates trust.

## Stability checks

`serve_local.sh start` waits until `GET {base}metadata/root.json` succeeds.
`smoke_local.sh` verifies:

1. root / timestamp / snapshot / targets metadata are reachable
2. served `root.json` SHA-256 matches the bootstrap pin
3. the admitted `a3s/registry-selftest` target artifact downloads
4. served root matches the committed on-disk `registry/metadata/root.json`

For a longer soak, leave the server running and re-run `./scripts/smoke_local.sh`
or `./scripts/serve_local.sh status` periodically.
