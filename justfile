_:
    just --list

build:
    ./scripts/build.sh

# Cross-compiled release zips → nimr/dist/ (version in filenames; default "dev").
build-cross version="dev":
    ./scripts/build-cross.sh "{{version}}"

# Installs the nimr binary to ~/.local/bin and runs `nimr completion zsh` (writes ~/.zsh/completions/_nimr).
install:
    ./scripts/install.sh

# Runs ``build-cross`` then ``release.sh`` with the same resolved tag. For ``patch`` / ``minor`` /
# ``major``, the version is resolved once (GitHub latest + bump) and used for zip names and upload.
release VERSION:
    #!/usr/bin/env bash
    set -euo pipefail
    cd "{{justfile_directory()}}"
    if [[ "{{VERSION}}" =~ ^(patch|minor|major)$ ]]; then
      VER="$(./scripts/release.sh --print-version "{{VERSION}}")"
      ./scripts/build-cross.sh "$VER"
      ./scripts/release.sh "$VER"
    else
      ./scripts/build-cross.sh "{{VERSION}}"
      ./scripts/release.sh "{{VERSION}}"
    fi

test:
    ./dist/nimr run examples/nimr-template -h