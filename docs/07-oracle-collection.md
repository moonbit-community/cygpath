# Oracle Collection and Replay

The collector in [`scripts/oracle.mbtx`](../scripts/oracle.mbtx) prepares P3 validation. It does not establish Cygwin or MSYS2 compatibility until it runs against the corresponding pinned programs on a real Windows host. The mechanics self-test is separate from official differential testing. Current execution evidence belongs in [the implementation index](README.md).

## Supported collection scope

Version 1 launches the official executable and this project's Wasm or Native artifact directly, using argument arrays. It compares redirected stdout/stderr bytes and integer exit status without decoding, trimming, newline conversion, or diagnostic normalization. It supports immutable stdin bytes and read-only conversion cases whose directory preparation is `none-read-only`. It does not prepare files, mutate a mount table, create 8.3 names, or configure symlinks/junctions. Such cases need an explicit extension before collection.

The two [starter corpora](../testdata/oracle/README.md) contain ten inputs each, and the shared `fixtures.readonly-matrix.json` adds forty inputs for each profile. These fifty inputs per profile cover drive/UNC paths, explicit cwd, root/nested mounts, normalization boundaries, trailing separators, lists, type/code-page selection, and stdin/partial-failure policies. They have no expected output and are not a comprehensive acceptance suite. Extending them to the full supported path and option matrix remains part of P3. Neither another implementation nor a synthetic fixture is accepted as the official oracle.

The runtime's `@async.platform` must report `Windows` for both collection and replay. A manifest string alone cannot bypass this check. Executables, the upstream runtime library, and the project launcher/artifact are verified by SHA-256 before execution and again after the run. Artifact, cwd, and installation-root paths must be drive-absolute or complete UNC Windows paths; current-drive-relative `/tools/cygpath.exe`, `\tools\cygpath.exe`, and `C:cygpath.exe` are rejected. There is no PATH search for `cygpath` and no shell wrapper. Wasm is launched as the pinned `moonrun` executable with the artifact as its first argument. Native launches the artifact directly.

## Manifest schema version 1

Start with [`environment.example.json`](../testdata/oracle/environment.example.json). Fields are required unless their script type is optional. For an absent Context cwd, omit `posix_cwd` or `windows_cwd`; do not write JSON `null`. MoonBit's derived object encoding omits `None` fields and stores the unwrapped value for `Some`. The script's `Manifest`, `Upstream`, `Project`, `HostSnapshot`, `CoreContext`, and `Artifact` declarations are the executable schema. Unknown profiles, missing required fields, invalid hashes, placeholder metadata, unsupported launch modes, and unavailable required capabilities fail preflight.

| Group | Required meaning |
| --- | --- |
| `schema_version`, `profile` | `1`, and exactly `cygwin` or `msys2` |
| `upstream` | Absolute executable and runtime-library paths/hashes; actual source URL/revision; distribution/runtime versions; raw `--version` stdout/stderr SHA-256 and expected integer exit |
| `project` | Artifact and launcher paths/hashes; `wasm` or `native`; full Git SHA and dirty flag; module/toolchain version; `debug` or `release` |
| `host` | Actual Windows version/build, architecture/filesystem/install root, direct launch, current-drive/per-drive cwd and mount observation, locale/code pages, redirected I/O, directory existence/permissions, long-path/8.3/volume/symlink conditions |
| `cwd`, `environment`, `cleared_environment` | Absolute child cwd, complete explicit environment, and deliberately absent variables |
| `context`, `context_mapping_evidence` | Explicit library Context equivalent and an explanation linking it to actual host observations |
| `capabilities`, `deadline_ms` | Available case prerequisites and per-process deadline from 1 to 60000 milliseconds |

Environment inheritance is always disabled. Variables not in `environment` are absent; `cleared_environment` documents deliberate exclusions and cannot overlap set keys. Supply Windows runtime necessities such as `SystemRoot` explicitly. The recorded environment is passed directly to both programs. The collector does not invoke a Cygwin/MSYS shell, so shell argv rewriting is not introduced by this launch path. The launch method is `direct-process-argv`, and I/O mode is `redirected-binary`.

The collector verifies runtime platform, binary hashes, `--version` bytes, cwd existence, input hashes, process results, and evidence integrity. Descriptions such as the source revision, installed mount table, Windows build, 8.3 policy, and mapping explanation are **operator attestations**, not automatically measured facts. Populate them using retained observations from the isolated Windows environment. The collector does not independently prove that a source revision produced a binary, that mount text is current, or that the declared Cygwin current directory matches an installation. Missing or inaccurate attestations prevent a credible compatibility claim even if byte comparisons pass.

`context` contains `profile`, `drive_prefix`, ordered `{posix, windows, case_policy}` mounts, optional POSIX/Windows cwd, and per-drive cwd. Version 1 requires `case_policy: "sensitive"`, matching the current CLI. The collector generates the corresponding context options itself and rejects fixture attempts to override them. No environment probing populates the product Context. Keep the complete official mount observation and explain every mapping or intentionally excluded mount.

## Fixture schema version 1

Each suite has `schema_version: 1`, `validation_kind: "official-comparison"`, applicable `profiles`, source URL/revision, and a nonempty `cases` array. Each case requires:

- A unique lowercase `case_id` using letters, digits, and hyphens, plus semantic `category` and `source_type` (`windows` or `posix`).
- Separate `upstream_argv` and `project_argv` arrays. The collector prepends source/context options only to the project command. Values are already tokenized; shell quotes must not be embedded.
- `stdin_hex`, whose bytes are saved as a separate immutable `stdin.bin` in the run directory.
- `required`, `required_capabilities`, `allowed_backends`, and `directory_preparation: "none-read-only"`.
- An optional `known_difference_id` string, omitted when no identifier applies; a known mismatch retains status `fail`. Explicit JSON `null` is not accepted for this field.

Missing capabilities for a required case stop preflight. Optional unavailable cases receive `skip`. The recognized capabilities are `portable-paths`, `utf8`, `stdin`, `root-mount`, `usr-bin-mount`, `posix-cwd`, `windows-cwd`, and `drive-cwd-c`. Context-dependent capabilities also check that the corresponding explicit mount/cwd field exists. The forty-case shared matrix requires all eight, including a real observed `/usr/bin` alias transcribed into Context; the template alone does not establish those conditions.

The sole argv template token is `{installation_root}`, expanded from the manifest and recorded in full in the process observation. Unknown brace tokens fail preflight. It allows one shared input matrix to refer to each installation's actual root without a hardcoded Cygwin/MSYS2 path. Stdin hex is literal bytes and has no substitution. Input JSON is copied byte-for-byte to the run directory and hashed before any case executes. Replay reads that saved copy; it never edits the source suite or refreshes expected bytes.

## Commands and evidence

Run the mechanics self-test on any supported script host:

```text
moon run scripts/oracle.mbtx self-test
```

On Windows, after replacing and verifying every template field:

```text
moon run scripts/oracle.mbtx collect C:/evidence/cygwin-manifest.json testdata/oracle/fixtures.cygwin.json C:/evidence/cygwin-run-001
moon run scripts/oracle.mbtx collect C:/evidence/msys2-manifest.json testdata/oracle/fixtures.msys2.json C:/evidence/msys2-run-001
moon run scripts/oracle.mbtx collect C:/evidence/cygwin-manifest.json testdata/oracle/fixtures.readonly-matrix.json C:/evidence/cygwin-matrix-001
moon run scripts/oracle.mbtx collect C:/evidence/msys2-manifest.json testdata/oracle/fixtures.readonly-matrix.json C:/evidence/msys2-matrix-001
moon run scripts/oracle.mbtx replay C:/evidence/cygwin-new-project.json C:/evidence/cygwin-run-001 C:/evidence/cygwin-replay-001
```

These are command shapes with environment-specific paths, not evidence that those files or Windows installations exist. Use a new output directory every time; an existing directory is refused. No command publishes a package or changes an upstream installation.

The output includes `manifest.json`, `fixtures.json`, `run.json`, raw version output, and separate `<case>/oracle/` and `<case>/project/` stream files. Each stream reference contains a run-relative path, byte length, and SHA-256. Each observation records executable/argv, cwd/environment, wall-clock start, monotonic elapsed time, deadline, integer exit status when observed, and termination information. Bytes go directly into files before they are hashed, preserving partial output on cancellation or spawn failure. Cancellation requests immediate termination through the official process API and waits for the child; process cleanup time can exceed the nominal deadline.

An observation's `execution_status` is `completed`, `error`, or `timeout`; a completed upstream capture by itself is **not a pass**. Case comparison separately produces `pass`, `fail`, `skip`, `error`, or `timeout`. Equality includes both streams and the raw integer exit status. Nonzero exits can match; timeouts never pass. The run summary records planned/executed counts, all status counts, and unexecuted case IDs. `complete` means every case has a recorded outcome, not that all passed. The script exits nonzero when any case is not a pass.

`run.json` is checkpointed after each case; immutable input/stream blobs are never overwritten. `integrity_verified` becomes true only after the final artifact verification succeeds; replay refuses a source run without it. If version validation fails, it retains the raw version observation with all cases unexecuted. If a later collector exception interrupts the run, the last checkpoint and already-written raw files remain available. Do not treat a partial directory as a successful run.

Replay verifies the saved manifest/fixture/blob hashes before starting a new output directory. It requires the same upstream identity, Windows/environment snapshot, cwd, and explicit Context; update only the project build identity for an ordinary regression replay. A changed upstream or environment requires a new collection. Replay copies verified official bytes into its own `oracle` subtree and executes only the new project artifact. It never reruns, mutates, or replaces the original oracle. Version 1 requires the pinned official artifacts still be available locally for preflight integrity checks.

## Acceptance limits and further work

The mechanics self-test checks hash correctness, invalid-profile/artifact/schema/capability/token rejection, Windows full-path requirements, safe evidence paths, binary fidelity, digest tampering, immutable file creation, and comparison handling for nonzero exits, missing observations, failures, and timeouts. It parses all three checked-in fixture files through the typed schema and validates all one hundred case/profile combinations using an explicitly synthetic manifest. Its observations are synthetic and clearly labeled. It does not test real process cancellation, Windows launcher argv fidelity, official conversion, or the metadata attestations.

Before P3 completion, run both profiles on isolated Windows installations, retain the supporting environment observations, expand the case matrix to all promised capabilities, and require zero unexplained differences and zero required skip/error/timeout outcomes. Independently exercise real timeout/termination and tampering scenarios in the target collector environment. The collector's existence and a local mechanics self-test do not satisfy those gates.
