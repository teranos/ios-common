# The iOS job every app follows: from App ID to tester.
#
# "but, don't you want something like a template for both App and laye to follow?"
#
# An app's ci/*.nix imports this at the tag its Cargo.toml takes the sheet
# from, passes what is its own (README.md says each argument), and emits its
# workflow from that nix. A run is green when App Store Connect says a tester
# can install the build, not when the upload returned (apple/delivered.py).
{
  dir ? ".",
  tag,
  profile,
  targets ? [ ],
  cache ? {
    path = [ "target" ];
    key = [ "Cargo.lock" ];
  },
  prepare ? [ ],
  project ? [ ],
  island ? null,
  build ?
    if island == null then
      "cargo tauri ios build --export-method app-store-connect --build-number \${{ github.run_number }}"
    else
      ''
        cargo tauri ios build --archive-only --build-number ''${{ github.run_number }}
        python3 "$IOS_COMMON/export-island.py"
      '',
  env ? { },
  # ITMS-90725: from April 2027 an upload is built with the iOS 27 SDK, which
  # Xcode 27 carries. GitHub's xcode-27 image holds it (actions/runner-images
  # images/macos/xcode-27-arm64-Readme.md).
  xcode ? "27.2",
}:
let
  held = "steps.signing.outputs.held == 'true'";
  # What reaches a phone is main, or a build somebody dispatched.
  reachesAPhone = "${held} && vars.APPLE_APP_ID != '' && (github.ref == 'refs/heads/main' || github.event_name == 'workflow_dispatch')";
  asc = {
    APPLE_API_KEY = "\${{ secrets.APPLE_API_KEY }}";
    APPLE_API_ISSUER = "\${{ secrets.APPLE_API_ISSUER }}";
    APPLE_API_KEY_CONTENT = "\${{ secrets.APPLE_API_KEY_CONTENT }}";
  };
  certificate = {
    IOS_CERTIFICATE = "\${{ secrets.IOS_CERTIFICATE }}";
    IOS_CERTIFICATE_PASSWORD = "\${{ secrets.IOS_CERTIFICATE_PASSWORD }}";
  };
  team.APPLE_DEVELOPMENT_TEAM = "\${{ secrets.APPLE_DEVELOPMENT_TEAM }}";
in
{
  runs-on = "xcode-27";
  defaults.run.working-directory = dir;
  inherit env;
  steps = [
    { uses = "actions/checkout@v5"; }
    # The Xcode an upload is built with is said here, and the SDK it carries
    # is printed: what App Store Connect reads of the build is this.
    {
      name = "Xcode ${xcode}";
      run = ''
        sudo xcode-select -s /Applications/Xcode_${xcode}.app
        xcodebuild -version
        xcrun --sdk iphoneos --show-sdk-version
      '';
    }
    {
      id = "rust";
      uses = "dtolnay/rust-toolchain@stable";
      # llvm-tools: on Xcode 27 SwiftPM keeps a package's @_cdecl exports
      # local, and swift-rs (1.0.8 on) makes them global again with
      # llvm-objcopy, from here. Without it swift-rs only warns, which Cargo
      # hides for a dependency, and Tauri's every Swift entry is undefined at
      # link (swift-rs #83; laye #13 and QNTX-App #40 on Xcode 27.2).
      "with" = {
        targets = builtins.concatStringsSep "," ([ "aarch64-apple-ios" ] ++ targets);
        components = "clippy,llvm-tools";
      };
    }
    # What was compiled is kept per Xcode: a build script's output names the
    # Xcode it ran under, and one restored from another links against paths
    # that are not there (laye #13: the sheet's Swift was looked for under
    # Xcode_26.6.app on the Xcode 27.2 image, and _init_sheet was undefined).
    {
      uses = "actions/cache@v4";
      "with" = {
        path = builtins.concatStringsSep "\n" cache.path;
        key = "ios-xcode-${xcode}-\${{ steps.rust.outputs.cachekey }}-\${{ hashFiles(${
          builtins.concatStringsSep ", " (map (f: "'${f}'") cache.key)
        }) }}";
        restore-keys = "ios-xcode-${xcode}-\${{ steps.rust.outputs.cachekey }}-";
      };
    }
    {
      name = "ios-common ${tag}";
      run = ''
        git clone -q --depth 1 --branch ${tag} https://github.com/teranos/ios-common "$RUNNER_TEMP/ios-common"
        echo "IOS_COMMON=$RUNNER_TEMP/ios-common/apple" >> "$GITHUB_ENV"
      '';
    }
  ]
  ++ prepare
  ++ [
    # The wall in Cargo.toml is a list of denials, and this is what asks it.
    {
      name = "The lib answers for every error";
      run = "cargo clippy --lib --target aarch64-apple-ios -- -D warnings";
    }
    {
      name = "Signing material";
      id = "signing";
      env = {
        inherit (certificate) IOS_CERTIFICATE;
        inherit (asc) APPLE_API_KEY_CONTENT;
      };
      run = ''
        if [ -n "$IOS_CERTIFICATE" ] && [ -n "$APPLE_API_KEY_CONTENT" ]; then
          echo "held=true" >> "$GITHUB_OUTPUT"
        else
          echo "::warning::no Apple signing secrets here: the app is proven, not signed"
          echo "held=false" >> "$GITHUB_OUTPUT"
        fi
      '';
    }
    {
      name = "App IDs, capabilities and profile at Apple";
      "if" = held;
      env = asc // certificate;
      run = ''
        python3 -m venv "$RUNNER_TEMP/asc"
        "$RUNNER_TEMP/asc/bin/pip" install --quiet 'pyjwt[crypto]' requests
        "$RUNNER_TEMP/asc/bin/python" "$IOS_COMMON/apple.py" apple.json "$RUNNER_TEMP/profiles"
        echo "IOS_MOBILE_PROVISION=$(base64 < "$RUNNER_TEMP/profiles/app.mobileprovision" | tr -d '\n')" >> "$GITHUB_ENV"
        if [ -f "$RUNNER_TEMP/profiles/island.mobileprovision" ]; then
          echo "IOS_ISLAND_MOBILE_PROVISION=$(base64 < "$RUNNER_TEMP/profiles/island.mobileprovision" | tr -d '\n')" >> "$GITHUB_ENV"
        fi
      '';
    }
    # The release binary, not a six-minute compile of the CLI on every run.
    {
      name = "Fetch tauri-cli 2.11.4";
      "if" = held;
      run = ''
        curl -sSL -o cargo-tauri.zip https://github.com/tauri-apps/tauri/releases/download/tauri-cli-v2.11.4/cargo-tauri-aarch64-apple-darwin.zip
        mkdir -p "$HOME/.cargo/bin"
        unzip -o -q cargo-tauri.zip -d "$HOME/.cargo/bin"
        rm cargo-tauri.zip
        cargo tauri --version
      '';
    }
    {
      name = "The Xcode project";
      "if" = held;
      run = "cargo tauri ios init";
    }
    {
      name = "Sign against the profile, not an account";
      "if" = held;
      env =
        team
        // {
          PROVISIONING_PROFILE = profile;
        }
        // (
          if island == null then
            { }
          else
            {
              ISLAND = "\${{ runner.temp }}/ios-common/island";
              ISLAND_NODE = island.node;
              ISLAND_SENTRY_DSN = island.sentry;
            }
        );
      run = ''python3 "$IOS_COMMON/ios-project.py" gen/apple/project.yml'';
    }
  ]
  # A step of the app's own runs where the app is signed, and where it says.
  ++ map (s: s // { "if" = if s ? "if" then "${held} && (${s."if"})" else held; }) project
  ++ [
    {
      name = "Generate the signed Xcode project";
      "if" = held;
      run = "cd gen/apple && xcodegen generate";
    }
    {
      name = "Build the signed IPA";
      "if" = held;
      env = certificate // team;
      run = build;
    }
    {
      name = "Locate the IPA";
      "if" = held;
      id = "ipa";
      run = ''
        found=$(find gen -name '*.ipa' -type f | head -1)
        test -n "$found" || { find gen/apple/build -type f 2>/dev/null; echo "no ipa produced"; exit 1; }
        echo "path=$PWD/$found" >> "$GITHUB_OUTPUT"
      '';
    }
    {
      uses = "actions/upload-artifact@v4";
      "if" = held;
      "with" = {
        name = "ipa";
        path = "\${{ steps.ipa.outputs.path }}";
      };
    }
    {
      name = "Upload to TestFlight";
      "if" = reachesAPhone;
      env = asc // {
        APPLE_APP_ID = "\${{ vars.APPLE_APP_ID }}";
        IPA = "\${{ steps.ipa.outputs.path }}";
      };
      run = ''sh "$IOS_COMMON/upload.sh" "$IPA" >> "$GITHUB_ENV"'';
    }
    {
      name = "Delivered to testers";
      "if" = reachesAPhone;
      env = asc;
      run = ''"$RUNNER_TEMP/asc/bin/python" "$IOS_COMMON/delivered.py" wait "$BUILD"'';
    }
  ];
}
