# 06 Architecture Decision Records

Recorded and revised on 2026-09-28. These records distinguish explicit user constraints, implemented decisions, and remaining release/extension boundaries. The frozen P3 matrix passed at `b32dd7448658bc251b216ba93a5c120ef54fdbc9`; [chapter 09](09-remote-validation.md) records the green CI and evidence. References to the absence of packages or source describe the historical P0 state.

## ADR-001: Pure MoonBit and moonx are hard constraints

**Status: Explicit user requirement.**

Both the library and executable CLI use pure MoonBit. The product must not introduce C/C++ FFI, specialized dynamic libraries, or a system `cygpath` subprocess proxy. Wasm and Native share path algorithms, error models, and CLI semantics. Argument, file, and standard-stream facilities supplied by the standard MoonBit runtime are wrapped in one boundary and checked for consistent behavior.

The alternatives considered were porting the Cygwin CLI and binding its DLL, invoking system cygpath, simple string conversions, and pure MoonBit conversion with explicit context. The first two violate the hard constraints; simple string conversions cannot adequately handle mounts, relative paths, and lists. The final option is selected, with system capabilities that cannot be provided correctly marked unsupported.

The cost is that the tool cannot immediately replace every official option unconditionally, and Native-specific APIs cannot fill gaps for one target. Future general-purpose MoonBit libraries may justify reconsidering individual capabilities if they provide consistent behavior, but the user's pure-implementation requirement cannot be revoked implicitly.

## ADR-002: Official Cygwin is the primary baseline; MSYS2 is a separate profile

**Status: Selected design baseline.**

The primary behavior is determined from pinned official source, manuals, and observations on real systems. JavaScript implementations inform interface organization and test cases only; Go wrappers around external commands help explain boundaries. [01](01-upstream-and-scope.md) maintains the research SHAs and licenses; [09](09-remote-validation.md) records the separately measured Windows distribution binaries and the limits of their source provenance.

Cygwin's `/cygdrive/c` and the `/c` commonly used by MSYS2 must be selected explicitly. The profiles also differ in measured mount ordering and mapped-root trailing separators; changing only a prefix cannot express their complete supported behavior. MSYS2 requires its own ordering, including the observable sorting behavior retained by the permitted BSD newlib adaptation. Do not infer the profile from the host platform or `MSYSTEM`, and do not confuse shell/runtime argument rewriting with this library's algorithms.

The cost is maintaining two oracle environments and separate evidence for the same path set. Revise the baseline only when a new source, upstream update, or real differential results show that it is inadequate, not because a third-party implementation is shorter.

## ADR-003: The root package provides the CLI entry point; `lib` owns the core and public types

**Status: Root entry point explicitly required by the user; library boundaries follow from that requirement.**

The user requires the final direct entry point, `main.mbt`, in the repository root, giving the invocation coordinate `moonx ZSeanYves/cygpath`, followed by normal cygpath options and paths such as `-h` and `-u`. Example arguments do not restrict options to either single or double hyphens. The root `moon.pkg` is therefore configured as an executable package, while root `main.mbt` composes `internal/cli`, `internal/encoding`, and `internal/host`; it contains no path conversion rules.

The `lib` package owns public types, Context, and the portable conversion engine. Its public import path is `ZSeanYves/cygpath/lib`. Responsibilities are separated by file initially, without introducing `internal/model` or `internal/engine`. Pure CLI parsing and per-file option state live in `internal/cli`; pure output encoding lives in `internal/encoding`; general-purpose I/O lives in `internal/host`.

Dependencies flow from the root executable to CLI, encoding, and host packages. CLI uses `lib` for conversion and `internal/encoding` for code-page support checks; the encoder and library use pure data facilities. The library does not depend on the root executable, CLI, or host boundary, and does not access the filesystem, environment, or processes. An `internal` package must not own public concrete types, and internal types must not leak into public `lib` signatures.

At P0 there were no implemented packages or public APIs, so this decision changed the plan without requiring migration of a published API. Create `lib/moon.pkg` with its first substantial implementation, and create root `moon.pkg` and `main.mbt` when implementing the CLI. The P0 design update added no empty entry point or placeholder package.

## ADR-004: Context is explicit and immutable; it does not inspect the host

**Status: Selected design baseline supporting backend consistency.**

Mounts, the cygdrive prefix, and POSIX/Windows cwd are inputs rather than global variables. The library validates and copies mutable containers when constructing Context; the CLI constructs it using explicit options. Supplied `drive_cwds`/`--drive-cwd` entries are validated compatibility metadata, not retained resolution state. When drive-relative input needs resolution, conversion follows the measured cygpath drive-root rule. An operation that lacks required context reports `MissingContext`.

Compared with reading host fstab files, the registry, or environment variables, this choice allows the same fixture to be replayed across machines and backends. The cost is that converting `/usr/bin` to Windows, for example, requires a supplied root or mount; ordinary relative/current-drive-rooted resolution may require explicit cwd. A parameterless convenience function cannot always solve the problem.

Any future configuration-file or environment import must be a separate, testable “data → Context” step that preserves the pure interface. Detection must not be hidden inside `convert`.

## ADR-005: Separate the portable contract from evidence of official compatibility

**Status: Selected design baseline.**

[03](03-path-semantics.md) governs conversion rules, and [04](04-api-and-cli.md) governs the CLI. Conclusions drawn from source can guide implementation, but real compatibility requires differential results against specified official artifacts.

The portable contract uses explicit library syntax/Context, natural CLI recognition where selected, measured profile rules, deterministic encoding, and typed errors. Windows/Mixed output supports 110 explicit legacy numeric pages plus UTF-8; POSIX output stays UTF-8, and main appends LF independently of the selected encoder. GNU option permutation, per-line options, root-local conversion, BOM preservation, and empty-stream behavior were revised using official evidence. Do not retain an obsolete design choice as a compatibility waiver.

The cost is maintaining a support matrix and difference records. The benefit is that compilation of an empty package, a few string cases, or recognizable error branches cannot be presented as a mature compatible implementation.

The first Windows subset retained 23 reviewed profile/case differences as historical discovery evidence. The current P3 gate does not consult those approvals: supported-domain cases require exact raw stdout/stderr and integer status, complete coverage, and Wasm/Native plus collect/replay consistency. The earlier differences were resolved or classified as source-backed undefined/unavailable input domains with independently checked project rejection. In particular, Cygwin and MSYS2 root separators now follow separate implemented profile rules.

Malformed UTF-8 exposes unchecked upstream conversion/allocation behavior; CP29001 conversion failed in a direct Win32 probe on the recorded host while CP1252 controls succeeded. Actual upstream bytes remain evidence, but neither boundary is counted as an exact conversion match or simulated using uninitialized-buffer observations. These conclusions do not attest the source commit used to build a distribution binary.

## ADR-006: Separate individual paths from path lists

**Status: Selected design baseline supported by upstream source.**

Expose `convert` and `convert_list`, with source syntax determining the list delimiter. Windows→POSIX and POSIX→Windows have different empty-member rules; drive-letter colons must not split Windows lists. A list fails atomically within one call and does not emit its already-converted prefix.

Compared with a `split/replace/join` shortcut, this requires member indices and representability checks. It prevents silent changes to the number or order of PATH members or their current-directory meaning. The library's empty-list result and the CLI's empty-operand handling are separate layers. The CLI now rejects an empty NAME with the measured empty-path diagnostic and exit 1, or skips it under `-i`; it does not manufacture a successful LF record by bypassing operand validation. Natural CLI list recognition and explicit library grammar remain distinct and are covered separately.

## ADR-007: Default to Wasm; use Native to verify consistency from the same source

**Status: User delivery requirement plus locally observed toolchain evidence.**

Retain `preferred_target = "wasm"`. Local `moonx --help` output observed on 2026-09-28 showed Wasm as the default, supported execution of versioned package coordinates, and marked the Native entry point deprecated. Release acceptance therefore centers on moonx/Wasm for a pinned version; Native continues to be compared through `moon run/build` for output, errors, and exit status.

Artifact formats and startup times are not required to match. Observable semantics under the supported contract must match. When the toolchain changes, check help output, builds, and real package retrieval again rather than carrying forward outdated publishing commands.

## ADR-008: Retain the existing module name and license for now

**Status: Existing settings retained during initialization.**

The Git remote is configured as the user-provided `moonbit-community/cygpath`; both the initial local branch and the remote default branch are `main`. The module name remains `ZSeanYves/cygpath`. A GitHub organization and a Mooncakes account are separate identities, so the organization name does not automatically replace the publishing namespace.

The existing Apache-2.0 license covers project-authored code. Path rules are independently implemented rather than copied from GPL/LGPL Cygwin runtime code. Generated mapping data retain their Unicode License v3 and Microsoft Open Specifications permission separately. The pure MoonBit MSYS2 sorting helpers adapt BSD-3-Clause newlib code with the required copyright, conditions, and disclaimer retained under `third_party/newlib`. Those notices must accompany distribution; no upstream C code is compiled or linked. Calling the project a “port” does not establish license compatibility.

Version `0.1.0` is currently module development metadata. Account, package-name, and version availability require explicit checks before the first release. P0 performed no publishing or account operations.

## ADR-009: Add packages, tests, and automation with substantial implementations

**Status: Selected design baseline.**

P0 retained module metadata and the complete design while removing the Hello CLI, placeholder tests, template workflows, and template hook. The P0 workspace contained no `moon.pkg`, MoonBit source, or generated interface. Earlier empty-library checks did not establish that this later workspace compiled or passed tests. Empty functions, numerous empty directories, and assertions that always pass must not be used to manufacture progress.

Each subsequent slice includes actual behavior, necessary tests, generated interfaces, and documentation updates. Automation uses `.mbtx` only, and build commands run serially. Validate concrete failure risks before moving to the next item. Measure performance after correctness and compatibility scope have stabilized.

The cost was that P0 provided no executable cygpath, consistent with its initialization-and-design deliverable. P1/P2 subsequently implemented the first end-to-end workflow and the packages needed by it, following this rule.

## ADR-010: Freeze a Reproducible P3 Scope

**Status: Implemented and verified for the recorded revision.**

[`p3-scope.json`](../testdata/oracle/p3-scope.json) freezes 152 capability rows and 473 unique suite/case identities: 461 supported-domain cases, ten malformed-UTF-8 cases, and two CP29001 cases. Coverage accounts for profile/context applicability and requires both backends in collect and replay. Actual process observations, exact matches, and boundary checks are reported separately in chapter 09. A case list alone is not execution evidence.

The freeze includes explicit default/custom contexts, profile-specific mount ordering, natural argv recognition, file-option state, lexical extended/long-path behavior, and the 111 archived mapping-table identities. CP29001 is archived but disabled, so 110 legacy numeric encoders plus UTF-8 are supported. Real Windows timeout/cancel/wait, spawn-failure, and tampered stdout/fixture/manifest drills are required in addition to successful conversions.

The benefit is a finite acceptance statement that can be reproduced and reviewed. P3 completion means all declared gates passed for that matrix. It does not mean full official compatibility, exhaustive input combinations, or completion of every algorithm that could be written in pure MoonBit.

Keep two kinds of unimplemented functionality separate. Actual 8.3 names, system directories, host ANSI/OEM selection, and runtime/entity queries need equivalent host facilities absent from the selected cross-target API boundary. Stateful encodings, GB18030, other mapping catalogs, and broader case-folding rules are feasible pure extensions that have not been implemented in this scope. Neither category may be hidden as a passing conversion or filled by product FFI/subprocess fallbacks.

## Remaining Questions and Minimum Evidence

| Question | Current conclusion | Evidence required for a change |
| --- | --- | --- |
| General-purpose I/O | async 0.22.4 and x 0.5.5; portable process contracts pass on Linux/macOS/Windows | Recheck affected host/backend behavior after dependency or toolchain changes |
| Official distribution baseline | Cygwin 3.6.10-1 and MSYS2 3.6.10-5, fixed binary/runtime hashes and measured contexts | New collection for changed artifacts/environment; a full source build commit remains independently unattested |
| Frozen P3 matrix | Completed at the recorded green revision, including actual fault drills | New scope rows or changed rules require new exact comparisons and coverage evidence |
| Extended paths and per-line options | Implemented within the frozen matrix | Additional namespaces or state combinations need explicit contracts and differential evidence |
| Output encoding | 110 legacy numeric pages plus UTF-8; CP29001 rejected with direct host evidence | New algorithms/data require provenance, meaningful regression tests, and official byte probes; automatic host-page selection requires a suitable host API |
| Filesystem/system capabilities | Unsupported through the current product boundary | An equivalent general-purpose MoonBit API with consistent Wasm/Native semantics and real environment evidence |
| Publication | Owner publishes; keep ZSeanYves/cygpath and development version provisionally | Chosen version, account/coordinate verification, package/license review, and exact-version moonx retrieval after publication |

These requirements do not make every extension mandatory or require user confirmation for ordinary implementation choices. They prevent source-only plans, undefined upstream output, or narrow successful probes from being reported as broader implemented and verified behavior.
