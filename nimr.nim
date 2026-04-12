#[
  nimr

  Single-file Nim runner: content-hash cache, optional temp copy when the source path is not a
  valid Nim module filename, then ``nim c`` and execute.

  Usage:
    nimr -h
    nimr run -h
    nimr run script.nim [args...]
    nimr cacheClear

  ``nimr run -h`` applies only when no script path is given (otherwise ``-h`` is forwarded to the
  compiled program).

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
    - Use cligen for CLI features (declare it in ``nimr.nimble`` / your package manager; no grab in
      this module)
      - default to no shortened flags for newly added options
    - Local dev build for this repo: ``just`` / ``justfile`` (needs ``nim`` + ``nimble`` on PATH)
    - Use line max-width of 100 characters, unless the line is a code block or a URL
]#

import std/[os, osproc, strutils]
import cligen

{.push warning[Deprecated]: off.}
import std/sha1
{.pop.}

const
  ## Cligen help: ``doc`` then options only (no ``$command`` / ``$args`` synopsis).
  coreUsageTmpl = "${doc}\nOptions:\n$options"


var coreClCfg = clCfg

## Narrow cligen help table to keys, defaults, and descriptions only.
coreClCfg.hTabCols = @[clOptKeys, clDflVal, clDescrip]

## Keep top-level ``doc`` line breaks readable (avoid aggressive reflow).
coreClCfg.wrapDoc = -1
coreClCfg.wrapTable = -1

## ``dispatchMulti`` top-level help uses global ``clCfg`` (``topLevelHelp``); mirror runner cfg.
clCfg = coreClCfg


## Returns the nimr cache directory under ``$HOME/.cache/nimr``.
proc cacheDirNimrGet(): string =
  let home = getEnv("HOME")
  if home.len == 0:
    stderr.writeLine "nimr: HOME is not set"
    quit(1)
  home / ".cache" / "nimr"


## Returns the absolute path to the cached executable for ``hashHex``.
proc cacheBinaryPathGet(hashHex: string): string =
  let dir = cacheDirNimrGet()
  createDir(dir)
  when defined(windows):
    dir / hashHex & ".exe"
  else:
    dir / hashHex


## Deletes the nimr cache directory when it exists.
proc cacheClearRun() =
  let dir = cacheDirNimrGet()
  if not dirExists(dir):
    return
  try:
    removeDir(dir, checkDir = false)
  except CatchableError as e:
    stderr.writeLine "nimr: could not clear cache: ", e.msg
    quit(1)
  stderr.writeLine "nimr: cleared ", dir


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
      stderr.writeLine "nimr: pixi.toml found (", manifest, ") but pixi is not on PATH"
      stderr.writeLine "nimr: install pixi: https://pixi.sh"
      quit(1)
    let args = @["run", "--manifest-path", manifest, "nim"] & compileTail
    return coreProcessExitCodeWait(pixiExe, args, workDir)
  let nimExe = findExe("nim")
  if nimExe.len == 0:
    stderr.writeLine "nimr: nim is not on PATH"
    stderr.writeLine "nimr: install Nim, or add pixi.toml + nim via pixi (https://pixi.sh)"
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


## Prints help for the ``run`` subcommand (stdout).
proc coreRunHelpPrint() =
  stdout.writeLine """
Compile (if needed) and execute a Nim source file. Extra tokens are forwarded to the compiled
program unchanged.

Usage:

nimr run <script.nim> [args...]

Use ``nimr run -h`` only when there is no script argument (same for ``--help`` / ``--helpsyntax``).
""".strip()


## Exported cligen entry for ``cacheClear``.
proc cacheClear*() =
  cacheClearRun()


## Compiles the first path when the content-hash cache misses, then runs the cached binary.
## Remaining tokens are forwarded to the compiled program unchanged.
proc runExecute(scriptAndArgs: seq[string]) =

  if scriptAndArgs.len == 0:
    stderr.writeLine "nimr: run: expected <script> [args...]"
    quit(1)

  let script = scriptAndArgs[0]
  let args =
    if scriptAndArgs.len > 1:
      scriptAndArgs[1 .. ^1]
    else:
      @[]

  let scriptPath = expandFilename(absolutePath(script))
  if not fileExists(scriptPath):
    stderr.writeLine "nimr: not a file: ", scriptPath
    quit(1)

  let raw = readFile(scriptPath)
  let normalized = coreNormalizeForHash(raw)
  let hashHex = $secureHash(normalized)
  let binaryPath = cacheBinaryPathGet(hashHex)

  if fileExists(binaryPath):
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

  runBinaryExec(binaryPath, args)


when isMainModule:
  let ps = commandLineParams()
  if ps.len >= 1 and ps[0] == "run":
    if ps.len == 2 and ps[1].len > 0 and ps[1][0] == '-' and ps[1] in ["-h", "--help", "--helpsyntax"]:
      coreRunHelpPrint()
      quit(0)
    runExecute(ps[1 .. ^1])

  dispatchMulti(
    [
      "multi",
      cf = coreClCfg,
      doc = """

Single-file Nim runner: content-hash cache, optional temp module when the path is not a valid Nim module filename, then nim c and execute.

Usage:

nimr -h
nimr run -h
nimr run <script.nim> [args...]
nimr cacheClear

""",
      noHdr = true,
      usage = "${doc}\nOptions:\n$$options",
    ],
    [
      cacheClear,
      doc = """

Remove the nimr content-hash cache directory (``$HOME/.cache/nimr`` when ``HOME`` is set).

Usage:

nimr cacheClear

""",
      mergeNames = @["nimr", "cacheClear"],
      noHdr = true,
      usage = coreUsageTmpl,
    ],
  )
