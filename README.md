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

From a clone, build and install the binary and (when zsh’s completion system is available) register **cligen-style** zsh completion in `~/.zshrc`:

```sh
just install
# or: ./scripts/install.sh
```

That copies `dist/nimr` to `~/.local/bin/nimr`. If `zsh` is on `PATH` and `compdef` works after `compinit` in a clean zsh, the script appends `compdef _gnu_generic nimr` to `~/.zshrc` when that line is not already present (or creates a minimal `~/.zshrc` with `compinit` plus that `compdef` if the file did not exist). Otherwise it prints a short message and skips editing `~/.zshrc` without failing the install.


## Completions

### Zsh (cligen / GNU-style long options)

cligen’s help tables match zsh’s **`_gnu_generic`** completer (long flags from `--help`; not a custom subcommand-aware `_nimr` script).

Put **`compinit` before `compdef`** in `~/.zshrc`, for example:

```zsh
autoload -Uz compinit && compinit
compdef _gnu_generic nimr
```

If you use **Oh My Zsh** or similar, `compinit` is usually already loaded; then only `compdef _gnu_generic nimr` is needed (after that initialization).

**Release binary only:** add the same two lines yourself, or run `./scripts/install.sh` from a clone so the script can update `~/.zshrc` when the zsh check passes.

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
