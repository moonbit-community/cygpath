# Remote Validation

## Accepted code baseline

On **2026-09-28**, commit
[`b32dd7448658bc251b216ba93a5c120ef54fdbc9`](https://github.com/moonbit-community/cygpath/commit/b32dd7448658bc251b216ba93a5c120ef54fdbc9)
passed [Check run 36385821361](https://github.com/moonbit-community/cygpath/actions/runs/36385821361)
and [Windows oracle run 36385821354](https://github.com/moonbit-community/cygpath/actions/runs/36385821354).
All three contract jobs and all four official comparison jobs succeeded.
This completes P3 for the frozen explicit-context portable matrix.

[`p3-evidence.json`](../testdata/oracle/p3-evidence.json) is the retained summary.
It was generated only after checking every job conclusion, clean project SHA,
complete coverage audit, accepted raw-comparison summary, API probe, and the
downloaded archive SHA-256 against GitHub's artifact digest. The scope hash is:

```text
d73ef908d14e0de4630dfff5c4584cb876a53ae93e1a246a30452061ac832874
```

The report identifies the tested code commit rather than a later documentation
commit. Subsequent pushes run both workflows again; the final delivery should
also have green checks on its own HEAD.

## Counts and acceptance

The scope contains **152 capability rows and 473 unique suite/case references**:
461 supported cases, 10 malformed-UTF-8 cases, and two CP29001 cases. There are
10 profile cases, 40 shared matrix cases, 394 P3 cases, and 29 custom-context
cases. Each applicable case runs on Wasm and Native in collection and replay.

| Profile / context | Cases | Observations | Supported exact | Malformed UTF-8 boundary | CP29001 boundary |
| --- | ---: | ---: | ---: | ---: | ---: |
| Cygwin / default | 444 | 1,776 | 1,728 | 40 | 8 |
| Cygwin / custom | 473 | 1,892 | 1,844 | 40 | 8 |
| MSYS2 / default | 444 | 1,776 | 1,728 | 40 | 8 |
| MSYS2 / custom | 473 | 1,892 | 1,844 | 40 | 8 |
| **Total** | — | **7,336** | **7,144** | **160** | **32** |

There are **zero supported-domain mismatches**, required skips, infrastructure
errors, unexpected timeouts, or backend/replay inconsistencies. All coverage
audits and fault drills passed. Boundary observations retain actual upstream
bytes, including raw mismatches, and independently require the exact project
rejection contract. They are not included in the 7,144 compatibility matches.

The three-host contract workflow separately passed 99 unit/documentation tests
per backend, 57 actual CLI cases per backend, the external public API consumer,
warning-free target checks, release builds, formatting, generated interfaces,
collector self-tests, and package inspection. A tooling self-test alone is never
counted as Windows behavior evidence.

## Official artifacts and environment

| Reference | Measured identity | Executable SHA-256 | Runtime DLL SHA-256 |
| --- | --- | --- | --- |
| Cygwin | `cygwin 3.6.10-1`, x86_64 | `473cf4cab34c085d15563e290fc17d36fb69f742fd83c1f0fcf6e2f9666d2192` | `d66788fce4ef1ce787fc1a83f2dd1e063e58bbf0d48ad93164ee195a983c035e` |
| MSYS2 | `msys2-runtime 3.6.10-5`, `3.6.10-c770e1b9.x86_64` | `a70581980983340cd7d1358f50f8e9d8e98e015da78724d1b1e824d0cfcf6bce` | `957d880559f0bfe7406a4cb27724610e7ce2f367030e299373d7ef37fbbb51b3` |

The recorded host is Windows NT `10.0.26100.0`, x64, using `C.UTF-8`, redirected
binary streams, and explicit measured root/cwd/mount context. The toolchain is
`moon 0.1.20260920 (914d7da)` and `moonc v0.10.14+7d59c7ec9`. Each manifest also
records filesystem, ACL, long-path and short-name policy, launcher/artifact
hashes, runtime package metadata, and the actual environment.

Source analysis uses pinned Cygwin and MSYS2 revisions linked in chapters 01
and 07. Package identities and runtime versions were measured; exact equivalence
between installed binaries and the cited full source Git commits was not
independently attested. The raw manifests preserve that qualification.

Custom contexts include a changed drive prefix, parent/nested mounts, same-target
aliases, a deeper reverse alias, and an ASCII-insensitive mount. A live official
runtime process retains temporary mounts throughout collection and replay.
Declarations are transcribed from the actual mount table; queried path mappings
are stored separately. MSYS2's implicit `/usr/bin` mapping does not cause the
collector to invent an extra mount. An independent `printf.exe` byte probe
verifies extended-path and wildcard argv transport before comparisons begin.

## What was converged

The earlier 50-case baseline allowed 23 reviewed profile/case differences.
Those approvals are no longer read by the gate. The supported differences were
resolved in the product, including drive-relative resolution, slash/trailing
separator behavior, empty path-list entries, GNU option parsing and precedence,
file records, `-o`, ordinary extended paths, filename PUA mapping, output code
pages, long paths, and profile-specific mount selection.

The current corpus includes valid multi-component paths at 259/260/261 UTF-16
units, independent overlong-component failures, long POSIX output, list errors,
8192-byte input-buffer boundaries, and explicit code-page numeric syntax. This
distinguishes successful long-path conversion from merely testing a rejection.

MSYS2 uses different forward and reverse mount priorities from Cygwin. The
MoonBit implementation reproduces the measured profile behavior, including the
observable newlib sorting steps used by MSYS2's partial ancestry comparator.
Equal native aliases in explicit contexts retain deterministic supplied priority;
unavailable original host insertion order and user/system flags are not invented.
The default and custom snapshots are covered by strict official comparison.

The encoder enables 110 legacy table identities plus UTF-8/65001. Four ambiguous
archive mappings were resolved from direct Windows observations and retained in
the [mapping provenance](../third_party/microsoft/codepages.json). The archive
contains 111 legacy identities; CP29001 is retained as source data but disabled.
Sampled official vectors and complete generated-table provenance do not imply
exhaustive Windows parity for every Unicode scalar on every code page.

## Why two rejection boundaries remain

**Malformed UTF-8:** the cited upstream `wide_path` helper does not safely handle
failed multibyte decoding before subsequent buffer use. Those inputs do not
provide a stable official output contract. The original bytes and actual
observations remain available. Both project backends must reject them with
exact diagnostics/status and the specified already-written output prefix.

**CP29001:** each job independently calls Windows `IsValidCodePage`, `GetCPInfo`,
and `WideCharToMultiByte` through a diagnostic-only oracle probe. On this host,
`IsValidCodePage` is false, `GetCPInfo` fails, both conversion-size and conversion
calls return zero with error 87, and a 256-byte destination initialized to `0xCC`
remains unchanged for both inputs. CP1252 controls produce exact expected bytes.
`IsValidCodePage` itself recorded last-error zero; last-error interpretation is
specific to each API. The full report is retained in each artifact and in the
checked-in evidence summary.

The pinned cygpath source ignores conversion failure and reads an uninitialized
output allocation. Its observed LF-only result is not implemented as an
empty-string encoding. The project instead rejects CP29001 deterministically.
This establishes unavailability on the measured host, not on every historical
or future Windows installation. If the independent probe stops proving failure,
CI fails and requires re-evaluation of this boundary.

## Evidence locations

| Environment | Raw artifact | Archive SHA-256 |
| --- | --- | --- |
| Cygwin default | [10955090420](https://github.com/moonbit-community/cygpath/actions/runs/36385821354/artifacts/10955090420) | `86e12805e3a93e8d284cb47ea523b922402751a87414aff30f0a87c626b9c71b` |
| Cygwin custom | [10954676562](https://github.com/moonbit-community/cygpath/actions/runs/36385821354/artifacts/10954676562) | `a84d131988ecc98f9b7feb6aad7e913bb816b427aa7740b2cb4a650d773ab4ce` |
| MSYS2 default | [10955160105](https://github.com/moonbit-community/cygpath/actions/runs/36385821354/artifacts/10955160105) | `5283d3b205c522b94c4c0b54292d62fa75a3c391354738e9e4d7c7f9f1e5cdee` |
| MSYS2 custom | [10954223686](https://github.com/moonbit-community/cygpath/actions/runs/36385821354/artifacts/10954223686) | `3b3ccab8f3f6a0543617b7023c9e91bc7eed77611e4f434a2b5bf9964f9d31b0` |

Each archive includes `summary.json`, `coverage-audit.json`, manifests,
preparation/transport/mapping observations, collection/replay input and raw
stdout/stderr/status, `codepage-api-probe/`, and `fault-drills/`. Timeout testing
confirms cancellation/reaping and preserved partial bytes. Separate drills
exercise real spawn failure and reject altered stdout, fixtures, and manifests
before replay execution.

Local retained copies use `_build/oracle-b32dd74-<environment>.zip`; extracted
summary material uses `_build/evidence-b32dd74-<environment>/`. These generated
files are ignored by Git. Hosted artifact retention is finite; the checked-in
summary preserves identities and results, but is not a replacement for raw
archives when investigating a specific case.

## Release boundary

The code is a validated candidate for the documented portable subset. It does
not resolve filesystem entities, provide 8.3 names or system-directory lookup,
discover ANSI/OEM settings, or implement non-ASCII Windows mount folding.
Stateful encodings and GB18030 remain unimplemented algorithmic extensions.
See [scope](01-upstream-and-scope.md) for the complete exclusions.

Mooncakes publication remains with the maintainer. No publication, account
mutation, or exact-version registry `moonx` retrieval was performed. P4 closes
only after the maintainer's release and the published coordinate is retrieved
and executed under the [release protocol](08-development-and-release.md).
