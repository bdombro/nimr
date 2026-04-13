# nimr: Single-file Nim runner

Run Nim files with a script-like workflow, fast reruns, and less setup friction. `nimr` reuses cached builds so unchanged programs start quickly, smooths over awkward filenames, and respects project-local Nim environments via `pixi.toml` when present.

Written in nim for max performance (1-5ms penalty).

## Usage

chmod +x, add a shebang and run the file (needs `nimr` on `PATH`) like [nimr-template](./examples/nimr-template)

CLI overview:

```text
nimr -h
nimr run -h
nimr run script.nim [args...]
nimr cacheClear
nimr completion zsh
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
nimr completion zsh
```

This installs `~/.zsh/completions/_nimr`. If the directory did not exist, `nimr` prints a warning when it creates it.

Put **`~/.zsh/completions` on `fpath` before `compinit`**. For example in `~/.zshrc`:

```zsh
fpath=(~/.zsh/completions $fpath)
autoload -Uz compinit && compinit
```

If you use **Oh My Zsh**, add the `fpath` line before Oh My Zsh is sourced (or wherever your theme loads `compinit`).

**Release binary only:** run `nimr completion zsh` after installing the binary, then configure `fpath` as above.

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

GitHub release (requires pre-built zips for that version in `dist/`):

```sh
just release v1.2.3
# or: ./scripts/build-cross.sh v1.2.3 && ./scripts/release.sh v1.2.3
```


## License

MIT
