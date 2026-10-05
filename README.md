# JevDK and jev-serve

Two free Mac tools for **decision models** ("Jev"): models that answer a few fixed questions about
some text, such as which team should handle a message, or whether it asks for a refund, with one of
the answers you allowed and how sure they are, instead of writing a reply.

- **JevDK** is a Mac app for designing and testing those questions: run them on a model on your
  Mac and on hosted Jev (TypeSafe, Featherless) side by side, mark the right answers, see where
  they go wrong, calibrate, and export the tested setup.
- **jev-serve** answers hosted Jev's HTTP API on your Mac. Code that already calls TypeSafe's Jev
  on OpenRouter or Featherless's classifier, in any language, gets private, free, on-device
  decisions by changing its base URL.

New to decision models? Read [Decision models (Jev) in your app](https://thisbrain.ai/locallm/jev.html)
first: what they are if you know chatbots, and links to TypeSafe's and others' documentation.

## Download

From the [latest release](https://github.com/ancientcomputing/jevdk/releases/latest). Both need
an Apple-silicon Mac with **macOS 27**, and both are signed and notarized.

| | File | |
|---|---|---|
| **JevDK** | `JevDK-x.y.z-arm64.dmg` | Open it, drag JevDK to Applications, open it from there. |
| **jev-serve** | `jev-serve-x.y.z-arm64.zip` | Unzip; keep the two `.framework` folders next to `jev-serve`. |

Each has a `.sha256` next to it: `shasum -a 256 -c <file>.sha256` checks your download.

## JevDK in two minutes

1. **Examples → Customer support** loads four questions and some sample messages.
2. **Models** (toolbar): download `mlx-community/Qwen3-4B-4bit` (2.3 GB), the tested starting point.
3. Click a sample. Each question shows its answer, how sure the model is, and a bar for every option.
4. **Batch → Ask all** runs every sample; mark the right answers under each cell to score them.
5. **Backends** adds a hosted decider next to the local one (the Featherless demo needs no key).

The [JevDK guide](https://thisbrain.ai/locallm/jdk-guide.html) walks through the whole workflow, from
writing questions to shipping them, in plain English.

## jev-serve in two minutes

```bash
./jev-serve --model mlx-community/Qwen3-4B-4bit          # quick try; downloads the model if needed
```

```bash
curl -s http://127.0.0.1:8746/v1/classifier -H "Content-Type: application/json" -d '{
  "state": "Nothing loads since this morning, my whole team is stuck.",
  "questions": {"team": {"type": "choice", "instructions": "Which team should handle this message?",
                         "criteria": {"billing": "payments and refunds", "technical": "bugs and outages",
                                      "account": "login and profile"}}}}'
```

For real use, export a config from JevDK (**File → Export Server Config…**): it carries the model
pinned to the exact version you tested, your system instructions and calibration, and an optional
token. Then `./jev-serve --config jev-serve.json`. Details: [jev-serve/README.md](jev-serve/README.md).

## Source code

Both are open source (Apache 2.0) and built on the [LocalLM Lab SDK](https://thisbrain.ai/locallm/sdk.html):

- [jevdk/](jevdk/): the app ([README](jevdk/README.md), [developer's guide](jevdk/GUIDE.md))
- [jev-serve/](jev-serve/): the server ([README](jev-serve/README.md))

They build only against the SDK's published binaries, which `jevdk/Package.swift` downloads from
the SDK's GitHub release (no other setup; Xcode 27, Swift 6.4):

```bash
cd jevdk && swift build -c release && .build/release/JevDK
cd jev-serve && swift build -c release && .build/release/jev-serve --help
```

The SDK version is set by `defaultSDKVersion` in `jevdk/Package.swift` (or `LOCALLM_SDK_VERSION`
in your shell); jev-serve follows it. This repo is a copy: both tools are maintained as examples in
[ancientcomputing/locallm](https://github.com/ancientcomputing/locallm) (see [SOURCE.md](SOURCE.md)).

## Contact

[Discord](https://discord.gg/dydVBTe9Jq).
