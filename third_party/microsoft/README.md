# Microsoft Windows code-page mapping data

## Windows mount uppercase table

`lib/mount_upper_ranges.mbt` derives from the 973 mappings in Microsoft's
[Windows 8 Upper Case Mapping Table](https://download.microsoft.com/download/c/f/7/cf713a5e-9fbc-4fd6-9246-275f65c0e498/Windows%208%20Upper%20Case%20Mapping%20Table.txt).
The generator checks the source SHA-256
`76a66e29298eafc744fa1e8e11c80c3de28219c70539b3fb10efbccadb6ae335`.
Unlisted UTF-16 units retain their values. The source comes from the
[Microsoft download collection](https://www.microsoft.com/en-us/download/details.aspx?id=10921).
See the [Open Specifications notice](LICENSE.txt).

```sh
moon run scripts/generate_mount_case.mbtx 'Windows 8 Upper Case Mapping Table.txt' lib/mount_upper_ranges.mbt
```

An independent comparison covered all 65,536 entries of the uppercase table
in `Files/Windows/System32/l_intl.nls` from Microsoft's Nano Server LTSC 2025
image (`10.0.26100.33828`, amd64). All entries matched. The layer SHA-256 was
`e40d20b402e4d48fbc6bffc91e47b0ab3947db95f949e6de8e05c7b8167a9f4a`
and the NLS file SHA-256 was `f8e9574c1c2ee28c669e903f5faf86ac24476f692076340b23881b4d0c82112b`.
The 65,536 uppercase words in little-endian order have SHA-256
`41c26bc7a12bdaeb26025c93118697c7e3ef81ee048b00fe5cce2a472e0e0742`.
The library test checks the full range after decompression. End-to-end Cygwin
and MSYS2 comparisons run as a separate check in the Windows custom-mount jobs.

## Code-page mappings

The additional OEM, ASCII, ISO-8859, KOI8, EBCDIC, Macintosh, and other legacy tables in `internal/encoding`
derive from Microsoft's **Windows Supported Code Page Data Files.zip**.
The generator emits 96 additional tables which, together with the original
15 Unicode-hosted tables, cover all 111 table identities in that archive.
CP29001 is retained as data but disabled at the encoder boundary, leaving
**110 supported legacy numeric code pages from this archive**. `codepages.json`
records all generated pages; its `excluded_pages` list is currently empty.

The encoder also reproduces 394 best fits present in 21 Windows Server 2022
NLS tables but absent from the archived encoder entries. Twenty ANSI and OEM
pages map previously unmapped punctuation to page-specific equivalents. For
example, U+202F maps to the nonbreaking space byte (`a0` on CP1252, `ff` on
CP437). CP932 maps the combining kana marks U+3099 and U+309A to the same two
byte sequences as their spacing forms. An explicit archived mapping takes
precedence. The original tables and their digests remain reproducible.

The regression test independently fingerprints the encoded bytes for every
valid BMP scalar in each of the 56 numbered NLS files supplied by the
[pinned Windows Server image](https://mcr.microsoft.com/v2/windows/nanoserver/manifests/sha256:076562f66717cad7b814e9665a95d1d773fcb073de511aa1929601dab50e8b58).
The reference bytes come from the final 65,536 entries in each file, using
one byte per entry for SBCS and one little-endian word for DBCS. An encoded
word above 255 emits its high byte first. Windows CLI cases cover the ANSI,
OEM and Japanese examples separately. See also [the additional UCM
pages](../unicode/README.md#east-asian-windows-code-pages).

In the same image, the SYSTEM hive at
`ControlSet001\Control\Nls\CodePage` assigns `38598` to `c_28598.nls`
and `51949` to `c_20949.nls`. The hive's SHA-256 is
`15cfd4a2d880eb6193301847862b6bf567e873b35de1ac3f34fed0a085b6a44b`.
Both numeric selectors reuse their registered tables. This matters for EUC
Korean because the historical IMultiLanguage mapping for 51949 differs from
the NLS encoding used by Win32. For example, U+0081 encodes as byte 81.
[Microsoft code page assignments](https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-ucoderef/28fefe92-d66c-4b03-90a9-97b473223d43).

A conflicting source mapping cannot be selected without direct Windows
evidence. The remote Windows capture resolved all four ambiguous
members: 10005 U+05B8 -> DE, 10008 U+2225 -> A1CE, 20269 #^`~¤ -> A6 C3 C1
C4 A8, and 20924 U+0178 -> E8. Neither source order nor an arbitrary overwrite
decides their behavior. The exact raw stream hashes, lengths, profile, and
case IDs are recorded in `codepages.json` under
`official_resolution_evidence`; the selected values are also recorded per
page under `resolved_conflicts`. The generator requires
`CPINFO` to declare one or two bytes, rejects wider mappings, and additionally
requires single-byte tables to contain only single-byte values. Four-byte
GB18030 uses the separate [.NET mapping](../dotnet/README.md). Stateful
encodings remain outside this catalog. Automatic ANSI/OEM page selection
is a separate missing host-discovery capability. Runtime availability of
legacy identifiers is checked separately
against the recorded Windows oracle; a mapping table's existence alone does
not prove that a modern Windows installation accepts its number.

CP29001 (Europa 3) is retained as mapping data but is rejected by both
`supported` and `encode`; CLI Windows/Mixed output reports
`UnsupportedCapability`. The observed Cygwin/MSYS2 CP29001 runs emitted only
LF, which is retained as raw evidence rather than defined as an empty-string
encoding rule. The pinned [Cygwin source](https://github.com/cygwin/cygwin/blob/b11613e477c006b2ce0332463ed07f1118260e79/winsup/utils/cygpath.cc#L715)
allocates an uninitialized byte buffer and ignores the result of
`my_wcstombs` before treating that buffer as a C string. The matching
[MSYS2 source](https://github.com/msys2/msys2-runtime/blob/c770e1b9fa537fff9287c1fd40ebc84ac498fcb6/winsup/utils/cygpath.cc#L775)
has the same source SHA-256:
`b88d2abc137835e384e40834825f561cd0d4cbc00605f342cd0c8b51cdcba46b`.
Microsoft documents a zero return from
[`WideCharToMultiByte`](https://learn.microsoft.com/en-us/windows/win32/api/stringapiset/nf-stringapiset-widechartomultibyte)
as failure. That failure branch therefore has no defined path-output contract.
The independent [`probe_windows_codepages.mbtx`](../../scripts/probe_windows_codepages.mbtx)
now records the Win32 calls directly. [Windows oracle run 36385821354](https://github.com/moonbit-community/cygpath/actions/runs/36385821354),
at project commit `b32dd7448658bc251b216ba93a5c120ef54fdbc9`, retains
`codepage-api-probe/result.json` for each profile/context job. On Windows
`10.0.26100.0`, X64, with kernel32 `10.0.26100.33296`, both test inputs showed:

| Operation | CP29001 observation |
| --- | --- |
| `IsValidCodePage` | false; recorded last-error 0 |
| `GetCPInfo` | false; recorded last-error 87 |
| `WideCharToMultiByte` sizing | return 0; recorded last-error 87 |
| `WideCharToMultiByte` conversion | return 0; recorded last-error 87 |
| Destination initialized with byte `CC` | All 256 bytes unchanged |

The CP1252 controls succeeded, with exact output bytes and return lengths
9 and 10 including the terminating NUL. The probe uses flags 0, input length
-1, and null default-character/used-default pointers, matching the relevant
upstream call settings. Error values are captured immediately; a successful
call is not assumed to set last-error. Its assertions passed in all four
profile/context jobs. This demonstrates the failed conversion and untouched
destination on the measured host. Combined with the unchecked upstream
allocation/return path, it establishes why an observed empty output must not
be implemented as a CP29001 encoding rule.

No claim is made that Europa 3 is invalid on every Windows installation. Its
entry in the [identifier catalog](https://learn.microsoft.com/en-us/windows/win32/intl/code-page-identifiers)
does not establish availability on a particular host. The source snapshots
explain the behavior, but their correspondence to the installed distribution
binaries is not independently attested. CP29001 raw observations are retained
as a capability boundary with a separately verified project rejection; they
are never counted as exact conversion matches. The probe's PowerShell/.NET
interop is independent test instrumentation and is not a product dependency
or conversion fallback.

The source chain is [MS-UCODEREF section 2.2.2](https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-ucoderef/d167d756-0c58-4564-a0de-77c647d367fa),
its `CODEPAGEFILES` reference, and the [official Microsoft Download Center](https://www.microsoft.com/en-us/download/details.aspx?id=10921).
The exact [archive URL](https://download.microsoft.com/download/c/f/7/cf713a5e-9fbc-4fd6-9246-275f65c0e498/Windows%20Supported%20Code%20Page%20Data%20Files.zip)
has SHA-256 `5074e6dd253056ba61fc6c870c9a955467855129c6ad3a51761c386b301b125a`
and length 4,020,112 bytes. The download page's publication date is 2024-12-19;
the archive members carry 2009 timestamps. These are frozen mapping data, not
a claim that every current Windows mapping has been exhaustively verified.

Microsoft's [Open Specifications copyright permission](https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-ucoderef/4a045e08-fc29-4f22-baf4-16f38c2825fb)
allows portions to be distributed in implementations and explicitly extends
to referenced documents. The retained [notice](LICENSE.txt) applies to this
data under the local identifier `LicenseRef-Microsoft-Open-Specifications`.
The archive contains no separate license file. These data are not relabeled
as Apache-2.0 or Unicode-3.0. Project-authored encoder and generator code remain
Apache-2.0; the original 15 [Unicode-hosted WindowsBestFit tables](../unicode/README.md)
retain their own notice and manifest.

`codepages.json` records each exact archive member, source hash and byte count,
mapping count, default character, maximum character width, and packed-table
hash. Only numeric `WCTABLE` entries enter the generated code; comments do not.
The encoder follows the published UTF-16-word mapping model: each unmatched
surrogate is replaced independently, while UTF-8 preserves supplementary
characters. No operating-system codec or locale lookup participates.

Regenerate with a local `unzip` executable and the downloaded archive:

```text
moon run scripts/generate_codepages.mbtx microsoft ARCHIVE_ZIP internal/encoding third_party/microsoft/codepages.json
moon run scripts/generate_codepages.mbtx UNICODE_SOURCE_DIRECTORY internal/encoding third_party/unicode/codepages.json
moon fmt
```

The generator verifies the pinned archive hash before extracting each member
directly, then emits a separate dispatch table. It performs no network access.
The conflict choices are checked against the exact source values and fail if a
future archive changes them, so regenerated data cannot silently reuse an old
tie-breaker.
Review both source and packed hashes when regenerating. Official Windows
`cygpath` byte probes, rather than data provenance alone, establish the tested
compatibility scope; see [remote validation](../../docs/09-remote-validation.md).

## Stateful code pages

The Windows 11 / Server 2025 family runner (build 26100) supplied the reference
bytes for pages 50220–50222, 50225, 50227, 50229 and 52936. The
`codepage-api-probe/bmp-CP.bin` artifacts contain one length-prefixed result
per BMP scalar. Each length counts the NUL passed through
`WideCharToMultiByte`. The Wasm tests verify the fingerprint of all 63,488
records per page and exercise adjacent character-set transitions.
[Windows runner artifacts](https://github.com/moonbit-community/cygpath/actions/runs/44847413626) · [Probe](../../scripts/probe_windows_codepages.mbtx).

The port reuses the documented Windows mappings in 20932, 20936, 20949
and 20000. CP50225 excludes the 259 one-way best fits in the Wansung table.
CP50229 excludes the two one-way mappings for U+FA0C and U+FA0D. The
character-set designations and output shifts are covered by byte comparisons.
[Unicode data provenance](../unicode/README.md) · [Microsoft code page assignments](https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-ucoderef/28fefe92-d66c-4b03-90a9-97b473223d43).

## Windows GSM code pages

The mappings for 55000–55004 derive from observable Windows conversion results.
Each file `codepage-api-probe/bmp-CP.bin` records one Win32 call per BMP scalar
with flags zero and NUL-terminated input. All five selectors encode the input
terminator as byte 20, encode U+0040 as 00 and substitute a space for each
unmapped UTF-16 unit. Extended letters and punctuation may take two bytes.
The five pages differ even for some ASCII letters. For example, `A@B` returns
`41 00 42 20` on 55000 and `20 00 20 20` on 55004. [Win32 probe](../../scripts/probe_windows_codepages.mbtx) · [Windows captures](https://github.com/moonbit-community/cygpath/actions/runs/44851348435)

To reproduce the tables, extract `codepage-api-probe` from the default Cygwin
or MSYS2 artifact and run
`moon run scripts/generate_codepages.mbtx gsm codepage-api-probe internal/encoding`.
The generator verifies all five input digests. Each four-byte entry stores a
Unicode value and its GSM code. The encoder supplies the default space for
values absent from the table.
