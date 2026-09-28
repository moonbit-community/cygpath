# 04 Library API, CLI, and moonx Delivery

Status: implemented and verified within the frozen P3 pure MoonBit,
explicit-context matrix at `b32dd7448658bc251b216ba93a5c120ef54fdbc9`.
See [the architecture index](README.md) and [remote validation](09-remote-validation.md)
for exact host/backend and official-program evidence. P3 completion does not
mean complete Windows runtime emulation or publication: registry retrieval and
version-pinned `moonx` acceptance remain release gates.

The generated [library interface](../lib/pkg.generated.mbti) is authoritative
for public signatures. Executable examples are in [the library guide](../lib/README.mbt.md).
Path algorithms and profile distinctions are defined in [03](03-path-semantics.md).

## 1. Public library API

Import `ZSeanYves/cygpath/lib`. The module root `ZSeanYves/cygpath` is the
executable coordinate. Public concrete conversion types belong to `lib/`;
internal command-line and host types are not consumer library API.

| Type | Purpose |
| --- | --- |
| `InputSyntax` | `Windows` or `Posix`; no automatic library grammar |
| `OutputFormat` | `Windows`, `Mixed`, or `Posix` |
| `Profile` | `Cygwin` or `Msys2`: drive-prefix default, mount ordering, and mapped-root behavior |
| `UnixPrefix` | `Configured` or `ProcCygdrive`, affecting unmatched drive fallback |
| `MountCase` | `Sensitive` or ASCII-only `AsciiInsensitive` |
| `Mount` | Opaque validated absolute POSIX-to-Windows mapping |
| `Context` | Opaque immutable explicit mapping/cwd snapshot |
| `ConversionError` | Checked, structured failures without host exception objects |

Signatures below omit the implicit method receiver and summarize defaults:

```text
Mount::new(posix, windows, case?=Sensitive)
  -> Mount raises ConversionError

Context::new(profile?=Cygwin, drive_prefix?, mounts?=[],
             posix_cwd?, windows_cwd?, drive_cwds?=empty)
  -> Context raises ConversionError

Context::convert(path, from~, to~, absolute?=false,
                 unix_prefix?=Configured)
  -> String raises ConversionError

Context::convert_list(paths, from~, to~, absolute?=false,
                      recognize_windows?=false, unix_prefix?=Configured)
  -> String raises ConversionError
```

Reuse a Context across conversions. Its constructor copies collections and
validates mounts, prefixes, cwd, and drive metadata. `drive_cwds` is validated
metadata, not a conversion-base override: explicit Windows drive-relative
conversion follows cygpath's drive-root rule. Context never reads the host.

`convert_list` owns source delimiters, empty-member handling, and atomic failure.
Its optional `recognize_windows` flag recognizes backslash-containing members
of an already-split POSIX list, as needed by the CLI. The default keeps library
source grammar explicit. Callers with structured arrays can call `convert`
under their own batch policy; no generic batch framework is imposed.

## 2. Structured errors and diagnostic ownership

| Library error | Payload and meaning |
| --- | --- |
| `EmptyPath` | Empty single-path input |
| `PathTooLong(String)` | Original path with an overlong Windows-output component |
| `InvalidDrivePrefix` | Configured drive branch is not followed by one ASCII drive letter |
| `InvalidPath(reason~, offset~)` | Invalid text/structure, including NUL or unpaired UTF-16 |
| `InvalidContext(field~, reason~)` | Invalid mount, cwd, prefix, or drive metadata |
| `MissingContext(field~)` | A required mapping or source cwd is absent |
| `UnsupportedNamespace(String)` | Unsupported device, incomplete UNC, or virtual mapping |
| `UnrepresentablePath(component~, reason~)` | Unsupported ordinary component/authority spelling |
| `InvalidOptions(String)` | Invalid library option combination |
| `ListEntryError(index~, cause)` | Original zero-based member index and underlying error |

The caller retains input/output request metadata. The library returns errors,
not formatted English messages, and never returns a partial list.

`internal/cli` owns argument errors and wraps conversion errors. Its
`ListConversion(original, cause)` retains a typed `ListEntryError` while emitting
the observed whole-list diagnostic. `internal/host` classifies file-not-found,
permission, non-directory, read/write, and UTF-8 decoding failures. The root
entry point dispatches on types, never on exception-message substrings.

Project-specific failures use stable identifiers such as `missing-context` and
`unsupported-capability`, with escaped values. Official option errors use the
observed usage/getopt protocol. Known conversion failures quote the **raw**
original operand, including backslashes and any control characters:

```text
cygpath: can't convert empty path
cygpath: error converting "NAME" - File name too long
cygpath: error converting "NAME" - No such file or directory
cygpath: error converting "WHOLE_LIST" - Unknown error -1
```

The final form applies to the tested list-member length and invalid-drive-prefix
failures: the upstream wrapper assigns a nested `-1` result to errno. Unsupported
project namespaces retain their typed project diagnostics. Diagnostic methods
return text without the final LF; root appends LF and writes stderr. Library
indices/UTF-16 offsets are zero-based; host input-record numbers are one-based.
Exact process expectations and raw evidence remain separate validation assets.

## 3. Executable entry point and package coordinate

The executable package is the repository root, with `main.mbt` directly there
and `pkgtype(kind: "executable")` in its `moon.pkg`. The entry point composes pure
argument/conversion code with general-purpose MoonBit runtime I/O. It performs
no Windows conversion FFI and never launches system cygpath as a fallback.

Local invocation:

```sh
moon run --target wasm . -- -u 'C:\work\demo.txt'
moon run --target native . -- -u 'C:\work\demo.txt'
```

After publication and namespace verification, ordinary usage is through the root
coordinate. These are future delivery examples; `<published-version>` is not
an already-published release:

```text
moonx ZSeanYves/cygpath -h
moonx ZSeanYves/cygpath -u 'C:\work\demo.txt'
moonx ZSeanYves/cygpath@<published-version> -u 'C:\work\demo.txt'
```

The `--` above separates `moon run` arguments. Cygpath itself accepts normal
short flags such as `-h`, `-u`, and `-aw`. The development version output is:

```text
cygpath (MoonBit) 0.1.0
Profiles: cygwin, msys2
```

It ends with LF and identifies this implementation rather than impersonating an
official version. Help documents project extensions and supported capabilities.
The root README is ordinary `README.md`; compiled documentation examples belong
in `lib/README.mbt.md` because the root package is executable.

Root and host I/O support Wasm and Native. The pure library and CLI compile for
all standard compiler targets, which does not imply JavaScript/Wasm GC CLI I/O
support. On 2026-09-28, local `moonx --help` confirmed coordinate/version syntax
and default Wasm delivery; its Native option was deprecated. Verify Native
through development build/run commands, and recheck current tooling at release.

## 4. Parser and execution interfaces

`parse_args(Array[String])` receives already-tokenized argv without the executable
name. It performs no I/O and returns `Help`, `Version`, `ExitSuccess`, or
`Convert(Request)`. `ExitSuccess` covers an ignored usage/no-input condition.
Request exposes `input()` (`Names` or `File`), `ignore_missing()`,
`per_line_options()`, and `prepare()`. Input arrays are copied.

`prepare()` creates a Converter with one validated immutable Context and mutable
conversion flags. `convert(path)` returns one string; `convert_operand(path)`
handles `-i` and returns `RecordAction`. `convert_file_record(record)` additionally
applies `-o` parsing/state. `RecordAction` is `Output(String)`, `Skip`, or
`Stop(String)`. Root writes Output using `codepage()`, ignores Skip, and writes
Stop control text as UTF-8 before ending the stream. These are internal
integration interfaces, not additions to the public library surface.

The parser does not repeat shell tokenization, remove backslash escapes, expand
variables, or interpret globs. GNU-style argument permutation permits options
after NAME arguments while preserving NAME order. `--` ends option parsing;
`-` is an ordinary NAME unless consumed as a file option's value.

Short flags may be combined (`-aw`). A value-taking short flag consumes the rest
of its token or the next argument (`-twindows`, `-C1252`, `-f input.txt`). Long
options accept `--type=windows` and `--type windows`. Unique official long-option
prefixes are recognized; ambiguous prefixes fail. Project extensions require
exact spelling and do not create new ambiguity among official option names.

Options are interpreted in scan order. Help/version stop at their position and
skip subsequent validation, context construction, and file reads. Thus
`-h --bad` shows help, while `--bad -h` fails; `-hV` shows help. Earlier immediately
invalid type/codepage syntax still fails before later help. Conflicts determined
after scanning may be bypassed by an earlier help/version action, matching the
official control flow.

## 5. Options and precedence

| Option | Implemented behavior |
| --- | --- |
| `-u`, `--unix` | POSIX output; ordinary default |
| `-w`, `--windows` | Windows output with backslashes |
| `-m`, `--mixed` | Windows semantics with forward slashes |
| `-t`, `--type TYPE` | Case-insensitive `unix`, `windows`, or `mixed`; `dos` is recognized but unsupported |
| `-a`, `--absolute` | Resolve relative paths from explicit context |
| `-p`, `--path` | Convert each NAME/record as one atomic PATH list |
| `-U`, `--proc-cygdrive` | POSIX drive fallback through `/proc/cygdrive`; ignored for Windows/Mixed output |
| `-r` | Add a root-local prefix to single Windows output; does not alter list output |
| `-f`, `--file FILE` | Read UTF-8 records from a file; `-` selects stdin |
| `-o`, `--option` | Interpret leading-hyphen records as per-record option declarations; requires `-f` |
| `-i`, `--ignore` | Skip empty operands/records and suppress official usage failures occurring after this flag |
| `-C`, `--codepage CP` | Select an implemented output encoding; ignored for POSIX output after syntax validation |
| `-A`, `--allusers` | Accepted without effect on ordinary conversion |
| `-h`, `--help`; `-V`, `--version` | Implementation help/version |

Repeated output flags are accepted. `-w` together with `-m` selects Mixed in
either order; POSIX plus Windows flags conflict except in the upstream's outer
`-o` configuration. `-r` requires Windows output and conflicts with Mixed,
short-name, or long-name modes. The upstream `--root-local` long spelling is
rejected in the pinned behavior; use `-r`.

`-i` is stateful during option scanning: `-i -tinvalid` exits successfully without
output, but `-tinvalid -i` fails. It does not suppress unknown/getopt errors,
conversion failures, missing context, invalid encoding, or I/O errors. No NAME
without `-i` is a usage failure; an explicitly selected empty input stream is
successful without needing `-i`.

The last `-f` value wins; `-f` and NAME cannot be combined. The last `-C` value
wins. Identical scalar project context declarations may repeat; conflicting
values fail. Mounts append, and Context rejects duplicates/conflicts. Duplicate
`--drive-cwd` letters are rejected after ASCII case folding.

Recognized but unsupported capabilities remain explicit errors: `-d/--dos`,
`-s/--short-name`, `-l/--long-name`, `-M/--mode`, `-c/--close HANDLE`,
`-D/--desktop`, `-H/--homeroot`, `-O/--mydocs`, `-P/--smprograms`, `-S/--sysdir`,
`-W/--windir`, and `-F/--folder ID`. Invalid combinations are diagnosed before
attempting unavailable capabilities. See [01](01-upstream-and-scope.md) for the
complete capability inventory.

## 6. Explicit context and natural input recognition

These project extensions change the request, never the real host environment:

| Option | Meaning |
| --- | --- |
| `--from windows\|posix` | Override natural source recognition |
| `--profile cygwin\|msys2` | Select drive-prefix defaults and profile-specific mapping rules |
| `--root WINDOWS` | Add `/` as an explicit mount, without implicit aliases |
| `--mount POSIX WINDOWS` | Append a mount using two operands |
| `--mount-case POSIX sensitive\|ascii-insensitive` | Set a matching mount's comparison policy, independent of declaration order |
| `--drive-prefix POSIX` | Override the profile's default prefix |
| `--posix-cwd POSIX` | Supply an absolute POSIX cwd |
| `--windows-cwd WINDOWS` | Supply an absolute Windows cwd/current drive |
| `--drive-cwd DRIVE WINDOWS` | Validate per-drive cwd metadata; does not alter drive-relative conversion |

Mount-case paths normalize trailing `/`; a policy without a matching mount is
an error. Default comparison is Sensitive. No process cwd, HOME, MSYSTEM,
registry, or installation-root guessing populates Context.

With no `--from`, POSIX output uses Windows grammar plus its already-POSIX
absolute passthrough. Single Windows/Mixed output recognizes a drive prefix,
backslashes, or ordinary extended/device prefix; otherwise it uses POSIX grammar.
Complete UNC is supported in either grammar. A single-backslash-rooted natural
Windows input resolves against the explicit Windows current drive.

For Windows/Mixed output, a bare drive (`C:`), or a drive-relative operand with
`-a` (`C:child`), follows the official CLI's literal POSIX-relative branch.
Given `posix_cwd=/cygdrive/c/cwd`, `-aw C:child` produces
`C:\cwd\C<U+F03A>child`, whereas explicit `--from windows -aw C:child`
produces `C:\child`. `-u C:child` yields `/cygdrive/c/child`. Per-drive metadata
does not change these rules.

Natural list input uses Windows syntax for POSIX output and POSIX syntax for
Windows/Mixed output. After delimiter splitting, backslash-containing members
of a POSIX list use Windows grammar. Consequently, `-wp 'C:\one'` splits on the
colon; use `--from windows` when deliberately supplying a Windows list for
Windows output. `-u /usr/bin` needs no override; explicit `--from posix` is useful
when the caller wants POSIX normalization rather than spelling passthrough.

Examples below show literal argument values; quote them for the actual shell:

```text
cygpath -w --root C:\cygwin64 /usr/bin
  => C:\cygwin64\usr\bin

cygpath -w --root C:\cygwin64 --mount /usr/bin C:\cygwin64\bin /usr/bin
  => C:\cygwin64\bin

cygpath -u --profile msys2 C:\work
  => /c/work

cygpath -aw --root C:\cygwin64 --posix-cwd /home/user ../work
  => C:\cygwin64\home\work
```

MSYS shells may rewrite argv before launching a program. The official collector
records and controls launch transport; product parsing cannot reconstruct argv
that a parent already changed.

## 7. File records and `-o` state

`-f FILE` and `-f -` stream input incrementally. The byte protocol is:

1. Translate CRLF to LF. Preserve a standalone CR, including a final CR at EOF.
2. End a record at LF or after 8192 bytes following CRLF translation, matching
   the official `fgets` capacity. LF itself is not part of the path. A longer
   physical line becomes independently converted chunks.
3. Treat the first NUL in a record as the end of path text. Bytes after it in
   that record are not UTF-8-decoded; subsequent records are still processed.
4. Decode the visible bytes as strict UTF-8. Retain BOM characters at every
   position, including byte zero. Preserve spaces and a final unterminated record.

An empty stream succeeds with no output. A BOM-only stream contains a BOM path.
An empty record is an empty operand, including in list mode: report
`can't convert empty path` with exit 1, or skip it with `-i`. Malformed UTF-8
fails deterministically, preserving earlier output. Upstream malformed-input
and unavailable-CP29001 observations are retained as separately identified
boundaries, not advertised as successful conversion matches.

With `-o`, only a record whose first character is `-` starts option parsing.
Split it at its first ASCII whitespace character: the first token is an option
bundle, and the remaining text after leading whitespace is **one** operand.
Do not apply shell quoting or split the remaining path on spaces. A value-taking
option can use its attached value (`-tWindows /path`); `-t windows /path` instead
passes `windows /path` as its type value and fails.

Each option record resets conversion flags to defaults, applies that record's
options, and converts its optional path under the same fixed Context. Plain
records reuse the latest state. Output type, absolute/list/proc/root-local flags,
ignore, explicit source grammar, and codepage all participate in that lifecycle.
The outer `-o` mode remains enabled. Before an option record selects a format,
outer `-o` without an output selector follows the official Windows-output default.

`-f` and `-o` inside option records are usage errors. The project Context is
immutable for the stream: `--profile`, `--root`, `--mount`, `--mount-case`,
`--drive-prefix`, `--posix-cwd`, `--windows-cwd`, and `--drive-cwd` in an option
record are explicitly rejected. `--from` remains permitted and effective.
A help/version record stops the stream after control output. An ignored usage
record, such as `-i` with no operand, stops successfully without processing later
records. An ignored empty operand skips only that operand.

## 8. Output encoding and failure ordering

Each successful conversion is encoded, then followed by one raw LF byte. Default
output is UTF-8; POSIX output always uses UTF-8. Windows/Mixed output additionally
supports 110 stateless legacy code pages plus UTF-8/65001. Their identities,
mapping hashes, default characters, and source notices are frozen in the
[Microsoft catalog](../third_party/microsoft/codepages.json) and
[Unicode catalog](../third_party/unicode/codepages.json). Numeric pages use
Windows best-fit mappings; unmapped UTF-16 words use the table's default
character, so an unmapped supplementary scalar can yield two replacement bytes.

`UTF8` and `UTF-8` aliases are case-insensitive. Numeric `-C` values use the
official decimal `strtoul` grammar: leading ASCII whitespace and an optional sign
are accepted; hex prefixes, underscores, and trailing junk are rejected.
Unsigned-long overflow saturates before conversion to a 32-bit page number.
`-C 4294968548`, for example, selects 1252. `-i` observes syntax errors in scan
order. Repeated `-C` replaces the previous selection.

Windows-output `ANSI`, `OEM`, and `0` require unavailable host selection and are
rejected. CP29001 and unimplemented/stateful pages are also rejected. POSIX
output ignores a syntactically valid codepage selection, including unavailable
identities, because that branch does not invoke the Windows encoder. No locale
or platform codec participates in product encoding.

There is no blanket CR/LF rejection in NAME arguments or results: POSIX output
can contain embedded line breaks before the final LF. Therefore output is not an
unambiguous one-line serialization of arbitrary path strings. Only encoded path
bytes are affected by `-C`; record LF, help/version, and diagnostics use the
specified raw/UTF-8 protocol without host newline translation.

Process NAMEs or file records in order, stopping on the first failure. Earlier
successful output remains visible. Convert an entire PATH list before writing
it. Stop after output failure without retrying the batch or processing later
records. stdout contains results or control text; stderr contains diagnostics.

## 9. Exit statuses

| Status | Meaning |
| --- | --- |
| 0 | Successful conversions, help/version, empty stream, skipped empty operands, or ignored usage |
| 1 | Option/context/I/O/encoding/capability failure; empty path; path too long; invalid drive prefix; known whole-list runtime-style failure |
| 2 | Other typed path-content failures, including InvalidPath, UnrepresentablePath, and UnsupportedNamespace |

Ordinary wrapped `ListEntryError` uses its cause's category; the known
`ListConversion` wrapper uses 1 and retains its typed cause. Unknown runtime
exceptions produce `cygpath: internal-error: unexpected runtime failure` and
exit 1. A failed stderr write does not turn failure into success. These are
implemented, tested classifications, not a promise to reproduce every error
branch of the full Windows runtime.

## 10. Delivery and remaining release gates

P3 verifies the frozen supported matrix against measured Cygwin/MSYS2 binaries,
with separate boundary outcomes and fault drills. Publication is still separate.
A release must retrieve and run the exact published version through `moonx`,
without local source or system cygpath, and exercise help, version, successful
conversion, invalid input, stdin, and exit status. Native from the same source
must retain the corresponding contract behavior.

Local installation and package-content inspection establish useful prerequisites
but cannot prove registry availability. Keep the root coordinate
`ZSeanYves/cygpath` until the publishing namespace is explicitly settled. If an
I/O or capability gate fails, retain the evidence; custom C stubs, shell
fallbacks, and backend-specific conversion rules remain prohibited.
