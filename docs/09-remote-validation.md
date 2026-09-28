# Remote Validation Report — 2026-09-28

The project passed its Linux, macOS, and Windows portable-contract jobs and its separate Windows Cygwin and MSYS2 review gates on **2026-09-28**, at repository commit **`7dfe6ba58520a6f5249c41bd9aad39cfeb215440`**. The official comparison corpus has **308 exact matches and 92 retained raw mismatches** across 400 comparisons. The mismatches correspond to **23 reviewed profile/case pairs**, each bound to exact inputs, upstream artifacts, output bytes, and exit codes. This establishes a verified subset with recorded differences; it does not establish full Cygwin/MSYS2 equivalence or completion of the entire P3 roadmap.

The completed workflows are:

| Workflow | Run | Jobs | Result |
| --- | --- | --- | --- |
| [Check](https://github.com/moonbit-community/cygpath/actions/runs/36371978473) | `36371978473` | `ubuntu-latest`, `macos-latest`, `windows-latest` | All three succeeded |
| [Windows oracle](https://github.com/moonbit-community/cygpath/actions/runs/36371978419) | `36371978419` | Cygwin and MSYS2 on separate Windows jobs | Both succeeded |

Both runs identify the same full repository SHA above. The final product correction is [commit `476d6a8`](https://github.com/moonbit-community/cygpath/commit/476d6a80caffe933821f997ce7ae948d6ce6f10e), which distinguishes the delimiter of POSIX root `/` from an optional trailing separator on a non-root input. Mapping `/` into a Windows installation directory therefore does not invent an extra trailing separator. A library regression and a portable process fixture cover the rule. [Commit `7dfe6ba`](https://github.com/moonbit-community/cygpath/commit/7dfe6ba58520a6f5249c41bd9aad39cfeb215440) records the reviewed official differences. The successful runs above rebuilt and executed that accepted baseline; this report uses their fresh artifacts.

## 1. Portable contract and backend results

Each host ran 59 MoonBit tests on Wasm and the same 59 on Native. Each host also ran all 57 portable process fixtures on both release artifacts, producing 114 successful process observations and 57 exact Wasm/Native comparisons.

| Host job | Wasm tests | Native tests | Process contract results | Exact backend comparisons |
| --- | --- | --- | --- | --- |
| `ubuntu-latest` | 59/59 | 59/59 | 114/114 | 57/57 |
| `macos-latest` | 59/59 | 59/59 | 114/114 | 57/57 |
| `windows-latest` | 59/59 | 59/59 | 114/114 | 57/57 |

All three process summaries record `complete: true`, no unexecuted cases, and zero fail/error/timeout/skip or backend-nonpass results. Across hosts, this is 342 process contract observations and 171 exact backend comparisons. These numbers are separate from the official comparisons below.

The Check workflow also passed warning-free all-target checking, collector and review-gate self-tests, the process collector's quoted-path regression, source/script formatting, public-interface generation with no tracked interface drift, release builds, and package-content inspection. Its all-target check respects package target declarations: the root executable and host adapter support Wasm/Native, while the pure library and CLI packages compile for the standard compiler targets.

The process fixtures cover explicit context and profile selection, conversions and lists, option parsing and validation, help/version, file/stdin records, BOM and CRLF handling, final unterminated records, malformed UTF-8, preserved output before failure, read errors, and closed stdout. They assert the project's portable contract described in [chapter 04](04-api-and-cli.md); they are independently authored expectations rather than official output snapshots.

## 2. Official comparison results

Each official profile uses its ten starter cases plus the forty shared read-only matrix cases. Every case runs once in collection and once in replay for each project backend. Collection executes both the official program and the project; replay verifies and reuses the saved official bytes while executing the project again.

| Profile | Distinct inputs | Comparisons | Raw exact `pass` | Raw `fail`, accepted as reviewed difference | Distinct reviewed profile/case pairs |
| --- | --- | --- | --- | --- | --- |
| Cygwin | 50 | 200 | 156 | 44 | 11 |
| MSYS2 | 50 | 200 | 152 | 48 | 12 |
| Total | 100 profile/input pairs | 400 | 308 | 92 | 23 |

Both profile summaries record `complete: true` and `accepted: true`. There are zero unexplained differences, required skips, process errors, timeouts, omitted cases, or backend/replay inconsistencies in these runs. Repeated backend and replay executions check consistency; they do not turn 100 distinct profile/input pairs into 400 distinct coverage cases.

Raw equality compares stdout, stderr, and integer exit status, including stream lengths and SHA-256 digests. An official nonzero exit can match exactly when both outputs and status agree. A timeout or missing observation never counts as a match.

The [collector](../scripts/oracle.mbtx) continues to report each mismatch as `fail` and exits nonzero for a collection/replay containing raw failures. The separate [CI wrapper](../scripts/ci_oracle.mbtx) checks complete execution, evidence integrity, case identity, expected collector exit status, and backend/replay consistency before applying the [reviewed-difference records](../testdata/oracle/reviewed-differences.json). Every accepted record specifies the profile, case ID, fixture digest, official executable/runtime digests, exact stream hashes and exit codes, policy ID, and reason. Changed or unlisted observations fail the gate. A policy identifier alone does not authorize any mismatch, and an approval cannot waive a backend inconsistency.

## 3. Measured environment and provenance

All three Check jobs and both official jobs reported:

| Component | Observed version |
| --- | --- |
| Moon | `0.1.20260920 (914d7da 2026-09-20)` |
| Moonc | `v0.10.14+7d59c7ec9 (2026-09-18)` |
| Moonrun | `0.1.20260920 (914d7da 2026-09-20)` |
| Project module | `0.1.0`, clean repository SHA `7dfe6ba58520a6f5249c41bd9aad39cfeb215440` |
| Product I/O dependencies | `moonbitlang/async@0.22.4`, `moonbitlang/x@0.5.5` |

The official comparison manifests identify release builds on Windows `10.0.26100.0`, architecture `X64`, filesystem `NTFS`. The test volume is `C:` with label `Windows`. `LongPathsEnabled=1` and `NtfsDisable8dot3NameCreation=2` were recorded, but no actual short-name operation was exercised. The cwd observations record ordinary directories, their ACLs, and no link type/target. These observations do not establish general symlink, junction, long-path, or 8.3 behavior.

The two official installations and packages were:

| Profile | Installation root | Distribution package | Runtime observation |
| --- | --- | --- | --- |
| Cygwin | `C:/cygpath-cygwin` | `cygwin 3.6.10-1` | `3.6.10-1.x86_64`, built `2026-07-13 20:20 UTC` |
| MSYS2 | `C:/cygpath-msys2/msys64` | `msys2-runtime 3.6.10-5` | `3.6.10-c770e1b9.x86_64`, built `2026-09-26 06:38 UTC` |

Both programs report `cygpath (cygwin) 3.6.10` in the retained `--version` output. Their distinct executable and runtime hashes identify the actual profile artifacts:

| Artifact | SHA-256 |
| --- | --- |
| Cygwin `bin/cygpath.exe` | `473cf4cab34c085d15563e290fc17d36fb69f742fd83c1f0fcf6e2f9666d2192` |
| Cygwin `bin/cygwin1.dll` | `d66788fce4ef1ce787fc1a83f2dd1e063e58bbf0d48ad93164ee195a983c035e` |
| MSYS2 `usr/bin/cygpath.exe` | `a70581980983340cd7d1358f50f8e9d8e98e015da78724d1b1e824d0cfcf6bce` |
| MSYS2 `usr/bin/msys-2.0.dll` | `957d880559f0bfe7406a4cb27724610e7ce2f367030e299373d7ef37fbbb51b3` |

Each profile's `manifest-wasm.json` and `manifest-native.json` retain the project artifact and launcher hashes. The separate Native builds have distinct binary digests. Their tested output semantics agree; this report does not claim reproducible Native binary builds.

The workflow pins [`cygwin/cygwin-install-action`](https://github.com/cygwin/cygwin-install-action/tree/121fc294c6b6864e1d52caeaa5c8ddb33d3e90f3) at `121fc294c6b6864e1d52caeaa5c8ddb33d3e90f3`, installs from `https://mirrors.kernel.org/sourceware/cygwin/`, and leaves its signature checks enabled. The action revision does not freeze the mirror catalog or downloaded installer. `installer-evidence.json` records setup executable SHA-256 `2c9f2fb56e1fb687b5d9680afa8f8b06e6214f0e483096af0eae1946431226c5`, retained raw `installed.db` and `setup.ini` bytes with their hashes, and the digest/length of `cygwin-3.6.10-1-x86_64.tar.xz`. The installer and package archive themselves are not retained in the project evidence artifact.

The workflow pins [`msys2/setup-msys2`](https://github.com/msys2/setup-msys2/tree/ec48f7c5447b3140e2b088413ae3a55687bccb6e) at `ec48f7c5447b3140e2b088413ae3a55687bccb6e`, with `release: true`, `update: false`, and `cache: false`. That action's source pins installer release `2026-09-27` and SHA-256 `ad336cccfda47758b5e15cda993fbba421115cb0b126697daef1ee4dfe37209f`; the job log records extraction of the `20260927` installer. The project artifact's MSYS2 `installer-evidence.json` has no entries, so it does not independently retain or attest the installer bytes. The actual installed `cygpath.exe`, runtime DLL, package identity, and version output are independently recorded in the oracle manifest and observations.

The manifest explicitly qualifies upstream source provenance: distribution package identity is measured, but a full source Git commit producing each official binary is **not independently attested**. The MSYS2 runtime's short `c770e1b9` suffix is part of its reported identity. The research commits in chapter 01 must not be substituted for build provenance. The MoonBit setup action is pinned, while its default toolchain channel can move; these recorded versions and artifact hashes define this run's toolchain evidence.

## 4. Context and launch controls

The official programs and project artifacts receive argument arrays through the process API. No MSYS/Cygwin shell launches the tested commands. Wasm runs through the recorded Moonrun artifact with an explicit `--` before the project arguments; Native runs directly. Environment inheritance is disabled, necessary Windows/Moon variables are enumerated, `LANG` and `LC_ALL` are `C.UTF-8`, and both `MSYS2_ARG_CONV_EXCL` and `MSYS2_ENV_CONV_EXCL` are `*`. `MSYSTEM` and `CYGWIN` are explicitly absent. Both recorded input/output code pages are 65001; the collector preserves redirected bytes without newline normalization. Each tested process has a 10,000 ms deadline.

The tool-only environment probes retain their commands, raw output, exit codes, and hashes. Root and `/usr/bin` mappings, mount tables, drive prefixes, POSIX/Windows cwd, locale, package identity, and Windows host facts are recorded. The product still receives only explicit Context arguments; it does not detect these values itself.

The current-drive and per-drive cwd values are `C:/cygpath-ci/cygwin/cwd` and `C:/cygpath-ci/msys2/cwd`, respectively. PowerShell 7 invokes the native .NET `[IO.Path]::GetFullPath('C:.')` from each cwd to measure the per-drive value. It is not inferred by asking official `cygpath -aw C:`, whose source-syntax interpretation does not measure native per-drive state. Mount entries preserve observed order, exclude virtual `/dev`/`/proc` and automatic drive mounts, and use the CLI's explicit sensitive matching policy. The default prefixes are `/cygdrive` for Cygwin and `/` for MSYS2.

## 5. Reviewed differences

The table lists all 23 approved profile/case pairs in twelve rows: the first eleven rows apply separately to both profiles, and the last applies only to MSYS2. The policy contracts are in [path semantics](03-path-semantics.md) and [API/CLI behavior](04-api-and-cli.md). The approval file retains each profile's exact hashes; the examples below explain the differences and are not comparison normalization rules.

In examples, `P` denotes the profile's C-drive POSIX path, `/cygdrive/c` or `/c`; `W` denotes its measured cwd rendered in POSIX syntax. `\n` denotes an LF byte. Every stated exit is the actual integer exit status.

| Case | Profiles | Policy ID | Observed difference and retained project contract |
| --- | --- | --- | --- |
| `empty-windows-list` | Both | `portable-empty-list-policy` | Official `-up ""` reports an empty-path error and exits 1. The project discards all empty list members, writes `"\n"`, and exits 0. |
| `drive-relative-cwd` | Both | `portable-drive-relative-policy` | Official `-au C:child` writes `P/child`; the project writes `W/child` using explicit per-drive cwd. Both exit 0. |
| `bare-drive-cwd` | Both | `portable-drive-relative-policy` | Official `-au C:` writes `P`; the project writes `W`. Both exit 0. The portable contract does not interpret a bare drive as its root. |
| `unc-root-traversal` | Both | `portable-unc-normalization-policy` | Official output retains `//server/share/../file`; the project clamps lexical traversal at the share root and writes `//server/share/file`. Both exit 0. |
| `stdin-empty` | Both | `portable-empty-input-policy` | Official empty stdin succeeds silently. The project reports missing input and exits 1 unless `-i` permits no input. |
| `stdin-empty-line` | Both | `portable-empty-record-policy` | Both reject the empty path with no stdout. Official stderr uses its empty-path message and exit 1; the project's stable diagnostic uses exit 2. |
| `stdin-initial-bom` | Both | `portable-initial-bom-policy` | Official output is `"\uFEFFC:/file\n"`. The project removes only the initial UTF-8 BOM and writes `P/file` followed by LF. Both exit 0. |
| `stdin-invalid-utf8` | Both | `portable-strict-utf8-policy` | For a valid first record, byte `FF` on line 2, and a later valid record, official stdout repeats `P/one` before `P/later` and exits 0. The project retains only the first output, diagnoses invalid UTF-8 at line 2, and exits 1. |
| `stdin-partial-conversion` | Both | `portable-empty-record-policy` | Both preserve the first successful record and stop at the following empty record. The empty-path stderr bytes and exit codes differ: official 1, project 2. |
| `argv-partial-conversion` | Both | `portable-failure-reporting-policy` | Both preserve the first successful NAME result and stop at the empty NAME. The project uses its stable empty-path diagnostic and exit 2; official uses its own message and exit 1. |
| `line-protocol-rejection` | Both | `portable-line-protocol-policy` | Official converts an operand containing LF and writes `P/a\nb\n`, exit 0. The project rejects embedded CR/LF before output, reports `invalid-record`, and exits 2. |
| `root-windows` | MSYS2 only | `portable-trailing-separator-policy` | Official `/` conversion appends a backslash after `C:\cygpath-msys2\msys64`; the project renders that mapped directory without an optional trailing separator. Both exit 0. The equivalent Cygwin case matches exactly. |

The shared empty-path diagnostic difference is official `"cygpath: can't convert empty path\n"` versus project `"cygpath: empty-path: path is empty\n"`. The malformed-UTF-8 project diagnostic is `"cygpath: invalid-encoding: invalid UTF-8 in \"stdin\" at line 2\n"`. Raw files remain the authority for all bytes, including the BOM and embedded newline examples.

## 6. Evidence layout and integrity

The Check run uploads `cli-evidence-ubuntu-latest`, `cli-evidence-macos-latest`, and `cli-evidence-windows-latest`. The Windows oracle run uploads `oracle-cygwin` and `oracle-msys2`. The reviewed local download is `_build/remote-7dfe6ba/`, with those artifact names as subdirectories. `_build/` is ignored and not a durable source-controlled evidence store; the workflow links identify the corresponding uploaded artifacts, subject to GitHub retention. Preserve those archives before expiration when a longer-lived audit record is needed.

Each portable artifact contains `manifest.json`, `summary.json`, raw metadata probe files, and per-case input, expected output, actual stdout/stderr, and `result.json` files. Each official artifact contains:

```text
oracle-<profile>/
  manifest-wasm.json
  manifest-native.json
  environment.json
  installer-evidence.json
  reviewed-differences.json
  observations/<probe>.json
  observations/<probe>.stdout.bin
  observations/<probe>.stderr.bin
  <profile|matrix>-<wasm|native>-<collect|replay>/
    manifest.json
    fixtures.json
    run.json
    <case>/stdin.bin
    <case>/oracle/stdout.bin
    <case>/oracle/stderr.bin
    <case>/project/stdout.bin
    <case>/project/stderr.bin
  summary.json
```

Replay additionally retains its source-run snapshot. Every run records planned/executed counts, raw case statuses, unexecuted IDs, and final integrity status. Observations retain actual executable/argv, cwd, environment, timestamps, monotonic elapsed time, deadlines, and integer exit codes. Input and stream blobs carry run-relative paths, byte lengths, and SHA-256 digests. The wrapper independently rechecks the stored blobs and rejects incomplete or inconsistent runs. Collector output directories must be new; collection and replay preserve previous evidence.

The fixture digests are retained in each `run.json` and approval entry. Both uploaded `reviewed-differences.json` copies match the repository baseline, SHA-256 `1f6fd2968969ac77ebf609a6e5b8aeed532a7d75af4b02e2af1189d402b553b1`.

## 7. Remaining verification boundaries

The full P3 gate in [chapter 05](05-validation-and-roadmap.md) requires complete evidence for the promised supported matrix. The current fifty inputs per profile cover a substantial read-only subset, but do not exhaust path/option combinations, all mount/case configurations, file existence and permissions, symbolic-link behavior, or filesystem-dependent upstream branches. Further cases must preserve the same distinction between portable-contract acceptance and official equality.

The collectors' synthetic self-tests exercise malformed metadata, immutable output, digest tampering, status classification, and reviewed-signature rejection. These successful ordinary Windows runs do not independently exercise deliberate Windows timeout/termination, partial-process failure, and on-disk tampering drills against the actual collector lifecycle. Those target-environment fault drills remain open.

Extended/device namespaces, 8.3 short-name operations, system-directory queries, non-UTF-8 code pages, and per-line `-o` options retain their documented unsupported/deferred status. Merely observing the host policy for a capability does not verify or implement it. The root executable remains a pure MoonBit program with explicit Context; official binaries are used exclusively by independent validation tooling.

Publication is also separate and will be handled by the maintainer. Version `0.1.0` is development metadata, and these workflows neither publish nor retrieve a registry package. Account/coordinate verification, the chosen release version, publication, and invocation of the exact published `moonx ZSeanYves/cygpath@<version>` on the promised hosts remain pending under [chapter 08](08-development-and-release.md).
