# cygpath

A pure MoonBit library and command-line tool for Windows and Cygwin/MSYS2-style
POSIX path conversion. The executable entry point is `main.mbt` in the repository
root; the public library is `ZSeanYves/cygpath/lib`.

P3 is complete for the [frozen portable matrix](testdata/oracle/p3-scope.json).
At [`b32dd74`](https://github.com/moonbit-community/cygpath/commit/b32dd7448658bc251b216ba93a5c120ef54fdbc9),
[three-platform CI](https://github.com/moonbit-community/cygpath/actions/runs/36385821361)
and [all four Windows oracle jobs](https://github.com/moonbit-community/cygpath/actions/runs/36385821354)
passed. **7,144 supported-domain comparisons matched raw stdout, stderr, and
exit status exactly.** Another 192 observations verify explicit rejection
boundaries and do not count as compatibility matches. See the
[evidence report](docs/09-remote-validation.md) for counts, hashes, and limits.

## Use

Run the root executable locally:

```sh
moon run --target wasm . -- -h
moon run --target wasm . -- -u 'C:\work\demo.txt'
moon run --target native . -- -w --root 'C:\cygwin64' /usr/bin
```

After the maintainer publishes the package, the intended invocation is:

```sh
moonx ZSeanYves/cygpath -h
moonx ZSeanYves/cygpath -u 'C:\work\demo.txt'
```

Ordinary short options are supported; a double-hyphen spelling is not required.
Use `moonx ZSeanYves/cygpath@<published-version>` to select an exact release.
Publication and retrieval of a published version have not been performed by
this work. The module's `0.1.0` is candidate metadata, not proof of a registry
release. Publication remains with the maintainer.

For embedding, import `ZSeanYves/cygpath/lib` and use `Mount::new`, `Context::new`,
`Context::convert`, and `Context::convert_list`. The [library guide](lib/README.mbt.md)
contains checked examples and typed-error handling.

## Supported scope

The implementation includes explicit mounts and working directories, Cygwin and
MSYS2 profiles, drive/UNC/relative paths, path lists, lexical normalization,
ordinary extended drive/UNC spellings, filename PUA conversion, long-path
handling, file/stdin records, per-record `-o` options, and UTF-8 plus 110 enabled
legacy numeric code pages. Profile selection affects mount ordering as well as
the default drive prefix. The [CLI contract](docs/04-api-and-cli.md) defines the
option and input protocols.

Mounts and cwd are explicit inputs. The product does not inspect an installed
Cygwin environment, execute system `cygpath`, or use project-owned FFI. Wasm and
Native use the same conversion and encoding code. The root executable and I/O
package support those two backends; pure packages also compile for Wasm GC and
JavaScript.

This is a verified portable subset, not complete official-tool compatibility.
Filesystem lookup for short/long names, symlinks and junctions, system-directory
queries, automatic ANSI/OEM discovery, and non-ASCII Windows mount case folding
remain outside the contract. Stateful encodings and GB18030 are unimplemented
pure-algorithm extensions. Malformed UTF-8 and the measured unavailable CP29001
are rejected deterministically rather than reproducing upstream reads of
uninitialized memory. See [scope](docs/01-upstream-and-scope.md).

## Development

Read the [architecture handbook](docs/README.md), then run commands serially:

```sh
moon check --target all --deny-warn
moon test --target wasm --deny-warn
moon test --target native --deny-warn
moon info --target all
moon fmt
```

The verified code revision passed 99 tests per backend on Linux, macOS, and
Windows, plus 57 actual CLI cases per backend and an external API consumer.
The [development guide](docs/08-development-and-release.md) documents release
builds, process checks, packaging, and the remaining publication gates.
Agent-authored automation uses `.mbtx`.

The repository is [moonbit-community/cygpath](https://github.com/moonbit-community/cygpath).
Its GitHub organization does not change the Mooncakes coordinate
`ZSeanYves/cygpath`.

## License

Project-authored code is [Apache-2.0](LICENSE). Generated mapping data retain the
[Unicode](third_party/unicode/README.md) and
[Microsoft Open Specifications](third_party/microsoft/README.md) notices.
The pure MoonBit MSYS2 sorting implementation adapts newlib's qsort algorithm
under [BSD-3-Clause](third_party/newlib/README.md). These notices are included in
the package; no upstream C code is compiled or linked into the product.
