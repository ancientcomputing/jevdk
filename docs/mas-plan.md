# JevDK on the Mac App Store — plan

Status: started 2026-10-14. The sandboxed build runs and was tested on this Mac (`MAS_SIGN=dev`); no store build or upload yet.
Modelled on LocalLM Lab's MAS build (locallmlab `docs/mas-plan.md`), which is in TestFlight.

## Decisions

| Decision | Choice | Consequence |
|---|---|---|
| Bundle ID | **`ai.thisbrain.jevdk`**, separate from the DMG build's `lab.locallm.sdk.reference.jevdk` | Both can be installed together; own Keychain items, own container |
| Minimum OS | macOS 27, Apple silicon | Same as the DMG |
| Price | Free | |
| jev-serve | **Not in the MAS build.** JevDK → **Get jev-serve…** opens https://thisbrain.ai/locallm/jev-serve.html | A sandboxed jev-serve can't run from the PATH (an `inherit`-signed tool only works as the app's child), and the installer's admin AppleScript is forbidden. File → Export Server Config… stays |
| Model cache | The app's container (`~/Library/Containers/ai.thisbrain.jevdk/Data/.cache/huggingface/hub`), not the shared `~/.cache/huggingface` | MAS users re-download models; the DMG build is unchanged |
| Hosted backends | **Ask before turning one on** (guideline 5.1.2(i)): an alert naming the service and what it receives; asked every time it's turned on | MAS build only (`AIDataConsent` in `HostedBackends.swift`) |
| Keychain | MAS items under service `ai.thisbrain.jevdk` (DMG: `JevDK`) | Found in testing: reading the DMG build's `JevDK` items from the sandboxed app made macOS show a Keychain access prompt that hung the app. Keys are re-entered in the MAS app |
| Code changes | `#if MAS_BUILD` in the app target, made in `locallmlab-sdk/examples/jevdk` (the source of truth) and copied here | The DMG build and `swift build` are unchanged |
| Branching | No MAS-only branch; the same tag builds the DMG and the `.pkg` | |

## What's in the repo

- `scripts/build-mas.sh` — archives `JevDK.xcodeproj` (Release, arm64, `SWIFT_ACTIVE_COMPILATION_CONDITIONS=MAS_BUILD`, unsigned), sets the bundle ID, versions, `ITSAppUsesNonExemptEncryption`, copyright and icon, adds `NOTICE` and the privacy manifest, then signs inside-out. `MAS_SIGN=dev` (Apple Development, runs locally) or `MAS_SIGN=store` (Apple Distribution + profile → installer-signed `.pkg`).
- `scripts/mas/JevDK.entitlements` — `app-sandbox`, `network.client`, `files.user-selected.read-write`. No App Group, no helper.
- `scripts/mas/PrivacyInfo.xcprivacy` — no tracking, nothing collected; UserDefaults CA92.1, file timestamps C617.1, disk space E174.1.
- App code (`Sources/JevDK`): `JevDKApp.swift` (menu item, consent on the Backends toggle), `HostedBackends.swift` (`dataRecipient`, `AIDataConsent`), `Keychain.swift` (MAS service name).

## Verified (dev build, 2026-10-14)

- Builds and signs; `codesign --verify --deep --strict` passes; entitlements as above; no jev-serve in the bundle.
- `strings`: "Get jev-serve" and the consent text are in; "Install jev-serve Command" and "administrator privileges" are not.
- Hosted Jev from inside the sandbox: `JevDK --check-remote "Customer support" featherlessDemo` answered all five samples.
- Local models: the app doesn't see `~/.cache/huggingface` (shows "No models found"); Models → Check and Download of `mlx-community/Qwen3-0.6B-4bit` (351 MB) into the container work, and Ask answers on it (MLX/Metal in the sandbox).
- JevDK menu shows "Get jev-serve…" (not the installer).
- Backends: no Keychain prompt after the service-name fix; turning on Featherless demo shows the consent alert — Cancel leaves it off, Allow turns it on.
- The DMG variant (`swift build`, no `MAS_BUILD`) still builds.

## To do

1. **Portal (you):** register App ID `ai.thisbrain.jevdk` (no capabilities needed); Mac App Store provisioning profile for it; App Store Connect record (name "JevDK", primary category Developer Tools); privacy policy and support URLs.
2. `VERSION=1.0.0 MAS_SIGN=store scripts/build-mas.sh` → upload the `.pkg` with Transporter → TestFlight.
3. TestFlight pass on a clean Mac: download Qwen3-4B-4bit, Customer support example, batch, a hosted backend (consent), every save/open panel, Keychain key survives relaunch.
4. Listing: screenshots (2880×1800), description, App Privacy label ("Data Not Collected"; hosted backends are the user's own choice of third party, disclosed in the app), age rating (free-text Hugging Face repo IDs → answer the AI questions as LocalLM Lab did).
5. Web: a note on the JevDK guide and jev-serve pages that the MAS version doesn't include jev-serve and keeps its models in its own container.
6. Before release: run the jevdk sync from ancientcomputing/locallm so the two code files match its output.
