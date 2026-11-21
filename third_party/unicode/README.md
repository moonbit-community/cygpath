# Windows code-page mapping data

The 15 packed tables identified in `codepages.json` derive from the `WCTABLE`
sections of Microsoft's WindowsBestFit mapping files published by the Unicode
Consortium. They are data, not copied Cygwin implementation code. The data is
covered by the accompanying [Unicode License v3](LICENSE.txt); project-authored
encoder and generator code retain the repository's Apache-2.0 license.

`codepages.json` records each source URL, exact downloaded SHA-256, byte length,
mapping count, default character, and packed-table SHA-256. Source comments do
not enter the generated mappings. Entries are sorted and stored as big-endian
16-bit Unicode/encoded-value pairs for binary search. Encoding requires an
explicit supported numeric code page; ANSI/OEM host detection is not inferred.

To regenerate, download the source URLs in the manifest into one directory,
verify their recorded hashes, then run:

```text
moon run scripts/generate_codepages.mbtx SOURCE_DIRECTORY internal/encoding third_party/unicode/codepages.json
moon run scripts/generate_codepages.mbtx microsoft MICROSOFT_ARCHIVE_ZIP internal/encoding third_party/microsoft/codepages.json
moon fmt
```

Review source and packed digests before accepting any regenerated data. The
generator does not query the network or use the host's encoding APIs.
Additional legacy tables have separate [Microsoft provenance and
permissions](../microsoft/README.md); the generated Unicode dispatch delegates
to their separate table after checking the original 15 pages.

## East Asian Windows code pages

The CP20932, CP20936 and CP20949 encoder tables are generated from
[Unicode ICU data revision 6eac2f4](https://github.com/unicode-org/icu-data/tree/6eac2f4d349d9f4a0825103bb41845d8e5ab7add/charset/data/ucm).
The data files credit Copyright (C) 2001-2002, International Business Machines
Corporation and others. All Rights Reserved. The repository credits
Copyright © 2016-2024 Unicode, Inc. See the [Unicode License v3](LICENSE.txt).

Download the three UCM files below into one directory. Run
`moon run scripts/generate_codepages.mbtx ucm DIRECTORY internal/encoding`.
The generator verifies their hashes, writes the round-trip and best-fit encoder
entries in Unicode order, and skips reverse-only entries. All three pages use
`3f` for unmapped UTF-16 words.

| Input from ICU | Encoder entries | SHA-256 of the Windows reference NLS file |
| --- | ---: | --- |
| [windows-20932-2000.ucm](https://raw.githubusercontent.com/unicode-org/icu-data/6eac2f4d349d9f4a0825103bb41845d8e5ab7add/charset/data/ucm/windows-20932-2000.ucm) | 15,181 | `b5b92488733c737898ce57c1c29bdb221f60c6ad786822e8f0bc9f80668eb6c1` |
| [windows-20936-2000.ucm](https://raw.githubusercontent.com/unicode-org/icu-data/6eac2f4d349d9f4a0825103bb41845d8e5ab7add/charset/data/ucm/windows-20936-2000.ucm) | 7,613 | `b9bc2bba9ab0461a27603bdc0035433d85316a00d3b341f3f1cf310d95c8b340` |
| [windows-20949-2000.ucm](https://raw.githubusercontent.com/unicode-org/icu-data/6eac2f4d349d9f4a0825103bb41845d8e5ab7add/charset/data/ucm/windows-20949-2000.ucm) | 8,651 | `78af92673903260793a1d1f5b2c411b2393e5be28c0539df4811fa043eee82aa` |

The reference files `Files/Windows/System32/C_<page>.NLS` came from Microsoft's
[Nano Server 10.0.20348.5873 amd64 image](https://mcr.microsoft.com/v2/windows/nanoserver/manifests/sha256:076562f66717cad7b814e9665a95d1d773fcb073de511aa1929601dab50e8b58).
For these DBCS files the final 65,536 little-endian words give the encoded value
for each UTF-16 input. Comparing every word against the ICU mappings and the
default byte yielded zero differences on all three pages. The Wasm tests use
fingerprints derived from those Windows words, with separate supplementary
fallback and CLI byte-order checks. The Windows workflow also exercises the
installed Cygwin executable. Only the ICU-derived tables ship in the product.
