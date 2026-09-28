# Validation and Implementation Roadmap

P1 library, P2 executable, and the frozen P3 official-comparison scope are implemented and verified at `b32dd7448658bc251b216ba93a5c120ef54fdbc9`. [Check run 36385821361](https://github.com/moonbit-community/cygpath/actions/runs/36385821361) passed on Linux, macOS, and Windows. [Windows oracle run 36385821354](https://github.com/moonbit-community/cygpath/actions/runs/36385821354) passed Cygwin/MSYS2 in default/custom contexts. [Remote Validation](09-remote-validation.md) records the immutable evidence. Publication and exact-version registry retrieval remain separate.

The product is pure MoonBit. Official cygpath and Windows API probes belong exclusively to independent validation tools; the library and executable use no custom FFI or conversion fallback. Wasm and Native share conversion semantics. See [scope](01-upstream-and-scope.md), [architecture](02-architecture.md), [path semantics](03-path-semantics.md), and [CLI contract](04-api-and-cli.md) for the commitments being tested.

## Evidence and status

Keep implementation, execution evidence, and unsupported scope distinct. A passing project-contract test does not by itself establish official compatibility. Each official profile, host, backend, context, and upstream identity must be identifiable.

| Raw status | Meaning |
| --- | --- |
| `pass` | Actual stdout, stderr, and integer exit match |
| `fail` | Completed observations differ; retain the bytes |
| `skip` | An optional prerequisite is unavailable; never a pass |
| `error` | A process or collector could not produce a valid comparison |
| `timeout` | The deadline expired; preserve partial output and termination evidence |

Reports retain planned/executed counts and unexecuted cases. Every case in the frozen P3 scope is required. Required omissions, skips, errors, timeouts, evidence changes, or backend/replay inconsistencies fail acceptance.

Current supported-domain acceptance requires exact equality; there is no difference allowlist. Historical `reviewed-differences.json` is retained as evidence of an earlier baseline and is not read by the gate. Two domains are counted separately:

- Ten malformed-UTF-8 cases retain upstream observations while requiring exact project rejection and preservation of earlier successful output. Upstream source contains an unchecked failed conversion, so arbitrary resulting bytes are not a defined compatibility target.
- Two CP29001 cases require direct Windows API evidence of conversion failure with an untouched destination buffer, plus exact project unsupported-capability rejection. A successful control encoding is mandatory. The observation is specific to the measured Windows environments.

These boundaries do not increase the supported exact count. They cannot hide launch errors or timeouts. [Collection and replay](07-oracle-collection.md) specifies the checks and retained evidence.

## Test layers

### Pure library

Public API tests build explicit immutable Context values and never consult host cwd, environment, registry, mounts, or filesystem. Caller changes to supplied collections must not alter an existing context. Generated public interfaces and a separate consumer module verify that concrete public types belong to `lib`.

Behavioral classes include:

- Drive-absolute, drive-relative, rooted, UNC, POSIX, and ordinary relative inputs; explicit source syntax is tested separately from CLI automatic detection.
- Dots, repeated/mixed separators, trailing separators, spaces, Unicode, filename escaping, component limits, and ordinary extended prefixes.
- Present/missing cwd and mount context, profile-specific ordering, nested mappings, aliases, ASCII case policy, custom drive prefixes, and proc-prefix behavior.
- POSIX/Windows/mixed output, absolute conversion, root-local behavior, and list conversion with empty members and delimiter boundaries.

Assertions follow the recorded semantics. For example, drive-relative official behavior must not be replaced by assumed Windows per-drive resolution; MSYS2 mount selection must not be assumed identical to Cygwin. Preserve real regressions as small stable tests.

Properties require an explicit domain. Determinism and immutable context are general goals. Round trips, normalization idempotence, and list/item equivalence apply only where alias choice, delimiters, and source-spelling behavior make them valid. Do not assert unconditional string round trips or mount-order independence: MSYS2's partial ordering can make the complete mount snapshot relevant.

### CLI and encoding

Pure parser tests cover GNU permutation, immediate help/version precedence, short/long/abbreviated options, attached values, repeated and combined options, first-error behavior, missing arguments, `--`, and operands beginning with hyphens. The CLI uses natural source detection for official comparisons; explicit library-syntax tests remain separate.

The implemented `-o` mode has tested per-record option state. Ordinary extended namespaces, short root-local output, numeric code pages, code-page fallback/best-fit behavior, and raw LF record endings are exercised in the official corpus. Long-option quirks and invalid combinations follow measured behavior rather than inferred equivalence.

The pure encoding tables retain their source/license provenance. Unsupported code-page families and environment-dependent ANSI/OEM selection remain explicit capability boundaries. Numeric availability is defined by the implementation and current support documentation, not by the existence of a historical table alone.

### Host and executable

The thin root `main.mbt` composes the pure request/engine with official MoonBit runtime argv, files, streams, and process exit. It does not discover conversion context.

Tests exercise UTF-8 input, retained BOM content, CRLF translation, final records, empty streams and records, NUL visibility, fixed input-buffer boundaries, malformed UTF-8, immutable file input, per-record options, missing files, and closed stdout. Output is raw bytes in the selected encoding with LF record separators. Earlier successful records survive a later failure; lists retain their documented atomicity.

The 57 portable process fixtures run against actual Wasm/Native artifacts. The collector varies irrelevant cwd/HOME/MSYSTEM state, checks expected bytes and integer exits, then compares the backends separately. These contracts are independently specified; they are not official-tool recordings.

## Official Windows comparison

The frozen scope index has 152 rows and 473 distinct suite/case references: 461 supported, ten malformed-input, and two CP29001 boundary cases. Each profile runs 444 cases in its default context and 473 in its custom context. Collect/replay × Wasm/Native yields:

| Measure | Verified count |
| --- | ---: |
| Total observations | 7,336 |
| Supported-domain exact comparisons | 7,144 |
| Malformed-UTF-8 boundary observations | 160 |
| CP29001 boundary observations | 32 |
| Required skips, execution errors, timeouts, or supported mismatches | 0 |

The repetitions verify backend and replay consistency; they are not 7,336 independent path inputs. Out-of-variant scope rows are recorded explicitly, and the coverage audit requires every applicable case exactly once in each mode/backend.

Each collection records:

| Dimension | Evidence |
| --- | --- |
| Upstream | Actual package/runtime identity, executable/runtime SHA-256, raw version bytes, qualified source provenance |
| Project | Git SHA/dirty state, compiler, backend, build mode, artifact/launcher hashes |
| Host | Windows build, architecture, filesystem, installation root, policies and directory permissions |
| Path context | Raw mount table, prefix, cwd/drive state, immutable context, actual setup commands |
| Transport | Explicit environment, noglob settings, direct argv-byte probes, immutable file/stdin bytes |
| Execution | Program/argv, raw streams and exits, deadline, elapsed time and execution status |

No source commit is claimed to be attested to an installed binary merely because a runtime version mentions it. Setup-action pins and binary hashes serve different purposes.

Custom jobs create and measure real runtime mounts: nested targets, aliases, ASCII-insensitive matching, and a custom drive prefix. A runtime holder preserves their temporary lifetime. Context contains only actual declarations; a measured `/usr/bin` mapping does not manufacture a separate mount. Product conversions consume that snapshot without querying mutable host state.

Inputs and observations remain separate immutable artifacts. Global whitespace trimming or stderr suppression is prohibited. A changed fixture, upstream binary, or environment requires a fresh collection directory. Replay preserves official bytes and tests the project again under the same captured conditions.

Five real Windows fault drills pass per job: partial-output timeout with termination and confirmed child absence, process-launch failure, and three independent evidence-tampering rejections. These complement tool self-tests; neither replaces normal conversion comparisons.

## Host, backend, and public API gates

The root executable and host adapter support Wasm and Native. All-target checking of the pure packages does not imply executable support for JavaScript or Wasm GC.

The current three-host Check run passed 99 MoonBit tests per backend, 57 portable fixtures per backend, 57 backend comparisons per host, public-interface checks, and a separate public API consumer for both backends. The consumer uses the local workspace dependency; it does not prove registry retrieval.

Retain the dependency direction: public `lib` owns its types and has no host/CLI/root dependencies; CLI depends on `lib`; the executable composes CLI, encoding, and host adapters. Native must not privately expand conversion capabilities.

Run Moon commands sequentially:

```text
moon check --target all --deny-warn
moon test --target wasm --deny-warn
moon test --target native --deny-warn
moon run --deny-warn scripts/oracle.mbtx self-test
moon run --deny-warn scripts/ci_oracle.mbtx self-test
moon test --deny-warn scripts/check_cli.mbtx
moon run --deny-warn scripts/check_consumer.mbtx _build/consumer-new
moon build --target wasm --release --deny-warn
moon build --target native --release --deny-warn
moon run scripts/check_cli.mbtx --wasm <absolute-wasm-artifact> --native <absolute-native-artifact> --out <new-directory>
moon info --target all
moon fmt
```

Review generated-interface changes. Use snapshot updates only for reviewed expectation changes, not as a generic response to failures. Tool warnings and external linker/archive messages have separate evidence; project compilation must pass `--deny-warn`.

## Roadmap and release boundary

| Stage | Current status and exit evidence |
| --- | --- |
| P0: foundation | Completed; historical setup checks do not count as conversion tests |
| P1: portable library | Implemented; public tests, immutable context, interfaces, and external consumer verified |
| P2: executable | Implemented; both backends and three hosts pass the portable process suite |
| P3: frozen official scope | Completed for the declared 152 rows, measured profiles/contexts, and two separate boundaries; strict comparisons, replay, coverage, and Windows fault drills pass |
| P4: distribution and future scope | Owner publication and exact-version `moonx` retrieval pending; future capability additions need contracts and fresh evidence |

P3 completion is bounded by the committed scope. It does not imply complete Windows filesystem behavior, arbitrary encodings, every official option, future upstream releases, or an unlimited “all pure implementations” claim. System-directory discovery, 8.3 identities, symlink/junction resolution, automatic environment discovery, and other unsupported host capabilities remain explicit.

The repository owner will publish separately after version/account/package review. Afterwards, verify `moonx ZSeanYves/cygpath@<published-version>` on promised hosts. Local installation, workspace consumers, and CI cannot substitute for that exact registry retrieval.

## Performance

Measure pure conversion, context construction, and CLI startup/I/O separately after correctness is stable. Fix machine, toolchain, build mode, fixtures, and context; retain repeated measurements. Character/component/list/mount counts and prefix overlap are relevant input dimensions. Linear mount scanning has a path-query bound of `O(m × n)` for m mounts and path length n; context sorting has its own cost. MSYS2 sorting behavior is observable and cannot be replaced by a different algorithm solely for speed without renewed semantic validation. No throughput or latency claim follows from the current correctness evidence.
