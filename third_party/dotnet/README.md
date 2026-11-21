# Microsoft code page encoders

## GB18030

The 439 runs in `internal/encoding/gb18030_runs.mbt` derive from the
MIT-licensed [.NET v10.0.0 GB18030Encoding table](https://github.com/dotnet/runtime/blob/v10.0.0/src/libraries/System.Text.Encoding.CodePages/src/System/Text/GB18030Encoding.cs).
The source identifies its mapping as a port of the Windows GB18030-2000 DLL.
The encoder shares the existing CP936 table and calculates supplementary
four-byte sequences from their scalar values. See [LICENSE.txt](LICENSE.txt).

To reproduce the table, download that source as `GB18030Encoding.cs` and run
`moon run scripts/generate_codepages.mbtx gb18030 GB18030Encoding.cs internal/encoding`.
The generator verifies the source SHA-256 and checks that the runs cover the
entire BMP. The Wasm tests compare all BMP scalars with the Python 3.14 codec
fingerprint and check supplementary boundaries. The Windows oracle includes
revision-sensitive characters for comparison with the installed Cygwin.

## ISCII

The ten Windows ISCII pages (57002–57011) share the 1,135 Unicode mapping
entries from U+0901 through U+0D6F in Microsoft's MIT-licensed
[`ISCIIEncoding.cs`](https://github.com/dotnet/runtime/blob/v10.0.0/src/libraries/System.Text.Encoding.CodePages/src/System/Text/ISCIIEncoding.cs).
To regenerate the table, download that file and run
`moon run scripts/generate_codepages.mbtx iscii ISCIIEncoding.cs internal/encoding`.
The generator verifies the source digest and entry count. [License](LICENSE.txt)

Windows leaves the active script selected at the end of a string. For example,
U+0981 on page 57002 produces `ef 43 a1` followed directly by the C terminator.
The Wasm regression fingerprints use length-prefixed Win32 results for all
63,488 non-surrogate BMP values on each page. The two default Windows artifacts
also contain 100 complete conversion samples covering script changes, virama
and joiners, extended characters and fallback. [Win32 captures](https://github.com/moonbit-community/cygpath/actions/runs/44851348435)
