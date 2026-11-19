# The ci workflow, emitted to .github/workflows/ci.yml and never edited by hand:
#   nix eval --json --file ci/ci.nix | jq . > .github/workflows/ci.yml
{
  name = "ci";
  on = {
    push = { };
    pull_request = { };
  };
  jobs = {
    # The sheet builds for a phone with every warning denied, the scripts
    # parse, the template evaluates, and every workflow is what its nix says.
    sheet = {
      runs-on = "macos-latest";
      steps = [
        { uses = "actions/checkout@v5"; }
        {
          uses = "dtolnay/rust-toolchain@stable";
          "with" = {
            targets = "aarch64-apple-ios";
            components = "clippy";
          };
        }
        { uses = "cachix/install-nix-action@v31"; }
        {
          name = "The sheet answers for every warning";
          working-directory = "sheet";
          run = "cargo clippy --target aarch64-apple-ios -- -D warnings";
        }
        {
          name = "The scripts parse";
          run = ''
            python3 -m py_compile apple/*.py
            sh -n apple/upload.sh
          '';
        }
        {
          name = "The template evaluates";
          run = ''nix eval --impure --json --expr 'import ./ci/ios.nix { tag = "v0"; profile = "p"; }' > /dev/null'';
        }
        {
          name = "Every workflow is what its nix says";
          run = ''
            nix eval --json --file ci/ci.nix | jq . | diff - .github/workflows/ci.yml
          '';
        }
      ];
    };
  };
}
