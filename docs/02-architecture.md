# 02 Overall Architecture and Project Structure

Status: implemented architecture, with the frozen P3 matrix verified at `b32dd7448658bc251b216ba93a5c120ef54fdbc9`. [The index](README.md) and [remote validation](09-remote-validation.md) record host/backend results. Related contracts: [path semantics](03-path-semantics.md), [API and CLI](04-api-and-cli.md), and [validation roadmap](05-validation-and-roadmap.md).

## 1. Goals and Boundaries

The project provides a reusable path-conversion library and a command-line package invoked through `moonx`. Both use pure MoonBit. Given identical input, explicit context, and options, conversion must have identical semantics across Wasm and Native, independent of the machine's environment or cwd.

The library converts representations and applies the selected Cygwin/MSYS2 rules. It does not establish that a converted name exists or identifies the same filesystem entity after symlink, junction, device, or short-name resolution. Implemented private-use-area filename mapping and extended-drive/UNC formatting are lexical operations; they do not introduce a filesystem resolver.

P3 completion means the declared portable matrix has exact evidence for its supported domain and separate evidence for its rejection boundaries. It does not mean full official compatibility or an unlimited maximum implementation. Missing host APIs and feasible but unimplemented pure algorithms are separate categories in [chapter 01](01-upstream-and-scope.md).

## 2. Pure MoonBit and the Runtime Boundary

Product code must not introduce C/C++ stubs, project-defined foreign imports, native Windows business-logic bindings, or a subprocess fallback to official cygpath, PowerShell, cmd, or a shell. General-purpose I/O from the official MoonBit runtime is allowed and concentrated in `internal/host`.

Validation tooling may launch official programs and independent diagnostic probes. In particular, the Windows code-page probe uses PowerShell/.NET interop only to observe Win32 behavior and retains its raw evidence. That code is not imported or called by the product. No upstream C implementation is compiled or linked into the product.

The only executable target is linear-memory Wasm, as accepted by `moonx`. The pure library, CLI parser and encoder can be checked independently on other targets. Raw bytes, exit status, argv and filesystem behavior still require executing the Wasm artifact on each supported host.

The November 2026 audit verified directory enumeration, `kind` and `realpath` through `core/async/fs` on linear-memory Wasm. On macOS the runner identified a dangling symlink and resolved a live symlink to its target. [Registered imports in moonrun 738607b](https://github.com/moonbitlang/moon/blob/738607b/crates/moonrun/src/async_api/registry.rs).

`x/fs.identity` merged into upstream on 2026-11-20. In the macOS Wasm probe a file, its hardlink and a followed symlink had equal identities. Querying the symlink with `follow_symlink=false` returned a distinct identity. On 2026-11-21 the latest Mooncakes version was `0.5.8`, which predates the API. Adoption in cygpath waits for the coordinated `x` release that exports it. [Upstream PR](https://github.com/moonbitlang/x/pull/373) · [Mooncakes](https://mooncakes.io/docs/moonbitlang/x) · [Adoption issue](https://github.com/moonbit-community/cygpath/issues/10).

On Windows the upstream API supports identity comparisons on NTFS. A missing identity returns `None`, a failed lookup raises `IOError`, and other filesystems including ReFS can return a non-unique identifier. The post-release Windows test therefore needs to record the fixture's filesystem before using identity equality. [Merged API contract](https://github.com/moonbitlang/x/blob/822f3a7fa84873735955688e09f57e0bbeb685a8/fs/stat.mbt#L183-L209).

The host adapter resolves the NT `SystemRoot` link through `core/async/fs.realpath` for POSIX system-directory output. The CLI converts the resulting path through its current mount context. An explicit Windows test compares both directory selectors and their numeric equivalents with Cygwin. Raw API spelling, registered shell-folder locations, alternate 8.3 names, active Windows code pages and Cygwin session mounts still require separate queries. [Folder behavior and evidence](04-api-and-cli.md#5-options-and-precedence).

`raw_fd` takes a runtime-owned descriptor. Cygwin's `-M` follows links and asks the resolved path for its binmode. [Cygwin implementation](https://github.com/cygwin/cygwin/blob/b11613e477c006b2ce0332463ed07f1118260e79/winsup/cygwin/external.cc#L403-L415).

## 3. Structure by Responsibility

The root-level `main.mbt` is the direct entry point. Root `moon.pkg` declares `pkgtype(kind: "executable")`; `lib/` is the public library. New packages are added for implemented responsibilities, not speculative layers.

```text
cygpath/
├── moon.mod                         Module metadata and pinned dependencies
├── moon.pkg                         Root executable, default Wasm
├── main.mbt                         Read → dispatch → encode/write → exit
├── README.md                        Module guide
├── lib/                             Public ZSeanYves/cygpath/lib
│   ├── types.mbt, error.mbt          Public types and checked errors
│   ├── context.mbt                  Immutable validated Context
│   ├── parse.mbt, normalize.mbt     Grammar and lexical resolution
│   ├── mount.mbt, mount_order.mbt     Profile-specific mount ordering/mapping
│   ├── filename_encoding.mbt        Filename private-use-area mapping
│   ├── convert.mbt, render.mbt      Conversion and output spelling
│   ├── path_list.mbt                Directional lists
│   ├── README.mbt.md, *_test.mbt    Executable examples and tests
│   └── pkg.generated.mbti           Public interface
├── internal/
│   ├── cli/                         Pure argv, requests, record state, diagnostics
│   ├── encoding/                    Pure numeric-codepage tables and encoder
│   └── host/                        Runtime argv, input, byte streams, exit
├── testdata/
│   ├── contracts/                   Independent portable process contracts
│   └── oracle/                      Immutable inputs and frozen P3 scope
├── scripts/                         .mbtx automation only
│   ├── check_cli.mbtx               Portable Wasm process contracts
│   ├── check_consumer.mbtx          External public-library consumer
│   ├── oracle.mbtx                  Official collection/replay/fault drills
│   ├── ci_oracle.mbtx               Measured Windows contexts and strict gate
│   ├── probe_windows_codepages.mbtx Independent Windows API diagnosis
│   └── generate_codepages.mbtx      Verified data → pure mapping tables
├── third_party/
│   ├── unicode/                    Unicode-hosted mapping data and notice
│   ├── microsoft/                  Microsoft archive data and permission
│   └── newlib/                     BSD sorting adaptation attribution
├── .github/workflows/              Three-host checks and Windows oracle jobs
└── docs/                            Architecture, contracts, and evidence
```

MoonBit package boundaries follow directories, not files. Parsing, conversion, and public types share `lib/`; private visibility separates their implementation details. Each package contains its `moon.pkg` and generated interface. Only public domain types that library callers should name, construct, or match belong to `lib/`. Internal `Command`, `Request`, `Converter`, and host errors must not leak into its API.

Library callers import `ZSeanYves/cygpath/lib`. After owner publication, command users invoke `moonx ZSeanYves/cygpath -h` or another ordinary option directly. Root remains a thin composition layer and contains no path-conversion algorithm.

## 4. Dependency Direction

```mermaid
flowchart TD
    User[Library callers] --> Core[lib: paths and explicit Context]
    Main[Root main.mbt] --> CLI[internal/cli: argv and record state]
    Main --> Encoder[internal/encoding: output bytes]
    Main --> Host[internal/host: standard I/O]
    CLI --> Core
    CLI --> Encoder
    Host --> Core
    Host --> Runtime[Verified MoonBit runtime APIs]
    Core --> Std[Pure MoonBit core facilities]
    Encoder --> Std
```

- `lib/` imports no environment, filesystem, process, CLI, or host facilities.
- `internal/cli` parses already-tokenized argv, validates supported code pages, and operates on explicit values. It performs no I/O.
- `internal/encoding` maps text to bytes without consulting the locale, filesystem, or operating-system codec.
- `internal/host` owns argv, streams, exit and optional Windows installation discovery. It reads fstab into a library `Context`; the library never calls the host.
- Root composes those packages. No lower package depends on the executable root.

The Wasm executable uses the toolchain's experimental `moonbitlang/core/async` for files and streams and `moonbitlang/core/env` for process context and exit. External `async` and `x/crypto` are standalone tooling dependencies only. Product conversion launches no subprocesses.

The encoder uses 110 tables from the original archive and three Windows mappings from Unicode ICU data. The seven ISO-2022/HZ selectors implement Windows shift sequences and use the JIS, Wansung, GB2312 and CNS mappings for their character sets. UTF-8, UTF-7 and GB18030-2000 have separate encoders. The MSYS2 sorting helpers adapt BSD-3-Clause newlib code with its full notice retained. [Data and implementation provenance](01-upstream-and-scope.md#3-licensing-and-implementation-provenance).

## 5. Data Flow and State Ownership

1. Host supplies argv without the executable name. CLI parsing applies option order and recognition rules and returns `Help`, `Version`, `ExitSuccess`, or `Convert(Request)`.
2. For a conversion, `Request::prepare` builds one validated immutable Context before reading a file or producing path results. Control commands skip that construction.
3. NAME operands are processed in order. File/stdin input is streamed through the host text-record adapter; `-o` records go through the converter's state machine.
4. The core classifies, resolves, maps, and renders each path/list using explicit syntax, options, and the selected profile.
5. The CLI can return `OutputBytes` to preserve POSIX filename bytes. For Windows and mixed output, the converter applies the requested encoding. The root writes the resulting bytes followed by LF. Help, version and diagnostics use UTF-8.
6. Host writes the exact supplied bytes and reports I/O errors. Root stops on a failure or successful control stop, formats the owning package's diagnostic, and exits with its assigned status.

Context stores the profile, drive prefix, ordered mount snapshots, and optional POSIX/Windows cwd. It copies caller-owned collections and never reads global host state. `drive_cwds` values are validated compatibility metadata; they are not stored as resolution state and do not override cygpath's drive-root behavior.

Converter owns mutable per-file option state separately from Context. With `-o`, a record beginning with a hyphen is divided at its first whitespace into an option token and the remaining argument. Parsing such a record resets conversion flags while retaining the prepared Context; following plain records reuse the new flags. There is no shell quoting or arbitrary argv tokenization. A help/version/control stop prevents later records from being decoded or executed.

The host passes each record's bytes and line number to the CLI after CRLF translation, truncation at the first NUL and the 8192-byte record limit. BOM content and final unterminated records survive. The CLI selects filename decoding after applying per-record options. An empty stream succeeds with no output. Chapter 04 defines the empty-record, `-i` and diagnostic behavior.

A single library call returns a complete result or an error. A list is atomic within its call. A batch/file can already have emitted earlier successful records when a later record fails; those bytes remain. A write failure stops processing and must not cause a batch retry that duplicates output.

## 6. Explicit Context and Profile Semantics

An unmatched Windows drive path needs only the selected profile and prefix to become a POSIX drive path. A POSIX-rooted input outside that prefix needs a matching root or mount for Windows output. Ordinary relative paths and current-drive-rooted paths use the relevant explicitly supplied cwd when resolution requires it. Missing necessary context reports `MissingContext`; the build host's cwd is never substituted.

`--root` declares the root mount; repeatable `--mount POSIX WINDOWS` uses two values to avoid drive-colon ambiguity. `--mount-case` selects sensitive, ASCII-insensitive, or Windows-insensitive comparison for an explicit mount. Context construction rejects invalid/duplicate mappings and drive-prefix collisions. Per-drive cwd metadata is validated without changing the drive-root conversion rule.

Cygwin and MSYS2 have separate mount ordering, mapped-root trailing separators
and default drive prefixes. An installation snapshot preserves the insertion
slot and user/system ownership of each entry. A user entry can coexist with
a later system entry at the same name. Replacing an entry of the same
ownership keeps its slot. The shared runtime table has 64 slots, including
the root and automatic mounts. An insertion that exceeds capacity stops
the current fstab file. The next file can still update existing entries.
[Cygwin mount insertion](https://github.com/cygwin/cygwin/blob/b11613e477c006b2ce0332463ed07f1118260e79/winsup/cygwin/mount.cc#L1504-L1555) · [Table size](https://github.com/cygwin/cygwin/blob/b11613e477c006b2ce0332463ed07f1118260e79/winsup/cygwin/local_includes/mount.h#L160-L173).

With an explicitly selected Windows Cygwin installation (`CYGPATH_ROOT`), the host reads system fstab and optionally `fstab.d/<CYGPATH_USER>`, then maps the physical cwd. The mount initialization order and fstab field semantics are based on [Cygwin mount.cc](https://github.com/cygwin/cygwin/blob/b11613e477c006b2ce0332463ed07f1118260e79/winsup/cygwin/mount.cc). Explicit CLI mount/cwd/prefix options bypass installation I/O. Nothing infers a root from `HOME`, `MSYSTEM` or the build host. The snapshot excludes in-memory session mounts. Ordinary absolute `bind` sources are resolved against preceding entries only; an otherwise unmodified bind inherits its source flags, not its immutability. Bind resolution is lexical, not `realpath`. The Windows oracle includes a disposable, separate Cygwin installation for bind comparisons; portable fixtures do not establish Windows parity.

For a `usertemp` mount both runtimes call `GetTempPathW`. The adapter qualifies
the first nonempty value of `TMP`, `TEMP`, or `USERPROFILE` against the Windows
process cwd. Parent traversal stops at the drive root or UNC share. On another
drive, a relative name uses that drive’s saved directory when present and
its root otherwise. The temporary directory can be missing and a symlink retains its name.
The Windows-directory fallback when all three variables are absent still
requires a host query. The disposable Windows comparison exercises four
path spellings per runtime, plus a drive-relative name when a second drive
is available.
[Cygwin mount reader](https://github.com/cygwin/cygwin/blob/b11613e477c006b2ce0332463ed07f1118260e79/winsup/cygwin/mount.cc#L1258-L1273) · [Windows temp lookup](https://learn.microsoft.com/en-us/windows/win32/api/fileapi/nf-fileapi-gettemppathw) · [Windows path normalization](https://learn.microsoft.com/en-us/dotnet/standard/io/file-path-formats#apply-the-current-directory).

With `--profile=msys2`, the same host adapter checks for
`usr/bin/msys-2.0.dll`. The runtime initially uses `/cygdrive`. The standard
MSYS2 fstab sets it to `/`. After the system fstab, MSYS2 supplies a missing
`/bin` mount pointing to `usr/bin` under the effective root. A two-column
MSYS2 fstab record that ends immediately after the target creates a
case-insensitive system mount, including in the per-user file. Live mounts
created after startup are outside this file-based snapshot.
[Runtime initialization](https://github.com/msys2/msys2-runtime/blob/c770e1b9fa537fff9287c1fd40ebc84ac498fcb6/winsup/cygwin/mount.cc#L545-L588) · [Two-field records](https://github.com/msys2/msys2-runtime/blob/c770e1b9fa537fff9287c1fd40ebc84ac498fcb6/winsup/cygwin/mount.cc#L1212-L1232) · [Distributed fstab](https://github.com/msys2/MSYS2-packages/blob/master/filesystem/fstab).

## 7. Algorithms and Resource Policy

Path scanning and rendering follow input/output size, with ASCII markers separating structural parsing from Unicode content. Filename escaping and legacy encoding are pure transformations. Generated encoding tables use sorted UTF-16/encoded-value pairs and binary search; source/member/packed hashes bind regeneration to its data.

Mount lookup scans profile-ordered arrays and compares component prefixes. With m mounts and input length n, lookup is bounded by `O(m × n)`; report construction and profile-specific sorting costs separately. MSYS2's observable sorting algorithm must not be replaced solely on an assumed complexity improvement. No performance claim follows from compatibility tests.

There is no blanket 260-character rejection. The measured Windows-output rules include 255-UTF-16-unit component checks, automatic long-path prefixes, and relative-path resolution where needed. These formatting checks are not assertions about filesystem access. File input uses fixed record chunks and sequential callbacks rather than retaining the entire stream. The core API still accepts caller-provided strings and allocates complete results; panics or integer overflow are not a resource policy.

Do not add tries, caches, parallel conversion, resident services, or plugin systems without a measured need. The async runtime serves sequential I/O; it does not change path semantics or introduce concurrent record execution.

## 8. Acceptance and Further Changes

The implemented P1/P2 architecture is exercised by portable contracts and real processes on Linux, macOS, and Windows. The completed P3 gate covers the frozen explicit-context matrix with separate Cygwin/MSYS2 default/custom environments, both backends, collection/replay, coverage audits, and real Windows fault drills. Supported-domain comparisons must be exact. Malformed UTF-8 and unavailable CP29001 retain raw observations but pass only their separate deterministic rejection contracts.

Source, tests, generated interfaces, documentation, and evidence must describe the same behavior. Historical discovery approvals do not waive new supported-domain differences. Feasible unimplemented algorithms such as stateful encodings remain extensions outside this freeze; 8.3 and system-directory queries additionally need unavailable equivalent host facilities. Neither category authorizes product FFI or command fallbacks.

Release is separate: the repository owner chooses and publishes the version. Preserve root `main.mbt`, all required third-party notices, and the root command coordinate. Exact-version `moonx` retrieval and execution remain post-publication acceptance, not a consequence of green repository CI.
