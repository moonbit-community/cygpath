# 04 Library API, CLI, and moonx Delivery

Status: implemented library and initial CLI contract. See [the architecture index](README.md) for current host/backend verification and open acceptance gates. The generated `lib/pkg.generated.mbti` is authoritative for the public library API. The pseudocode signatures below summarize the contract; executable MoonBit examples live in [the library guide](../lib/README.mbt.md). Portable CLI acceptance has run on Linux, macOS, and Windows; selected real Windows differential results are recorded in [the remote validation report](09-remote-validation.md). Broader official compatibility and registry/moonx acceptance remain separate requirements.

## 1. Minimal library surface

The public library package is `ZSeanYves/cygpath/lib`. Public concrete types belong to `lib/`; do not define them in an `internal` package and re-export them. The module root `ZSeanYves/cygpath` is reserved for the executable entry point and is not a library import path.

| Type | Design |
| --- | --- |
| `InputSyntax` | Windows / Posix; no Auto |
| `OutputFormat` | Windows / Mixed / Posix; no unsupported Dos variant |
| `Profile` | Cygwin / Msys2 |
| `UnixPrefix` | Configured / ProcCygdrive; affects only the drive fallback mapping |
| `MountCase` | Sensitive / AsciiInsensitive; not full Windows Unicode case folding |
| `Mount` | Validated POSIX absolute mount point, Windows absolute target, and comparison policy |
| `Context` | Opaque mapping and cwd snapshot, immutable after construction |
| `ConversionError` | Typed errors suitable for pattern matching, without host exception objects |

Constructor and conversion pseudocode signatures:

```text
Mount::new(posix, windows, case?=Sensitive) -> Mount raises ConversionError

Context::new(profile?=Cygwin, drive_prefix?, mounts?=[],
             posix_cwd?, windows_cwd?, drive_cwds?=empty)
  -> Context raises ConversionError

Context::convert(path, from~, to~, absolute?=false,
                 unix_prefix?=Configured)
  -> String raises ConversionError

Context::convert_list(paths, from~, to~, absolute?=false,
                      unix_prefix?=Configured)
  -> String raises ConversionError
```

Use MoonBit labeled parameters for optional settings rather than introducing a large Options structure for one call. Context is a reusable domain object holding related state. The first implementation may expose only its completed subset. API expansion requires corresponding tests and mbti updates; do not reserve API names with public methods that always raise NotImplemented.

`convert_list` is distinct from repeated `convert` calls: it owns direction-specific separators, empty-member semantics, and atomic failure. Callers that already have arrays can call `convert` according to their own batch failure policy. Do not add a generic batch-processing framework initially.

## 2. Structured errors and diagnostics

| Error category | Information for diagnostics | Example |
| --- | --- | --- |
| EmptyPath | Input category from the caller's request; no error payload | Empty single-path string |
| InvalidPath | Reason and UTF-16 offset when available | NUL or incomplete ordinary prefix |
| InvalidContext | Field/mount index and reason | Relative mount target or duplicate mount point |
| MissingContext | Required field and relevant drive | `C:a` without a cwd for C |
| UnsupportedNamespace | Prefix category | Extended or device namespace |
| UnrepresentablePath | Component and reason in the error; target format from the caller's request | A filename not representable in Windows |
| InvalidOptions | Conflicting combination | ProcCygdrive requested for non-POSIX output |
| ListEntryError | Original member index and underlying error | Conversion of the third member fails |

Input syntax and output format are explicit conversion arguments. Callers retain
them when composing diagnostics; errors do not duplicate that request metadata.
The generated interface records the exact payload of each error constructor.

`internal/cli` owns `CliError`, including unknown options, missing values,
conflicting options, unsupported capabilities, missing input, invalid records,
and wrapped library conversion failures. `internal/host` owns `HostError`, with
`ReadError`, `WriteError`, and `InvalidEncoding`. These host/command-line errors
do not belong in the pure library. Main matches their categories to choose a
diagnostic and exit status; it does not parse English messages.

Use checked errors for foreseeable input failures. Do not panic or silently
return the original input. CLI diagnostics use stable ASCII error identifiers,
fixed short English messages, and necessary position information, such as
`cygpath: missing-context: "root or mount"`. User-controlled values are quoted
and escaped. Each diagnostic formatter returns one string without LF; main
appends LF and writes it to stderr. Exact expected bytes are frozen in
[`testdata/contracts/cli.json`](../testdata/contracts/cli.json), with execution
results recorded separately. Library/list indices and UTF-16 offsets are zero
based; file diagnostic line numbers are one based.

## 3. Command-line entry point

The executable package is the module root. Place `main.mbt` directly in the repository root and declare `pkgtype(kind: "executable")` in the root `moon.pkg`. The public library resides in `lib/`. After publication, users pass options and paths directly to `moonx ZSeanYves/cygpath`. The root main only orchestrates arguments, I/O, and execution.

For the implemented local executable, use:

```sh
moon run --target wasm . -- -u 'C:\work\demo.txt'
moon run --target native . -- -u 'C:\work\demo.txt'
```

After publication and namespace verification, use the root coordinate for ordinary invocation and pin a version for reproduction. `<published-version>` is a placeholder; no version has been published yet:

```text
moonx ZSeanYves/cygpath -h
moonx ZSeanYves/cygpath -u 'C:\work\demo.txt'
moonx ZSeanYves/cygpath@<published-version> -u 'C:\work\demo.txt'
```

Toolchain evidence: on 2026-09-28, local `moonx --help` confirmed package coordinates, version pinning, and the default `wasm` target; `moon install --help` confirmed local executable-package installation. The [official package configuration documentation](https://docs.moonbitlang.com/en/latest/toolchain/moon/package.html) confirms the executable declaration. Current `moonx` help still lists native but marks it deprecated and scheduled for removal, so `moonx --target native` must not be treated as the long-term delivery entry point. Check Native consistency through `moon run/build`.

CLI version output must identify the MoonBit implementation, its own module version, and supported profiles. It must not impersonate an official Cygwin version. Version-pinned invocation supports reproduction; `@latest` is appropriate for intentional updates, not benchmark coordinates.

The current development version record is:

```text
cygpath (MoonBit) 0.1.0
Profiles: cygwin, msys2
```

The record ends with LF. The root module uses ordinary `README.md` because the
root package is executable; checked library examples remain in
`lib/README.mbt.md`. Root and `internal/host` currently support Wasm and Native.
The pure library and argument/conversion layer compile for all standard targets;
this does not imply JavaScript or Wasm GC command-line I/O support.

## 4. Option parsing and execution model

The CLI separates pure `parse_args`, pure application execution, and main's I/O orchestration. argv is the string array provided by the runtime. Do not repeat shell tokenization, backslash decoding, or variable expansion.

`parse_args` returns `Help`, `Version`, or `Convert(Request)`. An opaque Request
exposes `input()` (`Names` or `File`), `ignore_missing()`, and `prepare()`.
Preparing a conversion creates an opaque Converter with one validated Context;
`Converter::convert` handles one NAME/file record, including list conversion
when requested. None of these operations performs I/O. Request input arrays are
copied so callers cannot mutate the stored request. These integration types
belong to the internal CLI package and are not public library API.

Implemented output options are `-u/-w/-m`, `--unix/--windows/--mixed`, and `-t/--type`, with `-u` as the default. `-a/--absolute`, `-p/--path`, `-U/--proc-cygdrive`, and `-f/--file` control absolute resolution, list conversion, the prefix, and the input source respectively. `-i/--ignore` handles missing input only; it does not suppress conversion errors. Help and version use `-h/--help` and `-V/--version`.

Arguments in entry-point examples illustrate usage and do not require double hyphens. Short options use one hyphen; long options use the corresponding names above. The root `moonx` entry point does not change cygpath option spelling.

Short options may be combined, as in `-aw`. A short option's value may be attached or supplied in the next argument. Long options accept both `--type=windows` and `--type windows`. Everything after `--` is a NAME rather than an option. Initially, options are allowed only before the first NAME. Option-like text after a NAME is treated as a path. This is a portable CLI rule; retain its difference from GNU argument permutation in the compatibility matrix.

Repeated declarations of the same format are allowed when they do not conflict. Conflicting output formats produce InvalidOptions; do not silently use the last one. Recognize `-t dos` and `-d/-s`, but return UnsupportedCapability rather than treating them as ordinary Windows output. Diagnose conflicts among `-r/-l/-s` explicitly even while those capabilities are unavailable. Parsing must not silently discard unsupported capabilities.

Identical scalar context and file declarations may repeat; conflicting values
fail. `--mount` appends in declaration order, with duplicate or conflicting
mounts rejected during context construction. `--drive-cwd` accepts one ASCII
drive letter and rejects any duplicate after case folding. Supplying both help
and version is a conflict. Unsupported and malformed options still fail when
help/version is present; valid help/version skips context construction and file
reads.

`-U` with non-POSIX output is an invalid combination. Known unsupported options such as `-o`, `-M`, `-c`, system-directory options, and non-UTF-8 code pages explain why the capability is unsupported; only unknown names produce UnknownOption. See 01 for the complete inventory. P2 supports `-C UTF8`/`-C 65001` as explicit UTF-8 selection, restricted to Windows/Mixed output. `-C 0` remains unsupported rather than pretending to implement locale-dependent behavior.

For ordinary conversion requests, finish validating all options before reading files or producing stdout. Execute help/version control commands after successful parsing, without constructing context or reading files.

## 5. CLI extensions for explicit context

These options are project additions, not claimed to come from official cygpath:

| Option | Meaning |
| --- | --- |
| `--from windows\|posix` | Explicit input syntax, especially for lists and ambiguous paths |
| `--profile cygwin\|msys2` | Default to cygwin; explicitly switch prefix style |
| `--root WINDOWS` | Create the `/` root mount without implicit `/usr/bin` or other aliases |
| `--mount POSIX WINDOWS` | Repeatable; add ordinary mounts in declaration order, using two separate arguments to avoid colon ambiguity |
| `--drive-prefix POSIX` | Override the profile's default drive prefix |
| `--posix-cwd POSIX` | Supply cwd for making POSIX relative paths absolute |
| `--windows-cwd WINDOWS` | Supply cwd for Windows relative paths |
| `--drive-cwd DRIVE WINDOWS` | Repeatable; supply a drive-specific current directory |

Initial CLI mounts use the Sensitive policy; library callers may explicitly choose AsciiInsensitive. Do not read the process cwd, `HOME`, `MSYSTEM`, or the registry to guess Context. Every option changes only the request's context, never the actual environment, mount table, or current directory.

Determine the input direction as follows: honor `--from` first; otherwise, `-u` uses Windows and `-w/-m` use Posix. However, a single path outside list mode with a drive prefix, backslash root, or extended/device prefix is explicitly recognized as Windows. Do not infer a mixture of syntaxes member by member within a list. Complete double-forward-slash UNC is explicitly supported in both syntaxes. A same-format input such as `-u /usr/bin` requires `--from posix`; do not leave the ambiguity to the host machine.

Examples of the implemented explicit-context rules:

```text
cygpath -w --root C:\cygwin64 /usr/bin
  => C:\cygwin64\usr\bin

cygpath -w --root C:\cygwin64 --mount /usr/bin C:\cygwin64\bin /usr/bin
  => C:\cygwin64\bin

cygpath -u --profile msys2 C:\work
  => /c/work

cygpath -w -a --root C:\cygwin64 --posix-cwd /home/user ../work
  => C:\cygwin64\home\work
```

Spaces and backslashes in these examples are argument values; quote them according to the shell used in an actual terminal. In particular, MSYS2 may rewrite argv before launching a native program. The differential harness must control that boundary.

## 6. Input records and output protocol

Process NAME arguments in order. Write each successful result as one UTF-8 record followed by LF. Multiple NAME arguments and `-p` are independent dimensions: one NAME may contain an entire PATH list. stdout contains only results, help, or version output; diagnostics go to stderr.

`-f FILE` and `-f -` are implemented. The first version prohibits combining `-f` with NAME to avoid ambiguous ordering. Files are read incrementally, accepting LF/CRLF and removing only line terminators, without trimming path spaces. A UTF-8 BOM is allowed and removed only at the first byte position of the file; a BOM elsewhere is path content. The final line need not have a terminator. A BOM-only file has no records, while a BOM followed by LF has one empty record. Memory use is bounded by the longest individual record, not the complete file.

An empty line is an empty path and fails with EmptyPath; in `-p` mode, use the empty-list semantics from 03 instead. An empty file counts as no input, which `-i` may turn into success with no output. This empty-file/empty-line policy is a portable contract. The recorded official differences below do not broaden `-i` or change that policy.

All output uses UTF-8 regardless of Windows OEM/ANSI code pages or the environment locale. Do not translate line endings for the platform. Because the CLI uses a line protocol, validate CR/LF in NAME arguments and in each file/stdin record after removing its terminator, rejecting remaining embedded line breaks. Converted output is checked as well, including POSIX names introduced by explicit context. Such failures are `InvalidRecord` with exit code 2. Library single-path behavior is determined by its own syntax contract. File/stdin decoding rejects invalid UTF-8 rather than replacing characters automatically; argv is supplied as strings by the runtime.

Process multiple NAME arguments or file lines in order and stop at the first conversion failure. Earlier successful output may already have been written. An individual list must convert completely before its line is written. After an output I/O failure, do not process later input or automatically retry the entire batch and duplicate results.

`-i` only permits success with no output when there is no input at all. It does not suppress empty paths, invalid encoding, unknown options, missing context, or file-read errors.

The pinned Windows runs observed the following differences in both official
profiles. These descriptions apply to the collected fixtures, with exact raw
bytes, status, versions, and review records in
[the remote validation report](09-remote-validation.md):

| Recorded case | Project contract | Observed official behavior |
| --- | --- | --- |
| Empty stdin without `-i` | Missing-input diagnostic, exit 1 | No output, exit 0 |
| Empty single-path record or operand | Empty-path diagnostic, exit 2; preserve earlier output and stop | Different diagnostic, exit 1; the tested partial-input cases preserve the same earlier stdout |
| Initial UTF-8 BOM | Remove it only at byte zero | Retain it as path content |
| Malformed UTF-8 after a valid record | Preserve the earlier record, report invalid encoding, stop with exit 1 | Repeat the previous record, continue processing, and exit 0 in the measured fixture |
| Embedded LF in an operand | Reject it with InvalidRecord, exit 2 | Emit the embedded LF and exit 0 |

Reviewed differences remain failed byte/status comparisons in the raw oracle
records. They are accepted only under the explicit portable policies and exact
observations recorded for those fixtures; they are not blanket allowances for
new output. The portable contract suite continues to check the project behavior
independently. Unmeasured stream, platform, and filesystem conditions retain their
acceptance gates.

## 7. Exit-code contract

The project's stable exit codes form a portable CLI contract. They must not be claimed to match every official error branch:

| Exit code | Meaning |
| --- | --- |
| 0 | Complete success, valid help/version, or no input with `-i` |
| 1 | Argument, context, encoding, read/write error, or known unsupported capability |
| 2 | Path/list content conversion failure in an otherwise valid request |

MissingContext / InvalidContext use 1; EmptyPath / InvalidPath / UnrepresentablePath / UnsupportedNamespace use 2. Classify ListEntryError by its underlying category. Never swallow an unknown exception and report success. Preserve evidence and a minimal regression case for internal defects found during implementation.

The initial host adapter reports stable input-read, output-write, or invalid-encoding diagnostics without exposing runtime-specific exception text. A failed diagnostic write still exits with the original failure code. Unknown runtime exceptions produce `internal-error` and exit 1. If a future diagnostic includes platform-specific details, retain the stable identifier and include the platform reason only as supplementary information. Backend consistency checks should first fix controllable failure categories, then record OS-specific reasons separately; do not compare errno text from different operating systems as equivalent evidence.

## 8. moonx delivery gates

Release requires: an actual executable-package build; a version-pinned Wasm artifact downloaded and run through moonx; no dependence on local source or system cygpath; real-launch acceptance of help, version, successful conversions, invalid input, standard input, and exit codes; and the corresponding contract cases for Native built from the same source.

`moon install ./` can check the local root executable package first, but does not replace real registry/moonx acceptance. `moon package --list` checks package contents only; it does not prove that the registry contains an executable artifact. Publication and unverified automatic publishing workflows are outside the current work.

If the runtime library cannot reliably provide a required I/O capability, retain the exact blocking issue. Do not bypass the pure MoonBit constraint with a custom C shim, shell command, or backend-specific workaround. See 05 for the relevant evidence requirements and phase gates.
