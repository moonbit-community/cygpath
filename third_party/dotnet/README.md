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

## ISO-2022 and HZ

The encoders for CP50220, CP50221, CP50222, CP50225 and CP52936 use the
state transitions, Japanese extension remapping and character-set limits of
the [.NET ISO2022Encoding implementation](https://github.com/dotnet/runtime/blob/v10.0.0/src/libraries/System.Text.Encoding.CodePages/src/System/Text/ISO2022Encoding.cs).
Microsoft identifies this implementation as a port of the Windows ISO-2022 DLL.
The repository uses its existing CP932, CP949 and CP936 tables for character
lookup. See [LICENSE.txt](LICENSE.txt).

The encoding tests fingerprint the output of one string containing every BMP
scalar in ascending order. The reference for each page was
`Encoding.GetEncoding(page).GetBytes(text)` after registering
`CodePagesEncodingProvider.Instance`, using the runtime shipped with
[PowerShell 7.6.0 for macOS arm64](https://github.com/PowerShell/PowerShell/releases/tag/v7.6.0).
The Windows workflow separately exercises the installed Cygwin executable and
records the native `WideCharToMultiByte` results.
