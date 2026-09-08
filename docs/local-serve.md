# Local registry serve

Status: development preview. This is a **local transport** for the committed
signed tree under `registry/`. It does not change the bootstrap trust root.

## Start / stop / status

From this repository root:

```bash
chmod +x scripts/*.sh   # once
./scripts/serve_local.sh start
./scripts/serve_local.sh status
./scripts/smoke_local.sh
./scripts/consume_local.sh
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

`serve_local.sh start` keeps a background `python3 -m http.server` process
bound to the configured host/port, records a PID file, and refuses to return
until `metadata/root.json` is reachable. Re-running `start` is idempotent while
that PID remains healthy.

## Client binary requirement

Consuming the Registry requires the **A3S Use package manager** CLI (`registry`
and `plugin` routes), for example Use `0.3.x` built from
[A3S-Lab/Use](https://github.com/A3S-Lab/Use).

Homebrew `a3s-use` **capability wrappers** (currently `0.1.x`: browser / box /
office routes only) answer `Unknown Use route 'registry'` and cannot consume
this tree. Point `A3S_USE_BIN` at a package-manager build:

```bash
# from the Use checkout
cargo build -p a3s-use
export A3S_USE_BIN="$PWD/target/debug/a3s-use"
```

## Point a client at the local source

Trust is still the bootstrap root digest from the README. Transport is the
local URL:

```bash
ROOT=sha256:068207b2a075ab53e4a633084637169deee05a2fce33eb0362a870f5462b3d8a
URL="$(./scripts/serve_local.sh url)"

"$A3S_USE_BIN" registry source add local \
  --url "${URL}" \
  --trust-root "${ROOT}" \
  --json

"$A3S_USE_BIN" plugin plan-install a3s/registry-selftest \
  --registry-name local \
  --json
```

Or run the bundled consume check (starts the server if needed, uses an
isolated `A3S_USE_HOME`, and proves TUF refresh + catalog resolution):

```bash
export A3S_USE_BIN=/path/to/a3s-use   # package-manager binary
./scripts/consume_local.sh
```

Loopback `http://127.0.0.1/` is allowed by Use as a local transport; HTTPS is
still required for non-loopback URLs. Do not treat GitHub, localhost, or any
other URL as authority. Replace or remove the local source when you are done;
a redirect or hostname change never rotates trust.

## Stability checks

`serve_local.sh start` waits until `GET {base}metadata/root.json` succeeds.
`smoke_local.sh` verifies:

1. root / timestamp / snapshot / targets metadata are reachable
2. served `root.json` SHA-256 matches the bootstrap pin
3. the admitted `a3s/registry-selftest` target artifact downloads
4. served root matches the committed on-disk `registry/metadata/root.json`

`consume_local.sh` additionally verifies the package-manager client can add the
source and `plugin plan-install a3s/registry-selftest` against the live local
URL (TUF refresh + catalog provenance).

For a longer soak, leave the server running and re-run `./scripts/smoke_local.sh`,
`./scripts/serve_local.sh status`, or `./scripts/consume_local.sh` periodically.

## First-principles test gate

Run the automated gate (ephemeral port + isolated state dir):

```bash
export A3S_USE_BIN=/path/to/a3s-use   # Use package-manager 0.3.x
./scripts/test_local_registry.sh
```

| Invariant | Cases |
| --- | --- |
| I1 Transport is not trust | Wrong `--trust-root` fails at `plan-install` |
| I2 Served bytes == committed tree | Smoke root/target match disk + bootstrap pin |
| I3 Ready means our listener | Start/status only after our PID owns the port |
| I4 Lifecycle is deterministic | Status before start fails; start idempotent; stop clears readiness |
| I5 Client consume uses TUF pin | `consume_local.sh` provenance matches URL + root |
| I6 Failures are loud | Smoke fails when stopped; busy foreign port refused |

`serve_local.sh` treats a process as ready only when the recorded PID is alive,
listening on the configured port (via `lsof` when available), and
`metadata/root.json` is reachable. Stale PID files and foreign listeners do not
count as a healthy local registry.
