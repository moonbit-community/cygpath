# Development and Release Acceptance

The executable is the root package; the reusable library is
`ZSeanYves/cygpath/lib`. This guide describes local execution and the remaining
release gates. [Remote Validation](09-remote-validation.md) records the green
three-host checks and bounded official Windows comparisons at commit
`7dfe6ba58520a6f5249c41bd9aad39cfeb215440`.

## Local execution

Run commands from the repository root. The standalone `--` belongs to `moon`,
and separates its options from the arguments passed to cygpath.

```sh
moon run --target wasm . -- -h
moon run --target wasm . -- -u 'C:\work\demo.txt'
moon run --target native . -- -m --root 'C:\cygwin64' /usr/bin
moon run --target wasm . -- -u -f paths.txt
moon run --target wasm . -- -u -f -
```

The last command reads stdin. Input is UTF-8 with LF or CRLF records and an
optional initial BOM. Output uses UTF-8 and LF. Context options never change
the process cwd, mounts, or environment. See [the CLI contract](04-api-and-cli.md)
for short-option combinations, context arguments, unsupported capabilities,
and exit codes.

## Dependencies and target boundary

| Dependency | Pinned version | License | Use |
| --- | --- | --- | --- |
| [moonbitlang/async](https://github.com/moonbitlang/async) | 0.22.4 | Apache-2.0 | Runtime entry, asynchronous file reads and raw standard streams; subprocesses only in validation tools |
| [moonbitlang/x](https://github.com/moonbitlang/x) | 0.5.5 | Apache-2.0 | `sys.exit` at the host boundary; pure SHA-256 for validation evidence |
| MoonBit core | Bundled with the recorded compiler | Apache-2.0 | Collections, encoding, arguments, and debugging |

The library and pure CLI packages import no host I/O facilities. The executable
and `internal/host` declare Wasm and Native support, matching the verified
runtime boundary. JavaScript and Wasm GC checks apply to the pure packages;
they do not imply that the executable supports those targets.

Project source contains no foreign declarations, C stubs, external conversion
commands, or backend-specific conversion branches. Official runtime packages
provide the ordinary operating-system primitives needed for I/O and process
exit. Their internal native implementation is outside the project business
logic, as established in [the architecture](02-architecture.md).

## Reproduce portable acceptance

Run build commands sequentially. The process collector takes existing
artifacts and never rebuilds them during a run:

```sh
moon check --target all --deny-warn
moon test --target wasm --deny-warn
moon test --target native --deny-warn
moon build --target wasm --release --deny-warn
moon build --target native --release --deny-warn
moon run scripts/check_cli.mbtx --wasm _build/wasm/release/build/cygpath.wasm --native _build/native/release/build/cygpath.exe --out _build/cli-evidence
moon info --target all
moon fmt
```

Use a new `--out` directory for each execution. The collector resolves artifact
paths before changing child working directories. It saves the frozen inputs,
artifact hashes, expected and actual byte files, integer exit statuses,
deadlines, and separate contract/backend comparison results. Failures do not
rewrite expected fixtures. Interrupted runs retain a checkpoint with
unexecuted cases. These are project-contract tests, not official Windows
comparisons.

The [CI workflow](../.github/workflows/check.yml) schedules equivalent checks
on Linux, macOS, and Windows and uploads process evidence even on failure.
Action references are pinned; the selected toolchain is recorded in each run.
[Check run 36371978473](https://github.com/moonbit-community/cygpath/actions/runs/36371978473)
passed on Linux, macOS, and Windows: 59 tests per backend and 57 CLI process
fixtures per backend, or 114 process executions per host. Wasm/Native byte and
status comparisons passed in each host's actual runtime environment.

The separate [Windows oracle workflow](../.github/workflows/oracle.yml) installs
official Cygwin/MSYS2 and runs the manifest-generating CI wrapper. At the same
commit, [run 36371978419](https://github.com/moonbit-community/cygpath/actions/runs/36371978419)
completed 400 comparisons: 308 exact matches and 92 preserved reviewed
differences. The latter correspond to 23 profile/case records bound to exact
fixture and upstream hashes plus output bytes/status. Its green gate establishes
the documented subset and backend consistency; it does not establish complete
Cygwin/MSYS2 equivalence. See [the collection guide](07-oracle-collection.md).

Native builds on the local macOS toolchain can print `libtool` warnings about
empty platform-specific object files supplied by `moonbitlang/async`. The
project's MoonBit sources must still pass `--deny-warn`; these external archive
tool messages are recorded separately from compiler or behavioral failures.

## Local packaging and installation

```sh
moon package --list
moon install ./ --bin _build/local-bin
```

Review the archive before publishing: it must contain root `main.mbt` and
`moon.pkg`, the library and internal packages, module metadata, license, and
documentation. Build outputs and local dependencies must be absent. Root
`README.md` is an ordinary Markdown file; executable packages should not carry
blackbox-only `.mbt.md` inputs. Executable documentation tests remain in `lib/`.

Local installation checks the root command coordinate and compiler packaging.
It does not test registry download, installed account ownership, or `moonx`
retrieval. Use an isolated installation directory to preserve existing tools.

## Remaining release gates

1. Preserve the green three-host contract matrix and rerun relevant checks for
   subsequent code or dependency changes.
2. Expand the verified 50-case-per-profile Windows subset to the remaining P3
   matrix using [the oracle collection guide](07-oracle-collection.md). Complete
   real Windows collector timeout/termination and evidence-tampering drills.
   Resolve unexplained differences and retain reviewed differences as raw
   failures, with exact approved scopes. Installed package identities and binary
   hashes are recorded; upstream source Git commits are not independently attested.
3. Choose a release version, synchronize module metadata and CLI version text,
   and record a reviewed commit and clean-workspace artifact hashes.
4. The repository owner will publish to Mooncakes. Before that step, verify the
   account and `ZSeanYves/cygpath` coordinates independently of the GitHub
   organization and review package contents. These CI workflows do not publish.
5. After publication, retrieve the exact version through
   `moonx ZSeanYves/cygpath@<published-version>` on promised hosts and exercise
   help, version, conversion, failure statuses, file input, and stdin.

Publication has not been performed by this work, and registry retrieval remains
unverified until the owner publishes an exact version. No automatic publication
workflow is installed. Pure MoonBit
extensions such as root-local output and per-line options require their own
contracts and differential evidence before becoming supported capabilities.
