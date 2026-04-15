_:
    just --list

# Hyperfine: nimr vs `nim r` shebang vs compiled binary (see README **Benchmark**).
bench:
    ./scripts/bench.sh

# Builds the nimr binary (no zips, no cross-compilation) → nimr/dist/nimr.
build:
    ./scripts/build.sh

# Cross-compiled release zips → nimr/dist/ (version in filenames; default "dev").
build-cross version="dev":
    ./scripts/build-cross.sh "{{version}}"

# Installs Nimble dev dependencies (`nimble install --depsOnly` + `nimble setup`).
deps:
    nimble install -y --depsOnly
    nimble setup


# Installs the nimr binary to ~/.local/bin; install.sh refreshes ~/.zsh/completions/_nimr and clears cache using dist/nimr.
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
    PATH=./dist:$PATH ./examples/nimr-stat

