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
  build ? "cargo tauri ios build --export-method app-store-connect --build-number \${{ github.run_number }}",
  env ? { },
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
  runs-on = "macos-latest";
  defaults.run.working-directory = dir;
  inherit env;
  steps = [
    { uses = "actions/checkout@v5"; }
    {
      id = "rust";
      uses = "dtolnay/rust-toolchain@stable";
      "with" = {
        targets = builtins.concatStringsSep "," ([ "aarch64-apple-ios" ] ++ targets);
        components = "clippy";
      };
    }
    {
      uses = "actions/cache@v4";
      "with" = {
        path = builtins.concatStringsSep "\n" cache.path;
        key = "ios-\${{ steps.rust.outputs.cachekey }}-\${{ hashFiles(${
          builtins.concatStringsSep ", " (map (f: "'${f}'") cache.key)
        }) }}";
        restore-keys = "ios-\${{ steps.rust.outputs.cachekey }}-";
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
        "$RUNNER_TEMP/asc/bin/python" "$IOS_COMMON/apple.py" apple.json "$RUNNER_TEMP/app.mobileprovision"
        echo "IOS_MOBILE_PROVISION=$(base64 < "$RUNNER_TEMP/app.mobileprovision" | tr -d '\n')" >> "$GITHUB_ENV"
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
      env = team // {
        PROVISIONING_PROFILE = profile;
      };
      run = ''python3 "$IOS_COMMON/ios-project.py" gen/apple/project.yml'';
    }
  ]
  ++ map (s: s // { "if" = held; }) project
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
