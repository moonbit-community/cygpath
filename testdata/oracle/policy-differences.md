# Historical differences and current boundaries

The current gate requires exact equality for every supported case.
[Windows run 36385821354](https://github.com/moonbit-community/cygpath/actions/runs/36385821354)
verified the frozen scope at
`b32dd7448658bc251b216ba93a5c120ef54fdbc9`, including default/custom contexts and
both backends with collection/replay. It does not read
[`reviewed-differences.json`](reviewed-differences.json).

That file preserves the historical `7dfe6ba` baseline's 23 profile/case
approvals, previously responsible for 92 repeated raw mismatches. Its hashes
and reasons remain a historical record; they do not authorize current or future
output differences. Fixture `known_difference_id` fields likewise remain
annotations only.

## Current boundary contracts

| Domain | Evidence and required project behavior |
| --- | --- |
| Malformed UTF-8: ten case references | Preserve actual upstream observations and prior output. The project must reject invalid decoding with its exact diagnostic and exit 1, consistently across backends/replay. |
| CP29001: two case references | First require independent Win32 evidence of failure and an untouched initialized destination, with a correct CP1252 control. Then require empty project stdout, the exact unsupported-capability diagnostic, and exit 1. |

The pinned Cygwin and MSYS2
[`wide_path.h`](https://github.com/cygwin/cygwin/blob/b11613e477c006b2ce0332463ed07f1118260e79/winsup/utils/wide_path.h)
helpers expose the unchecked malformed-input conversion; the corresponding
[MSYS2 helper](https://github.com/msys2/msys2-runtime/blob/c770e1b9fa537fff9287c1fd40ebc84ac498fcb6/winsup/utils/wide_path.h)
has the same bytes. Their SHA-256 is
`4b9e9c9de0b9525d4758312f94338125ee9ecd07ade479d9ceab29d0dc5dce99`.
Arbitrary output after that failure is not a defined byte-equivalence target.

For CP29001, the measured Windows API rejects the conversion; upstream
[`cygpath.cc`](https://github.com/cygwin/cygwin/blob/b11613e477c006b2ce0332463ed07f1118260e79/winsup/utils/cygpath.cc)
does not check the failed conversion before using its destination. The direct
probe is a necessary gate condition, not an assumption that every Windows host
universally lacks CP29001. Pinned source references explain the failure path;
installed-binary source provenance remains independently unattested.

The current run retains 160 malformed-input and 32 CP29001 observations
separately from 7,144 supported exact comparisons. Boundaries are neither raw
passes nor reviewed-output waivers. The raw collector can remain nonzero while
the wrapper verifies the explicit boundary contract. Missing observations,
process errors, timeouts, altered bytes, and project inconsistency still fail.

## Historical identifiers

The following identifiers may appear in old records. Their old descriptions
must not be read as the current implementation contract; [path semantics](../../docs/03-path-semantics.md)
and [CLI behavior](../../docs/04-api-and-cli.md) describe current behavior.

| Historical identifier | Current disposition |
| --- | --- |
| `portable-empty-list-policy` | Empty-list operand behavior converged with the measured official programs. |
| `portable-drive-relative-policy` | Drive-relative and bare-drive behavior converged; recorded per-drive cwd no longer implies the former resolution policy. |
| `portable-unc-normalization-policy` | Unmatched UNC source spelling follows measured official behavior. |
| `portable-trailing-separator-policy` | Profile-specific root rendering is implemented and compared exactly. |
| `portable-empty-input-policy` | Empty stream success matches official file-input behavior. |
| `portable-empty-record-policy` | Empty-record diagnostics, exit, and ignore handling are exact supported comparisons. |
| `portable-initial-bom-policy` | Initial BOM content is retained as measured. |
| `portable-strict-utf8-policy` | Replaced as an acceptance concept by the explicit malformed-input boundary above. |
| `portable-failure-reporting-policy` | Supported failure diagnostics, exits, and earlier output are exact comparisons. |
| `portable-line-protocol-policy` | Representable record/operand delimiter behavior follows the measured contract. |

Changes to scope, upstream distributions, or behavior require fresh evidence.
Do not add approvals or edit expected output to make supported mismatches green.
