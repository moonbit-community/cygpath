# Windows code-page mapping data

The packed tables in `internal/encoding/cp_*.mbt` derive from the `WCTABLE`
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
moon fmt
```

Review source and packed digests before accepting any regenerated data. The
generator does not query the network or use the host's encoding APIs.
