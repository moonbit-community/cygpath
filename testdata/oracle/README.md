# Official oracle inputs

This directory holds immutable input corpora, the environment template, the
independent P3 scope index, and historical evidence annotations. Official
expected bytes are captured from the selected real Cygwin/MSYS2 executable on
Windows; they are never guessed or regenerated from the project.

The current baseline is `b32dd7448658bc251b216ba93a5c120ef54fdbc9`.
[Windows run 36385821354](https://github.com/moonbit-community/cygpath/actions/runs/36385821354)
passed Cygwin/MSYS2 in default/custom contexts, using collect/replay and
Wasm/Native for every applicable case. See
[Remote Validation](../../docs/09-remote-validation.md) for the retained evidence.

| Input file | Cases | Use |
| --- | ---: | --- |
| `fixtures.cygwin.json` / `fixtures.msys2.json` | 10 each | Profile-specific starter inputs |
| `fixtures.readonly-matrix.json` | 40 | Shared path, context, list, and input behavior |
| `fixtures.p3.json` | 394 | Frozen path/option/encoding/input/error coverage |
| `fixtures.custom.json` | 29 | Actual custom drive-prefix, nested/alias/case mount contexts |

[`p3-scope.json`](p3-scope.json) maps 152 independently described capability
rows to 473 distinct suite/case references: 461 supported, ten malformed-UTF-8
boundaries, and two CP29001 boundaries. Default jobs execute 444 cases per
profile; custom jobs execute 473. Across four jobs and four observations per
case, 7,336 observations comprise 7,144 supported exact comparisons, 160 input
boundaries, and 32 capability boundaries. A scope audit rejects missing,
duplicate, or unmapped observations. Out-of-variant rows are recorded explicitly.

The frozen P3 scope and real Windows fault drills are complete. This is a
bounded claim about the committed matrix and measured environments, not full
official-tool compatibility or arbitrary Windows behavior.

## Authoring and collection

Read [Oracle Collection and Replay](../../docs/07-oracle-collection.md).
Each fixture is independently authored and cites design/source provenance.
Its source revision does not attest an installed executable's build commit.
Current manifests freeze measured Cygwin `3.6.10-1` / MSYS2 `3.6.10-5`
package identities and executable/runtime hashes, with source correspondence
explicitly qualified.

Fill every placeholder in a copy of `environment.example.json`. Change profile,
installation paths, upstream identity, prefix, mounts, and context together.
Native uses the artifact itself as its launcher. Record actual mount declarations
only: `usr-bin-mapping` describes an independently measured path, and does not
require or create a separate `/usr/bin` mount.

The project receives explicit context while retaining natural CLI source
detection. Source-type fixture metadata does not inject `--from`. Stdin uses
literal hex; optional file bytes are prepared once and verified unchanged.
The wrapper records directory preparation and actual custom mount commands.
Input/output paths and byte hashes remain in the evidence.

Use a new collection directory outside this directory for each run. Replay
uses the retained fixture/input/oracle bytes, and may update project artifact
identity only while preserving the upstream/environment/context snapshot.
Required cases never silently skip.

## Acceptance domains

Supported cases require exact raw stdout, stderr, and integer exit equality,
plus project/backend/replay consistency. No output allowlist is used.

Malformed UTF-8 is outside the defined upstream conversion domain. Its raw
official observations remain visible; the gate separately requires exact
deterministic project rejection and any prior successful output. CP29001 is an
observed unavailable capability: each job must first prove direct Win32
conversion failure with an untouched buffer and a passing control encoding,
then verify exact project rejection. Neither boundary contributes to supported
exact comparisons. Process failures/timeouts cannot satisfy either boundary.

[policy-differences.md](policy-differences.md) explains these boundaries and the
historical policy records. `reviewed-differences.json` is retained solely for
the earlier baseline; current scripts do not read it. A `known_difference_id`
annotation never grants an exemption.

Publication is reserved for the repository owner. Exact-version `moonx`
retrieval remains a separate, unverified release step.
