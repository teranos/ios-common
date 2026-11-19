#!/usr/bin/env python3
"""Settings XcodeGen needs and cargo-mobile2 does not write.

Run from the app's directory, the one holding tauri.conf.json.
Automatic signing resolves through an Apple ID and a runner has none, so the
project names the profile instead. Neither trailing args to `cargo tauri ios
build` nor the environment reach xcodebuild, so this is the file that decides.

The anchor is matched exactly. A template that stops containing it fails here
rather than producing a project that builds unsigned.

    ios-project.py gen/apple/project.yml
"""

import json
import os
import sys

TEAM = os.environ["APPLE_DEVELOPMENT_TEAM"]
PROFILE = os.environ["PROVISIONING_PROFILE"]
APP_ID = json.load(open("tauri.conf.json"))["identifier"]
ANCHOR = "      PRODUCT_BUNDLE_IDENTIFIER: " + APP_ID


def main(path):
    lines = open(path).read().split("\n")
    at = lines.index(ANCHOR)
    lines[at + 1:at + 1] = [
        "      CODE_SIGN_STYLE: Manual",
        "      DEVELOPMENT_TEAM: " + TEAM,
        "      PROVISIONING_PROFILE_SPECIFIER: " + PROFILE,
        '      CODE_SIGN_IDENTITY: "Apple Distribution"',
    ]
    open(path, "w").write("\n".join(lines))
    print("\n".join(lines[at - 4:at + 6]))


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    main(sys.argv[1])
