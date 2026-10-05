# Where this code comes from

This repository is a **copy**, made for people who want JevDK and jev-serve without the rest of
the LocalLM Lab SDK. Both tools are maintained as examples in
[ancientcomputing/locallm](https://github.com/ancientcomputing/locallm):

| Here | Source of truth |
|---|---|
| `jevdk/` | `examples/jevdk/` |
| `jev-serve/` | `examples/jev-serve/` |
| `NOTICE` | `NOTICE` |

They're copied with `scripts/sync-jevdk-repo.sh` in that repo, so a fix belongs there
(issues and pull requests welcome on either repo; we carry them over). Only this repository's own
files are edited here: `README.md`, `SOURCE.md`, `.gitignore` and `scripts/`.

One thing differs on purpose: **the SDK version**. The examples in ancientcomputing/locallm follow
the SDK's releases closely; this repository stays on the SDK's main x.0.0 releases, and moves to a
newer one only when it brings something these tools need. The sync keeps this repository's
`defaultSDKVersion` in `jevdk/Package.swift` unless it's told to change it. To try a newer SDK
yourself, set `LOCALLM_SDK_VERSION` (see [README](README.md#source-code)).

Releases (the JevDK DMG and the jev-serve zip) are built from this repository with
`scripts/release.sh`.
