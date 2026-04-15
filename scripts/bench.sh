#!/usr/bin/env bash
#
# Compare wall-clock time to run the same tiny Nim program three different ways, using
# hyperfine (https://github.com/sharkdp/hyperfine). Each benchmark is a full process:
# kernel loads the shebang or ELF, then nimr / `nim r` / the compiled binary runs until exit.
#
# Artifacts (checked in under scripts/bench-assets/):
#   - nimr-hello           — `#!/usr/bin/env nimr` script
#   - nim_r_hello.nim      — `#!/usr/bin/env -S nim r` script (classic Nim “run this file”)
#   - nimr-hello.bin       — same program compiled once with `nim c` (no script runner)
#
# What the numbers mean:
#   Hyperfine reports mean ± σ over multiple runs. `--warmup` runs happen first and are
#   excluded from those statistics, which mostly measures “warm” behavior (e.g. nimr’s
#   content-hash cache hit, `nim r` not recompiling when nothing changed). For cold-start /
#   first-compile behavior, run the commands manually or clear caches and use hyperfine
#   without warmup / with `--runs 1` as a separate experiment.
#
# Prerequisites:
#   - hyperfine on PATH (e.g. brew install hyperfine)
#   - nim on PATH (for the `nim r` shebang script)
#   - nimr on PATH, or a release build at dist/nimr (this script prepends dist/ to PATH when
#     that binary exists so you can `just build` then benchmark without installing nimr)
#
# Usage (from repo root or anywhere):
#   ./scripts/bench.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
NIMR_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd -P)"

main() {
  if ! command -v hyperfine >/dev/null 2>&1; then
    echo "bench.sh: hyperfine not found. Install it first, e.g.: brew install hyperfine" >&2
    exit 1
  fi

  local art="${NIMR_ROOT}/scripts/bench-assets"
  local nimr_script="${art}/nimr-hello"
  local nim_r_script="${art}/nim_r_hello.nim"
  local compiled="${art}/nimr-hello.bin"

  for f in "${nimr_script}" "${nim_r_script}" "${compiled}"; do
    if [[ ! -f "${f}" ]]; then
      echo "bench.sh: missing artifact: ${f}" >&2
      exit 1
    fi
  done

  # Prefer freshly built nimr from this checkout when present.
  if [[ -x "${NIMR_ROOT}/dist/nimr" ]]; then
    export PATH="${NIMR_ROOT}/dist:${PATH}"
  fi

  if ! command -v nimr >/dev/null 2>&1; then
    echo "bench.sh: nimr not on PATH (and dist/nimr missing?). Build with: just build" >&2
    exit 1
  fi

  if ! command -v nim >/dev/null 2>&1; then
    echo "bench.sh: nim not on PATH (required for the nim r shebang script)" >&2
    exit 1
  fi

  cd "${NIMR_ROOT}"

  # Paths are relative to repo root so they match docs and local mental model.
  hyperfine \
    --warmup 3 --runs 100 \
    -n "nim r (compile and run)" "./scripts/bench-assets/nim_r_hello.nim" \
    -n "nimr" "./scripts/bench-assets/nimr-hello" \
    -n "compiled " "./scripts/bench-assets/nimr-hello.bin"
}

main "$@"
