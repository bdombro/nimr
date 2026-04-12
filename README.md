# nimr: Single-file Nim runner

Run Nim files with a script-like workflow, fast reruns, and less setup friction. `nimr` reuses cached builds so unchanged programs start quickly, smooths over awkward filenames, and respects project-local Nim environments via `pixi.toml` when present.


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

From a clone, build and install the binary plus the zsh completion in one step:

```sh
just install
# or: ./scripts/install.sh
```

That copies `dist/nimr` to `~/.local/bin/nimr` and `completions/_nimr` to `~/.zsh/completions/_nimr` (creating those directories with a warning if they did not exist).


## Completions

### Zsh (subcommands and flags)

The repo ships `completions/_nimr` (name must stay `_nimr` so zsh associates it with the `nimr` command).

**Install the file**

Prebuilt release zips only contain the `nimr` binary; they do **not** ship the zsh completion. Install `_nimr` separately (still only needs the file on disk, not a full Nim build).

- **Release binary only (no local clone):** download `completions/_nimr` from GitHub and place it next to your other completion scripts:

  ```sh
  mkdir -p ~/.zsh/completions
  curl -sSL -o ~/.zsh/completions/_nimr \
    https://raw.githubusercontent.com/bdombro/nimr/main/completions/_nimr
  ```

  Pin a tag instead of `main` if you want the completer to track a specific release, e.g. replace `main` with `v0.1.0` in the URL when that tag exists.

- **From a clone:** `just install` or `./scripts/install.sh` (see **Install**), or:

  ```sh
  mkdir -p ~/.zsh/completions && cp completions/_nimr ~/.zsh/completions/_nimr
  ```

**Wire zsh to load it**

Put the completions directory on `fpath` **before** `compinit`, e.g. in `~/.zshrc`:

```zsh
fpath=(~/.zsh/completions $fpath)
autoload -Uz compinit && compinit
```

**Refresh after changes**

If TAB still ignores updates, restart the shell or clear the dumpfile and re-init:

```zsh
rm -f ~/.zcompdump*
autoload -Uz compinit && compinit
```

Then type `nimr ` and press TAB—you should see `run`, `cacheClear`, `help`, and the top-level help flags.

### Bash or Zsh without `_nimr` (GNU-style flags only)

cligen’s help tables work with generic completers that read `--help` (subcommand-aware completion is **not** included here):

- **Bash** (often needs the `bash-completion` package for `_longopt`):

  ```bash
  complete -F _longopt nimr
  ```

- **Zsh**:

  ```zsh
  compdef _gnu_generic nimr
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
