# Where this code comes from

This repository is a **copy**, made for people who want JevDK and jev-serve without the rest of
the LocalLM Lab SDK. Both tools are maintained as examples in
[ancientcomputing/locallm](https://github.com/ancientcomputing/locallm):

| Here | Source of truth |
|---|---|
| `jevdk/` | `examples/jevdk/` |
| `jev-serve/` | `examples/jev-serve/` |
| `NOTICE` | `NOTICE` |

They're copied unchanged with `scripts/sync-jevdk-repo.sh` in that repo, so a fix belongs there
(issues and pull requests welcome on either repo; we carry them over). Only this repository's own
files are edited here: `README.md`, `SOURCE.md`, `.gitignore` and `scripts/`.

Releases (the JevDK DMG and the jev-serve zip) are built from this repository with
`scripts/release.sh`.
