# 06 Architecture Decision Records

Recorded on 2026-09-28. These records distinguish explicit user constraints, the selected design baseline, and questions that require evidence. New implementation evidence may revise a design baseline; selecting that baseline does not imply user approval of every detail. References to the absence of packages or source below describe the historical P0 state.

## ADR-001: Pure MoonBit and moonx are hard constraints

**Status: Explicit user requirement.**

Both the library and executable CLI use pure MoonBit. The product must not introduce C/C++ FFI, specialized dynamic libraries, or a system `cygpath` subprocess proxy. Wasm and Native share path algorithms, error models, and CLI semantics. Argument, file, and standard-stream facilities supplied by the standard MoonBit runtime are wrapped in one boundary and checked for consistent behavior.

The alternatives considered were porting the Cygwin CLI and binding its DLL, invoking system cygpath, simple string conversions, and pure MoonBit conversion with explicit context. The first two violate the hard constraints; simple string conversions cannot adequately handle mounts, relative paths, and lists. The final option is selected, with system capabilities that cannot be provided correctly marked unsupported.

The cost is that the tool cannot immediately replace every official option unconditionally, and Native-specific APIs cannot fill gaps for one target. Future general-purpose MoonBit libraries may justify reconsidering individual capabilities if they provide consistent behavior, but the user's pure-implementation requirement cannot be revoked implicitly.

## ADR-002: Official Cygwin is the primary baseline; MSYS2 is a separate profile

**Status: Selected design baseline.**

The primary behavior is determined from pinned official source, manuals, and observations on real systems. JavaScript implementations inform interface organization and test cases only; Go wrappers around external commands help explain boundaries. [01](01-upstream-and-scope.md) maintains the research SHAs and licenses; [09](09-remote-validation.md) records the separately measured Windows distribution binaries and the limits of their source provenance.

Cygwin's `/cygdrive/c` and the `/c` commonly used by MSYS2 must be selected explicitly. Do not infer the profile from the host platform or `MSYSTEM`, and do not confuse MSYS2 shell argument rewriting with this library's algorithms.

The cost is maintaining two oracle environments and separate evidence for the same path set. Revise the baseline only when a new source, upstream update, or real differential results show that it is inadequate, not because a third-party implementation is shorter.

## ADR-003: The root package provides the CLI entry point; `lib` owns the core and public types

**Status: Root entry point explicitly required by the user; library boundaries follow from that requirement.**

The user requires the final direct entry point, `main.mbt`, in the repository root, giving the invocation coordinate `moonx ZSeanYves/cygpath`, followed by normal cygpath options and paths such as `-h` and `-u`. Example arguments do not restrict options to either single or double hyphens. The root `moon.pkg` is therefore configured as an executable package, while root `main.mbt` only composes `internal/cli` and `internal/host`; it contains no path conversion rules.

The `lib` package owns public types, Context, and the portable conversion engine. Its public import path is `ZSeanYves/cygpath/lib`. Responsibilities are separated by file initially, without introducing `internal/model` or `internal/engine`. Pure CLI parsing lives in `internal/cli`; general-purpose I/O lives in `internal/host`.

Dependencies flow as `root executable → internal/cli + internal/host` and `internal/cli → lib`. The library does not depend on the root executable, CLI, or host boundary, and does not access the filesystem, environment, or processes. An `internal` package must not own public concrete types, and internal types must not leak into public `lib` signatures.

At P0 there were no implemented packages or public APIs, so this decision changed the plan without requiring migration of a published API. Create `lib/moon.pkg` with its first substantial implementation, and create root `moon.pkg` and `main.mbt` when implementing the CLI. The P0 design update added no empty entry point or placeholder package.

## ADR-004: Context is explicit and immutable; it does not inspect the host

**Status: Selected design baseline supporting backend consistency.**

Mounts, the cygdrive prefix, POSIX/Windows cwd, and per-drive cwd are inputs rather than global variables. The library validates and copies mutable containers when constructing Context. The CLI constructs Context using explicit options. An operation that lacks necessary information reports `MissingContext`.

Compared with reading host fstab files, the registry, or environment variables, this choice allows the same fixture to be replayed across machines and backends. The cost is that converting `/usr/bin`, for example, requires a supplied root or mount, and `C:foo` requires per-drive context; a parameterless convenience function cannot always solve the problem.

Any future configuration-file or environment import must be a separate, testable “data → Context” step that preserves the pure interface. Detection must not be hidden inside `convert`.

## ADR-005: Separate the portable contract from evidence of official compatibility

**Status: Selected design baseline.**

[03](03-path-semantics.md) governs conversion rules, and [04](04-api-and-cli.md) governs the CLI. Conclusions drawn from source can guide implementation, but real compatibility requires differential results against specified official artifacts.

Selected portable behavior includes explicit source syntax, limited lexical normalization, stable UTF-8/LF output, explicit error categories, deterministic mount-alias ordering, and restricted option combinations. These are not all guarantees of official behavior. When differences emerge, either revise the contract or give the differences identifiers and narrow support claims. Do not describe the result as equivalent to full Cygwin.

The cost is maintaining a support matrix and difference records. The benefit is that compilation of an empty package, a few string cases, or recognizable error branches cannot be presented as a mature compatible implementation.

The first Windows subset records 23 reviewed profile/case differences across
the two profiles. CI accepts only their exact fixture, official-binary, and
output signatures; raw comparisons retain `fail`. The observed root conversion
also led to a product correction: `/` no longer adds an optional trailing
separator when mapped to an ordinary Windows installation directory. Cygwin
matches that result; the measured MSYS2 trailing separator remains a scoped
difference. The report in [09](09-remote-validation.md) does not promote this
subset to complete compatibility.

## ADR-006: Separate individual paths from path lists

**Status: Selected design baseline supported by upstream source.**

Expose `convert` and `convert_list`, with source syntax determining the list delimiter. Windows→POSIX and POSIX→Windows have different empty-member rules; drive-letter colons must not split Windows lists. A list fails atomically within one call and does not emit its already-converted prefix.

Compared with a `split/replace/join` shortcut, this requires member indices and representability checks. It prevents silent changes to the number or order of PATH members or their current-directory meaning. In the first Windows subset, both official CLIs reject an entirely empty Windows list operand with exit 1; the portable contract produces an empty list and the CLI writes LF with exit 0. This observed difference is retained as `portable-empty-list-policy`. Broader list/error compatibility still requires additional differential coverage.

## ADR-007: Default to Wasm; use Native to verify consistency from the same source

**Status: User delivery requirement plus locally observed toolchain evidence.**

Retain `preferred_target = "wasm"`. Local `moonx --help` output observed on 2026-09-28 showed Wasm as the default, supported execution of versioned package coordinates, and marked the Native entry point deprecated. Release acceptance therefore centers on moonx/Wasm for a pinned version; Native continues to be compared through `moon run/build` for output, errors, and exit status.

Artifact formats and startup times are not required to match. Observable semantics under the supported contract must match. When the toolchain changes, check help output, builds, and real package retrieval again rather than carrying forward outdated publishing commands.

## ADR-008: Retain the existing module name and license for now

**Status: Existing settings retained during initialization.**

The Git remote is configured as the user-provided `moonbit-community/cygpath`; both the initial local branch and the remote default branch are `main`. The module name remains `ZSeanYves/cygpath`. A GitHub organization and a Mooncakes account are separate identities, so the organization name does not automatically replace the publishing namespace.

The existing Apache-2.0 license is retained. The project independently implements behavior rather than directly copying GPL/LGPL upstream code. If code, tests, or data are incorporated later, retain their sources and applicable notices individually. Calling the project a “port” does not establish license compatibility.

Version `0.1.0` is currently module development metadata. Account, package-name, and version availability require explicit checks before the first release. P0 performed no publishing or account operations.

## ADR-009: Add packages, tests, and automation with substantial implementations

**Status: Selected design baseline.**

P0 retained module metadata and the complete design while removing the Hello CLI, placeholder tests, template workflows, and template hook. The P0 workspace contained no `moon.pkg`, MoonBit source, or generated interface. Earlier empty-library checks did not establish that this later workspace compiled or passed tests. Empty functions, numerous empty directories, and assertions that always pass must not be used to manufacture progress.

Each subsequent slice includes actual behavior, necessary tests, generated interfaces, and documentation updates. Automation uses `.mbtx` only, and build commands run serially. Validate concrete failure risks before moving to the next item. Measure performance after correctness and compatibility scope have stabilized.

The cost was that P0 provided no executable cygpath, consistent with its initialization-and-design deliverable. P1/P2 subsequently implemented the first end-to-end workflow and the packages needed by it, following this rule.

## Open questions and minimum evidence

| Question | Current conclusion | Evidence needed to resolve it |
| --- | --- | --- |
| General-purpose I/O dependency | Implemented with async 0.22.4 and x 0.5.5; Wasm/Native contract suites pass on Linux, macOS, and Windows | Revalidate the documented host boundary when dependencies or toolchains change |
| Actual official distribution baseline | Cygwin 3.6.10-1 and MSYS2 runtime 3.6.10-5 executed on Windows; hashes and measured context retained in [09](09-remote-validation.md) | Preserve exact binary baselines; review upstream changes and do not infer unattested source commits |
| `.`/`..`, aliases, and empty-list boundaries | The first subset records drive-cwd, UNC traversal, and empty-list differences; full compatibility is unconfirmed | Expand differential vectors with fixed cwd, mounts, and per-drive state to cover the remaining matrix |
| Extended namespaces and per-line options | Initially explicitly unsupported; they do not block common pure conversions | A separate specification, a pure implementation strategy, and evidence from both backends and official differential tests before enabling support |
| Non-UTF-8 code pages, 8.3 names, and system directories | No solution meeting the constraints; remain unsupported | Evidence of new, consistent pure MoonBit capabilities; otherwise no schedule to “complete” them |
| Publishing namespace and final version | Retain the existing module name and development version provisionally | Verify the account, package availability, and actual moonx entry point before publishing |

These questions do not require the user to approve each item during initialization and do not prevent implementation within the established boundaries. Insufficient evidence blocks only the promotion of the affected capability to supported or verified status.
