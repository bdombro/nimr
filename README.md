# nimr: Single-file Nim runner

Run Nim files with a script-like workflow, fast reruns, and less setup friction. `nimr` reuses cached builds so unchanged programs start quickly, smooths over awkward filenames, and **auto-installs Nimble dependencies**.

It's kinda like using a shebang `#!/usr/bin/env -S nim r`, but skips recompile on no change, no virtual machine, and auto-installs external dependencies.

Note: While nimr is convenient, it does add ~8ms startup delay compared to running a nim bin directly (see [Benchmark](#benchmark)).

## Usage

Just chmod +x, add a shebang (`#!/usr/bin/env nimr`), and run the file (needs `nimr` on `PATH`) like [nimr-stat](./examples/nimr-stat) or [nimr-neo](./examples/nimr-neo) (Neo + extra compiler flags).

Your script, `foo`:
```python
#!/usr/bin/env nimr

import std/[options, ...]
import argsbarg

# ...rest of your code, `argsbarg` is auto-installed
echo "bar"
```

```sh
chmod +x foo
./foo # --> prints "bar"
```


## Benchmark

We have a hyperfine benchmark (`./scripts/bench.sh`) to measure the cost of usign nimr vs alternatives:

1. "compiled" - A fully compiled nim app ran directly
2. "nimr" - An app that uses nimr that has been previously ran (aka warm). This means the app has already been compiled and cached, so nimr basically confirms the source has not changed and runs the compiled app, so the real difference vs compiled is doing the check and running the compiled app.
3. "nim_r" - An app that uses `nim r` to compile and run

**Results**

The most important metric in the results is the min time taken per app:

1. compiled - 1.7ms
2. nimr - 9.9ms
3. nimr_r - 135.5ms


## Additional Features

### Declaring dependencies (`# nimr-requires:`)

Add a `# nimr-requires:` comment in the first 40 lines of your script (after the shebang).
The value is a **comma-separated** list of Nimble package specs. Multiple directives are merged
in order.

```python
# nimr-requires: neo
# nimr-requires: argsbarg@1.3.2,chronos
# nimr-requires: argsbarg@#head <-- use latest

```

Note: nimr caches the deps until the app changes or nimr cache is cleared -- so #head/#branch may fall behind as long as the cache is valid.

On each run `nimr` checks whether each package is already installed (via `nimble path`). If not,
it calls `nimble install -Y <spec>` and streams the progress. Then it passes `--path:…` to
`nim c` so the packages are visible at compile time without needing a `.nimble` project file.

The `# nimr-requires:` lines are part of the **content-hash cache key**, so changing a spec
automatically triggers a fresh compile.

See [nimr-neo](./examples/nimr-neo) and [nimr-arraymancer](./examples/nimr-arraymancer) for
full working examples.

### Extra `nim c` flags (`# nimr-flags:`)

Add a `# nimr-flags:` comment in the first 40 lines to pass extra flags to `nim c`. The value
is a **comma-separated** list of tokens (each segment is trimmed; empty segments are ignored).

```python
# nimr-flags: --mm:refc,-d:release
```

The `# nimr-flags:` lines are part of the **content-hash cache key**, so changing flags triggers
a fresh compile.

See [nimr-neo](./examples/nimr-neo) for a full script that combines `# nimr-requires:` with
`# nimr-flags: --mm:refc` (Neo on Nim 2 often needs `--mm:refc`).

### IDE Integration

Nim language support for VSCode/Cursor:

1. Install the unofficial Nim extension bc the official one is not working with nim language server
2. Download a release bin for nim language server and place in ~/.nimble/bin

Auto-selecting nim language when scripts don't end with ".nim" in VSCode:

1. Install the [Shebang Language Association extension](https://marketplace.visualstudio.com/items?itemName=davidhewitt.shebang-language-associator)
2. Add the following to your VSCode JSON settings:

```json
  "shebang.associations": [
    {
      "pattern": "^#!/usr/bin/env nimr$",
      "language": "nim"
    }
  ],
```


### CLI overview:

```text
nimr -h
nimr run -h
nimr run script.nim [args...]
nimr cache-clear
nimr completion zsh > ~/.zsh/completions/_nimr
```

Use `nimr run -h` only when there is no script path (otherwise `-h` is passed through to your program).


## Install

Use precompiled binaries from the [releases](https://github.com/bdombro/nimr/releases) page, or build from source (see **Building** below).

To quickly install the latest **Apple Silicon** (aarch64) macOS build with `curl`:

```sh
curl -sSL https://api.github.com/repos/bdombro/nimr/releases/latest | grep -Eo 'https://[^"]*aarch64-apple-darwin[^"]*\.zip' | head -1 | xargs curl -sSL -o nimr.zip
unzip -o nimr.zip && chmod +x nimr
mv nimr ~/.local/bin/
rm nimr.zip
```

Assumes `~/.local/bin` is on your `PATH`.

From a clone, build and install the binary to `~/.local/bin/nimr` and write a zsh completion file:

```sh
just install
# or: ./scripts/install.sh
```

That copies `dist/nimr` to `~/.local/bin/nimr`, then runs `nimr completion zsh`, which writes `~/.zsh/completions/_nimr` (creating `~/.zsh/completions/` if needed, or replacing `_nimr` if it already exists). The install script does **not** edit `~/.zshrc`; you must put that directory on zsh `fpath` **before** `compinit` (see below).


## Completions

### Zsh (file-based `_nimr`)

Generate or refresh the completion script:

```sh
nimr completions-zsh
```

This installs `~/.zsh/completions/_nimr`. If the directory did not exist, `nimr` prints a warning when it creates it.

Put **`~/.zsh/completions` on `fpath` before `compinit`**. For example in `~/.zshrc`:

```zsh
fpath=(~/.zsh/completions $fpath)
autoload -Uz compinit && compinit
```

If you use **Oh My Zsh**, add the `fpath` line before Oh My Zsh is sourced (or wherever your theme loads `compinit`).

**Release binary only:** run `nimr completions-zsh` after installing the binary, then configure `fpath` as above.

**Refresh if TAB seems stale**

```zsh
rm -f ~/.zcompdump*
autoload -Uz compinit && compinit
```

### Bash

Often needs the `bash-completion` package for `_longopt`:

```bash
complete -F _longopt nimr
```


## Building

```sh
just build
# or: ./scripts/build.sh
```

Cross-compiled release zips (macOS host + Linux glibc) live under `dist/`:

```sh
just build-cross dev
```

GitHub release (requires pre-built zips for that version in `dist/`). `release.sh` sets an annotated git tag for that version at the current `HEAD` (replacing the local tag if needed) before publishing.

```sh
just release v1.2.3
# or: ./scripts/build-cross.sh v1.2.3 && ./scripts/release.sh v1.2.3
```


## License

MIT
