# 01 Upstream Behavior Baseline and Compatibility Scope

Status: the frozen P3 portable matrix passed real Windows collection and replay at commit `b32dd7448658bc251b216ba93a5c120ef54fdbc9` on 2026-09-28. [Windows oracle run 36385821354](https://github.com/moonbit-community/cygpath/actions/runs/36385821354) passed Cygwin and MSYS2 in both default and custom contexts; [Check run 36385821361](https://github.com/moonbit-community/cygpath/actions/runs/36385821361) passed Linux, macOS, and Windows. [The architecture index](README.md) and [remote report](09-remote-validation.md) record the evidence and counts. Source inspection and execution remain distinct evidence sources.

P3 completion applies to the capability rows and input domains frozen in [`p3-scope.json`](../testdata/oracle/p3-scope.json). Supported-domain cases require exact stdout bytes, stderr bytes, and exit status across Wasm/Native and collect/replay. Malformed UTF-8 and unavailable CP29001 have separately verified rejection contracts; neither is counted as exact official compatibility. This is not full Cygwin/MSYS2 compatibility or a claim that every possible pure MoonBit extension has been implemented.

Subsequent Windows execution is recorded in [09 Remote Validation](09-remote-validation.md).
Its measured distribution binaries are a separate baseline from the research
source commits below; their exact correspondence to a full source commit has
not been independently attested.

## 1. Product Goals and Reference Priority

This project independently implements a `cygpath` path-conversion library and a command-line tool invoked through `moonx`, entirely in MoonBit. Wasm and Native share the same conversion implementation and semantics. The compatibility matrix retains the complete official option surface and explicitly marks system-specific capabilities that cannot be implemented reliably under this constraint as unsupported. Filling these gaps with FFI, external commands, or backend-specific implementations would violate the pure MoonBit requirement.

Behavioral references, in priority order, are the pinned official Cygwin manual and implementation, actual execution results from the same version, MSYS2 behavior recorded as a separate environment, and API and test organization from implementations in other languages. When the manual, source, and execution results disagree, record the discrepancy and applicable version before changing any contract.

The library workflow is explicit: the caller supplies source syntax, output format, input, and context; the core parses and converts. The CLI adds natural argument recognition and explicit context options, then handles files, standard streams, and exit status. Host I/O uses only verified general-purpose MoonBit runtime libraries, with shared application code for Wasm and Native. The portable core never inspects the host operating system, environment variables, filesystem, or external commands to infer context.

Product sources must not add C/C++ stubs, FFI, or dynamic calls into the Cygwin DLL, or launch a system `cygpath.exe` to perform product functionality. Official executables and the independent Win32 diagnostic probe are validation tools only; they are never imported or called by the product. Runtime internals that provide general I/O are a different boundary from project-authored backend-specific application code; dependency selection and actual `moonx` execution must both pass release gates.

“POSIX format” describes path syntax; “Cygwin/MSYS2” also describes roots, mounts, and runtime behavior. These are distinct concepts. Converting Windows input into POSIX output does not imply that the result names an accessible file on the current macOS or Linux filesystem.

## 2. Pinned Upstreams and Their Roles

The following commits are research snapshots, not claims about the latest stable releases or attestations of installed binary build inputs. Future research must add new baselines and difference records rather than silently moving existing expectations with `main`.

| Reference | Pinned version or commit | Inspected material | Role in this project |
| --- | --- | --- | --- |
| Official Cygwin C/C++ implementation | `b6e315143bf72c6d4e75a858716adbbe03c679f0`, committed 2026-09-27 | CLI, runtime path conversion, mount ordering, and licensing; source version macros identify 3.7.0, which does not establish a stable release | Initial research baseline; actual distribution oracles are recorded separately |
| Cygwin 3.6.10 source snapshot | `b11613e477c006b2ce0332463ed07f1118260e79` | CLI conversion, file records, `wide_path.h`, and unchecked conversion failures | Source explanation for the measured 3.6.10 distribution behavior; not a binary-to-commit attestation |
| MSYS2 runtime | `c770e1b9fa537fff9287c1fd40ebc84ac498fcb6`, committed 2026-09-24; from the current default branch `msys2-3.6.10`, not the old `master` | Mount handling, version macros, and licensing; source version macros identify 3.6.10 | Separate compatibility profile for the second runtime environment |
| JavaScript `suchipi/node-cygpath` | `82500753ab47eae21c9b2577acf49a84806c6324`, committed 2026-09-13; `package.json` version 1.0.0 | `toUnix`, `toWindows`, `toMixed`, three test groups, and the MIT license file | Supplementary reference for a small portable API and table-driven cases |
| Go `openshift/source-to-image/pkg/util/cygpath` | Tag `v1.6.2` resolves to `038c647b1a9046569c07e6159641786a67a990fc`, committed 2026-05-31 | External-command wrapper and host detection; the directory contains only `cygpath.go` | Example of the external-command adapter boundary, not an independent conversion algorithm |

Immutable sources:

- Cygwin: [cygpath.cc](https://github.com/cygwin/cygwin/blob/b6e315143bf72c6d4e75a858716adbbe03c679f0/winsup/utils/cygpath.cc), [path.cc](https://github.com/cygwin/cygwin/blob/b6e315143bf72c6d4e75a858716adbbe03c679f0/winsup/cygwin/path.cc), [mount.cc](https://github.com/cygwin/cygwin/blob/b6e315143bf72c6d4e75a858716adbbe03c679f0/winsup/cygwin/mount.cc), [version.h](https://github.com/cygwin/cygwin/blob/b6e315143bf72c6d4e75a858716adbbe03c679f0/winsup/cygwin/include/cygwin/version.h), and [manual source utils.xml](https://github.com/cygwin/cygwin/blob/b6e315143bf72c6d4e75a858716adbbe03c679f0/winsup/doc/utils.xml). The readable [online manual](https://cygwin.com/cygwin-ug-net/cygpath.html) was accessed during this research but is not a pinned version.
- Cygwin 3.6.10: [cygpath.cc](https://github.com/cygwin/cygwin/blob/b11613e477c006b2ce0332463ed07f1118260e79/winsup/utils/cygpath.cc) and [wide_path.h](https://github.com/cygwin/cygwin/blob/b11613e477c006b2ce0332463ed07f1118260e79/winsup/utils/wide_path.h). The measured Cygwin `3.6.10-1` and MSYS2 `3.6.10-5` package identities, executable/runtime hashes, and source-attestation limits belong to the execution manifests in chapter 09.
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
| Unicode-hosted Microsoft WindowsBestFit data | Unicode License v3 | Fifteen generated mapping tables; retain [source hashes and notice](../third_party/unicode/README.md) |
| Microsoft Windows Supported Code Page Data Files | Microsoft Open Specifications copyright permission | Ninety-six additional generated mapping tables; retain the [archive/member hashes and separate permission](../third_party/microsoft/README.md) |
| newlib `qsort.c` | BSD-3-Clause | Adapted to pure MoonBit for observable MSYS2 mount ordering; retain the [source attribution and full notice](../third_party/newlib/README.md) in source and binary distributions |

Sources: [Cygwin CYGWIN_LICENSE](https://github.com/cygwin/cygwin/blob/b6e315143bf72c6d4e75a858716adbbe03c679f0/winsup/CYGWIN_LICENSE), [MSYS2 CYGWIN_LICENSE](https://github.com/msys2/msys2-runtime/blob/c770e1b9fa537fff9287c1fd40ebc84ac498fcb6/winsup/CYGWIN_LICENSE), [JS LICENSE](https://github.com/suchipi/node-cygpath/blob/82500753ab47eae21c9b2577acf49a84806c6324/LICENSE), and [Go LICENSE](https://github.com/openshift/source-to-image/blob/038c647b1a9046569c07e6159641786a67a990fc/LICENSE). These are explicit file declarations and project provenance decisions; the linking exception is not treated as permission to relicense upstream source arbitrarily.

Each compatibility rule should record its description, upstream location, observable cases, and verification status. Express the implementation using MoonBit's own data model and control flow. Any future plan to port GPL/LGPL source directly must first revisit licensing and architecture; it cannot retain the current assumption of an independent Apache-licensed implementation.

The independently written path-conversion rules, generated third-party mapping data, and permitted BSD sorting adaptation have different provenance. The repository's Apache-2.0 license does not relicense those third-party materials. No upstream C code is compiled or linked into the product.

## 4. What the Official Implementation Actually Does

### 4.1 The Conversion Command Depends on the Runtime

`cygpath.cc::do_pathconv` calls `cygwin_conv_path` or `cygwin_conv_path_list`. Actual path behavior also resides in `path.cc`, `mount.cc`, and path-resolution infrastructure. Translating only the CLI file would not complete the port.

The POSIX-to-Windows branch of `path.cc::cygwin_conv_path` enters `path_conv::check`, including symlink-related processing; `mount.cc::conv_to_posix_path` reads mount information. Even ordinary official conversions may involve the real environment, so the entire `-u/-w/-m` surface must not be described as unconditional string manipulation. P1 implements behavior determined by explicit context; P3 verifies differences; P4 adds only capabilities consistent with pure MoonBit and cross-target semantics. Automatic symlink resolution, junction handling, and other filesystem-entity behavior are not implicit P1 guarantees.

### 4.2 Mount Mapping Has Semantics

Mount conversion matches complete path-component boundaries, but ordering is profile-specific. Cygwin and MSYS2 must not share an assumed generic longest-prefix ordering: the inspected MSYS2 source uses different native/POSIX ordering and an ancestry comparison whose equal-element placement makes its sorting algorithm observable. Windows-to-POSIX conversion tries the selected profile's mount order before falling back to cygdrive syntax. Therefore:

- The Windows result for `/usr/bin/tool` depends on the environment's mounts; it cannot always be formed as `<root>\usr\bin\tool`.
- A mount `/work -> D:\src` must not match `/worker`.
- `-U` affects cygdrive fallback syntax; it does not require every explicit mount match to become `/proc/cygdrive/...`.
- When POSIX `..` crosses a mount point, resolve it in the correct path space first. Do not replace the prefix and then arbitrarily reduce Windows components.

The Cygwin conclusions come from `conv_to_win32_path`, `conv_to_posix_path`, `sort_by_posix_name`, and `sort_by_native_name` in the pinned [mount.cc](https://github.com/cygwin/cygwin/blob/b6e315143bf72c6d4e75a858716adbbe03c679f0/winsup/cygwin/mount.cc); the separate MSYS2 rules come from its [mount.cc](https://github.com/msys2/msys2-runtime/blob/c770e1b9fa537fff9287c1fd40ebc84ac498fcb6/winsup/cygwin/mount.cc). The frozen Windows matrix verifies measured default/custom mounts, same-target aliases, and ASCII-insensitive matching. Explicit Context does not model arbitrary runtime user/system flags or reconstruct unavailable host insertion history. Non-ASCII Windows case folding remains outside this matrix.

### 4.3 Formatting, Absolutization, and Filesystem Entities Are Separate Operations

`C:\a`, `C:a`, `\a`, `a`, and `\\server\share\a` are not a single class of “Windows path.” Drive-relative and current-drive-rooted paths need different context; UNC server names must not be treated as drive letters. The library API must expose the source syntax explicitly.

Absolutization needs the relevant explicit POSIX or Windows cwd, but does not automatically perform realpath canonicalization. When drive-relative input needs resolution, conversion follows the measured cygpath drive-root rule, rather than Win32's per-drive working-directory rule. The `drive_cwds` API parameter and `--drive-cwd` option validate supplied compatibility metadata; they do not alter conversion results. Natural CLI argument recognition has additional distinctions from an explicitly declared library source grammar, documented in chapter 04.

Short and long names require filesystem APIs; symlinks can change the entity path; device namespaces have special mappings. The pure implementation supports measured lexical extended-drive/UNC conversion, root-local output, long-path prefix rules, and filename private-use-area encoding. These operations do not implement device-object resolution or prove the existence of the resulting filesystem entity.

### 4.4 Path Lists Are Directional

The pinned `path.cc::conv_path_list` shows that Windows lists use `;`, while POSIX lists use `:`. Windows-to-POSIX conversion skips empty members; POSIX-to-Windows conversion treats empty members as `.`. Automatic environment-variable conversion has additional branches that must not be assumed to describe `cygpath -p`.

Consequently, `;C:\x;;` and `:/x::` do not share an empty-member policy. Nor may `C:/x` be silently treated as a single path when the caller explicitly declares a POSIX list. Source syntax determines list parsing, and single-path and list APIs must remain separate.

## 5. Complete Option Coverage Matrix

This table inventories the official primary options and the current implementation boundary. An implemented option is verified only within the frozen cases and explicit environments recorded by P3. Recognizing an option and reporting it as unsupported does not implement that capability. [The architecture index](README.md) records the current acceptance status.

| Option | Official behavior | Capability | Current implementation and limitations |
| --- | --- | --- | --- |
| `-u`, `--unix` | POSIX output; default format | Core conversion | Implemented; mounts and root come from explicit context |
| `-w`, `--windows` | Windows separators | Core conversion | Implemented; never invent an installation directory |
| `-m`, `--mixed` | Windows path with forward slashes | Core conversion | Implemented; still uses the Windows namespace |
| `-t`, `--type TYPE` | Select dos/mixed/unix/windows | Argument parsing | mixed/unix/windows implemented; dos requires unsupported short-name lookup |
| `-p`, `--path` | Convert a path list | Core lists | Implemented; direction, empty members, natural CLI recognition, and atomic failure have separate contracts |
| `-a`, `--absolute` | Absolute output | Core and context | Implemented with explicit context and measured drive-relative rules |
| `-U`, `--proc-cygdrive` | Use /proc/cygdrive for drive fallback | Core mapping | Implemented for POSIX output; explicit mounts keep precedence |
| `-d`, `--dos` | Windows short-name output | Windows filesystem | Unsupported; never fabricate 8.3 names by truncating or adding a tilde suffix |
| `-s`, `--short-name` | Windows/mixed short names | Windows filesystem | Unsupported; requires actual filesystem short-name records |
| `-l`, `--long-name` | Windows/mixed long names | Windows filesystem | Unsupported; requires actual filename queries |
| `-r`, `--root-local` | Windows root-local prefix | Namespace and conversion context | Short -r implemented for single Windows output; the list branch leaves it unapplied. The measured upstream long spelling is rejected because its option table maps it to an unhandled value; use -r |
| `-C`, `--codepage CP` | ANSI/OEM/UTF8/numeric output bytes | Encoding adapter | UTF8/UTF-8/65001 and 110 explicit legacy numeric pages implemented; Windows/Mixed output uses the selected encoder, while POSIX stays UTF-8. Host ANSI/OEM selection and CP29001 output are unsupported |
| `-M`, `--mode` | Cygwin binary/text file mode | Cygwin runtime | Unsupported; do not infer it from file extensions |
| `-D`, `--desktop` | Desktop directory | Windows system information | Unsupported; do not hard-code user directories |
| `-H`, `--homeroot` | Profiles root | Windows system information | Unsupported; not the home of a single user |
| `-O`, `--mydocs` | Documents directory | Windows system information | Unsupported; environment variables do not describe all folder redirection |
| `-P`, `--smprograms` | Start Menu Programs directory | Windows system information | Unsupported; no equivalent verified runtime query across delivery targets |
| `-S`, `--sysdir` | System directory | Windows system information | Unsupported; no equivalent verified runtime query across delivery targets |
| `-W`, `--windir` | Windows directory | Windows system information | Unsupported; no equivalent verified runtime query across delivery targets |
| `-F`, `--folder ID` | Special folder by numeric ID | Windows system information | Unsupported; joining directory names cannot simulate the system API |
| `-A`, `--allusers` | Common-user locations for directory queries | Windows system information | Accepted without effect for ordinary conversions; common system-directory queries remain unsupported |
| `-f`, `--file FILE` | Read records; - means stdin | CLI I/O | Implemented with measured text-mode record behavior, retained BOM, CRLF handling, fixed buffer chunks, final records, and ordered partial output |
| `-o`, `--option` | Read per-line options with file input | CLI state | Implemented: leading-option records split at the first whitespace, reset conversion flags, and preserve Context; plain records reuse flags. This is not shell tokenization |
| `-i`, `--ignore` | Ignore selected usage/missing-path conditions | CLI error policy | Implemented for measured usage suppression and empty operands; not blanket suppression of encoding, file-I/O, or conversion errors |
| `-c`, `--close HANDLE` | Close a captured process handle | Windows process capability | Unsupported; host-handle operations do not belong in a pure converter |
| `-h`, `--help` | Help | CLI presentation | Implemented; project help describes explicit context and support boundaries |
| `-V`, `--version` | Version | CLI presentation | Implemented; identifies this project, not an official Cygwin binary |

Requests that require unimplemented functionality produce `UnsupportedCapability`; unknown options are separate argument errors. Options that have no effect in a selected upstream mode remain distinct from requests that require the capability: POSIX output does not invoke the Windows output encoder, and `-A` alone does not request a system directory. The CLI must not fabricate short names or system directories. Missing context produces an error, never an invented Windows root. [03](03-path-semantics.md) defines path semantics; [04](04-api-and-cli.md) defines CLI encoding, input, and errors.

The CLI now supports GNU-style option permutation, natural recognition of ordinary Windows/POSIX arguments, measured empty-input/empty-operand behavior, and upstream-compatible errors for the frozen option/path cases. Explicit `--from` still selects a grammar deliberately. Project context errors and unsupported-capability errors remain typed project contracts. Default UTF-8 does not discover the host locale; project help/version identify this implementation. These boundaries remain visible even when every supported-domain P3 comparison passes.

The encoder catalog contains 111 archived table identities: 15 Unicode-hosted WindowsBestFit tables and 96 additional Microsoft tables. CP29001 remains archived data but is disabled, leaving **110 supported legacy numeric code pages plus UTF-8**. Each legacy encoder maps UTF-16 code units, including separate fallback bytes for unmatched surrogate units; main appends an unencoded LF after the encoded path. The archive is not a claim to support every Windows code-page identifier. Source/member hashes, notices, and observed resolutions of four conflicting source tables are retained under [`third_party/`](../third_party/microsoft/README.md).

The remaining scope has three distinct classes:

- **Missing host capabilities:** actual 8.3/long-name lookup, system-directory discovery, host ANSI/OEM selection, Cygwin file mode, process handles, and device/symlink/junction resolution. The selected general-purpose MoonBit APIs do not provide the required equivalent queries across delivery targets. Guessing from environment variables or using a product subprocess/FFI fallback is not an implementation.
- **Unimplemented pure extensions:** stateful encodings, GB18030/four-byte mappings, additional numeric catalogs, and broader case-folding rules can in principle be implemented as pure algorithms/data. They are outside the frozen scope and are not claimed impossible in MoonBit. The implemented scope covers explicit context and the enabled archived tables; it does not establish a maximum over all possible pure implementations.
- **Undefined or unavailable upstream input domains:** malformed UTF-8 and CP29001 on the measured Windows host retain raw observations and require deterministic project rejection. They do not count as exact conversion matches.

For malformed UTF-8, the pinned [Cygwin helper](https://github.com/cygwin/cygwin/blob/b11613e477c006b2ce0332463ed07f1118260e79/winsup/utils/wide_path.h#L19) and matching [MSYS2 helper](https://github.com/msys2/msys2-runtime/blob/c770e1b9fa537fff9287c1fd40ebc84ac498fcb6/winsup/utils/wide_path.h#L19) fail to check `mbstowcs` before using allocated storage. Their common SHA-256 is `4b9e9c9de0b9525d4758312f94338125ee9ecd07ade479d9ceab29d0dc5dce99`. Previously observed repeated records are not a portable rule to reproduce.

For CP29001, the independent Windows API probe measured `IsValidCodePage=false`, failed `GetCPInfo`, zero sizing/conversion returns, error 87 from the failing information/conversion calls, and an unchanged sentinel-filled destination on both inputs; CP1252 controls succeeded. The pinned CLI source ignores the failed conversion before reading its output allocation. This establishes the failure branch on the recorded host, not unavailability on every Windows version. [The data provenance](../third_party/microsoft/README.md) and chapter 09 retain the exact probe and source evidence.

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

## 7. Verified Matrix and Remaining Boundaries

The frozen scope maps 152 capability rows to 473 unique suite/case identities: 461 supported-domain inputs, ten malformed-UTF-8 inputs, and two CP29001 inputs. Each applicable case is exercised by both backends in collection and replay; default/custom contexts and Cygwin/MSYS2 are reported separately. Capability rows, unique inputs, and repeated process observations are different counts. Chapter 09 records the actual run totals.

| Area | Evidence and supported scope | Boundary retained |
| --- | --- | --- |
| Root-local and extended paths | Short -r, its list behavior, measured long-option rejection, extended drive/UNC inputs, and long-path prefixes | Device-object queries and arbitrary NT namespaces are not lexical conversion |
| Mounts and profiles | Default/custom roots and drive prefixes, nested mounts, same-target aliases, ASCII-insensitive matching, and profile-specific ordering | No inferred user/system flags, hidden host context, or full Unicode Windows folding |
| Relative paths and lists | Natural argv detection, explicit source grammar, cwd forms, drive-root handling, directional empty members, and atomic list failure | Do not substitute Win32 per-drive cwd semantics or shell argument rewriting |
| File and option records | File/stdin bytes, empty streams, BOM preservation, CRLF/final records, NUL interpretation, buffer boundaries, partial failure, and persistent -o state | Malformed UTF-8 is a separately checked rejection domain, never an exact conversion result |
| Encoding | Text and fallback probes for all 110 enabled legacy numeric pages, UTF-8, and direct CP29001 API diagnosis | Probes establish the recorded vectors, not exhaustive verification of every mapping; host ANSI/OEM discovery and unimplemented algorithms remain outside scope |
| Collector lifecycle | Actual Windows timeout/cancel/wait with partial bytes, spawn failure, and separate stdout/fixture/manifest tampering drills | Successful normal captures alone would not prove failure handling |
| Filesystem-dependent options | Explicit product rejection for unsupported operations | No 8.3, system-folder, symlink/junction, device, mode, or handle equivalence claim |

Each real differential record includes oracle executable/runtime provenance and hashes, versions, Windows host observations, profile, mount/prefix configuration, cwd metadata, exact argv and input bytes, locale/code-page conditions, raw stdout/stderr, integer exit status, deadlines, and integrity results. The collector launches direct argv arrays and controls runtime glob/argument behavior; shell rewriting must not be mistaken for conversion behavior. Changing an upstream binary, environment, or frozen input requires new evidence.

The earlier 23 reviewed profile/case differences are historical discovery records. The current supported-domain gate does not consult reviewed-difference approvals. Exact equality, coverage, backend/replay consistency, independent boundary contracts, and real fault drills must all pass. Neither undefined upstream output nor a capability rejection may be relabeled as a successful conversion.

## 8. Completion Criteria by Phase

| Phase | Deliverable | Does not establish |
| --- | --- | --- |
| P0: Initialization and design | Removed templates, configured the repository/remote, and established architecture and agreements | A runnable tool or publication |
| P1: Portable core | Explicit source types, immutable Context, paths, lists, mounts, normalization, profile rules, and tests | Complete filesystem-entity semantics |
| P2: CLI and host boundary | Root main.mbt, argument/record state, output encoding, standard I/O, errors, and Wasm/Native contracts | Every official option or automatic host discovery |
| P3: Frozen real-environment matrix | Exact supported-domain evidence for declared rows, separate boundaries, coverage audit, and real Windows fault drills; completed at the recorded green revision | Full official compatibility, exhaustive combinations, or all theoretically feasible pure extensions |
| P4: Release and further extensions | Owner-selected version/publication, package/license review, exact-version moonx retrieval, and separately specified extensions | Availability of unimplemented host capabilities or compatibility on untested targets |

Pure extensions may be implemented and verified alongside P3; phase names are acceptance boundaries rather than mandatory sequencing. The completed P3 matrix includes the implemented per-line options, root-local paths, and encoder catalog. New algorithms or environmental capabilities require a new declared scope and evidence; their feasibility must not be confused with prior implementation.

Publication remains the repository owner's action. Keep root `main.mbt` and the command coordinate `moonx ZSeanYves/cygpath`, followed by ordinary options such as `-h` or `-u`. Version `0.1.0` remains development metadata until a release is chosen. A green source/build matrix does not establish registry publication or exact-version consumer retrieval.
