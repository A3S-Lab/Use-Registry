# A3S Use Registry

The official signed package Registry deployment for
[A3S Use](https://github.com/A3S-Lab/Use).

> **Status:** dev-preview bootstrap. The tree under `registry/` is signed by
> the development custody key set and is verified end to end by the released
> client, but it is **not** a production trust root. Production bootstrap
> material is added only after the custody, rotation, expiry, withdrawal,
> mirror-replacement, and recovery procedures in the
> [A3S Use roadmap](https://github.com/A3S-Lab/Use/blob/main/ROADMAP.md) are
> implemented and reviewed.

## Bootstrap pin

| Item | Value |
| --- | --- |
| Bootstrap root SHA-256 | `sha256:068207b2a075ab53e4a633084637169deee05a2fce33eb0362a870f5462b3d8a` |
| Root version | 1 |
| Metadata version | 1 |
| Served path | `registry/` on `main` |

Clients consume this Registry through the pinned digest, never through the
transport. Use a Use **package-manager** build (`0.3.x+` with `registry`
routes). Homebrew capability wrappers (`0.1.x`) do not implement Registry
consumption.

```bash
# Prefer an explicit package-manager binary when PATH has a capability wrapper.
export A3S_USE_BIN=/path/to/a3s-use   # crates/use target/debug/a3s-use

"$A3S_USE_BIN" registry source add official \
  --github A3S-Lab/Use-Registry \
  --trust-root sha256:068207b2a075ab53e4a633084637169deee05a2fce33eb0362a870f5462b3d8a \
  --json
```

Architecture (transport vs trust, ownership): 
[docs/registry-service-architecture.md](docs/registry-service-architecture.md).

## Admitted packages

| Package | Version | Surfaces |
| --- | --- | --- |
| `a3s/registry-selftest` | 0.1.0 | Skill |

## Ownership boundary

This repository owns reviewed admission records (`admissions.acl`), committed
package sources for admitted releases (`packages/`), and the signed static
publication state (`registry/`).

It does not own:

- the package manager, Registry formats, or authoring and verification tools;
  those belong to A3S Use (`crates/registry-tools` on Use `main`, binary
  `a3s-use-registry-tools`);
- package source code for third-party packages; those stay in their owning
  repositories and are admitted as reviewed release artifacts;
- consumer installation authority; each A3S Use installation owns its selected
  source, independently obtained bootstrap-root digest, reviewed plan, Grants,
  and activation state.

## Trust model

GitHub is a transport and review surface, not a trust root. A client must pin
an independently obtained SHA-256 digest for the initial TUF root and must
verify the complete metadata chain and target digests before installation.
Repository renames, redirects, branches, and Git history do not grant trust
authority.

Operators: see [docs/operators.md](docs/operators.md) for custody,
publication, expiry, rotation, withdrawal, and incident procedures.

## Local serve (dev-preview transport)

To start a stable local HTTP transport for the committed `registry/` tree
(no Docker):

```bash
./scripts/serve_local.sh start
./scripts/smoke_local.sh
# optional: prove Use package-manager consume (needs A3S_USE_BIN with registry routes)
./scripts/consume_local.sh
# first-principles gate (ephemeral port; needs A3S_USE_BIN for I1/I5)
./scripts/test_local_registry.sh
```

Default base URL: `http://127.0.0.1:4873/`. Point a Use **package-manager**
client (`0.3.x+`) with `--url` and the same bootstrap `--trust-root` pin above.
Homebrew capability wrappers without `registry` routes cannot consume this
tree. Full recipe: [docs/local-serve.md](docs/local-serve.md).
