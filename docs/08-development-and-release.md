# Development and Release Acceptance

The root executable is `ZSeanYves/cygpath`; the reusable package is
`ZSeanYves/cygpath/lib`. The verified baseline is
`b32dd7448658bc251b216ba93a5c120ef54fdbc9`.
[Remote Validation](09-remote-validation.md) records the three-host checks,
frozen P3 scope, and separate publication boundary.

## Local execution

Run from the repository root. The standalone `--` separates Moon options from
cygpath arguments; ordinary cygpath options still include `-h`, `-u`, and `-w`.

```sh
moon run --target wasm . -- -h
moon run --target wasm . -- -u 'C:\work\demo.txt'
moon run --target wasm . -- -m --root 'C:\cygwin64' /usr/bin
moon run --target wasm . -- -u -f paths.txt
moon run --target wasm . -- -u -f -
moon run --target wasm . -- -u -o -f paths-with-options.txt
moon run --target wasm . -- -w -C1252 --root 'C:\cygwin64' /usr/café
```

Input uses UTF-8. BOM bytes remain path content; CRLF, NUL visibility, final
records, empty streams, and per-record option state follow the tested contract.
Output uses the selected encoding with raw LF record endings. Context options
describe conversion state without changing actual cwd, mounts, or environment.
See [the CLI contract](04-api-and-cli.md) for supported selectors, option
precedence, per-record state, errors, and remaining unsupported capabilities.

## Dependencies and licensing

| Dependency or source | Version/provenance | Use |
| --- | --- | --- |
| Official MoonBit async | 0.22.10, Apache-2.0 | Standalone test tooling only |
| Official MoonBit x | 0.5.8, Apache-2.0 | Standalone tooling only: SHA-256 for fixtures and evidence |
| MoonBit core | Recorded compiler, Apache-2.0 | Collections/encoding, env and experimental `core/async` I/O for the product |
| Unicode/Microsoft encoding tables | Pinned source manifests in `third_party/` | Pure numeric-code-page data; preserve supplied licenses |
| newlib sorting adaptation | Pinned source and BSD-3-Clause notice in `third_party/newlib/` | Observable MSYS2 mount-order behavior |

The product contains no project-owned foreign imports, C stubs, or official-tool
fallback. The Win32 code-page probe uses PowerShell/PInvoke only for independent
test evidence and is not imported by the executable. Package and binary
distributions must preserve applicable third-party notices.

The library and pure CLI contain no host I/O. The executable/host adapter support
linear-memory Wasm only. All-target checks of pure packages do not imply executable
Native, JavaScript or Wasm GC support.

## Reproduce acceptance

Serialize Moon commands and use fresh evidence directories:

```sh
moon check --target all --deny-warn
moon test --target wasm --deny-warn
moon run --deny-warn scripts/oracle.mbtx self-test
moon run --deny-warn scripts/ci_oracle.mbtx self-test
moon test --deny-warn scripts/check_cli.mbtx
moon run --deny-warn scripts/check_consumer.mbtx _build/consumer-new
moon build --target wasm --release --deny-warn
moon run scripts/check_cli.mbtx --wasm _build/wasm/release/build/cygpath.wasm --out _build/cli-new
moon info --target all
moon fmt
```

Review interface diffs and formatting, including standalone scripts. The process
collector runs the existing Wasm artifact and records exact input/expected/actual
bytes and exits. Failures never refresh
expectations; interrupted runs retain unexecuted identifiers.

[Check run 36385821361](https://github.com/moonbit-community/cygpath/actions/runs/36385821361)
passed on Linux, macOS, and Windows: 99 MoonBit tests per backend, 57 CLI
fixtures per backend (114 process observations per host), and all 57 backend
comparisons per host. A separate public API consumer passed both backends
through a local workspace dependency. This checks consumer visibility without
claiming package-registry retrieval.

[Windows oracle run 36385821354](https://github.com/moonbit-community/cygpath/actions/runs/36385821354)
passed all four profile/context jobs. The frozen 152-row scope produced 7,336
observations: 7,144 supported exact comparisons, 160 malformed-input boundaries,
and 32 independently measured CP29001 capability boundaries. Coverage audits
and five real Windows fault drills per job passed. Historical reviewed output
records are not consulted by the current gate. Follow
[the collection guide](07-oracle-collection.md) to reproduce this environment;
local portable tests cannot substitute for it.

Official setup actions are commit-pinned, while installed package identities,
binary hashes, and toolchain versions are measured per run. Source-to-binary
Git provenance remains unattested. These runs establish the frozen supported
scope, not every official or Windows-specific capability.

## Package review and local execution

```sh
moon package --list
moon build --target wasm --release --deny-warn
moonrun _build/wasm/release/build/cygpath.wasm -- -u 'C:\work'
```

Review root `main.mbt`/`moon.pkg`, the library/internal packages, metadata,
documentation, and all licenses/notices. Build outputs and local dependencies
must be absent. Root README is ordinary Markdown; executable documentation
tests belong in the library.

Local package review and the workspace consumer validate package layout and API
visibility. They do not validate registry download, account ownership, or
exact-version `moonx` execution.

## Remaining release work

1. Preserve the green baseline and rerun affected portable/official evidence
   after implementation, dependency, fixture, or scope changes.
2. Select the release version, synchronize metadata and version output, and
   retain clean-commit artifact identities and applicable third-party notices.
3. The repository owner will publish separately. Confirm the account and
   `ZSeanYves/cygpath` coordinates independently of GitHub organization ownership.
   No automatic publishing workflow is installed.
4. After publication, retrieve
   `moonx ZSeanYves/cygpath@<published-version>` on promised hosts and test help,
   version, conversions, failures, file input, and stdin.

Publication and exact-version registry retrieval have not been performed by this
work. P3 is complete for its frozen scope. The file identity API has already
merged into `x/fs`. After the coordinated `x` release, adopt the published
version and run the NTFS identity cases described in
[issue #10](https://github.com/moonbit-community/cygpath/issues/10#issuecomment-7047844931).
