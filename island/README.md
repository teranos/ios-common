# island

What waits on a person, on the island, the lock screen and the Mac's menu
bar, for any app that takes it in. The story is QNTX's node's:
[ADR-060](https://github.com/teranos/QNTX/blob/main/docs/adr/ADR-060-What-Waits-On-A-Person-Is-A-Live-Activity.md).

"i really like having the island be available to both the existing QNTX App and laye now as well,"

## Three folders, two targets

| Folder | Compiled into | Holds |
|---|---|---|
| `shared/` | the app and the widget | `WaitsAttributes`, the one shape, and `PressWaits`, a press |
| `app/` | the app | the tokens handed to the node, and the node asked outside the page |
| `widget/` | the widget | what is drawn |

`apple/ios-project.py` adds them to the generated Xcode project when the app's
`apple.json` names an island. None of it is a Tauri plugin: a plugin's Swift is
built outside Xcode, and the system runs a press only when it finds it among
what Xcode compiled into the app.

## Whose island it is

The app's `apple.json` says it, under `island`, and the build writes it into
both Info.plists:

| `apple.json` | Info.plist | What it is |
|---|---|---|
| `profile` | | The island's App Store profile's name. |
| `display` | `CFBundleDisplayName` | The widget's name. |
| `session` | `IslandSession` | The key the app's page keeps its session under. |
| `agent` | `IslandAgent` | How the island names itself to the node, which the node's log is searched by. |
| `release` | `IslandRelease` | The Sentry release, before `@` and the build. |
| `mark` | `IslandMark` | The mark drawn on the island: an SF Symbol's name, drawn as the symbol, or a character, drawn as text. |
| `name` | `IslandName` | The name drawn beside it on the lock screen. |
| `accent` | `IslandAccent` | The accent, six hex digits. |

The node (`IslandNode`) and the Sentry DSN (`IslandSentry`) are the CI's to
say, as `ci/ios.nix`'s `island.node` and `island.sentry`. The app's ids also
name `.island`, and its `Info.ios.plist` says `NSSupportsLiveActivities`.

## The node says, the app draws

`WaitsAttributes` is decoded by the system from what the node sends (teranos/QNTX
`server/phones.go`, `waitsOf` and `waitsShown`): the two are one shape, key for
key, and a key one side has and the other lacks is a Live Activity that does
not start. A node that is not QNTX's speaks the same: `/api/phones` takes the
tokens, and a press asks a path under `/api/`.

A press is drawn as its mark and never as a word. `markOf` is the one place a
press is given its mark.

## The app's main is not this repo's

Tauri generates it. `app/WaitsBoot.m` is loaded with the app's image and
begins handing over tokens once the app has launched, also when Apple launched
it in the background for a Live Activity that started.

## The session

The app's page is at another site than the node, so its session is no cookie:
the page holds it and presents it on each request. `app/WaitsNode.swift`
presents the same, read from the page while it is there and kept in the
Keychain for when the system runs the app with no page. No token is made.

## Proven here

- `ci/island-wall`: every way the Swift could let a failure go, refused.
- `ci/island-tests`: what the island decides on its own, in the Simulator.
- `ci/island-draw`: the island's Live Activity started and drawn, in the Simulator.

What it asks of a real node is tested by the app whose node it is: QNTX-App's
`ci/island-tests`, against a QNTX node on the runner.
