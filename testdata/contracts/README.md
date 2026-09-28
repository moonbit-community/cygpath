# Portable CLI contracts

`cli.json` contains independently specified process expectations for chapter 04.
These are project contracts, not observations from official Cygwin or MSYS2.
`help.txt` freezes the exact help record, including its final LF. Every case has
a stable identifier, semantic category, argv array, expected raw UTF-8 stdout and
stderr, and an integer exit code. The suite records schema version and provenance.

The current suite has 57 cases per backend. At commit
`b32dd7448658bc251b216ba93a5c120ef54fdbc9`, the
[three-host Check run](https://github.com/moonbit-community/cygpath/actions/runs/36385821361)
passed on Linux, macOS, and Windows: each host passed 114 Wasm/Native process
observations and all 57 backend comparisons. Each backend also passed 99 MoonBit
tests on each host. The `mapped-root` fixture covers the structural POSIX root
slash correction: `-w --root C:\root /` produces `C:\root` followed by LF, with
no extra backslash. See [the remote validation report](../../docs/09-remote-validation.md)
for the frozen revision, artifact evidence, and distinct official-oracle results.

Run the collector after building both executable artifacts:

```text
moon run scripts/check_cli.mbtx --wasm <absolute-wasm-artifact> --native <absolute-native-artifact> --out <new-evidence-directory>
```

Optional collector flags are `--moonrun <program>`, `--fixtures <JSON>`, and
`--deadline-ms <positive-integer>` (default 10000). Existing output directories
are rejected. Arguments are passed as arrays without shell interpolation.

Optional `stdin_text` and `file_text` describe UTF-8 bytes; their corresponding
`stdin_hex` and `file_hex` fields represent arbitrary bytes. Specify at most one
representation for each input. Missing input content means zero bytes.
`stdout_text` and `stdout_file` are mutually exclusive. File oracle paths are
relative to the collector's launch directory. `{input}` and `{missing}` in argv
are expanded to an existing immutable fixture input and a nonexistent pathname
inside the new evidence directory. `{input_quoted}` and `{missing_quoted}` expand
to escaped, quoted names in expected diagnostics. Files and stdin are separate
input channels.

`stdout_closed: true` connects stdout to a pipe whose read end has already been
closed. The expected stdout is empty because the pipe cannot deliver bytes; the
case requires a write error before processing the next invalid operand.

Each backend runs in its own empty directory with different irrelevant `HOME`
and `MSYSTEM` values. Both consume the same explicit arguments and input bytes.
This simultaneously checks that conversions do not guess host context. File
names supplied to `-f` are absolute so this perturbation does not change I/O.

The output retains the fixture snapshot, artifact and fixture SHA-256 digests,
an environment manifest, raw `.bin` stdin/stdout/stderr, expected output bytes,
per-process execution metadata, and a summary. Equality compares bytes and
integer exit status, with no whitespace trimming or diagnostic normalization.
Contract results and backend consistency are separate observations. Timeout and
process-launch failures remain nonpassing outcomes; partial output is retained.
The collector exits nonzero if any required result fails, errors, or times out.

Provenance records the raw output and status of `moon version --all`, the exact
selected moonrun program's `--version`, and Git HEAD/status probes. An unborn
repository has a null commit SHA and an explicit `unborn` state, established by
its symbolic HEAD pointing to an absent branch reference. The status probe keeps
untracked files visible. Metadata collection failures stop before product cases
run, retaining an incomplete summary with all unexecuted case identifiers.

The script uses pinned official `moonbitlang/async` process/filesystem facilities
and `moonbitlang/x/crypto` for SHA-256. These are test-tool dependencies. It never
invokes official `cygpath`; a separate Windows collector owns compatibility
observations. Passing a host's suite establishes the tested portable behavior on
that host; results on another host cannot substitute for it.

The separate [Windows oracle run](https://github.com/moonbit-community/cygpath/actions/runs/36385821354)
verified the frozen P3 scope for Cygwin/MSYS2 in default/custom contexts:
7,144 supported exact comparisons, 160 malformed-UTF-8 boundary observations,
and 32 independently measured CP29001 capability boundaries. Raw boundary
results remain visible and do not count as supported parity. No historical
reviewed-difference file is read by the current gate. Coverage audits and real
Windows collector fault drills passed. This establishes the committed scope,
not every official capability or registry retrieval.

`consumer.mbt.txt` is compiled as a separate module by
`scripts/check_consumer.mbtx`. The three-host Check run passed this public API
consumer on both backends using the repository as a local workspace dependency.
Its source and raw compiler/test streams are retained separately from process
contracts. This proves public API visibility and ordinary consumer usage; it
does not prove that a published version can be fetched through Mooncakes or
`moonx`. Publication belongs to the repository owner.
