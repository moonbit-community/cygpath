# Oracle Collection and Replay

The frozen P3 scope passed at commit `b32dd7448658bc251b216ba93a5c120ef54fdbc9` in [Windows oracle run 36385821354](https://github.com/moonbit-community/cygpath/actions/runs/36385821354). Its four jobs cover Cygwin/MSYS2 and default/custom contexts, with both project backends and collection/replay. There are 7,336 observations: 7,144 supported-domain exact comparisons, 160 malformed-UTF-8 boundary observations, and 32 CP29001 capability-boundary observations. No supported difference is approved or ignored. [Remote Validation](09-remote-validation.md) records the evidence and limits.

## Scope and process boundary

[`p3-scope.json`](../testdata/oracle/p3-scope.json) independently maps 152 capability rows to 473 distinct suite/case references: 461 supported cases, ten malformed-input cases, and two CP29001 cases. Each profile executes 444 cases in the default context and 473 in the custom context. Each case has four observations: collect/replay × Wasm/Native. Repeated observations are not additional independent inputs.

The corpus comprises ten profile-specific inputs, forty shared matrix inputs, 394 P3 inputs, and 29 custom-context inputs. It covers the promised path/option/list/input/encoding behavior, measured mount and cwd contexts, ordinary extended namespaces, root-local output, per-record options, GNU parsing, and documented failure behavior. Custom jobs additionally configure a drive prefix, nested mappings, same-target aliases, and ASCII-insensitive mounts. The frozen scope is complete; this does not claim all possible Windows or official-tool behavior.

The low-level [collector](../scripts/oracle.mbtx) launches executable paths with argument arrays. It compares redirected stdout/stderr bytes and integer exits without decoding, trimming, newline conversion, or diagnostic normalization. `@async.platform` must report Windows for both collection and replay. Executable/runtime/launcher/artifact hashes are checked before and after execution. Paths must be drive-absolute or complete UNC paths. Wasm launches the recorded `moonrun` with the artifact followed by `--`; Native launches the artifact directly. No PATH lookup or shell wrapper selects the official program.

These are test-only processes. The product never invokes official cygpath, discovers the runtime installation, or uses custom FFI.

## Manifest schema version 1

Start with [environment.example.json](../testdata/oracle/environment.example.json). The script's typed records are the executable schema. Replace every placeholder; a template is not measured evidence. Omit absent optional fields instead of writing JSON `null`.

| Group | Required meaning |
| --- | --- |
| `schema_version`, `profile` | `1`, and `cygwin` or `msys2` |
| `upstream` | Absolute executable/runtime paths and SHA-256; distribution/runtime identity; source provenance; raw version-stream hashes and integer exit |
| `project` | Artifact/launcher paths and SHA-256; backend; full Git SHA and dirty state; module/toolchain version and build mode |
| `host` | Windows version, architecture, filesystem/install root, drive/cwd/mount observations, locale/code pages, permissions, long-path/8.3/volume/reparse conditions |
| `cwd`, `environment`, `cleared_environment` | Absolute child cwd, complete explicit environment, and deliberately absent variables |
| `context`, `context_mapping_evidence` | Explicit conversion context and its link to actual host measurements |
| `capabilities`, `deadline_ms` | Explicit case prerequisites and a 1–60000 ms per-process deadline |

Environment inheritance is disabled. The CI wrapper supplies Windows necessities and a limited environment, sets `CYGWIN=noglob` and `MSYS=noglob`, fixes `LANG=LC_ALL=C.UTF-8`, and records MSYS argument/environment conversion exclusions. Direct same-installation `printf.exe` probes prove the selected argv payloads arrive unchanged. Extended-namespace stdin cases separately isolate conversion from argv transport.

Context contains profile, drive prefix, ordered mount declarations, optional POSIX/Windows cwd, and per-drive cwd. Mount policies are `sensitive` or `ascii-insensitive`; the collector generates `--mount-case` explicitly. Raw mount declarations alone populate context. Independent queries for `/` and `/usr/bin` are retained without inventing additional mounts. MSYS2 may select a different matching mount from Cygwin; custom mapping observations preserve both declared targets and measured results.

The low-level collector verifies platform, artifacts, version bytes, cwd, immutable inputs, and evidence integrity. A manual manifest still relies on its author for descriptive host facts. The wrapper measures those facts. Neither route independently attests that an installed binary was built from a particular source commit.

## Fixture schema version 1

A suite declares `validation_kind: "official-comparison"`, applicable profiles, source provenance, and nonempty cases. Each case has:

- A unique lowercase case ID, category, and descriptive source syntax.
- Separate upstream/project argv arrays. The project receives explicit context options; source syntax is naturally detected by its CLI. The collector does not inject `--from`.
- Literal `stdin_hex`, plus optional `file_hex` for an immutable input file.
- Required capabilities, allowed backends, a required/optional flag, and directory-preparation metadata.
- Optional boundary-contract fields or a historical `known_difference_id` annotation. An annotation never permits a mismatch.

Recognized capabilities are `portable-paths`, `utf8`, `stdin`, `root-mount`, `usr-bin-mapping`, `posix-cwd`, `windows-cwd`, and `drive-cwd-c`. The `usr-bin-mapping` capability means the path mapping was measured and an applicable context mount exists; it does not require a distinct `/usr/bin` mount. MSYS2's ordinary root/bin declarations satisfy the matrix without an invented alias.

Required unavailable capabilities stop preflight. Although the low-level format permits optional skips, every case in the frozen scope is required and CI rejects skips or missing observations.

Supported argv tokens are `{installation_root}`, `{input_file}`, `{missing_file}`, `{drive_prefix}`, `{cwd_windows}`, `{custom_base}`, `{custom_nested}`, `{custom_shared}`, `{custom_fold}`, and `{custom_fold_case}`. Unknown tokens fail preflight. Stdin bytes have no substitution. Full expanded argv is recorded.

Input files are created once below the fixed cwd or verified byte-identical if already present. They are checked before and after use; replay verifies the same bytes. The wrapper records directory/mount/file preparation separately. No fixture creates 8.3 names or symlinks/junctions. Shared source JSON is copied byte-for-byte and hashed, never populated with guessed official output.

## Commands and retained evidence

Mechanics self-tests run on supported script hosts:

```text
moon run --deny-warn scripts/oracle.mbtx self-test
moon run --deny-warn scripts/ci_oracle.mbtx self-test
```

On Windows, using prepared installations and measured manifests:

```text
moon run scripts/oracle.mbtx collect C:/evidence/manifest.json testdata/oracle/fixtures.p3.json C:/evidence/collect-001
moon run scripts/oracle.mbtx replay C:/evidence/new-project-manifest.json C:/evidence/collect-001 C:/evidence/replay-001
moon run scripts/oracle.mbtx fault-drill C:/evidence/manifest.json C:/evidence/collect-001 C:/evidence/fault-001 C:/tools/pwsh.exe
```

Use a new output directory every time. These command shapes neither publish a package nor prove that the placeholder installations exist.

Each run retains `manifest.json`, `fixtures.json`, `run.json`, version observations, and `<case>/oracle/` and `<case>/project/` byte files. Stream references include relative path, byte length, and SHA-256. Process observations record exact program/argv, cwd/environment, wall-clock start, monotonic elapsed time, deadline, integer exit, and execution status. Bytes reach files before hashing, preserving partial output.

Case status is `pass`, `fail`, `skip`, `error`, or `timeout`. Nonzero exits can match. A timeout or an upstream-only capture cannot pass. `complete` means all planned cases have recorded outcomes, not that they passed. The collector exits nonzero for any raw nonpass, including the separately classified domain boundaries.

Only `run.json` is checkpointed; inputs and stream blobs are immutable. Unexecuted IDs remain visible after interruption. `integrity_verified` becomes true only after final artifact verification, and replay requires it. Replay checks saved input/blob hashes and identical upstream/environment/context before starting. It copies verified official bytes and executes the new project artifact; it does not rerun or overwrite the oracle. Changed upstream or environment requires fresh collection.

## CI orchestration and acceptance

The [Windows workflow](../.github/workflows/oracle.yml) runs four isolated profile/context jobs through [ci_oracle.mbtx](../scripts/ci_oracle.mbtx). Setup actions are pinned to commits. MSYS2's action pins its installer release/digest; Cygwin selects packages from its configured mirror. The actual installed package identities and executable/runtime hashes are frozen in each manifest. Setup pins do not attest source-to-binary correspondence.

The wrapper retains package, version, uname, mount, locale, root/path/cwd, argv-transport, and Windows metadata observations. Native per-drive C cwd is measured with `.NET Path.GetFullPath("C:.")`. Custom jobs create and record test directories and mount commands, verify the actual table and case flags, and keep an official runtime process alive while temporary mounts are used. The product receives an immutable snapshot; it does not share the test host's mutable mount state.

An equivalent manual wrapper invocation is:

```text
moon run --deny-warn scripts/ci_oracle.mbtx -- --profile msys2 --context-variant custom --root C:/cygpath-msys2/msys64 --wasm C:/repo/_build/wasm/release/build/cygpath.wasm --native C:/repo/_build/native/release/build/cygpath.exe --moon C:/tools/moon.exe --moonrun C:/tools/moonrun.exe --out C:/evidence/msys2-custom-new
```

Default jobs run profile/matrix/P3 suites; custom jobs also run the custom suite. Each suite executes collect/replay with both backends. The wrapper independently verifies exact manifest and fixture identities, complete cases, stream lengths/hashes, collector exit, raw equality, and backend/replay consistency. A scope audit requires exactly four unique observations for each applicable case, rejects duplicate/missing/unmapped references, and records out-of-variant rows explicitly.

Supported-domain results pass only through exact stdout/stderr/exit equality. Two separate boundary domains require exact deterministic project rejection:

| Domain | Required evidence and interpretation |
| --- | --- |
| Malformed UTF-8 | Retain actual upstream bytes, including instability; verify the project's fixed diagnostic/exit and any earlier successful output across both backends and replay. Pinned upstream source exposes an unchecked failed conversion, so these inputs do not establish defined upstream-output parity. |
| CP29001 | Each Windows job must first pass the direct Win32 probe, including a correct CP1252 control and CP29001 conversion failure with an untouched initialized buffer. The project must emit exactly the unsupported-capability diagnostic, empty stdout, and exit 1. The observed platform is unavailable for this encoding; this is not a universal claim about every Windows installation. |

The Win32 probe's PowerShell/PInvoke code exists only in validation tooling. It is not a product dependency. Probe failure prevents boundary acceptance. Boundaries are counted separately from `supported_exact_comparisons`; raw failures remain in low-level evidence. A process error or timeout cannot be reclassified as a boundary.

The historical [reviewed-differences.json](../testdata/oracle/reviewed-differences.json) is retained for the earlier baseline. Current scripts do not read it. There is no reviewed-output acceptance category or supported-domain exemption.

Real Windows fault drills now cover a child that emits partial output then exceeds its deadline, hard termination and confirmed process absence, a missing executable, and replay rejection after independently tampering stdout, fixture, and manifest bytes. Five recorded drills pass in each job. Normal comparisons, the scope audit, and fault drills must all pass; artifacts upload on failures too.

## Limits

The self-tests establish tool mechanics, not official behavior. The linked four-job run establishes the frozen P3 scope and its two explicit boundaries against measured distributions. Filesystem identity, 8.3 discovery, system-directory queries, automatic host-state discovery, unimplemented encoding families, and arbitrary future upstream versions are outside that claim. New scope requires fixtures and fresh evidence. Publication belongs to the repository owner; exact-version `moonx` retrieval is still unverified.
