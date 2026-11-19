# ios-common

What the iOS apps share: QNTX-App, laye, and any other.

"i feel like there is a good argument to put the island into its own repo, and a generalised thing all other projects of mine use that would be using it,"

"and the same really goes for everything else that laye app would be using from QNTX-App"

| Path | What it is |
|---|---|
| `sheet/` | The Tauri plugin `sheet`: the provider ceremony in `ASWebAuthenticationSession`. One command, `run`. |
| `apple/apple.py` | The app's App IDs, their capabilities, and its App Store profile at Apple, made where missing. |
| `apple/ios-project.py` | Signing against that profile instead of an account, in the generated Xcode project. |
| `apple/upload.sh` | An IPA to App Store Connect. |
| `apple/delivered.py` | Waits until App Store Connect says testers can install a build. |
| `apple/export-island.py` | The archive exported with the app's profile and the island's. |
| `island/` | What waits on a person, as a Live Activity: `island/README.md`. |
| `ci/ios.nix` | The iOS job every app follows. |

## Taking it in

An app names one tag of this repo, in its Cargo.toml:

```toml
sheet = { git = "https://github.com/teranos/ios-common", tag = "v0.1.0" }
```

Its CI is the job `ci/ios.nix` makes, imported at that same tag by the app's
own `ci/*.nix`, which emits the app's workflow as every workflow here is
emitted: `nix eval --json --file ci/<name>.nix | jq .`, never edited by hand.
What the app passes:

| Argument | What it is |
|---|---|
| `dir` | The directory holding `tauri.conf.json`, `apple.json` and `Cargo.toml`. |
| `tag` | The ios-common tag the job runs `apple/` from. |
| `profile` | The App Store profile's name, `apple.json`'s. |
| `targets` | Rust targets beyond `aarch64-apple-ios`. |
| `cache` | `path`, what is cached, and `key`, the files it is keyed on. |
| `prepare` | The steps that make the app's page, before the lib is checked. |
| `project` | Steps after the project is signed, before xcodegen. |
| `island` | `node` and `sentry`, when `apple.json` names an island. |
| `build` | The command that leaves an IPA under `gen/`; with an island, the archive exported by `apple/export-island.py`. |
| `env` | What every step is given. |
| `xcode` | The Xcode the IPA is built with, on GitHub's `xcode-27` image; 27.2 unless said. |

`apple.py` reads the app's `apple.json`: the profile's name and, per App ID,
its capabilities. Its docstring has the shape.
