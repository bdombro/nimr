#!/usr/bin/env bash

# Build nimr, install the binary to ~/.local/bin, and install the zsh completion.
# Run from anywhere; paths are resolved from this script.
#
# Usage:
#   ./scripts/install.sh
#
# Dependencies:
#   - same as ./scripts/build.sh (nim, nimble, nimr.nimble deps)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
NIMR_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd -P)"

main() {
  local dist_bin="${NIMR_ROOT}/dist/nimr"
  local local_bin="${HOME}/.local/bin"
  local zsh_comp="${HOME}/.zsh/completions"
  local zsh_comp_created="false"

  cd "${NIMR_ROOT}"
  ./scripts/build.sh

  if [[ ! -f "${dist_bin}" ]]; then
    echo "[install.sh] expected binary missing after build: ${dist_bin}" >&2
    exit 1
  fi

  if [[ ! -d "${local_bin}" ]]; then
    echo "[install.sh] warning: ${local_bin} did not exist; creating it" >&2
    mkdir -p "${local_bin}"
  fi
  cp -f "${dist_bin}" "${local_bin}/nimr"
  chmod +x "${local_bin}/nimr"
  echo "[install.sh] installed ${local_bin}/nimr"

  if [[ ! -d "${zsh_comp}" ]]; then
    echo "[install.sh] warning: ${zsh_comp} did not exist; creating it" >&2
    mkdir -p "${zsh_comp}"
    zsh_comp_created="true"
  fi
  cp -f "${NIMR_ROOT}/completions/_nimr" "${zsh_comp}/_nimr"
  echo "[install.sh] installed ${zsh_comp}/_nimr"
  if [[ "${zsh_comp_created}" == "true" ]]; then
    echo "[install.sh] ensure fpath includes ${zsh_comp} before compinit (then rehash or restart zsh)"
  fi
}

main "$@"
