#!/usr/bin/env bash

# Build nimr, install the binary to ~/.local/bin, write zsh completion to
# ~/.zsh/completions/_nimr (stdout from `nimr completion zsh`), and clear the run cache.
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

  mkdir -p "${HOME}/.zsh/completions"
  # Use dist binary here: first exec of the freshly copied ~/.local/bin/nimr can stall on macOS
  # (Gatekeeper / notarization checks).
  set -x
  "${dist_bin}" completion zsh > "${HOME}/.zsh/completions/_nimr"
  "${dist_bin}" cache-clear
  rm -rf "${HOME}/.nimble/bin/nimr" 2>/dev/null || true
  set +x
}

main "$@"
