# nimr: single-file Nim runner

**NOTICE** This app has been merged into my multi-language app -- https://github.com/bdombro/shebangsy

**nimr** runs a Nim source file like a script: shebang, `chmod +x`, run. It can **skip recompiling** when nothing important changed, **install Nimble packages** for you, and **paper over** filenames that are not valid Nim module names.

Similar idea to `#!/usr/bin/env -S nim r`, but nimr avoids a full compile when that metadata matches, does not use a VM for your app, lets you name it whatever you want, and can pull in **external Nimble dependencies** without a local `.nimble` project.

**Supported platforms:** macOS and Linux (POSIX). Windows is not supported.

### Startup cost

Expect on the order of **~6 ms** extra startup versus running a pre-built binary directly (see [Benchmark](#benchmark)). Most of that is process startup and the CLI stack, not the cache lookup itself.

### My similar tools

- [gor](https://github.com/bdombro/gor) — Go  
- [mojor](https://github.com/bdombro/mojor) — Mojo  

---

## Quick start

1. Put **`nimr` on your `PATH`** (see [Install](#install)).
2. Start your script with `#!/usr/bin/env nimr`.
3. `chmod +x` and run it.

Examples in this repo: [nimr-stat](./examples/nimr-stat), [nimr-neo](./examples/nimr-neo) (Neo plus extra compiler flags).

Minimal script `foo`:

```nim
#!/usr/bin/env nimr

import std/[options, ...]
import argsbarg

# ... your code; argsbarg can be auto-installed via # requires:
echo "bar"
```

```sh
chmod +x foo
./foo   # prints bar
```

See [examples](./examples) for more.

---

## Benchmark

[`./scripts/bench.sh`](./scripts/bench.sh) uses [hyperfine](https://github.com/sharkdp/hyperfine) to compare three ways to run the same tiny program:

| Label | What it measures |
|--------|------------------|
| **compiled** | `nim c` output run directly |
| **nimr** | Warm run: cache hit after `stat`, no full source read, no recompile. Nimr then **`execv`s** into the cached binary (no long-lived parent waiting on a child). |
| **nim r** | `#!/usr/bin/env -S nim r` ([`scripts/bench-assets/nim_r_hello.nim`](./scripts/bench-assets/nim_r_hello.nim)) |

Rough minimum times (machine-dependent; see your own hyperfine output):

| | Time |
|--|------|
| compiled | ~3 ms |
| nimr (warm) | ~9 ms |
| nim r | ~120 ms |

---

## Dependencies: `# requires:`

In the **first 40 lines** of your script (after the shebang), list Nimble packages as a **comma-separated** list. You can use several lines; they are merged in order.

```nim
# requires: neo
# requires: argsbarg@1.3.2,chronos
# requires: arraymancer@#head   # latest from git head
```

**When it runs:** directives are handled on first run and are cached until the file changes.

**What nimr does:** for each package it runs `nimble path`; if missing, `nimble install -Y <spec>`. It then passes `--path:…` into `nim c` so imports resolve without a local Nimble project.

---

## Compiler flags: `# flags:`

Also in the **first 40 lines**, comma-separated tokens (trimmed; empties ignored) are passed to `nim c`:

```nim
# flags: --mm:refc,-d:release
```


Example: [nimr-neo](./examples/nimr-neo) (Neo on Nim 2 often needs `--mm:refc`).

---

## Run cache (`~/.cache/nimr`)

- **Layout:** under `$HOME/.cache/nimr`, one **folder per script path** (flattened path segments joined by `__`). Inside that folder, cached executables are named like `s_<bytes>_t_<unix_seconds>` (whole-second mtime from `stat`).
- **Cleanup:** after a successful compile, **older binaries in that same folder are removed**. There is **no** “delete if unused for N days” sweep. Wipe everything with **`nimr cache-clear`**.
- **Run:** on a warm hit or after compile, nimr **`execv`s** into the cached binary—no parent `nimr` left waiting on a child.
- **Concurrent misses:** if two processes compile the same cache entry at once, they **serialize** with **`flock`** on a **`.lock`** file next to that binary; the second waits for the first compile, then runs the same output.

---

## Command line

In addition to shebang, you can use cli.

```text
nimr -h
nimr script.nim [args...]
nimr run -h
nimr run script.nim [args...]
nimr cache-clear
nimr completion zsh > ~/.zsh/completions/_nimr
```

---

## Install

**Releases:** prebuilt binaries are on the [releases](https://github.com/bdombro/nimr/releases) page. You can copy them to your path (e.g. `~/.local/bin`).

```sh
curl -sSL https://api.github.com/repos/bdombro/nimr/releases/latest | grep -Eo 'https://[^"]*aarch64-apple-darwin[^"]*\.zip' | head -1 | xargs curl -sSL -o nimr.zip
unzip -o nimr.zip && chmod +x nimr
mv nimr ~/.local/bin/
rm nimr.zip
```

**From a clone** (builds, copies to `~/.local/bin/nimr`, writes zsh completion, clears cache):

```sh
just install
# or: ./scripts/install.sh
```

---

## Completions

### Zsh

Generate the completion script (stdout—redirect to install):

```sh
# If using zsh fpath feature
nimr completion zsh > ~/.zsh/completions/_nimr
# else
echo 'eval "$(nimr completion zsh)"' >> ~/.zshrc
```
---

## Building

```sh
just build
# or: ./scripts/build.sh
```

Cross-compiled zips (macOS host + Linux glibc) land in `dist/`:

```sh
just build-cross
# or ./scripts/build-cross.sh
```

---

## Editor tips (VS Code / Cursor)

**Nim extension:** many people use a community Nim extension because the official one may not work well with `nimlangserver`. Install a Nim language server binary into `~/.nimble/bin` if the extension expects it.

**Shebang files without `.nim`:** install [Shebang Language Associator](https://marketplace.visualstudio.com/items?itemName=davidhewitt.shebang-language-associator) and add:

```json
  "shebang.associations": [
    {
      "pattern": "^#!/usr/bin/env nimr$",
      "language": "nim"
    }
  ]
```

---

## License

MIT
