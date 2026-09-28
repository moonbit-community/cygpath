# Validation and Implementation Roadmap

This chapter defines how to turn the architecture into a verifiable implementation. At the historical **P0: initialization and design** baseline, the workspace contained only module metadata and design documents: no `moon.pkg`, MoonBit source, generated interfaces, path conversion implementation, behavioral tests, or differential collector. P1 library and P2 executable source are now implemented. Their current execution evidence is recorded in [the architecture index](README.md); the full cross-host, Windows oracle, and release gates below remain binding. Earlier empty-package checks do not validate later implementation.

The project uses pure MoonBit, and the CLI is intended for distribution and invocation through `moonx` after publication. The product does not introduce project-owned C/C++ FFI or depend on system `cygpath` as an implementation or fallback; official programs are used only by independent test collectors. Wasm and Native must share semantics. Selecting a backend must not change path conversion capabilities.

See [01](01-upstream-and-scope.md) for upstream sources and compatibility scope, [02](02-architecture.md) for dependency boundaries, [03](03-path-semantics.md) for path contracts, and [04](04-api-and-cli.md) for the API/CLI design. Acceptance criteria in this chapter must not expand the commitments of those chapters.

## 1. Validation goals and evidence levels

Validation addresses three separate questions: whether the pure core satisfies this project's explicit contract, whether the CLI interprets arguments and handles input/output correctly, and whether actual Windows results match a specified version of the official program. Passing the first two does not automatically answer the third.

Track each capability as `planned / implemented / verified / unsupported / deferred`, with an evidence path. `implemented` requires code; `verified` also requires tests in an applicable environment. Support claims identify the compatibility profile, host system, and backend. Record Cygwin and MSYS2 separately; output from one is not a substitute oracle for the other.

Each case execution has exactly one of these outcomes:

| Status | Definition | Meaning for acceptance |
| --- | --- | --- |
| `pass` | All required observations match the specified oracle | Covers only that input and environment |
| `fail` | The program completes but differs from the specified expected observation | Remains a raw mismatch; requires correction or a scoped, reviewed difference record |
| `skip` | A capability, host, or prerequisite is unavailable, with the reason recorded | Unverified; must not count as a pass |
| `error` | The collector, toolchain, fixture preparation, or runtime environment fails | Repair the infrastructure before rerunning |
| `timeout` | Execution exceeds the explicitly configured deadline for this run | Preserve partial output; do not treat it as an ordinary exit |

Reports include counts for planned, executed, pass, fail, skip, error, and timeout, and retain the list of unexecuted cases. Record portable-contract results, backend consistency, and official behavior comparisons separately. Returning an error as designed can pass a project contract test without matching official output or establishing that the requested feature is implemented. Give each known difference its own identifier, affected scope, and evidence. Do not turn differences into passes by weakening assertions or updating snapshots in bulk.

The Windows CI wrapper adds a separate acceptance result to the raw collector
result. A `reviewed-difference` must match the checked-in profile/case, fixture
digest, official executable/runtime digests, both streams, and both exit codes
exactly. It does not change raw `fail` to `pass`. Unknown or changed differences,
incomplete runs, skips, errors, timeouts, and backend/replay inconsistencies
fail the gate. See [07](07-oracle-collection.md) for the mechanism and
[09](09-remote-validation.md) for the first accepted evidence.

## 2. Test layers and responsibilities

### 2.1 `lib`: the deterministic pure core

Blackbox tests for `lib` call the public API and explicitly construct both the source path type and immutable `Context`. They must not depend on the test process's cwd, environment variables, registry, or actual mount table. Copy or freeze caller-owned mutable containers when constructing `Context`; later changes to the original arrays must not change conversion results. Use whitebox tests only for parsing boundaries that public observations cannot adequately cover.

Organize cases by behavioral equivalence classes instead of mirroring every private helper:

- Path kinds: Windows drive-absolute, drive-relative, current-drive-root-relative, UNC, and ordinary relative paths; POSIX absolute and relative paths. Assert the interpretation of the same string under different input types separately, without host-based guesses.
- Component boundaries: mixed separators, repeated separators, `.`, `..`, root boundaries, trailing separators, empty input, spaces, and non-ASCII characters. Distinguish lexical processing from filesystem-dependent real-path resolution; lexical collapsing must not simulate symlink resolution.
- Context: present and absent POSIX/Windows cwd, current drive, and per-drive cwd. Resolving `C:foo` must not silently substitute `C:\foo`; missing necessary context must produce distinguishable errors.
- Mounts: root mounts, nested mounts, longest valid component prefixes, similar but distinct boundary names, case policies, alias conflicts, and cygdrive prefixes. Mount order must not accidentally alter specified results.
- Output: the format capabilities behind `-u/-w/-m`, `-t` type selection, `-a` absolute resolution, and `-U` cygdrive output policy. Define valid combinations and required context before checking results.
- Lists: Windows and POSIX list delimiters, drive-letter colons, consecutive delimiters, leading/trailing empty members, paths containing delimiters, and error positions. Define which inputs are representable; global string replacement is not path-list parsing.

Use assertions for stable strings and error categories. Complex diagnostic structures may use `Debug` and `debug_inspect`, but snapshots do not replace assertions on essential fields. Official behavior that is not yet established goes into the research backlog instead of receiving a guessed “correct result.”

### 2.2 `internal/cli`: argv to execution requests

The pure argument parser receives already-tokenized argv and returns a request or structured error without reading files or the global environment. Test short/long options, attached arguments, option combinations, repeated options, mutually exclusive options, missing arguments, unknown options, `--`, paths beginning with a hyphen, and multiple operands. Option precedence, defaults, exclusion rules, and interpretation after the first NAME follow the portable contract in chapter 04. Record any different official parsing behavior separately; it does not automatically override the established contract.

Reading `-f` files or stdin and writing stdout/stderr belong to the execution boundary. P2 integration tests cover empty files, a final line without a newline, CRLF, empty lines, a UTF-8 BOM only at the initial position, invalid UTF-8, read/write failures, and rejection of mixed `-f` and NAME input. Output must use UTF-8 + LF regardless of locale. Test `-C UTF8`/`-C 65001` within the output-format restrictions of chapter 04; reject other code pages explicitly. Each case specifies the rules from bytes read to decoding, record boundaries, and requests. Do not trim spaces from paths. Processing multiple NAME operands or input lines stops at the first failure while preserving earlier successful output. A single list fails atomically and emits no partial list.

Per-line option state from `-o` returns `UnsupportedCapability` under the current contract and is only a P4 extension candidate. P3 may collect upstream `-o` behavior, but must not list it as an input mode implemented in P2. Its state lifecycle needs a separate definition and validation before future enablement.

CLI tests separately verify the mapping from library errors to diagnostics, stdout/stderr routing, and exit codes. Successful argument parsing does not mean the request can be fulfilled. Requests for short paths, system directories, or other capabilities without a consistent pure MoonBit implementation must return `UnsupportedCapability`, not an ordinary conversion result that appears successful.

### 2.3 `internal/host` and the executable entry point

`internal/host` wraps only argv, file I/O, standard-stream I/O, and exit facilities supplied by official general-purpose MoonBit APIs. It does not populate Context from the environment or provide Windows business-logic FFI. The first Context version comes only from library arguments or the explicit CLI options in chapter 04. There is no automatic cwd, fstab, registry, or installation-root detection. For conversion requests that do not read files, integration tests change irrelevant host state such as cwd, HOME, and MSYSTEM to establish that identical explicit requests produce identical results. Resolving a relative filename supplied to `-f` remains ordinary I/O. Tests of the executable package containing root `main.mbt` cover composition, input/output, and process behavior without repeating the full `lib` path matrix.

## 3. Property tests must define their domain

Property tests may use a fixed seed and shrink failing inputs. Preserve minimized failures as stable regression cases. Applicable properties include determinism for identical input and `Context`; preservation of input and context; normalization idempotence within supported, already-normalized formats; independence from unrelated mounts for unmatched paths; and equivalence between list conversion and item-by-item conversion where every member is unambiguously representable.

**Do not require POSIX→Windows→POSIX to restore the original string unconditionally.** Multiple mounts may map to the same Windows path, and case or separators may be normalized. Assert a round trip to a specified canonical form only when the mapping is unique, paths are representable, context is unchanged, and filesystem-dependent interpretation is excluded. Lists involving empty members, delimiters, or drive-letter colons likewise require a restricted input domain first. Define properties for UNC, device paths, and extended prefixes separately rather than applying general path properties without qualification.

## 4. Differential testing against official programs and fixed environments

P3 invokes real Cygwin and real MSYS2 `cygpath` separately on Windows. Each run first creates an environment manifest, then prepares fixtures, and finally executes both upstream and this project. The collector starts processes using executable paths and argument arrays, not concatenated shell commands. Both sides share the same immutable path inputs, with writable working directories copied separately. Test tooling transcribes the real upstream environment into this project's explicit Context/CLI arguments and preserves that mapping. The product itself does not perform this environment detection.

Fix and record at least the following for every run:

| Dimension | Required records |
| --- | --- |
| Upstream | Source URL, source commit/tag when independently established, measured distribution package identity, absolute executable path and SHA-256, raw `--version` output, runtime-library version; explicitly identify unattested source-to-binary correspondence |
| This project | Git SHA, dirty-workspace status, MoonBit version, backend, build mode, artifact digest |
| Host | Windows version/build, architecture, filesystem type, Cygwin/MSYS2 installation root, launch method |
| Path environment | cwd, current drive, per-drive cwd, mount table and cygdrive configuration, relevant environment variables, actual directory existence and permissions |
| Encoding | Locale, input/output code pages, console or redirected execution, collector encoding and newline policy |
| Filesystem capabilities | Long-path policy, 8.3-name policy, test volume and actual short names, symlink/junction conditions |

An 8.3 test cannot merely establish that the volume allows short-name creation: it must prove that the target file actually has the expected short name. Cases requiring existing files retain their creation steps and directory listings; behavior for nonexistent files receives separate cases. Any change to a fixed condition starts a new run output directory. Do not combine old results and a new environment into one successful run.

MSYS may automatically convert arguments and environment variables when launching native Windows programs. Collection must distinguish strings written in a shell, actual argv, and the tested conversion output. Prefer direct launch methods that do not introduce this conversion. If using an MSYS shell, record the launch chain and exact values of `MSYS2_ARG_CONV_EXCL` and `MSYS2_ENV_CONV_EXCL`, and prove received arguments using an argv echo probe. Until launcher conversion is excluded, classify the result as a collection-environment problem.

Save stdout/stderr as raw bytes before creating readable displays. Comparisons are byte-exact by default and preserve trailing newlines, CRLF, NUL, and encoding differences. Save raw integer exit status together with timeout/termination information; a Boolean “was it zero?” is insufficient. Any normalization rule for diagnostic positions, language, or similar fields must identify its rationale, affected fields, and raw evidence individually. Global trimming and ignoring stderr are prohibited.

## 5. Fixtures and result format

`testdata/contracts/`, `testdata/oracle/`, and `scripts/` are validation assets,
not public MoonBit packages. The first stores this project's portable contract;
the second stores official-environment templates and, when collected, provenance
for official observations. Schemas carry `schema_version`. JSON describes
structures while separate `.bin` files preserve raw stdin/stdout/stderr,
avoiding attempts to put undecodable bytes into JSON strings. Evidence payload
paths are relative to the run directory; executable paths and recorded launch
arguments retain their actual values. Save byte lengths and SHA-256 digests;
text previews do not participate in equality checks.

The implemented portable suite uses
[`testdata/contracts/cli.json`](../testdata/contracts/cli.json) and an exact
[`help.txt`](../testdata/contracts/help.txt). Its 57 process fixtures exercise
options, explicit context, NAME/file/stdin input, UTF-8, record boundaries,
partial output, list atomicity, and closed-stdout failures. The
[`check_cli.mbtx`](../scripts/check_cli.mbtx) runner executes both artifacts,
varies irrelevant cwd/HOME/MSYSTEM state, preserves raw bytes and digests, and
reports contract results separately from backend equality. See
[the fixture guide](../testdata/contracts/README.md) for the schema and runner
options. These fixtures specify project behavior and are not official-tool
observations.

Every fixture has at least these fields:

| Field group | Contents |
| --- | --- |
| Identity | Unique `case_id`, schema version, semantic category, validation kind (contract/backend consistency/official comparison), source link/commit, applicable compatibility profile |
| Input | argv arrays for both sides, stdin byte reference, explicit source type, core `Context`, separately stored official-host snapshot and its mapping to Context |
| Preconditions | Required capabilities, allowed hosts/backends, directory preparation requirements, rules for setting and clearing environment variables |
| Expected result | Core result/error, or stdout/stderr byte references and exit status from the specified oracle |
| Execution result | Actual observations, status, skip/error reasons, start time, deadline, structured representation of the execution command |
| References | Fixture digest, environment-manifest digest, implementation version, difference identifier, full raw-evidence paths |

Save test input, official collected output, and project execution results separately so running a test cannot overwrite its oracle. A fixture update must explain the behavioral change and revalidate affected cases. An official upgrade is also a baseline change. For cases depending on local usernames or installation paths, first fix isolated directories and Context. Model anything that cannot be fixed as explicit template parameters, and still save the complete bytes after expansion.

## 6. Host, backend, and public API acceptance

A backend is a compilation/execution method; a host is the execution environment. Passing Native and Wasm tests on macOS does not verify real Windows path environments. The planned matrix is below. Record results and reasons for non-execution separately for each cell. Wasm/Native consistency is mandatory; extend the matrix to other backends once actually supported.

The root executable and host adapter currently declare Wasm/Native support.
The pure library and CLI packages compile for all standard compiler targets.
An all-target check honors those package declarations; it does not assert that
the executable supports Wasm GC or JavaScript. The checked-in
[CI workflow](../.github/workflows/check.yml) schedules Wasm/Native tests and
process acceptance separately on Linux, macOS, and Windows. All three hosts
passed at `7dfe6ba`; [09](09-remote-validation.md) records the run and artifacts.

| Suite | Host | Backend | What it establishes |
| --- | --- | --- | --- |
| Pure core | Linux, macOS, Windows | Wasm, Native | Contract consistency for identical fixtures across available combinations |
| CLI parsing | Same as the pure core | Available backends | Consistent argv parsing and request construction |
| CLI process integration | List each of the three hosts separately | Wasm, Native | Byte-exact consistency of actual input/output, exit status, and diagnostics |
| Official differential tests | Windows + Cygwin / MSYS2, run separately | The project's actual delivery backend | Compatibility with a specified official program and environment |
| Pure MoonBit extensions | Promised hosts | Wasm, Native | Consistent behavior for new capabilities, or consistent rejection of unsupported requests |
| `moonx` release acceptance | Promised hosts | The current officially supported `moonx` execution method, prioritizing Wasm | The exact published version can be retrieved, launched, and satisfies the CLI contract |

Given the same fixture, explicit Context, host, and I/O conditions, Wasm and Native must produce identical stdout/stderr bytes and exit status, including error paths. Differences in artifact format, digest, size, and startup time are normal artifact differences rather than semantic differences. Differences in output content, error categories, newlines, or exit codes require explanation and correction. If official general-purpose I/O APIs cannot satisfy a semantic requirement, both backends reject that capability consistently; Native must not privately expand support.

Dependency checks require `lib` to have no host, CLI, or root-executable dependencies, and all public concrete types to be owned by `lib`. Allowed directions are `internal/cli → lib`, `root executable → internal/cli`, and `root executable → internal/host`. `internal/host` uses only general-purpose I/O dependencies. Cycles and reverse dependencies are prohibited. Root `moon.pkg` is configured as an executable package, and root `main.mbt` only composes the CLI and host boundary. Internal types must not leak into public `lib` signatures. Record the purpose, version, license, backend support, and any project business-logic FFI introduced by each new dependency. Do not add dependencies in advance for empty scaffolding.

Once real packages exist, each stage generates and reviews `.mbti` files using `moon info`, checking that newly public types, constructors, methods, and errors belong to the approved contract. External-consumer tests subsequently verify importing `ZSeanYves/cygpath/lib`, constructing values, pattern matching, method calls, and error handling, preventing an API that works only inside the repository. Passing backend checks for `lib` must not conceal unsupported combinations at the CLI's general-purpose I/O boundary.

## 7. Stage deliverables and stop conditions

| Stage | Deliverables | Completion criteria |
| --- | --- | --- |
| P0: initialization and design | Template cleanup, module metadata, remote association, documentation index, architecture handbook | Valid local structure and links; accurately record the absence of packages, source, generated interfaces, and behavioral tests at P0; do not reuse earlier empty-package checks as current evidence |
| P1: pure core | Create `lib` with explicit source types, immutable Context, path classification, mounts/cygdrive, lists, and core conversion | Cover capabilities needed by `u/w/m/t/p/a/U`; pass normal, error, and missing-context cases; establish conditional properties; pass dependency and external `ZSeanYves/cygpath/lib` API gates |
| P2: thin CLI | Create root executable `moon.pkg` and root `main.mbt`, internal CLI/host packages, pure argv parsing, explicit Context, UTF-8 encoding/decoding, general-purpose I/O boundary, and basic `-f` input | Pass the CLI option matrix, actual stream/file integration, error routing, and exit-status checks; byte-exact Wasm/Native consistency; runnable root package; explicit rejection of unimplemented capabilities such as `-o` |
| P3: official differential tests | Isolated Windows environments, fixed official artifacts, collection and replay tools | Complete raw evidence for all promised supported cases; zero unexplained differences; zero skip/error/timeout outcomes for required cases; separate Cygwin/MSYS2 reports |
| P4: pure MoonBit extensions and release | Extensions with consistent pure MoonBit implementations, packaging, and `moonx` acceptance | New capabilities pass Wasm/Native consistency and official differential tests; retrieval and execution of the exact published version through `moonx` pass after publication; proprietary system capabilities without a consistent solution retain `UnsupportedCapability` |

P1/P2 may proceed from explicit project contracts, but unresolved upstream semantics must remain traceable. Do not advertise full Cygwin/MSYS2 compatibility before P3. P4 does not promise complete Windows-specific functionality. Capabilities such as 8.3 names, system directories, and code pages remain unsupported without a consistent pure MoonBit solution; FFI or system-command fallbacks must not bypass this gate. Before the first formal release, also review the support table, licenses, published package contents, consumer usability, and all required evidence.

Current local macOS evidence includes 59 passing tests on each of Wasm and
Native, and 57 portable process fixtures on each backend: 114 process results
passed and all 57 backend comparisons matched stdout, stderr, and exit status
exactly. The latest local process report is `_build/cli-root-regression/`.
The same counts passed remotely on Linux, macOS, and Windows at `7dfe6ba`.

The first real Windows oracle subset also passed its reviewed-difference gate
at that revision: 50 cases per profile, two backends, and collection/replay
produced 400 comparisons. Cygwin had 156 exact matches and 44 raw mismatches;
MSYS2 had 152 exact matches and 48 raw mismatches. The 92 raw mismatches represent
23 reviewed profile/case records and remain visible in the artifacts. There
were zero unexplained differences, required skips, errors, timeouts, or
backend/replay inconsistencies. [09](09-remote-validation.md) gives the fixed
official binaries and limits of this evidence. Completing the full supported
matrix and real Windows timeout/termination and tampering drills remains P3
work; publication and registry/moonx acceptance remain P4 work.

Use these tool commands for acceptance. Run MoonBit commands sequentially to avoid contention for the build lock. Tool behavior on the historical package-free module is not implementation validation:

```text
moon check --target all --deny-warn
moon test
moon test --target native --deny-warn
moon info --target all
moon fmt
```

During implementation, also execute tests for the appropriate targets in the matrix, recording the target set actually accepted by the toolchain. Warning-free checks for all targets do not replace execution on each host. Use `moon test --update` only for confirmed expected changes and review the diff; it is not a general procedure for fixing failing tests.

For developer smoke checks, run `moon run --target wasm . -- <arguments>` and `moon run --target native . -- <same-arguments>` separately. Process acceptance uses the collector to compare raw output and status of built artifacts. After formal publication, users pass ordinary options such as `-h` and `-u` to the root coordinate `moonx ZSeanYves/cygpath`. Release acceptance uses `moonx ZSeanYves/cygpath@<published-version> -u 'C:\work'` to test the actual package at an exact published version. The version and local execution arguments here are placeholders; there was no executable entry point or published package at P0. The standalone `--` in `moon run` separates tool arguments and does not require cygpath options to use two hyphens. Release acceptance prioritizes the default Wasm execution method and does not rely on continued availability of a Native option in `moonx`; Native semantics are verified separately through the development toolchain.

After building both root executable artifacts, run the portable process suite:

```text
moon build --target wasm --release
moon build --target native --release
moon run scripts/check_cli.mbtx --wasm <absolute-wasm-artifact> --native <absolute-native-artifact> --out <new-directory>
```

The official differential workflow uses one `oracle.mbtx` program with separate
collection and replay modes. Its manifest/schema guide is
[07 Oracle Collection and Replay](07-oracle-collection.md):

```text
moon run scripts/oracle.mbtx collect <manifest> <fixtures> <new-oracle-directory>
moon run scripts/oracle.mbtx replay <manifest> <oracle-directory> <new-replay-directory>
moon run scripts/oracle.mbtx self-test
```

A tooling self-test validates the collector, not official compatibility. Real
collection still requires a prepared Windows environment, pinned Cygwin/MSYS2
executables, and complete manifests. An example manifest or empty oracle
directory is not evidence that P3 passed. Replay must preserve collected input
and observations instead of overwriting them. Run the profiles separately.

All automation uses `.mbtx` and launches subprocesses with argument arrays.
The [Check workflow](../.github/workflows/check.yml) runs portable checks and
uploads process evidence. The [Windows oracle workflow](../.github/workflows/oracle.yml)
installs official distributions and runs `scripts/ci_oracle.mbtx` to measure
context, collect/replay both backends, and apply exact reviewed-difference
records. Successful executions are linked in [09](09-remote-validation.md).
Before official collection,
validate the manifest, upstream digests, required capabilities, and fixture
schema. Stop on failure; do not fall back to another `cygpath` found on system
PATH. Official `cygpath` subprocess calls belong only in test tooling and are
prohibited in the product. Publication remains a distinct, unexecuted workflow.

## 8. Performance work follows stable semantics

First establish correctness and differential results for the supported scope, then measure three costs separately: pure conversion, Context construction, and CLI startup/I/O. Input dimensions include total characters, component count, list-member count, mount count, and common-prefix length. Scale input sizes to observe time and allocation behavior. Scanning and output should be approximately linear in input/output size. Initial table-scanning mount matching must include prefix-character comparisons: a query of path length n against m mounts has an upper bound of `O(m × n)`. For lists of total length N using the same mount table, matching has an upper bound of `O(m × N)`, plus scanning/output costs. Report Context pre-sorting cost separately. Decide whether to build an index from real scales and observations.

Performance reports fix the machine, toolchain, build mode, fixtures, and Context, and show repeated samples and variation. Measure Context preprocessing separately from individual conversions. Do not promise millisecond thresholds, throughput, or speedup ratios before establishing a baseline, and do not remove error checks to improve metrics. Optimize only after observing a concrete bottleneck, then revalidate output and error behavior with the same fixtures.
