# Microsoft Windows code-page mapping data

The additional OEM, ASCII, ISO-8859, KOI8, EBCDIC, Macintosh, and other legacy tables in `internal/encoding`
derive from Microsoft's **Windows Supported Code Page Data Files.zip**.
The generator inspects 96 additional pages which, together with the original
15 tables, cover all 111 table identities in that archive. `codepages.json`
distinguishes generated pages from temporary `excluded_pages`: a conflicting
mapping cannot be enabled until direct Windows evidence resolves the source
ambiguity. The first remote Windows capture resolved all four ambiguous
members: 10005 U+05B8 -> DE, 10008 U+2225 -> A1CE, 20269 #^`~¤ -> A6 C3 C1
C4 A8, and 20924 U+0178 -> E8. Neither source order nor an arbitrary overwrite
decides their behavior. The exact raw stream hashes, lengths, profile, and
case IDs are recorded in `codepages.json` under
`official_resolution_evidence`; the selected values are also recorded per
page under `resolved_conflicts`. The generator requires
`CPINFO` to declare one or two bytes, rejects wider mappings, and additionally
requires single-byte tables to contain only single-byte values. This does not
implement stateful encodings, four-byte GB18030, or automatic ANSI/OEM host-page
discovery. Runtime availability of legacy identifiers is checked separately
against the recorded Windows oracle; a mapping table's existence alone does
not prove that a modern Windows installation accepts its number.

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
