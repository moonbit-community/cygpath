# cygpath Architecture Handbook

Design baseline: 2026-09-28. At the P0 baseline, initialization was complete and all functionality and APIs were still planned.

This handbook tells implementers and reviewers what to build, where the behavior comes from, how packages are separated, what the input/output contracts are, and which evidence establishes completion. “Should” and “must” in these chapters express implementation requirements; they do not imply that the corresponding feature already exists.

## Current implementation status

The P1 library is implemented in [`lib/`](../lib/README.mbt.md). Its public interface is recorded in [`lib/pkg.generated.mbti`](../lib/pkg.generated.mbti). `Context::new`, `Mount::new`, `Context::convert`, and `Context::convert_list` provide:

- Explicit Windows/POSIX input syntax and Windows/Mixed/POSIX output formats.
- Cygwin and MSYS2 drive-prefix profiles, custom prefixes, and `/proc/cygdrive` fallback output.
- Drive-absolute, relative, drive-relative, rooted, and UNC paths; lexical normalization and explicit cwd resolution.
- Validated mount tables with component-boundary matching, longest-prefix selection, case policies, and stable reverse aliases.
- Direction-specific PATH-list conversion and structured errors with original member indices.
- Validation of Unicode, namespaces, context, and Windows filename representability.

`Context` and `Mount` have private fields. Context construction copies caller-owned collections. Conversion uses pure MoonBit with no host inspection, I/O, project FFI, or external process invocation. The package uses only the MoonBit core library.

The P2 executable is implemented in root [`main.mbt`](../main.mbt), composed from
the pure [`internal/cli`](../internal/cli/moon.pkg) package and the
[`internal/host`](../internal/host/moon.pkg) runtime boundary. It supports the
documented conversion and context options, help/version, file and stdin
records, strict UTF-8, stable diagnostics, and exit codes. Known unsupported
options are recognized and rejected explicitly. The root and host packages
support Wasm and Native; the pure packages remain checked on all compiler
targets. The [development guide](08-development-and-release.md) records pinned
runtime dependencies and local commands.

Local macOS validation on 2026-09-28 used `moon 0.1.20260920 (914d7da)` and `moonc v0.10.14+7d59c7ec9`:

| Command | Result |
| --- | --- |
| `moon check --target all --deny-warn` | Passed; pure packages checked on all targets, root/host on their declared Wasm/Native targets |
| `moon test --target wasm --deny-warn` | 58 passed, 0 failed |
| `moon test --target native --deny-warn` | 58 passed, 0 failed |
| Release executable builds | Passed on Wasm and Native |
| `scripts/check_cli.mbtx` | 56 cases per backend: 112 passed; all 56 exact byte/exit backend comparisons passed |
| Isolated `moon install ./ --bin ...` | Passed; installed command passed version, conversion, and unknown-option smoke checks |
| `moon package --list` | Passed; archive contains source, interfaces, documentation, and fixtures, without build outputs or installed dependencies |
| `scripts/oracle.mbtx self-test` | Passed synthetic integrity, comparison, serialization, and manifest checks; validated 100 fixture/profile inputs; no official Windows program was run |
| `moon test --deny-warn scripts/check_cli.mbtx` | One collector regression passed for Windows diagnostic escaping and raw argv preservation |
| `moon info --target all` | Passed; generated interfaces reviewed for the intended public API |
| `moon fmt` | Passed |

The suite comprises 29 library blackbox tests in [`conversion_test.mbt`](../lib/conversion_test.mbt), [`context_test.mbt`](../lib/context_test.mbt), and [`parsing_test.mbt`](../lib/parsing_test.mbt), four executable documentation examples in the [library guide](../lib/README.mbt.md), 16 pure CLI tests, and nine host record/streaming tests. It covers conversion vectors, context validation and collection ownership, scoped round trips and normalization, list errors, option parsing, and strict input framing.

The separate [process fixtures](../testdata/contracts/README.md) exercise real
executables, including closed stdout, file-read errors, invalid UTF-8, BOM/CRLF,
partial earlier output, and atomic list failures. The initial successful run
is saved locally under `_build/cli-evidence-1/`. A second successful run under
`_build/cli-evidence-2/` adds raw toolchain-version and Git-state provenance to
the same raw byte files, artifact/fixture SHA-256 hashes, manifest, and summary.
These generated files
are ignored by Git. Portable-contract success does not establish complete
Cygwin/MSYS2 compatibility.

During P1, an additional temporary consumer module imported `ZSeanYves/cygpath/lib` through a local `moon.work` dependency. Its public-API smoke test passed on both Wasm and Native with `--deny-warn`, covering named types, context and mount construction, both conversion methods, and error construction and matching. This checks use from another module, not registry retrieval. The module now declares runtime dependencies for the executable; `lib/moon.pkg` still imports only core facilities.

The Linux/Windows P2 host matrix, P3 real Cygwin/MSYS2 differential verification,
and P4 publication/moonx acceptance remain pending. The cross-platform CI
workflow has been created locally; no remote run has been claimed. All-target
compiler checks do not imply execution beyond the tested macOS Wasm and Native
targets. [Oracle collection and replay tooling](07-oracle-collection.md) is
implemented with explicit manifests and unexecuted input corpora; its local
mechanics checks do not complete P3. Each profile has 10 dedicated inputs and
40 shared inputs, giving 50 planned cases each for Cygwin and MSYS2. An incomplete example manifest was also
confirmed to fail preflight before collecting results. No package has been
published or pushed as part of this implementation.

## Reading order

| Document | Questions it answers |
| --- | --- |
| [01 Upstream, Scope, and Compatibility Boundaries](01-upstream-and-scope.md) | Which mature implementations inform the project, which behavior can be modeled directly, and which capabilities are unsupported |
| [02 Architecture and Project Structure](02-architecture.md) | Where code belongs, how data flows, and which dependencies are allowed |
| [03 Path Semantics and Algorithm Contracts](03-path-semantics.md) | How drive letters, mounts, UNC, relative paths, lists, and Unicode are handled |
| [04 Library API, CLI, and moonx Delivery](04-api-and-cli.md) | Invocation, option combinations, errors, input/output, and the published entry point |
| [05 Validation and Implementation Roadmap](05-validation-and-roadmap.md) | Work at each stage, acceptance evidence, differential testing, and release gates |
| [06 Architecture Decision Records](06-decisions.md) | Major choices, rationale, costs, and conditions for reconsideration |
| [07 Oracle Collection](07-oracle-collection.md) | Manifest preparation, raw official observations, replay, and remaining Windows evidence |
| [08 Development and Release](08-development-and-release.md) | Local execution, runtime dependencies, process acceptance, packaging, and release gates |

Explicit user constraints take precedence when requirements conflict. Within this handbook, chapter 03 governs path contracts and chapter 04 governs interface contracts; chapter 01 records sources and scope, and chapter 05 assigns validation responsibilities. A semantic change must update the relevant chapters, fixtures, and API together. Snapshot updates must not conceal compatibility changes.

## Established constraints

1. Implement both the library and CLI in pure MoonBit. The direct entry point is `main.mbt` in the repository root, and the root package is executable. Users pass ordinary cygpath options and paths, such as `-h` and `-u`, to `moonx ZSeanYves/cygpath`. The public library lives in `lib/`.
2. Wasm and Native share the same conversion engine and option semantics. Do not introduce project C/C++ FFI, an external `cygpath` proxy, or conversion logic that branches by backend.
3. Official Cygwin behavior is the primary reference. Select MSYS2 mode explicitly; do not conflate `/c` with `/cygdrive/c`.
4. Model context explicitly. Report errors for information unavailable to a pure algorithm; do not invent an installation root, short filename, or system directory.
5. Build a reusable library and minimal CLI first, then collect differential evidence in real Windows environments. Planned, implemented, and differentially verified are separate states.

Pure MoonBit means that project source and business logic do not depend on implementations in another language. Ordinary use of argument, file, and standard-stream facilities provided by the MoonBit compiler and runtime is allowed. This project does not reimplement the runtime's I/O internals, but boundary tests must expose any backend differences.

## Repository baseline and future structure

The P0 baseline retained module metadata, the license, project documentation, agent agreements, and this handbook; template CLI code, placeholder source/tests, and template workflows were removed. At that baseline there was no `moon.pkg`, source code, or generated interface; `README.md` linked to `README.mbt.md`. Once implemented, the public library API is defined by `lib/pkg.generated.mbti`, generated with `moon info`; the root package is responsible only for the command-line entry point.

The planned source directories are described in [02](02-architecture.md). Create each directory when its responsibility is implemented. Empty functions, `TODO` tests, and `.gitkeep` files do not establish feature completion. P0 did not create a conversion implementation, published package, Git commit, or remote push.

The Git remote is `https://github.com/moonbit-community/cygpath.git`, and the initial local branch is `main`. The MoonBit module remains `ZSeanYves/cygpath`; version `0.1.0` is development metadata. The publishing namespace requires independent verification.

## First complete workflow

The first workflow now runs without an installed Cygwin environment or a system `cygpath`:

```text
argv: ["-u", "C:\work\demo.txt"]
  → CLI parses Windows input, POSIX output, and the default Cygwin prefix
  → Construct an explicit Context without an installation root or cwd
  → The core recognizes and renders a drive-absolute path
stdout: /cygdrive/c/work/demo.txt + LF
stderr: empty
exit: 0
```

At P0 this was a planned end-to-end acceptance case. It is now covered by the
`unix-default` process fixture on both Wasm and Native. Root mounts, relative
paths, lists, file input, and failure cases have their own acceptance cases.
File reading is invoked only when the selected options actually require it.

## Historical P0 local validation and its limits

Local macOS toolchain on 2026-09-28: `moon 0.1.20260920 (914d7da)` and `moonc v0.10.14+7d59c7ec9`.

The following results came from the initial state, which still contained an empty root library package. They do not validate the subsequent root-executable design:

| Command | Initial setup result |
| --- | --- |
| `moon check --target all --deny-warn` | Passed; checked only the configuration and backend checks for the then-empty root library package |
| `moon test` | Exited successfully with no test entry point; 0 tests do not establish conversion correctness |
| `moon info` | Passed; the generated interface contained no public values, types, or errors |
| `moon fmt` | Passed; module metadata was formatted |

The empty package configuration and generated interface were subsequently removed. The root-entry-point design update only synchronized the architecture agreements for the root executable and `lib/`; it did not restore placeholder packages or add an empty main. P0 did not run official Cygwin/MSYS2, compare Wasm/Native CLI output, or perform registry/moonx release acceptance. Those tasks have separate completion criteria in P1–P4.
