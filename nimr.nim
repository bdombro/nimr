#[
  nimr

  Single-file Nim runner: content-hash cache, optional temp copy when the source path is not a
  valid Nim module filename, then ``nim c`` and execute.

  Usage:
    nimr -h
    nimr run -h
    nimr run <script.nim> [args...]
    nimr cacheClear
    nimr completions-zsh

  Code Standards:
    - Commands that shell out to non-bundled binaries should check PATH, print install hints, and
      exit non-zero when required commands are missing.
    - Multi-word identifiers:
      - order from general → specific (head-first: main concept, then qualifier)
      - typically topic → optional subtype/format → measured attribute → limit/qualifier
      - e.g. coreProcessExitCodeWait, not waitExitCodeCoreProcess
    - Field names:
      - minimal tokens within the owning type
      - no repeated type/module/domain prefixes unless required for disambiguation
    - module-scope (aka top-level, not-nested) declarations (except imports) must be
      - documented with a doc comment above the declaration
      - sorted alphabetically by identifier (consts, object types, fields inside exported objects,
        vars, then procs)
      - procs: callee before caller when required by the compiler; otherwise alphabetical
      - prefixed with a short domain token for app features (``run`` / ``cache``); use ``core`` for
        shared CLI/runtime helpers
    - functions must have a doc comment, and a blank empty line after the function
    - Function shape:
      - entry-point and orchestration procs read top-down as a short sequence of named steps
      - keep the happy path obvious; move mechanics into helpers with intent-revealing names
    - Helper placement:
      - prefer nested helpers only for tiny logic tightly coupled to one block
      - promote helpers to module scope when nesting makes the caller hard to scan, even if the
        helper currently has one call site
      - shared by ≥2 call sites → smallest common ancestor (often a private proc at module
        scope)
      - must be visible to tests, callbacks, or exports → keep at the level visibility requires
      - recursion between helpers → shared scope as the language requires
    - Parameter shape:
      - if a proc takes more than four primitive or config parameters, prefer an options object
      - if the same cluster of values passes through multiple layers, define a named type for it
    - Branching:
      - materially different pipelines → separate helpers, not interleaved
      - repeated status literals and sentinels → centralized constants (or enums when suitable)
    - Assume unix arch and POSIX features are available
    - Use argsbarg for CLI features (declare it in ``nimr.nimble`` / your package manager; no grab in
      this module)
      - default to no shortened flags for newly added options
    - Local dev build for this repo: ``just`` / ``justfile`` (needs ``nim`` + ``nimble`` on PATH)
    - Use line max-width of 100 characters, unless the line is a code block or a URL
    - ``CliCommand.handler`` must be a named proc, not an inline proc literal, and must implement
      the command directly rather than just forwarding to another proc
]#

import std/[options, os, osproc, strutils, times]
import argsbarg

{.push warning[Deprecated]: off.}
import std/sha1
{.pop.}

## Oldest last-use ``mtime`` still kept after a compile-triggered sweep of the hash cache directory.
const cacheUnusedMaxAgeDays = 30

type
  ## Zsh completion behavior after a top-level subcommand word (word 2).
  CoreCliSurfaceZshTail = enum
    coreCliSurfaceZshTailNone
    coreCliSurfaceZshTailFiles
    coreCliSurfaceZshTailNestedWords

type
  ## One flag or option for zsh ``_arguments`` generation.
  CoreCliSurfaceOptionSpec = object
    ## Short help shown in zsh completion (sanitized for ``_arguments``).
    help: string
    ## Option spellings (e.g. ``-q`` and ``--quality``); combined into one zsh spec when grouped.
    names: seq[string]
    ## When true, expect ``:placeholder:`` value completion after the flag.
    takesValue: bool
    ## Placeholder label after the colon (e.g. ``pixels``, ``preset``).
    valuePlaceholder: string
    ## When non-empty, zsh offers these literals as the flag value.
    valueWords: seq[string]

type
  ## One top-level subcommand plus zsh tail behavior and an optional usage line suffix.
  CoreCliSurfaceTopCmd = object
    ## Subcommand name offered at ``CURRENT == 2``.
    name: string
    ## Words offered at ``CURRENT == 3`` when ``zshTail`` is ``coreCliSurfaceZshTailNestedWords``.
    nestedWords: seq[string]
    ## Flags and options valid after this subcommand (or for ``defaultSubcommand`` before it is spelled).
    options: seq[CoreCliSurfaceOptionSpec]
    ## Text after ``prog & " "`` for one usage line; empty to omit from usage output.
    usageLine: string
    ## How zsh completes further tokens under this subcommand.
    zshTail: CoreCliSurfaceZshTail

type
  ## Declarative CLI surface for zsh completion text and indented usage lines.
  CoreCliSurfaceSpec = object
    ## When set, ``options`` on that subcommand may appear before its word (implicit subcommand).
    defaultSubcommand: string
    ## Program name for ``#compdef`` and usage lines.
    prog: string
    ## Top-level subcommands (TAB at word 2).
    topCommands: seq[CoreCliSurfaceTopCmd]
    ## Options valid before a subcommand word (e.g. global ``-h`` / ``--help``).
    topOptions: seq[CoreCliSurfaceOptionSpec]
    ## Usage line suffixes (after ``prog & " "``) printed before per-command lines.
    usagePreamble: seq[string]
    ## Zsh completion function name including leading underscore.
    zshFunc: string


## Indented usage lines from ``spec.usagePreamble`` and non-empty ``usageLine`` fields.
proc coreCliSurfaceUsageIndented(spec: CoreCliSurfaceSpec): string =
  var lines: seq[string]
  for p in spec.usagePreamble:
    lines.add("  " & spec.prog & " " & p)
  for c in spec.topCommands:
    if c.usageLine.len > 0:
      lines.add("  " & spec.prog & " " & c.usageLine)
  lines.join("\n")


## Sanitizes help text for zsh ``_arguments`` bracket descriptions.
proc coreCliSurfaceZshBracketDesc(help: string): string =
  const maxLen = 72
  var n = 0
  for c in help:
    if n >= maxLen:
      break
    case c
    of '[', ']', ':', ';', '\'', '"', '\\', '\n', '\r':
      result.add(' ')
    else:
      result.add(c)
    inc n
  result = result.strip()
  if result.len == 0:
    result = "option"


## Comma-separated brace group for zsh (``{-h,--help}``).
proc coreCliSurfaceZshOptBraceNames(names: seq[string]): string =
  result = "{"
  for i, n in names:
    if i > 0:
      result.add(',')
    result.add(n)
  result.add('}')


## One ``_arguments`` spec line for a flag or value-taking option.
proc coreCliSurfaceZshOptionArgumentLine(o: CoreCliSurfaceOptionSpec): string =
  if o.names.len == 0:
    return ""
  let desc = coreCliSurfaceZshBracketDesc(o.help)
  let excl = "(" & o.names.join(" ") & ")"
  let brace = coreCliSurfaceZshOptBraceNames(o.names)
  if not o.takesValue:
    return "'" & excl & "'" & brace & "'[" & desc & "]'"
  let phRaw = o.valuePlaceholder.strip()
  let ph = if phRaw.len > 0: phRaw else: "value"
  if o.valueWords.len > 0:
    var inner = "(("
    for i, w in o.valueWords:
      if i > 0:
        inner.add(' ')
      inner.add(w)
    inner.add("))")
    return "'" & excl & "'" & brace & "'[" & desc & "]:" & ph & ":" & inner & "'"
  "'" & excl & "'" & brace & "'[" & desc & "]:" & ph & ":'"


## ``_arguments`` block for file-taking subcommands (flags then files).
proc coreCliSurfaceZshCompressArgumentsWithIndent(opts: seq[CoreCliSurfaceOptionSpec]; sp: string): string =
  if opts.len == 0:
    return sp & "_files && return 0\n"
  result = sp & "_arguments -s -S \\\n"
  for o in opts:
    let line = coreCliSurfaceZshOptionArgumentLine(o)
    if line.len > 0:
      result.add(sp & "  ")
      result.add(line)
      result.add(" \\\n")
  result.add(sp & "  '*:file:_files' && return 0\n")


## Dedupes strings while preserving first-seen order.
proc coreCliSurfaceSeqDedupePreserve(xs: seq[string]): seq[string] =
  for x in xs:
    var seen = false
    for y in result:
      if y == x:
        seen = true
        break
    if not seen:
      result.add(x)


## Words offered at ``CURRENT == 2`` (subcommands plus global and implicit-subcommand flags).
proc coreCliSurfaceZshWordTwoCompaddWords(spec: CoreCliSurfaceSpec): seq[string] =
  for o in spec.topOptions:
    for n in o.names:
      result.add(n)
  if spec.defaultSubcommand.len > 0:
    for c in spec.topCommands:
      if c.name == spec.defaultSubcommand:
        for o in c.options:
          for n in o.names:
            result.add(n)
        break
  for c in spec.topCommands:
    result.add(c.name)


## Options for the implicit default subcommand, or empty.
proc coreCliSurfaceOptionsForDefault(spec: CoreCliSurfaceSpec): seq[CoreCliSurfaceOptionSpec] =
  if spec.defaultSubcommand.len == 0:
    return @[]
  for c in spec.topCommands:
    if c.name == spec.defaultSubcommand:
      return c.options
  @[]


## Builds the zsh completion script body (``#compdef``, ``_arguments``, ``case`` arms, ``_files``).
proc coreCliSurfaceZshScript(spec: CoreCliSurfaceSpec): string =
  let w2 = coreCliSurfaceSeqDedupePreserve(coreCliSurfaceZshWordTwoCompaddWords(spec))
  let w2line = w2.join(" ")
  let dopts = coreCliSurfaceOptionsForDefault(spec)
  var arms = ""
  for c in spec.topCommands:
    arms.add("    ")
    arms.add(c.name)
    arms.add(")\n")
    case c.zshTail
    of coreCliSurfaceZshTailNone:
      arms.add("      return 0\n      ;;\n")
    of coreCliSurfaceZshTailFiles:
      arms.add("      compset -n 2\n")
      arms.add(coreCliSurfaceZshCompressArgumentsWithIndent(c.options, "      "))
      arms.add("      ;;\n")
    of coreCliSurfaceZshTailNestedWords:
      arms.add("      if (( CURRENT == 3 )); then\n")
      arms.add("        compadd ")
      arms.add(c.nestedWords.join(" "))
      arms.add(" && return 0\n      fi\n      return 0\n      ;;\n")
  var tail = "    esac\n"
  if spec.defaultSubcommand.len > 0:
    tail = "    *)\n"
    tail.add("      compset -n 1\n")
    tail.add(coreCliSurfaceZshCompressArgumentsWithIndent(dopts, "      "))
    tail.add("      ;;\n    esac\n")
  result = "#compdef " & spec.prog & "\n\n" & spec.zshFunc & "() {\n"
  result.add("  if (( CURRENT == 2 )); then\n")
  result.add("    compadd -- ")
  result.add(w2line)
  result.add("\n    return\n  fi\n")
  result.add("  if (( CURRENT > 2 )); then\n")
  result.add("    case ${words[2]} in\n")
  result.add(arms)
  result.add(tail)
  result.add("  fi\n  _files\n}\n\n")
  result.add(spec.zshFunc)
  result.add(" \"$@\"\n")


## Returns the nimr cache directory under ``$HOME/.cache/nimr``.
proc cacheDirNimrGet(): string =
  let home = getEnv("HOME")
  if home.len == 0:
    stderr.writeLine "[nimr] HOME is not set"
    quit(1)
  home / ".cache" / "nimr"


## Bumps ``path`` ``mtime`` to now so sweeps use last-run time, not compile time.
proc cacheBinaryLastUseTouch(path: string) =
  try:
    setLastModificationTime(path, getTime())
  except CatchableError:
    discard


## Returns the absolute path to the cached executable for ``hashHex``.
proc cacheBinaryPathGet(hashHex: string): string =
  let dir = cacheDirNimrGet()
  createDir(dir)
  when defined(windows):
    dir / hashHex & ".exe"
  else:
    dir / hashHex


## Drops cached binaries under ``dir`` whose ``mtime`` is older than ``cacheUnusedMaxAgeDays``.
proc cacheStaleBinaryRemove(dir: string) =
  if not dirExists(dir):
    return
  let cutoff = getTime() - initTimeInterval(days = cacheUnusedMaxAgeDays)
  for kind, path in walkDir(dir):
    if kind != pcFile:
      continue
    try:
      if getLastModificationTime(path) < cutoff:
        removeFile(path)
    except CatchableError:
      discard


## Deletes the nimr cache directory when it exists.
proc cacheClearRun() =
  let dir = cacheDirNimrGet()
  if not dirExists(dir):
    return
  try:
    removeDir(dir, checkDir = false)
  except CatchableError as e:
    stderr.writeLine "[nimr] could not clear cache: ", e.msg
    quit(1)
  stderr.writeLine "[nimr] cleared ", dir


## Removes the nimr content-hash cache directory.
proc nimrCacheClearHandle(ctx: CliContext) =
  discard ctx
  let dir = cacheDirNimrGet()
  if not dirExists(dir):
    return
  try:
    removeDir(dir, checkDir = false)
  except CatchableError as e:
    stderr.writeLine "[nimr] could not clear cache: ", e.msg
    quit(1)
  stderr.writeLine "[nimr] cleared ", dir


## Writes ``body`` to stdout with a blank line before and after (for ``-h`` / help output).
## Optional ``docAttrsPrefix`` / ``docAttrsSuffix`` wrap ``body`` (e.g. faint ANSI for no-arg help).
proc coreCliHelpStdoutWrite(body: string; docAttrsPrefix = ""; docAttrsSuffix = "") =
  stdout.write '\n'
  stdout.write docAttrsPrefix
  stdout.write body
  stdout.write docAttrsSuffix
  if not body.endsWith('\n'):
    stdout.write '\n'
  stdout.write '\n'


## True when ANSI colors should be suppressed (same rule as former cligen config loading).
proc coreCliPlainGet(): bool =
  existsEnv("NO_COLOR") and getEnv("NO_COLOR") notin ["0", "no", "off", "false"]


## If ``absPath`` starts with ``home`` as a directory prefix, returns tilde form (``~`` + suffix).
proc corePathDisplayTilde(home, absPath: string): string =
  if home.len == 0 or absPath.len < home.len:
    return absPath
  if not absPath.startsWith(home):
    return absPath
  if absPath.len > home.len and absPath[home.len] != DirSep:
    return absPath
  if absPath.len == home.len:
    return "~"
  "~" & absPath[home.len .. ^1]


## Builds an SGR ``on`` sequence from space-separated attribute words, or empty when ``plain``.
proc coreTextAttrOn(words: openArray[string]; plain: bool): string =
  if plain:
    return ""
  const esc = "\x1b["
  var parts: seq[string]
  for w in words:
    case w
    of "bold": parts.add "1"
    of "faint": parts.add "2"
    of "cyan": parts.add "36"
    of "green": parts.add "32"
    of "yellow": parts.add "33"
    else: discard
  if parts.len == 0:
    return ""
  esc & parts.join(";") & "m"


## Resets SGR when not ``plain``.
proc coreTextAttrOff(plain: bool): string =
  if plain:
    ""
  else:
    "\x1b[m"


## Writes ``contents`` to ``HOME/.zsh/completions/zshFileName``. Warns when the directory is created;
## prints an ``fpath``/``compinit`` hint only in that case.
proc coreZshCompletionFileWrite(appBin, zshFileName, contents: string) =
  let home = getEnv("HOME")
  if home.len == 0:
    stderr.writeLine appBin, ": HOME is not set"
    quit(1)
  let dir = home / ".zsh" / "completions"
  let dirExisted = dir.dirExists
  if not dirExisted:
    stderr.writeLine appBin, ": warning: ", corePathDisplayTilde(home, dir), " did not exist; creating it"
    createDir(dir)
  let path = dir / zshFileName
  writeFile(path, contents)
  stdout.writeLine appBin, ": wrote ", corePathDisplayTilde(home, path)
  if not dirExisted:
    stdout.writeLine appBin, ": add ", corePathDisplayTilde(home, dir),
      " to fpath before compinit, then restart zsh or run: compinit"


## True when ``stem`` is a valid Nim identifier stem.
proc coreIdentStemIsNim(stem: string): bool =
  if stem.len == 0:
    return false
  case stem[0]
  of 'a' .. 'z', 'A' .. 'Z', '_': discard
  of '0' .. '9': return false
  else: return false
  for i in 1 ..< stem.len:
    case stem[i]
    of 'a' .. 'z', 'A' .. 'Z', '0' .. '9', '_': discard
    else: return false
  true


## Drops a leading shebang so changing only the runner line does not bust the cache.
proc coreNormalizeForHash(content: string): string =
  if content.startsWith("#!"):
    let nl = content.find('\n')
    if nl >= 0:
      return content[nl + 1 .. ^1]
    return ""
  content


## True when ``path`` uses a ``.nim`` extension and its basename is a valid Nim module name.
proc coreNimModuleFilenameIsCompatible(path: string): bool =
  let (_, name, ext) = splitFile(path)
  ext == ".nim" and coreIdentStemIsNim(name)


## Walks parents from ``walkFromFile``'s directory and returns the first ``pixi.toml`` path found.
proc corePixiTomlPathFind(walkFromFile: string): string =
  var dir = parentDir(expandFilename(absolutePath(walkFromFile)))
  while true:
    let manifest = dir / "pixi.toml"
    if fileExists(manifest):
      return manifest
    let parent = parentDir(dir)
    if parent == dir:
      break
    dir = parent
  ""


## Runs ``cmd`` with ``args`` in ``workingDir`` and returns the exit code.
proc coreProcessExitCodeWait(cmd: string; args: openArray[string]; workingDir: string): int =
  let p = startProcess(cmd, args = args, workingDir = workingDir, options = {poParentStreams})
  result = waitForExit(p)
  close(p)


## Compiles ``nimSource`` to ``binaryPath``, preferring ``pixi run`` when a manifest exists.
proc runCompileInvoke(nimSource: string; scriptPathForPixiWalk: string; binaryPath: string): int =
  let workDir = parentDir(nimSource)
  let compileTail = @[
    "c",
    "--verbosity:0",
    "--hints:off",
    "-o:" & binaryPath,
    nimSource,
  ]
  let manifest = corePixiTomlPathFind(scriptPathForPixiWalk)
  if manifest.len > 0:
    let pixiExe = findExe("pixi")
    if pixiExe.len == 0:
      stderr.writeLine "[nimr] pixi.toml found (", manifest, ") but pixi is not on PATH"
      stderr.writeLine "[nimr] install pixi: https://pixi.sh"
      quit(1)
    let args = @["run", "--manifest-path", manifest, "nim"] & compileTail
    return coreProcessExitCodeWait(pixiExe, args, workDir)
  let nimExe = findExe("nim")
  if nimExe.len == 0:
    stderr.writeLine "[nimr] nim is not on PATH"
    stderr.writeLine "[nimr] install Nim, or add pixi.toml + nim via pixi (https://pixi.sh)"
    quit(1)
  coreProcessExitCodeWait(nimExe, compileTail, workDir)


## Returns a filesystem stem suitable for a synthesized ``.nim`` module name.
proc runNimStemForNaming(path: string): string =
  let (_, name, ext) = splitFile(path)
  if ext == ".nim":
    name
  else:
    name & ext


## Sanitizes ``stem`` into a Nim-safe module stem.
proc runNimStemSanitize(stem: string): string =
  var r = ""
  for c in stem:
    case c
    of 'a' .. 'z', 'A' .. 'Z', '0' .. '9', '_':
      r.add c
    else:
      r.add '_'
  while r.contains "__":
    r = r.replace("__", "_")
  r = r.strip(chars = {'_'})
  if r.len == 0:
    r = "script"
  if r[0] in '0' .. '9':
    r = "_" & r
  r


## Executes ``binary`` and forwards ``args``, then quits with the child exit code.
proc runBinaryExec(binary: string; args: openArray[string]) =
  let p = startProcess(binary, args = args, options = {poParentStreams})
  let code = waitForExit(p)
  close(p)
  quit(code)


## Compiles and runs a Nim script.
proc nimrRunHandle(ctx: CliContext) =
  let scriptAndArgs = ctx.args

  if scriptAndArgs.len == 0:
    stderr.writeLine "[nimr] run: expected <script> [args...]"
    quit(1)

  let script = scriptAndArgs[0]
  let args =
    if scriptAndArgs.len > 1:
      scriptAndArgs[1 .. ^1]
    else:
      @[]

  let scriptPath = expandFilename(absolutePath(script))
  if not fileExists(scriptPath):
    stderr.writeLine "[nimr] not a file: ", scriptPath
    quit(1)

  let raw = readFile(scriptPath)
  let normalized = coreNormalizeForHash(raw)
  let hashHex = $secureHash(normalized)
  let binaryPath = cacheBinaryPathGet(hashHex)

  if fileExists(binaryPath):
    cacheBinaryLastUseTouch(binaryPath)
    runBinaryExec(binaryPath, args)

  var nimSource = scriptPath
  var tmpRoot = ""
  if not coreNimModuleFilenameIsCompatible(scriptPath):
    tmpRoot = getTempDir() / ("nimr-build-" & hashHex[0 ..< 16])
    createDir(tmpRoot)
    let stem = runNimStemSanitize(runNimStemForNaming(scriptPath))
    nimSource = tmpRoot / (stem & ".nim")
    writeFile(nimSource, raw)

  let code = runCompileInvoke(nimSource, scriptPath, binaryPath)
  if tmpRoot.len > 0:
    try:
      removeDir(tmpRoot)
    except CatchableError:
      discard
  if code != 0:
    quit(code)

  cacheStaleBinaryRemove(cacheDirNimrGet())
  runBinaryExec(binaryPath, args)


## Prints help for the ``run`` subcommand (stdout).
proc coreRunHelpPrint() =
  coreCliHelpStdoutWrite """
Compile (if needed) and execute a Nim source file. Extra tokens are forwarded to the compiled
program unchanged.

Usage:

nimr run <script.nim> [args...]

""".strip()


## Compiles the first path when the content-hash cache misses, then runs the cached binary.
## Remaining tokens are forwarded to the compiled program unchanged.
proc runExecute(scriptAndArgs: seq[string]) =

  if scriptAndArgs.len == 0:
    stderr.writeLine "[nimr] run: expected <script> [args...]"
    quit(1)

  let script = scriptAndArgs[0]
  let args =
    if scriptAndArgs.len > 1:
      scriptAndArgs[1 .. ^1]
    else:
      @[]

  let scriptPath = expandFilename(absolutePath(script))
  if not fileExists(scriptPath):
    stderr.writeLine "[nimr] not a file: ", scriptPath
    quit(1)

  let raw = readFile(scriptPath)
  let normalized = coreNormalizeForHash(raw)
  let hashHex = $secureHash(normalized)
  let binaryPath = cacheBinaryPathGet(hashHex)

  if fileExists(binaryPath):
    cacheBinaryLastUseTouch(binaryPath)
    runBinaryExec(binaryPath, args)

  var nimSource = scriptPath
  var tmpRoot = ""
  if not coreNimModuleFilenameIsCompatible(scriptPath):
    tmpRoot = getTempDir() / ("nimr-build-" & hashHex[0 ..< 16])
    createDir(tmpRoot)
    let stem = runNimStemSanitize(runNimStemForNaming(scriptPath))
    nimSource = tmpRoot / (stem & ".nim")
    writeFile(nimSource, raw)

  let code = runCompileInvoke(nimSource, scriptPath, binaryPath)
  if tmpRoot.len > 0:
    try:
      removeDir(tmpRoot)
    except CatchableError:
      discard
  if code != 0:
    quit(code)

  cacheStaleBinaryRemove(cacheDirNimrGet())
  runBinaryExec(binaryPath, args)


const
  nimrTopHelpOpts = @[
    CoreCliSurfaceOptionSpec(
      help: "Show help",
      names: @["-h", "--help"],
      takesValue: false,
      valuePlaceholder: "",
      valueWords: @[]),
  ]
  ## Declarative CLI surface for zsh completion and usage lines.
  nimrCoreCliSurface = CoreCliSurfaceSpec(
    defaultSubcommand: "",
    prog: "nimr",
    topCommands: @[
      CoreCliSurfaceTopCmd(
        name: "run",
        nestedWords: @[],
        options: @[],
        usageLine: "run <script.nim> [args...]",
        zshTail: coreCliSurfaceZshTailFiles),
      CoreCliSurfaceTopCmd(
        name: "cacheClear",
        nestedWords: @[],
        options: @[],
        usageLine: "cacheClear",
        zshTail: coreCliSurfaceZshTailNone),
      CoreCliSurfaceTopCmd(
        name: "completion",
        nestedWords: @["zsh"],
        options: @[],
        usageLine: "completions-zsh",
        zshTail: coreCliSurfaceZshTailNestedWords),
    ],
    topOptions: nimrTopHelpOpts,
    usagePreamble: @["-h", "run -h"],
    zshFunc: "_nimr",
  )
  ## Zsh completion script for ``nimr`` (from ``nimrCoreCliSurface``).
  nimrZshCompletionScript = coreCliSurfaceZshScript(nimrCoreCliSurface)


let nimrCliSchema = CliSchema(
  commands: @[
    cliLeaf(
      "cacheClear",
      "Remove the nimr content-hash cache directory.",
      nimrCacheClearHandle,
    ),
    cliLeaf(
      "run",
      "Compile and run a Nim script.",
      nimrRunHandle,
      arguments = @[
        cliOptPositional(
          "scriptAndArgs",
          "The Nim file to compile and run, followed by forwarded args.",
          isRepeated = true,
        ),
      ],
    ),
  ],
  defaultCommand: none(string),
  description: "Single-file Nim runner: content-hash cache, optional temp module when the path is not a valid Nim module filename, then nim c and execute.",
  name: "nimr",
  options: @[],
)


when isMainModule:
  let ps = commandLineParams()
  if ps.len >= 1 and ps[0] == "run":
    if ps.len == 2 and ps[1].len > 0 and ps[1][0] == '-' and ps[1] in ["-h", "--help", "--helpsyntax"]:
      coreRunHelpPrint()
      quit(0)
  cliRun(nimrCliSchema, ps)
