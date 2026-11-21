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
