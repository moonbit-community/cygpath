# 01 Upstream Behavior Baseline and Compatibility Scope

Status: Architecture baseline, 2026-09-28; implementation status is tracked in [docs/README.md](README.md). This document records facts established by reading upstream sources, the project's design constraints, and questions that still require execution evidence. The initial research did not run the official `cygpath` on Windows, Cygwin, or MSYS2, or execute third-party implementation tests. Source inspection does not replace compatibility acceptance testing.

## 1. Product Goals and Reference Priority

This project independently implements a `cygpath` path-conversion library and a command-line tool invoked through `moonx`, entirely in MoonBit. Wasm and Native share the same conversion implementation and semantics. The compatibility matrix retains the complete official option surface and explicitly marks system-specific capabilities that cannot be implemented reliably under this constraint as unsupported. Filling these gaps with FFI, external commands, or backend-specific implementations would violate the pure MoonBit requirement.

Behavioral references, in priority order, are the pinned official Cygwin manual and implementation, actual execution results from the same version, MSYS2 behavior recorded as a separate environment, and API and test organization from implementations in other languages. When the manual, source, and execution results disagree, record the discrepancy and applicable version before changing any contract.

The primary workflow is explicit: the caller supplies the source syntax, output format, input, and context; the core parses and converts; the command-line adapter handles arguments, files, standard streams, and exit status. Host I/O uses only verified general-purpose MoonBit runtime libraries, with shared application code for Wasm and Native. The portable core never inspects the host operating system, environment variables, filesystem, or external commands to infer context.

Project sources must not add C/C++ stubs, FFI, or dynamic calls into the Cygwin DLL, or launch a system `cygpath.exe` to perform product functionality. Official executables are used only for isolated differential testing. Runtime internals that provide general I/O are a different boundary from project-authored backend-specific application code; dependency selection and actual `moonx` execution must both pass release gates.

“POSIX format” describes path syntax; “Cygwin/MSYS2” also describes roots, mounts, and runtime behavior. These are distinct concepts. Converting Windows input into POSIX output does not imply that the result names an accessible file on the current macOS or Linux filesystem.

## 2. Pinned Upstreams and Their Roles

The following commits are research snapshots, not claims about the latest stable releases. Future research must add new baselines and difference records rather than silently moving existing expectations with `main`.

| Reference | Pinned version or commit | Inspected material | Role in this project |
| --- | --- | --- | --- |
| Official Cygwin C/C++ implementation | `b6e315143bf72c6d4e75a858716adbbe03c679f0`, committed 2026-09-27 | CLI, runtime path conversion, mount ordering, and licensing; source version macros identify 3.7.0, which does not establish a stable release | Primary behavior baseline and Windows differential-test oracle |
| MSYS2 runtime | `c770e1b9fa537fff9287c1fd40ebc84ac498fcb6`, committed 2026-09-24; from the current default branch `msys2-3.6.10`, not the old `master` | Mount handling, version macros, and licensing; source version macros identify 3.6.10 | Separate compatibility profile for the second runtime environment |
| JavaScript `suchipi/node-cygpath` | `82500753ab47eae21c9b2577acf49a84806c6324`, committed 2026-09-13; `package.json` version 1.0.0 | `toUnix`, `toWindows`, `toMixed`, three test groups, and the MIT license file | Supplementary reference for a small portable API and table-driven cases |
| Go `openshift/source-to-image/pkg/util/cygpath` | Tag `v1.6.2` resolves to `038c647b1a9046569c07e6159641786a67a990fc`, committed 2026-05-31 | External-command wrapper and host detection; the directory contains only `cygpath.go` | Example of the external-command adapter boundary, not an independent conversion algorithm |

Immutable sources:

- Cygwin: [cygpath.cc](https://github.com/cygwin/cygwin/blob/b6e315143bf72c6d4e75a858716adbbe03c679f0/winsup/utils/cygpath.cc), [path.cc](https://github.com/cygwin/cygwin/blob/b6e315143bf72c6d4e75a858716adbbe03c679f0/winsup/cygwin/path.cc), [mount.cc](https://github.com/cygwin/cygwin/blob/b6e315143bf72c6d4e75a858716adbbe03c679f0/winsup/cygwin/mount.cc), [version.h](https://github.com/cygwin/cygwin/blob/b6e315143bf72c6d4e75a858716adbbe03c679f0/winsup/cygwin/include/cygwin/version.h), and [manual source utils.xml](https://github.com/cygwin/cygwin/blob/b6e315143bf72c6d4e75a858716adbbe03c679f0/winsup/doc/utils.xml). The readable [online manual](https://cygwin.com/cygwin-ug-net/cygpath.html) was accessed during this research but is not a pinned version.
- MSYS2: [runtime commit](https://github.com/msys2/msys2-runtime/commit/c770e1b9fa537fff9287c1fd40ebc84ac498fcb6), [mount.cc](https://github.com/msys2/msys2-runtime/blob/c770e1b9fa537fff9287c1fd40ebc84ac498fcb6/winsup/cygwin/mount.cc), and [version.h](https://github.com/msys2/msys2-runtime/blob/c770e1b9fa537fff9287c1fd40ebc84ac498fcb6/winsup/cygwin/include/cygwin/version.h). [Filesystem Paths](https://www.msys2.org/docs/filesystem-paths/) explains `/c/`, the installation root, and automatic argument conversion; its access date is the research date above.
- JavaScript: [implementation](https://github.com/suchipi/node-cygpath/blob/82500753ab47eae21c9b2577acf49a84806c6324/index.js), [tests](https://github.com/suchipi/node-cygpath/blob/82500753ab47eae21c9b2577acf49a84806c6324/index.test.js), and [package.json](https://github.com/suchipi/node-cygpath/blob/82500753ab47eae21c9b2577acf49a84806c6324/package.json). This implementation depends on `nice-path`; its short entry-point file does not establish that all path semantics are implemented locally.
- Go: [cygpath.go](https://github.com/openshift/source-to-image/blob/038c647b1a9046569c07e6159641786a67a990fc/pkg/util/cygpath/cygpath.go). `ToSlashCygwin` actually executes `cygpath`; it is not a pure Go reimplementation.

## 3. Licensing and Implementation Provenance

This repository uses Apache-2.0. The upstream files declare the following licenses:

| Scope | Upstream declaration | Project treatment |
| --- | --- | --- |
| Cygwin `winsup/utils/`, including `cygpath.cc` | Generally GPL-3.0-or-later; explicit declarations in individual files take precedence | Inspect behavior and write independent contracts and tests; do not directly translate or copy implementation source |
| Cygwin `winsup/cygwin/` runtime | Generally LGPL-3.0-or-later with a specific linking exception; individual file declarations take precedence | Understand runtime dependencies and behavior; do not copy runtime source into the Apache-licensed core |
| Corresponding directories in this MSYS2 runtime snapshot | `CYGWIN_LICENSE` retains the directory-level declarations above | Apply the same provenance controls as for Cygwin |
| `node-cygpath` | MIT, Copyright 2025 Lily Skye | Currently an API and case reference only; preserve the applicable license and attribution if substantial code or tests are copied later |
| `source-to-image` | Apache-2.0 | Currently a reference for adapter boundaries only; record provenance and required notices if code is introduced |

Sources: [Cygwin CYGWIN_LICENSE](https://github.com/cygwin/cygwin/blob/b6e315143bf72c6d4e75a858716adbbe03c679f0/winsup/CYGWIN_LICENSE), [MSYS2 CYGWIN_LICENSE](https://github.com/msys2/msys2-runtime/blob/c770e1b9fa537fff9287c1fd40ebc84ac498fcb6/winsup/CYGWIN_LICENSE), [JS LICENSE](https://github.com/suchipi/node-cygpath/blob/82500753ab47eae21c9b2577acf49a84806c6324/LICENSE), and [Go LICENSE](https://github.com/openshift/source-to-image/blob/038c647b1a9046569c07e6159641786a67a990fc/LICENSE). These are explicit file declarations and project provenance decisions; the linking exception is not treated as permission to relicense upstream source arbitrarily.

Each compatibility rule should record its description, upstream location, observable cases, and verification status. Express the implementation using MoonBit's own data model and control flow. Any future plan to port GPL/LGPL source directly must first revisit licensing and architecture; it cannot retain the current assumption of an independent Apache-licensed implementation.

## 4. What the Official Implementation Actually Does

### 4.1 The Conversion Command Depends on the Runtime

`cygpath.cc::do_pathconv` calls `cygwin_conv_path` or `cygwin_conv_path_list`. Actual path behavior also resides in `path.cc`, `mount.cc`, and path-resolution infrastructure. Translating only the CLI file would not complete the port.

The POSIX-to-Windows branch of `path.cc::cygwin_conv_path` enters `path_conv::check`, including symlink-related processing; `mount.cc::conv_to_posix_path` reads mount information. Even ordinary official conversions may involve the real environment, so the entire `-u/-w/-m` surface must not be described as unconditional string manipulation. P1 implements behavior determined by explicit context; P3 verifies differences; P4 adds only capabilities consistent with pure MoonBit and cross-target semantics. Automatic symlink resolution, junction handling, and other filesystem-entity behavior are not implicit P1 guarantees.

### 4.2 Mount Mapping Has Semantics

Mount conversion matches complete path-component boundaries. The POSIX and native sides are each ordered by longest path first. User and system mounts at the same path also have precedence rules. Windows-to-POSIX conversion tries the mount table before falling back to cygdrive syntax. Therefore:

- The Windows result for `/usr/bin/tool` depends on the environment's mounts; it cannot always be formed as `<root>\usr\bin\tool`.
- A mount `/work -> D:\src` must not match `/worker`.
- `-U` affects cygdrive fallback syntax; it does not require every explicit mount match to become `/proc/cygdrive/...`.
- When POSIX `..` crosses a mount point, resolve it in the correct path space first. Do not replace the prefix and then arbitrarily reduce Windows components.

These conclusions come from `conv_to_win32_path`, `conv_to_posix_path`, `sort_by_posix_name`, and `sort_by_native_name` in the pinned [mount.cc](https://github.com/cygwin/cygwin/blob/b6e315143bf72c6d4e75a858716adbbe03c679f0/winsup/cygwin/mount.cc). They currently constitute source evidence.

### 4.3 Formatting, Absolutization, and Filesystem Entities Are Separate Operations

`C:\a`, `C:a`, `\a`, `a`, and `\\server\share\a` are not a single class of “Windows path.” Drive-relative and current-drive-rooted paths need different context; UNC server names must not be treated as drive letters. The library API must expose the source syntax explicitly.

Absolutization needs context such as cwd and the current drive, but does not automatically perform realpath canonicalization. Short and long names require filesystem APIs; symlinks can change the entity path; device namespaces have special mappings. P1 may perform lexical operations when context determines the result, and returns an explicit error when an unavailable capability is required.

### 4.4 Path Lists Are Directional

The pinned `path.cc::conv_path_list` shows that Windows lists use `;`, while POSIX lists use `:`. Windows-to-POSIX conversion skips empty members; POSIX-to-Windows conversion treats empty members as `.`. Automatic environment-variable conversion has additional branches that must not be assumed to describe `cygpath -p`.

Consequently, `;C:\x;;` and `:/x::` do not share an empty-member policy. Nor may `C:/x` be silently treated as a single path when the caller explicitly declares a POSIX list. Source syntax determines list parsing, and single-path and list APIs must remain separate.

## 5. Complete Option Coverage Matrix

The phases below describe the implementation plan, not current support. P0 provides initialization, documentation, and an engineering foundation for further work. P1 delivers library capabilities; P2 establishes the corresponding CLI. All official primary options are included in the comparison scope. Recognizing an option and reporting it as unsupported does not implement that capability. Current implementation and verification status is tracked in [docs/README.md](README.md).

| Option | Official behavior | Capability | Planned phase and limitations |
| --- | --- | --- | --- |
| `-u`, `--unix` | POSIX output; the default when no primary format option is selected | Core conversion | P1 library / P2 CLI; mounts and root come from explicit context |
| `-w`, `--windows` | Output with Windows separators | Core conversion | P1/P2; never invent a Cygwin installation directory |
| `-m`, `--mixed` | Windows path with `/` separators | Core conversion | P1/P2; still uses the Windows namespace |
| `-t`, `--type TYPE` | Select `dos/mixed/unix/windows` output | Argument parsing | P2, with the corresponding type model in P1; `dos` is explicitly unsupported under the current design |
| `-p`, `--path` | Convert a path list | Core lists | P1/P2; direction, empty members, and failure behavior have separate contracts |
| `-a`, `--absolute` | Absolute path output | Core and context | P1/P2; missing required cwd or drive state is an error; P3 verifies real environments |
| `-U`, `--proc-cygdrive` | Use `/proc/cygdrive` for cygdrive fallback | Core mapping | P1/P2; preserve explicit-mount precedence |
| `-d`, `--dos` | `-w` with short-name output | Windows filesystem | Unsupported under current constraints; never fabricate 8.3 names through truncation or `~1` suffixes |
| `-s`, `--short-name` | Windows/mixed short names | Windows filesystem | Unsupported; requires actual 8.3 records, which general string rules cannot recover |
| `-l`, `--long-name` | Windows/mixed long names | Windows filesystem | Unsupported; requires actual filename queries and cannot be supplied through FFI |
| `-r`, `--root-local` | Windows `\\?\` prefix | Namespace and conversion context | Candidate pure MoonBit extension for P4; first verify UNC, relative paths, long paths, lists, and option conflicts |
| `-C`, `--codepage CP` | Output bytes in ANSI/OEM/UTF8/numeric code pages | Encoding adapter | P2 supports explicit `UTF8`/`65001`, limited to Windows/Mixed output; other values, including `0` and ANSI/OEM, are unsupported; do not simulate the host locale |
| `-M`, `--mode` | Cygwin binary/text file mode | Cygwin runtime | Unsupported; do not infer from file extensions or call the Cygwin runtime |
| `-D`, `--desktop` | Desktop directory | Windows system information | Unsupported; do not hard-code user directories |
| `-H`, `--homeroot` | Profiles root | Windows system information | Unsupported; not the home of a single user |
| `-O`, `--mydocs` | Documents directory | Windows system information | Unsupported; environment variables cannot fully describe system folder redirection |
| `-P`, `--smprograms` | Start Menu Programs directory | Windows system information | Unsupported; no verified pure MoonBit query works across delivery targets |
| `-S`, `--sysdir` | System directory | Windows system information | Unsupported; no verified pure MoonBit query works across delivery targets |
| `-W`, `--windir` | Windows directory | Windows system information | Unsupported; no verified pure MoonBit query works across delivery targets |
| `-F`, `--folder ID` | Special folder identified by a numeric ID | Windows system information | Unsupported; joining directory names cannot simulate the system API |
| `-A`, `--allusers` | Use common-user locations for directory queries | Windows system information | Unsupported along with system-directory queries |
| `-f`, `--file FILE` | Read a file line by line; `-` means stdin | CLI I/O | P2; acceptance includes blank lines, CRLF, a final line without a newline, and I/O failures |
| `-o`, `--option` | Read per-line options with file input | CLI state | Unsupported in the current design; optional P4 extension after source and real execution establish per-line state semantics; do not parse an entire line as generic shell syntax |
| `-i`, `--ignore` | Ignore missing path input | CLI error policy | P2; do not broaden this into suppression of all I/O or conversion errors |
| `-c`, `--close HANDLE` | Close the handle of a captured process | Windows process capability | Unsupported; host-handle operations do not belong in a pure converter |
| `-h`, `--help` | Help | CLI presentation | P2; distinguish supported options from recognized but unsupported options |
| `-V`, `--version` | Version | CLI presentation | P2; identify this project rather than impersonating the official Cygwin binary |

Known but unimplemented options must be recognized and produce a clear diagnostic corresponding to `UnsupportedCapability`; unknown options are a separate argument error. Silently ignoring `-s/-C ANSI/-D` and returning an ordinary path as apparent success is forbidden. The CLI uses official primary-option spellings, but portable deployments without the required context must report an error, never invent a Windows root because they run on Linux or macOS. A verified general-purpose pure MoonBit capability could justify reevaluating an entry later; there is no commitment to fill gaps with platform FFI. [03](03-path-semantics.md) defines portable input semantics; [04](04-api-and-cli.md) defines CLI encoding, input, and error contracts.

Compatibility claims must retain these intentional differences: default UTF-8 does not follow the locale; the CLI does not perform GNU-style argument permutation after the first NAME; `-i` ignores only absence of input; empty input lists follow this project's directional contract; ambiguous or same-format inputs such as `-u /usr/bin` require an explicit `--from`; and exit codes use this project's stable categories. Static upstream code can explain these differences, but only actual differential records establish the externally observable behavior of each pinned version.

## 6. Differences Between Cygwin, MSYS2, JavaScript, and Go

### 6.1 Verify Cygwin and MSYS2 Separately

Cygwin's default cygdrive prefix is `/cygdrive`, and users may configure it. Official MSYS2 examples use `/c/foo`; paths within its root convert relative to the MSYS2 installation directory. These are path spaces under different environment configurations, not alternatives to select automatically from the current host OS.

When launching some native programs, MSYS2 also automatically converts arguments and environment variables that resemble paths. This is runtime launch behavior, not a general string rule for this library. Differential runs of the MoonBit native CLI must record the launching shell, actual argv, and `MSYS2_ARG_CONV_EXCL`/`MSYS2_ENV_CONV_EXCL` to detect changes made before inputs reach the program under test. Source: [MSYS2 Filesystem Paths](https://www.msys2.org/docs/filesystem-paths/).

### 6.2 JavaScript Is an API Reference, Not a Compatibility Oracle

The visible `node-cygpath` tests cover ordinary relative paths, paths containing spaces, separator replacement, drive-letter conversion, and inputs already in the target form. Its implementation converts `C:\x` to `/c/x` and `/a/b/c` to `A:\b\c`. This follows its chosen single-letter-root rule, not Cygwin's default behavior. Its entry point does not implement mount tables, a CLI, path lists, system directories, encoding, or short names.

For example, under the default Cygwin configuration, an unmatched `C:\x` needs `/cygdrive/c/x`; `/home/x` needs installation-root or mount context; and `/a/b` is merely a directory in general POSIX syntax. Our `source` and `Context` remove these implicit assumptions rather than making three context-free convenience functions the only API.

### 6.3 The Go Reference Illustrates a Process Boundary

On Windows, the Go package uses `LookPath` to compare the directories containing `git` and `cygpath` and infer the environment. Its conversion function launches external `cygpath`, removes a trailing newline, and returns subprocess errors. This wrapper does not establish pure Go path rules or independent cross-platform behavior.

This product does not depend on external `cygpath`. The official tool is used only as a P3 oracle. A Go-style subprocess proxy would violate the user's requirement and must not become a CLI or library fallback.

## 7. Open Questions for Windows Differential Testing

| Item | Current static evidence / risk | Minimum verification and acceptance condition |
| --- | --- | --- |
| `--root-local` spelling | In the pinned `cygpath.cc`, the long option maps to `L`, while the short option and handling branch use `r` | Run `-wr` and `-w --root-local` separately; record stdout, stderr, exit code, and version; do not copy a suspected upstream defect |
| `-r` with `-p` | `rootlocal_flag` is handled in the single-path branch, without a corresponding step in the list branch | Run the same path as a single path and as a list, and record version differences; explicitly label any designed extension |
| `-U` and mounts | The runtime matches mounts before cygdrive fallback | On one drive, select a path inside the installation root, one inside an additional mount, and one without a mapping; verify all three output classes |
| Empty list members | Source behavior differs between the two directions | Cover leading, trailing, and consecutive separators, all-empty lists, and `-a`, with a fixed cwd |
| Relative paths and drive state | Ordinary Windows relative, drive-relative, and current-drive-rooted paths need different context | Fix cwd and per-drive cwd; test `x`, `C:x`, `\x`, `.`, and `..` |
| Symlinks and mount traversal | POSIX-to-Windows conversion passes through runtime path checks | Create a symlink, a junction, and an additional mount; inspect `link/..` and nonexistent suffixes; record lexical and realpath behavior separately |
| Long paths and prefixes | Both runtime and CLI handle long paths and extended prefixes; byte length can differ from UTF-16 length | Test ASCII, CJK, and non-BMP paths near boundaries, UNC, trailing dots, and trailing spaces; compare output bytes |
| `-s/-d/-l` | Short names may not exist; long-name API failure behavior differs from short-name behavior | Preserve descriptions of upstream behavior; all project targets must consistently report unsupported, and these cases do not count as output-equivalence cases |
| `-f/-o/-i` | Official file mode maintains per-line state; `-i` affects usage and empty paths; this project's current design does not support `-o`, and `-i` ignores only absence of input | In P2, compare blank lines, CRLF, missing final newline, long lines, and invalid arguments, recording intentional differences; if P4 enables `-o`, also compare per-line option state; a single final exit code is not a substitute for per-line evidence |
| Code pages and error output | Official output encoding follows `-C`, or locale by default; input has a separate decoding boundary | In P2, compare raw bytes for `-C UTF8` and `-C 65001`; all other unsupported values must have stable diagnostics; default UTF-8 is this project's explicit contract |
| System directories and mode | Depend on system folder redirection, runtime mounts, user identity, and permissions | All project targets consistently report unsupported; do not assert machine-independent constant outputs |
| Device namespaces and handles | `get_device_name` queries NT objects; `-c` closes a handle directly | System-dependent paths and operations produce stable errors; do not fabricate results through ordinary path conversion |

Each real differential record must include at least: oracle executable provenance and hash, version, Windows version, Cygwin/MSYS2 profile, mount and cygdrive configuration, cwd and drive state, input argv or file bytes, locale and code page, stdout bytes, stderr bytes, and exit status. Samples with an unpinned version or unresolved shell argument rewriting cannot directly become core contracts.

## 8. Completion Criteria by Phase

| Phase | Deliverable | Does not establish |
| --- | --- | --- |
| P0: Initialization and design | Remove templates, configure the local repository and remote URL, and establish documentation and engineering agreements | A runnable cygpath, upstream compatibility, or publication |
| P1: Portable core | Explicit Windows/POSIX input syntax, context, common formats, lists, absolutization, mount conversion, and contract tests | Complete real Windows filesystem semantics |
| P2: Thin CLI | Arguments, input files, standard streams, errors, and exit status; diagnostic handling for known unsupported options | Availability of every official option |
| P3: Real-environment differential testing | Pin Cygwin and MSYS2 oracles, compare each behavior and record differences, and correct core contracts | Compatibility for untested options, platforms, or system capabilities |
| P4: Pure MoonBit extensions and release | Implement feasible extensions based on evidence, confirm the unsupported matrix, and verify Wasm/Native and `moonx` execution, packaging, and installation | Availability of all official Win32/Cygwin-specific capabilities, or compatibility on untested targets |

Pure implementation extensions may be verified alongside P3 when useful. Phase numbers represent acceptance gates, not a requirement to postpone every boundary question until the end. List unfinished items separately from capabilities explicitly unsupported because of user constraints. Recognizing an option and reporting it as unsupported does not count as implementing the function. The complete official capability matrix explains compatibility boundaries; it is not a future commitment to violate the pure MoonBit requirement.

The initial research and architecture work established the P0 baseline. Follow-up architecture, API, testing, and release work must retain its source priorities, capability boundaries, and unverified checklist. Current implementation and verification status is tracked in [docs/README.md](README.md).
