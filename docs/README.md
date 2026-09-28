# cygpath Architecture Handbook

This handbook describes the implemented contracts, package boundaries, upstream
references, validation evidence, and remaining delivery work. Its baseline is
2026-09-28. The reusable library and root executable are implemented; P3 is
complete for the explicit-context portable matrix frozen in
[`p3-scope.json`](../testdata/oracle/p3-scope.json).

## Verified status

Code revision **`b32dd7448658bc251b216ba93a5c120ef54fdbc9`** passed
[Check](https://github.com/moonbit-community/cygpath/actions/runs/36385821361)
on Linux, macOS, and Windows, and
[Windows oracle](https://github.com/moonbit-community/cygpath/actions/runs/36385821354)
for Cygwin/MSYS2 with both default and custom mount contexts.

| Evidence | Result |
| --- | --- |
| Unit and documentation tests | 99 passed per backend, Wasm and Native, on each of three hosts |
| Actual CLI contracts | 57 cases per backend on each host; byte/exit equality across backends |
| External public API consumer | Passed Wasm and Native on all three hosts |
| Official supported-domain comparisons | 7,144 exact; zero mismatches |
| Rejection-boundary observations | 160 malformed UTF-8 and 32 unavailable CP29001; counted separately |
| Scope coverage | 152 capability rows; 473 unique fixture references; every required observation accounted for |
| Windows failure-path evidence | Real timeout/cancellation/reaping, spawn failure, and three evidence-tampering drills passed in all four environments |
| Publication | Maintainer-owned; exact published-version `moonx` retrieval remains pending |

The [remote report](09-remote-validation.md) and checked-in
[`p3-evidence.json`](../testdata/oracle/p3-evidence.json) retain the exact run,
artifact, upstream, environment, and digest identities. Raw observations are
retained in the linked CI artifacts. Boundary tests do not count as official
equality. Old reviewed-difference records are historical data and are not
consulted by the current gate.

P3 completion is a claim about this frozen supported matrix and the recorded
hosts, profiles, and backends. It does not mean full official compatibility,
every possible input combination, or every theoretically feasible pure MoonBit
extension. The support and exclusion tables remain part of the contract.

## Reading order

| Document | Responsibility |
| --- | --- |
| [01 Upstream References and Scope](01-upstream-and-scope.md) | Behavior sources, complete option inventory, supported and excluded capabilities |
| [02 Architecture](02-architecture.md) | Package ownership, dependency direction, pure conversion and I/O boundaries |
| [03 Path Semantics](03-path-semantics.md) | Roots, normalization, mounts, profile ordering, lists, Unicode and length rules |
| [04 Library API, CLI, and moonx Delivery](04-api-and-cli.md) | Public API, option parsing, file records, diagnostics and root command entry |
| [05 Validation and Implementation Roadmap](05-validation-and-roadmap.md) | P0–P4 acceptance criteria and evidence responsibilities |
| [06 Architecture Decision Records](06-decisions.md) | Durable decisions, their costs, and conditions for revision |
| [07 Oracle Collection](07-oracle-collection.md) | Measured contexts, immutable inputs, exact comparisons, replay and failure drills |
| [08 Development and Release](08-development-and-release.md) | Local commands, dependencies, packaging, release and registry checks |
| [09 Remote Validation](09-remote-validation.md) | Current verified revision, counts, upstream artifacts and evidence limits |

User constraints take precedence. Chapter 03 governs path semantics and chapter
04 governs interface behavior; chapter 01 defines scope and chapter 05 assigns
acceptance duties. A semantic change must update the corresponding code,
contract, fixtures, and evidence together.

## Established constraints

1. Implement product logic in MoonBit. Root `main.mbt` is the direct executable
   entry, with `moonx ZSeanYves/cygpath -h` or `-u` as the intended published
   command. The public library remains in `lib/`.
2. Share conversion and encoding between Wasm and Native. Do not introduce a
   system-cygpath proxy, project C/C++ FFI, or backend-specific path rules.
3. Select Cygwin/MSYS2 explicitly and preserve their observed differences,
   including mount ordering. Do not guess host profiles, roots, or cwd.
4. Keep immutable Context separate from mutable CLI record options and host
   I/O. `drive_cwds` is validated metadata; upstream-compatible drive-relative
   resolution uses the drive root.
5. Require exact supported-domain bytes and status. Explicit undefined-input
   and unavailable-code-page boundaries have independently checked project
   rejection contracts and remain outside supported parity.

Ordinary argument, file, and stream facilities supplied by MoonBit dependencies
are allowed. The product does not replace the runtime's general I/O internals.
Oracle tooling may invoke official programs and read Windows API facts solely
to establish evidence; product packages never invoke that tooling.

## Implementation entry points

[`lib/pkg.generated.mbti`](../lib/pkg.generated.mbti) records the public API.
[`lib/README.mbt.md`](../lib/README.mbt.md) provides checked consumer examples.
[`main.mbt`](../main.mbt) composes the CLI, encoding, and host packages.
[`p3-scope.json`](../testdata/oracle/p3-scope.json) maps capabilities to required
fixtures. The workflows retain process and official-oracle evidence separately.

The original P0 template cleanup and design-only state are historical. Empty
package checks from that stage are not implementation evidence. Module version
`0.1.0` is candidate metadata; the maintainer still owns publication and the
subsequent registry retrieval check.
