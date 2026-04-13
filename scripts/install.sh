#!/usr/bin/env bash

# Build nimr, install the binary to ~/.local/bin, and optionally write zsh completion to
# ~/.zsh/completions/_nimr via `nimr completions-zsh`.
# Run from anywhere; paths are resolved from this script.
#
# Usage:
#   ./scripts/install.sh
#
# Dependencies:
#   - same as ./scripts/build.sh (nim, nimble, nimr.nimble deps)
#
# Shell: this script does not modify ~/.zshrc. Add ~/.zsh/completions to fpath before compinit
# (see README).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
NIMR_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd -P)"

main() {
  local dist_bin="${NIMR_ROOT}/dist/nimr"
  local local_bin="${HOME}/.local/bin"

  cd "${NIMR_ROOT}"
  ./scripts/build.sh

  if [[ ! -f "${dist_bin}" ]]; then
    echo "install.sh: expected binary missing after build: ${dist_bin}" >&2
    exit 1
  fi

  if [[ ! -d "${local_bin}" ]]; then
    echo "install.sh: warning: ${local_bin} did not exist; creating it" >&2
    mkdir -p "${local_bin}"
  fi
  cp -f "${dist_bin}" "${local_bin}/nimr"
  chmod +x "${local_bin}/nimr"
  echo "install.sh: installed ${local_bin}/nimr"

  if [[ -x "${local_bin}/nimr" ]]; then
    "${local_bin}/nimr" completions-zsh || true
  fi
}

main "$@"
