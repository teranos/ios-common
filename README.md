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

The island comes here next, from QNTX-App's `island/`.

## Taking it in

An app names one tag of this repo, in its Cargo.toml:

```toml
sheet = { git = "https://github.com/teranos/ios-common", tag = "v0.1.0" }
```

Its CI checks out the same tag and runs `apple/` from the app's directory, the
one holding `tauri.conf.json`; laye's `.github/workflows/app.yml` reads the tag
from `app/Cargo.toml`.

`apple.py` reads the app's `apple.json`: the profile's name and, per App ID,
its capabilities. Its docstring has the shape.
