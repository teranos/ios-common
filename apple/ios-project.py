#!/usr/bin/env python3
"""Settings XcodeGen needs and cargo-mobile2 does not write.

Run from the app's directory, the one holding tauri.conf.json and apple.json.
Automatic signing resolves through an Apple ID and a runner has none, so the
project names the profile instead. Neither trailing args to `cargo tauri ios
build` nor the environment reach xcodebuild; both were tried and both were
ignored, so this is the file that decides.

Every anchor is matched exactly. A template that stops containing one fails
here rather than producing a project that builds unsigned.

    ios-project.py gen/apple/project.yml

Reads APPLE_DEVELOPMENT_TEAM, PROVISIONING_PROFILE and IOS_MOBILE_PROVISION.
With an island in apple.json, also ISLAND (where ios-common's island/ is),
ISLAND_NODE, ISLAND_SENTRY_DSN and IOS_ISLAND_MOBILE_PROVISION.
"""

import base64
import json
import os
import plistlib
import subprocess
import sys
import tempfile

TEAM = os.environ["APPLE_DEVELOPMENT_TEAM"]
PROFILE = os.environ["PROVISIONING_PROFILE"]
APP_ID = json.load(open("tauri.conf.json"))["identifier"]
ISLAND_ID = APP_ID + ".island"
ANCHOR = "      PRODUCT_BUNDLE_IDENTIFIER: " + APP_ID

# ITMS-90068: from Spring 2027 an upload needs 15.0.
FLOOR_AT = "    iOS: "
FLOOR = 15.0

# The app target's last dependency in the template: the island is embedded after it.
EMBED_AFTER = "      - sdk: WebKit.framework"
# The app target's last source in the template: what the app itself compiles of
# the island goes before it. A press on the island is run by the system in the
# app's process, and the system finds it only among what Xcode compiled into
# the app: a Tauri plugin's Swift is built outside Xcode and is not among it.
SOURCES_BEFORE = "      - path: LaunchScreen.storyboard"
# The first of the app's Info.plist properties in the template: what the island
# needs of the app goes after it.
INFO_AFTER = "        LSRequiresIPhoneOS: true"
# Where the template names the app's entitlements file, which cargo-mobile2
# writes empty beside the project.
ENTITLEMENTS = "    entitlements:"
ENTITLEMENTS_PATH = "      path: "

# "the magic island"
#
# The widget that draws what waits as a Live Activity. It is its own bundle,
# signed by its own profile.
ISLAND_TARGET = """  IslandWidget:
    type: app-extension
    platform: iOS
    deploymentTarget: "17.2"
    sources:
      - path: {island}/widget
      - path: {island}/shared
    info:
      path: IslandWidget/Info.plist
      properties:
        CFBundleDisplayName: {display}
        CFBundleShortVersionString: $(MARKETING_VERSION)
        CFBundleVersion: $(CURRENT_PROJECT_VERSION)
        NSExtension:
          NSExtensionPointIdentifier: com.apple.widgetkit-extension
{widget_info}
    dependencies:
      - package: Sentry
      - package: SacredError
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: {id}
        SWIFT_VERSION: "5.0"
        CODE_SIGN_STYLE: Manual
        DEVELOPMENT_TEAM: {team}
        PROVISIONING_PROFILE_SPECIFIER: {profile}
        CODE_SIGN_IDENTITY: "Apple Distribution"
"""

# 「[Opus 5.5] What the island's every failure is, and where it is sent (island/shared/Island.swift).」
# 「[Opus 5.5] Pinned, as everything a build signs is: sacred-error by the commit that added」
# 「[Opus 5.5] Swift and its CI, Sentry by a release.」
ISLAND_PACKAGES = """packages:
  Sentry:
    url: https://github.com/getsentry/sentry-cocoa
    exactVersion: 9.32.0
  SacredError:
    url: https://github.com/teranos/sacred-error
    revision: d8834c0089eb56c6ad0aae78b1d0406a2ca7011a
"""


def read_profile(held, named):
    """A provisioning profile handed over in base64, as Apple wrote it."""
    if not held:
        raise SystemExit(named + " is empty: the build has no provisioning profile to sign with")
    with tempfile.NamedTemporaryFile(suffix=".mobileprovision") as profile:
        profile.write(base64.b64decode(held))
        profile.flush()
        read = subprocess.run(["security", "cms", "-D", "-i", profile.name], capture_output=True, check=True)
    return plistlib.loads(read.stdout)


def the_floor(lines):
    """No deployment target under the floor Apple takes uploads at."""
    for at, line in enumerate(lines):
        if line.startswith(FLOOR_AT) and float(line[len(FLOOR_AT):]) < FLOOR:
            lines[at] = FLOOR_AT + str(FLOOR)


def entitled(path, lines, push_asked):
    """The app says it takes notifications through Apple when its profile
    carries aps-environment: without it in the entitlements Apple gives the
    phone no push token, and codesign refuses an app that says it without the
    profile carrying it, in words that name neither. Said in the project, not
    written into the file: xcodegen writes the file anew from what the project
    says of it (XcodeGen FileWriter.writePlists)."""
    signed_with = read_profile(os.environ.get("IOS_MOBILE_PROVISION", ""), "IOS_MOBILE_PROVISION")
    if signed_with.get("Name") != PROFILE:
        raise SystemExit(
            "IOS_MOBILE_PROVISION holds the profile " + repr(signed_with.get("Name")) + " and PROVISIONING_PROFILE "
            "names " + repr(PROFILE) + ": the project would be signed with a profile the build did not install")
    if "aps-environment" not in signed_with.get("Entitlements", {}):
        if push_asked:
            raise SystemExit(
                "the provisioning profile " + PROFILE + " does not carry Push Notifications, and the island is "
                "reached through them: turn PUSH_NOTIFICATIONS on in apple.json")
        return
    at = lines.index(ENTITLEMENTS) + 1
    named = lines[at]
    if not named.startswith(ENTITLEMENTS_PATH):
        raise ValueError("the template names no entitlements path under entitlements: " + named)
    held_at = os.path.join(os.path.dirname(path), named[len(ENTITLEMENTS_PATH):].strip())
    with open(held_at, "rb") as held:
        entitlements = plistlib.load(held)
    entitlements["aps-environment"] = "production"
    lines[at + 1:at + 1] = ["      properties:"] + [
        "        " + json.dumps(key) + ": " + json.dumps(value) for key, value in sorted(entitlements.items())]
    print("entitlements:", held_at, sorted(entitlements))


def island_is_signed(path, island_profile):
    """The island's own profile, installed where Xcode looks, and the export
    that names it beside the app's: the Tauri CLI exports with the app's
    profile alone, and an archive that carries the island is refused by it."""
    raw = os.environ.get("IOS_ISLAND_MOBILE_PROVISION", "")
    signed_with = read_profile(raw, "IOS_ISLAND_MOBILE_PROVISION")
    if signed_with.get("Name") != island_profile:
        raise SystemExit(
            "IOS_ISLAND_MOBILE_PROVISION holds the profile " + repr(signed_with.get("Name")) + " and apple.json "
            "names " + repr(island_profile))
    of = signed_with.get("Entitlements", {}).get("application-identifier", "")
    if not of.endswith("." + ISLAND_ID):
        raise SystemExit("the profile " + island_profile + " is of " + repr(of) + ", and the island is " + ISLAND_ID)
    where = os.path.expanduser("~/Library/MobileDevice/Provisioning Profiles")
    os.makedirs(where, exist_ok=True)
    with open(os.path.join(where, signed_with["UUID"] + ".mobileprovision"), "wb") as installed:
        installed.write(base64.b64decode(raw))
    export = {
        "method": "app-store-connect", "signingStyle": "manual", "teamID": TEAM,
        "provisioningProfiles": {APP_ID: PROFILE, ISLAND_ID: island_profile},
    }
    with open(os.path.join(os.path.dirname(os.path.abspath(path)), "IslandExportOptions.plist"), "wb") as options:
        plistlib.dump(export, options)
    print("the island's profile:", island_profile, "installed, and the export names it beside", PROFILE)


def the_island(path, lines, island):
    """The island in the project: its Swift compiled into the app and into its
    own widget, which is embedded, and what the app says of itself to it in
    both Info.plists (island/README.md)."""
    where = os.environ.get("ISLAND", "")
    if not os.path.isdir(os.path.join(where, "widget")):
        raise SystemExit("ISLAND names no island: " + repr(where) + " holds no widget/")
    node = os.environ.get("ISLAND_NODE", "")
    # Over https: the system lets the app ask nothing else of a node, the page or a press.
    if not node.startswith("https://"):
        raise SystemExit("ISLAND_NODE names no node over https, and a press on the island asks the node: " + repr(node))
    # 「[Opus 5.5] Where the island sends its failures (island/shared/Island.swift): a」
    # 「[Opus 5.5] build that names none would drop every one, so it is not made.」
    sentry = os.environ.get("ISLAND_SENTRY_DSN", "")
    if not sentry.startswith("https://"):
        raise SystemExit("ISLAND_SENTRY_DSN names no Sentry DSN, and the island sends every failure there")
    for key in ("profile", "display", "session", "agent", "release", "mark", "name", "accent"):
        if not island.get(key):
            raise SystemExit("apple.json's island names no " + key + " (island/README.md)")
    of_the_app = {"IslandNode": node, "IslandSentry": sentry, "IslandSession": island["session"],
                  "IslandAgent": island["agent"], "IslandRelease": island["release"]}
    of_the_widget = {"IslandSentry": sentry, "IslandRelease": island["release"], "IslandMark": island["mark"],
                     "IslandName": island["name"], "IslandAccent": island["accent"]}

    embed = lines.index(EMBED_AFTER)
    lines[embed + 1:embed + 1] = [
        "      - target: IslandWidget",
        "        embed: true",
        "      - package: Sentry",
        "      - package: SacredError",
    ]
    before = lines.index(SOURCES_BEFORE)
    lines[before:before] = ["      - path: " + where + "/app", "      - path: " + where + "/shared"]
    info = lines.index(INFO_AFTER)
    lines[info + 1:info + 1] = ["        " + key + ": " + json.dumps(value) for key, value in of_the_app.items()]
    # The app compiles Swift of its own now, which the template never had.
    at = lines.index(ANCHOR)
    # Live Activities and presses are newer than the oldest iOS the app runs
    # on: linked weakly, the app starts where they are not there.
    lines[at + 1:at + 1] = [
        '      SWIFT_VERSION: "5.0"',
        '      OTHER_LDFLAGS: "$(inherited) -weak_framework ActivityKit -weak_framework AppIntents -weak_framework WidgetKit"',
    ]
    # targets: is the template's last key, so a target appended is one of them.
    lines.append(ISLAND_TARGET.format(
        island=where, display=json.dumps(island["display"]), id=ISLAND_ID, team=TEAM,
        profile=json.dumps(island["profile"]),
        widget_info="\n".join("        " + key + ": " + json.dumps(value) for key, value in of_the_widget.items())))
    # 「[Opus 5.5] A key at the left margin after the last target is the project's own.」
    lines.append(ISLAND_PACKAGES)
    island_is_signed(path, island["profile"])


def main(path):
    island = json.load(open("apple.json")).get("island")
    lines = open(path).read().split("\n")
    the_floor(lines)
    at = lines.index(ANCHOR)
    lines[at + 1:at + 1] = [
        "      CODE_SIGN_STYLE: Manual",
        "      DEVELOPMENT_TEAM: " + TEAM,
        "      PROVISIONING_PROFILE_SPECIFIER: " + json.dumps(PROFILE),
        '      CODE_SIGN_IDENTITY: "Apple Distribution"',
    ]
    if island:
        the_island(path, lines, island)
    entitled(path, lines, push_asked=bool(island))
    open(path, "w").write("\n".join(lines))
    at = lines.index(ANCHOR)
    print("\n".join(lines[at - 4:at + 8]))
    print("the island:", "IslandWidget, signed by " + island["profile"] if island else "not built: apple.json names none")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    main(sys.argv[1])
