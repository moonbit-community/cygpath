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
| `MountCase` | `Sensitive`, `AsciiInsensitive`, or `WindowsInsensitive` |
| `Mount` | Opaque validated absolute POSIX-to-Windows mapping |
| `Context` | Opaque immutable explicit mapping/cwd snapshot |
| `ConversionError` | Checked, structured failures without host exception objects |

Signatures below omit the implicit method receiver and summarize defaults:

```text
Mount::new(posix, windows, case?=Sensitive)
  -> Mount raises ConversionError

Context::new(profile?=Cygwin, drive_prefix?, drive_prefix_bytes?, mounts?=[],
             posix_cwd?, windows_cwd?, drive_cwds?=empty)
  -> Context raises ConversionError

Context::convert(path, from~, to~, absolute?=false,
                 unix_prefix?=Configured)
  -> String raises ConversionError

Context::convert_list(paths, from~, to~, absolute?=false,
                      recognize_windows?=false, unix_prefix?=Configured)
  -> String raises ConversionError

Context::with_native_cwd(directory : String) -> Context raises ConversionError

Context::windows_to_posix_bytes(path, absolute?=false,
                                unix_prefix?=Configured, list?=false)
  -> Bytes raises ConversionError
```

Reuse a Context across conversions. Its constructor copies collections and
validates mounts, prefixes, cwd, and drive metadata. `drive_cwds` is validated
metadata, not a conversion-base override: explicit Windows drive-relative
conversion follows cygpath's drive-root rule. Context never reads the host.

`Mount::new` accepts either text or narrow bytes for each field. For a
byte-valued drive prefix, pass `drive_prefix_bytes` in place of `drive_prefix`.
`resolve_bind_source_bytes` returns the narrow native field and its mount index.

`with_native_cwd` derives the POSIX working directory from an observed Windows
directory using the existing mount table. A native component ending in U+F0FF
contributes byte `FF` to POSIX output. Windows output retains its native spelling.

`convert`, `relative_windows_name` and `mode_candidate` take either a
Unicode `String` or a narrow `Bytes` operand. For Windows output, byte
operands preserve filename bytes through mount and working-directory lookup.
For example, `convert(b"/cygdrive/c/\xff", from=Posix, to=Mixed)` returns
`C:/` followed by U+F0FF.

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
| `InvalidWindowsPrefix` | The remaining NT or extended Windows prefix has an invalid drive or UNC form during Windows-to-POSIX conversion |
| `NotDirectory` | A directory was required at a known virtual file or terminal |
| `PathNotFound` | The virtual filesystem has no such entry |
| `TooManyLinks` | Conversion exceeded Cygwin's ten-link lookup limit |
| `InvalidPath(reason~, offset~)` | Invalid text/structure, including NUL or unpaired UTF-16 |
| `InvalidContext(field~, reason~)` | Invalid mount, cwd, prefix, or drive metadata |
| `MissingContext(field~)` | A required mapping or source cwd is absent |
| `NetworkServerLookup(String)` | Cancelling a POSIX server component or rendering its absolute Windows/mixed directory spelling needs observed server presence |
| `UnsupportedNamespace(String)` | Unsupported device or virtual mapping, or an incomplete UNC path in a conversion requiring a share |
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
```

Mooncakes has a September release at `ZSeanYves/cygpath@0.1.0`. On macOS,
`moonx ZSeanYves/cygpath@0.1.0 -u 'C:\work\demo.txt'` returned
`/cygdrive/c/work/demo.txt`. The November validation branch still carries
the same version in its manifest. Its changes require a new owner release.
[Release tracking](https://github.com/moonbit-community/cygpath/issues/13)

Use the root coordinate to run a published version.

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

The executable and its host adapter target linear-memory Wasm for `moonx`.
The conversion library, parser and encoder also compile on other targets.
CI runs the Wasm executable on Linux, macOS and Windows.

## 4. Parser and execution interfaces

`parse_args(Array[String])` receives already-tokenized argv without the executable
name. It performs no I/O and returns `Help`, `Version`, `ExitSuccess`, or
`Convert(Request)`. `ExitSuccess` covers an ignored usage/no-input condition.
Request exposes `input()` (`Names`, `File` or `Folder`), `ignore_missing()`,
`per_line_options()`, and `prepare()`. Input arrays are copied.

`prepare()` creates a Converter with one validated immutable Context and mutable
conversion flags. `convert(path)` returns one string; `convert_operand(path)`
handles `-i` and returns `RecordAction`. `convert_file_record(record)` additionally
applies `-o` parsing/state. The executable uses `convert_file_bytes` for file and
stdin records. It encodes `Output` with the selected code page, writes
`OutputBytes` verbatim, and dispatches `QueryMode` and `QueryFolder` to the host.
`Skip` advances to the next record. `Stop` writes control text and ends the stream.

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
| `-t`, `--type TYPE` | Case-insensitive `unix`, `windows`, `mixed`, or `dos` |
| `-a`, `--absolute` | Resolve relative paths from explicit context |
| `-p`, `--path` | Convert each NAME/record as one atomic PATH list |
| `-U`, `--proc-cygdrive` | POSIX drive fallback through `/proc/cygdrive`; ignored for Windows/Mixed output |
| `-r` | Add a root-local prefix to single Windows output; does not alter list output |
| `-f`, `--file FILE` | Read UTF-8 records from a file; `-` selects stdin |
| `-o`, `--option` | Interpret leading-hyphen records as per-record option declarations; requires `-f` |
| `-i`, `--ignore` | Skip empty operands/records and suppress official usage failures occurring after this flag |
| `-C`, `--codepage CP` | Select an implemented output encoding; ignored for POSIX output after syntax validation |
| `-l`, `--long-name` | Expand ordinary short-name components on Windows with `-w` or `-m` |
| `-d`, `--dos`, `-s`, `--short-name` | Preserve the case of an existing ASCII 8.3 path, including a supplied alias, drive root or dot operand. A missing Windows operand or list member reports its converted spelling and exits 2. Shortening a long component requires its stored alternate name |
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

On Windows, the input name in `-f C:records` is a POSIX filename with a
literal colon. Its native spelling contains U+F03A. In `-f C:dir\records`
the backslash selects Windows syntax and the lookup starts at the drive root.

The last `-f` value wins; `-f` and NAME cannot be combined. The last `-C` value
wins. Identical scalar project context declarations may repeat; conflicting
values fail. Mounts append, and Context rejects duplicates/conflicts. Duplicate
`--drive-cwd` letters are rejected after ASCII case folding.

The absolute terminal names `/dev/tty` and `/dev/ptmx` and fixed `/proc`
entries report binary mode without an installation snapshot.
On Windows, `-M C:/work/file` and its backslash spelling can query the drive
directly. On a local drive, backslash-relative names use the process working
directory. For example, `-am sub\tool` returns the full path to `tool.exe`
when that file supplies the executable suffix. An ordinary local Windows
file or missing leaf uses binary mode. Following a
native link can require a selected installation to map its target.
With an installation snapshot, POSIX operands use the flags of the resolved
mount. The CLI prints the original operand followed by `: text` or
`: binary`. Ordinary missing names retain the selected mount mode; an empty
name (even with `-i`) or a regular file used as a parent gets a diagnostic
on stderr and does not stop later operands or change the exit status. `-f`
and per-record `-o` use the same dispatch. Known limitations include live
mount changes, Cygwin-only link metadata and native links without a resolvable
target. Missing installation context is a capability failure, not a binary
default. See [upstream mode lookup](https://github.com/cygwin/cygwin/blob/b11613e477c006b2ce0332463ed07f1118260e79/winsup/cygwin/external.cc#L425-L436).

`-l` queries the Windows host after path conversion. For ordinary files and
directories, `moonrun` obtains the normalized name of the opened entry. The CLI
uses only the last component of that result so a junction in an earlier
component keeps its spelling. Directory enumeration supplies the reparse point's
own name, including an unambiguous ASCII case variant of an eligible DOS name.
Unresolved reparse aliases and
OEM-dependent case or alias decisions produce a capability error. A missing
path returns the whole original spelling, including any short parent names.
Lists apply the lookup to each member. With `-C`, the first encoded result
must decode in the supported UTF-8 locale before the lookup. Windows
comparisons use names obtained from the fixture volume itself.
[Cygwin fallback](https://github.com/cygwin/cygwin/blob/b11613e477c006b2ce0332463ed07f1118260e79/winsup/utils/cygpath.cc#L430-L445),
[moonrun Windows realpath](https://github.com/moonbitlang/moon/blob/738607b/crates/moonrun/src/filesystem/job/runner.rs#L1343-L1405),
and [Windows normalized names](https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-fscc/20bcadba-808c-4880-b757-4af93e41edf6).

On Windows, POSIX `-W` and `-S` use the running installation's NT
`SystemRoot` link and the normalized local directory name from an open handle.
The directory then passes through the selected mounts and drive prefix,
including `-U`. For a linked subdirectory, the adapter reads the stored name
from its parent. An unresolved root reparse point or a result without a DOS
drive path produces a capability error. The upstream POSIX branch tries to
restore disk casing, while Windows/mixed output preserves the spelling from
the Windows API. That raw spelling and redirected shell folder queries remain
open. [Cygwin folder conversion](https://github.com/cygwin/cygwin/blob/b11613e477c006b2ce0332463ed07f1118260e79/winsup/utils/cygpath.cc#L551-L674) ·
[Windows SystemRoot handle observation](https://bugs.python.org/msg226540).

`-F` accepts a signed integer in decimal, octal or hexadecimal. IDs `0x24`
and `0x25` select the Windows and system directories. On the 64-bit Windows
hosts supported by Cygwin and moonrun, `0x29` selects SysWOW64. IDs `0x14`
and `0x38` select Fonts and Resources. The Wasm host looks up these entries
under the NT SystemRoot using the documented fixed-folder layout. An absent
entry supplies no folder path. The `NO_ALIAS` and `DONT_UNEXPAND` flags
also select the absolute filesystem path for these fixed directories.
[Windows known folders](https://learn.microsoft.com/en-us/windows/win32/shell/knownfolderid)
and [folder categories](https://learn.microsoft.com/en-us/windows/win32/api/shobjidl_core/ne-shobjidl_core-kf_category).

Virtual IDs `1`, `3`, `4`, `10`, `17`, `18`, `49` and `61` have no filesystem
path, including when combined with the documented CSIDL flags. They emit the upstream
diagnostic on stderr and allow subsequent file records to run. A malformed ID
exits with status 1. The last folder selector wins, a folder query takes no NAME,
and plain input records use the current conversion options. [Windows CSIDL definitions](https://learn.microsoft.com/en-us/windows/win32/shell/csidl) ·
[Shell path lookup contract](https://learn.microsoft.com/en-us/windows/win32/api/shlobj_core/nf-shlobj_core-shgetpathfromidlistw).

`-c HANDLE` reads a hexadecimal prefix, including an optional sign. A null
handle or the 64-bit current process/thread pseudo handle (`-1` or `-2`) lets
option processing continue. For example, `-c0 -u C:/x` converts the path.
`-c0` alone reaches the usual missing-operand check. A real inherited handle
requires a Windows handle operation. [Cygwin parser](https://github.com/cygwin/cygwin/blob/b11613e477c006b2ce0332463ed07f1118260e79/winsup/utils/cygpath.cc#L865-L869),
[current process](https://learn.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-getcurrentprocess)
and [current thread](https://learn.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-getcurrentthread).
See [the option inventory](01-upstream-and-scope.md) for their host requirements.

## 6. Explicit context and natural input recognition

These project extensions change the request, never the real host environment:

| Option | Meaning |
| --- | --- |
| `--from windows\|posix` | Override natural source recognition |
| `--profile cygwin\|msys2` | Select drive-prefix defaults and profile-specific mapping rules |
| `--root WINDOWS` | Add `/` as an explicit mount, without implicit aliases |
| `--mount POSIX WINDOWS` | Append a mount using two operands |
| `--mount-case POSIX POLICY` | Set a mount's comparison policy to `sensitive`, `ascii-insensitive`, or `windows-insensitive`, independent of declaration order |
| `--drive-prefix POSIX` | Override the profile's default prefix |
| `--posix-cwd POSIX` | Supply an absolute POSIX cwd |
| `--windows-cwd WINDOWS` | Supply an absolute Windows cwd/current drive |
| `--drive-cwd DRIVE WINDOWS` | Validate per-drive cwd metadata; does not alter drive-relative conversion |

Mount-case paths normalize trailing `/`; a policy without a matching mount is
an error. Default comparison is Sensitive. These arguments select the offline
model; it never consults the host. On Windows, `CYGPATH_ROOT` selects an
installed Cygwin or, with `--profile=msys2`, an MSYS2 installation when no
explicit mount, prefix or cwd is supplied. In that
mode both operands and `-f FILE` use the mount snapshot and physical cwd;
`CYGPATH_USER` optionally selects a per-user fstab. Neither mode guesses a root.

With no `--from`, POSIX output uses Windows grammar plus its already-POSIX
absolute passthrough. Single Windows/Mixed output recognizes a drive prefix,
backslashes, or ordinary extended/device prefix; otherwise it uses POSIX grammar.
Complete UNC is supported in either grammar. A single-backslash-rooted natural
Windows input resolves against the explicit Windows current drive.

For Windows/Mixed output, a bare drive (`C:`), or a drive-relative operand with
`-a` (`C:child`), follows the official CLI's literal POSIX-relative branch.
Given `posix_cwd=/cygdrive/c/cwd`, `-aw C:child` produces
`C:\cwd\C<U+F03A>child`, whereas explicit `--from windows -aw C:child`
produces `C:\child`. `-u C:child` prints `C:child`. With the default drive
prefix, `-au C:child` prints `/cygdrive/c/child` and `-u C:` prints `/cygdrive/c`.

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

`-f names.lst` opens the exact input name first and can open
`names.lst.exe` if the exact entry is absent. The suffix applies to the final
component. A directory found only by appending `.exe` is skipped. Opening
an explicitly named readable directory returns zero records and exits
successfully. With a selected installation, Cygwin mount mappings and
native link traversal also apply to the input filename.
[Cygwin open](https://github.com/cygwin/cygwin/blob/b11613e477c006b2ce0332463ed07f1118260e79/winsup/cygwin/syscalls.cc#L1479-L1489) ·
[Suffix scan](https://github.com/cygwin/cygwin/blob/b11613e477c006b2ce0332463ed07f1118260e79/winsup/cygwin/path.cc#L2902-L3007) ·
[File-input loop](https://github.com/cygwin/cygwin/blob/b11613e477c006b2ce0332463ed07f1118260e79/winsup/utils/cygpath.cc#L1066-L1115).

`-f FILE` and `-f -` stream input incrementally. The byte protocol is:

1. Translate CRLF to LF. Preserve a standalone CR, including a final CR at EOF.
2. End a record at LF or after 8192 bytes following CRLF translation, matching
   the official `fgets` capacity. LF itself is not part of the path. A longer
   physical line becomes independently converted chunks.
3. Treat the first NUL in a record as the end of path text. Bytes after it in
   that record are not UTF-8-decoded; subsequent records are still processed.
4. Apply the record's options, then interpret the filename using the selected
   conversion. Retain BOM characters, spaces and a final unterminated record.

An empty stream succeeds with no output. A BOM-only stream contains a BOM path.
An empty record is an empty operand, including in list mode: report
`can't convert empty path` with exit 1, or skip it with `-i`. Unix output accepts
UTF-8 and paired CESU-8, and preserves earlier output on a decoding error.
For Windows and mixed output,
C.UTF-8 filename bytes outside a valid sequence map to U+F080–U+F0FF.
This mapping happens after POSIX mount matching. A raw `ff` and the three
UTF-8 bytes for U+F0FF can therefore select different mounts. On a path
error the diagnostic quotes the original filename bytes. [Cygwin filename conversion](https://github.com/cygwin/cygwin/blob/b11613e477c006b2ce0332463ed07f1118260e79/winsup/cygwin/strfuncs.cc#L1155-L1210).

A six-byte CESU-8 pair denotes two UTF-16 units. For example,
`ed a0 bd ed b8 80` becomes 😀 and writes `f0 9f 98 80` under UTF-8 output.
The single-name length check uses those two units. Narrow POSIX mount
matching and error messages retain all six input bytes. The port currently
rejects an isolated encoded surrogate unit. [Newlib multibyte decoder](https://github.com/cygwin/cygwin/blob/b11613e477c006b2ce0332463ed07f1118260e79/newlib/libc/stdlib/mbtowc_r.c#L595-L637).

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

Each successful conversion ends with one raw LF byte. POSIX output preserves
Cygwin filename bytes, including bytes outside UTF-8. Windows/Mixed output
defaults to UTF-8 and additionally
supports 115 table-based legacy code pages. The original 110 are recorded in the
[Microsoft catalog](../third_party/microsoft/codepages.json) and
[Unicode catalog](../third_party/unicode/codepages.json). CP20932, CP20936
and CP20949 use Unicode's published Windows mappings. All 65,536 encoder
entries per page agree with the corresponding Windows Server 2022 NLS table.
[Data sources and verification](../third_party/unicode/README.md#east-asian-windows-code-pages).
CP38598 (logical Hebrew) uses CP28598 and preserves input character order.
CP51949 (EUC Korean) uses CP20949, including its best-fit and control-character
mappings. [Windows code page assignments](https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-ucoderef/28fefe92-d66c-4b03-90a9-97b473223d43).
Numeric pages use
Windows best-fit mappings; unmapped UTF-16 words use the table's default
character, so an unmapped supplementary scalar can yield two replacement bytes.
On 20 ANSI/OEM pages the encoder applies the additional Windows punctuation
best fits. CP932 also encodes U+3099 and U+309A as `81 4a` and `81 4b`
respectively. [Windows table verification](../third_party/microsoft/README.md).

The three Japanese pages use Windows JIS (20932), including JIS X 0212.
CP50220 widens halfwidth kana. CP50221 designates kana with `ESC ( I`.
CP50222 enters kana with `ESC ( J SO` and designates the next set explicitly.
CP50225, CP50227 and CP50229 use the Wansung, GB2312 and CNS Taiwan tables,
respectively. CP50229 changes designation when switching CNS planes.
CP52936 applies HZ quoting to a stream of Windows GB2312 bytes. Windows can
produce an embedded zero in that stream. The CLI ends the output name at
the first zero, as Cygwin does before printing.
[Windows evidence and byte samples](../third_party/microsoft/README.md#stateful-code-pages).

Windows GSM pages 55000–55004 map `@` to zero and the wide-string terminator to
a space. Cygwin prints the bytes before the first zero. The CLI requires a zero
in the encoded result and reports a capability error if one is absent. Each name
or path list must fit the initial 32,768-byte conversion buffer, including the
converted terminator. For mixed output, separator replacement happens after
encoding and truncation. [Windows samples and mapping provenance](../third_party/microsoft/README.md#windows-gsm-code-pages)

ISCII (57002–57011) starts each output name in the selected script.
For example, Bengali `অঅ` produces `a4 a4` on 57003 and `ef 43 a4 a4`
on 57006. A script change persists across ASCII path separators. After virama,
U+200C adds the virama byte and U+200D adds the nukta byte. [Mapping and Windows evidence](../third_party/dotnet/README.md#iscii)

CP54936 uses the Windows-derived GB18030-2000 mapping and encodes each
supplementary scalar as four bytes. The Windows comparison includes characters
whose mappings changed in later standards. See [the data source and regeneration command](../third_party/dotnet/README.md).
Mixed output encodes the Windows path and then replaces byte `5c` with `2f`.
This also changes a Shift-JIS trail byte in ソ (`83 5c` becomes `83 2f`).

CP42 (Windows Symbol) passes through U+0000–U+001F and maps U+F020–U+F0FF
to bytes `20`–`ff`. For example, U+F041 U+F05C U+F042 renders as `A\B` with
`-wC42` and `A/B` with `-mC42`. A character outside this repertoire causes
the CLI to return status 1 before writing the affected record. Cygwin ignores
the failed Win32 conversion, so its output on those inputs has no reliable
byte contract. [Windows Symbol mapping](https://archives.miloush.net/michkap/archive/2005/11/08/490495.html) and [Cygwin conversion call](https://github.com/cygwin/cygwin/blob/b11613e477c006b2ce0332463ed07f1118260e79/winsup/utils/cygpath.cc#L765-L796).

For single Windows or mixed paths, the CLI also recognizes an extended drive
or UNC prefix created by best-fit encoding. It removes the prefix if the
encoded name fits in 259 bytes without it. A path list and explicit `-r`
keep the prefix. [Cygwin output order](https://github.com/cygwin/cygwin/blob/b11613e477c006b2ce0332463ed07f1118260e79/winsup/utils/cygpath.cc#L783-L811).

CP65000 encodes each shifted run as unpadded Base64 of big-endian UTF-16
units. Windows ends the run with a hyphen, encodes a literal plus as `+-`,
and shifts optional punctuation including backslash. Consequently `-mC65000`
can retain an encoded Windows separator. Single-path `-wr` inspects and
prefixes the encoded bytes. For example, a short drive path gets the four
literal prefix bytes even with UTF-7 or EBCDIC output.
[RFC 2152](https://www.rfc-editor.org/rfc/rfc2152#section-2),
[Win32 encoding test vectors](https://github.com/wine-mirror/wine/blob/wine-11.0/dlls/kernel32/tests/codepage.c#L509-L747),
and [Cygwin output order](https://github.com/cygwin/cygwin/blob/b11613e477c006b2ce0332463ed07f1118260e79/winsup/utils/cygpath.cc#L768-L810).

`UTF8` and `UTF-8` aliases are case-insensitive. Numeric `-C` values use the
official decimal `strtoul` grammar: leading ASCII whitespace and an optional sign
are accepted; hex prefixes, underscores, and trailing junk are rejected.
Unsigned-long overflow saturates before conversion to a 32-bit page number.
`-C 4294968548`, for example, selects 1252. `-i` observes syntax errors in scan
order. Repeated `-C` replaces the previous selection.

A numeric value of zero restores the default conversion. Cygwin uses the
current locale for that branch. The Wasm CLI's default encoding is UTF-8.
[Cygwin multibyte conversion](https://github.com/cygwin/cygwin/blob/b11613e477c006b2ce0332463ed07f1118260e79/winsup/utils/cygpath.cc#L156-L163).
Windows-output `ANSI` and `OEM` require host selection. CP29001 remains unavailable. POSIX
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
conversion, invalid input, stdin, and exit status.

Local installation and package-content inspection establish useful prerequisites
but cannot prove registry availability. Keep the root coordinate
`ZSeanYves/cygpath` until the publishing namespace is explicitly settled. If an
I/O or capability gate fails, retain the evidence; custom C stubs, shell
fallbacks, and backend-specific conversion rules remain prohibited.
