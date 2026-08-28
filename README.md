# A3S Use Registry

The official signed package Registry deployment for
[A3S Use](https://github.com/A3S-Lab/Use).

> **Status:** pre-bootstrap. This repository does not yet publish a production
> trust root or an installable package catalog.

## Ownership boundary

This repository owns reviewed admission records, immutable release artifacts,
software-supply-chain evidence, signed TUF publication state, and Registry
operator procedures.

It does not own:

- the package manager, Registry formats, or authoring and verification tools;
  those belong to A3S Use;
- package source code or package-specific builds; those stay in their owning
  repositories, such as A3S MHS;
- consumer installation authority; each A3S Use installation owns its selected
  source, independently obtained bootstrap-root digest, reviewed plan, Grants,
  and activation state.

## Trust model

GitHub is a transport and review surface, not a trust root. A client must pin an
independently obtained SHA-256 digest for the initial TUF root and must verify
the complete metadata chain and target digests before installation. Repository
renames, redirects, branches, and Git history do not grant trust authority.

The future static Registry will be published below `registry/`. Production
bootstrap material will only be added after the custody, rotation, expiry,
withdrawal, mirror-replacement, and recovery procedures in the
[A3S Use roadmap](https://github.com/A3S-Lab/Use/blob/main/ROADMAP.md) are
implemented and reviewed.
