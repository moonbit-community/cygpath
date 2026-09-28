# cygpath

A pure MoonBit implementation of Windows and Cygwin-style POSIX path conversion, with a reusable library and a command-line executable.

The project is in development. The current implementation and validation status is tracked in the [architecture index](docs/README.md). The `0.1.0` module version is a development placeholder, not a published release or a claim of full Cygwin compatibility.

## Design

Start with the [architecture documents](docs/README.md). Official Cygwin sources and documentation provide the primary behavior reference, with MSYS2 and independent ports as additional references. The design separates pure path conversion, explicit environment context, and host I/O.

The library and CLI must use pure MoonBit. Wasm and Native share the same conversion rules, without project-specific C/C++ FFI or calls to a system `cygpath`. Mounts and working directories are explicit inputs. Features without a correct implementation under these constraints, such as 8.3 filename lookup, system-directory queries, and arbitrary code pages, are explicitly unsupported.

The initial library provides `Context::new`, `Mount::new`, `Context::convert`,
and `Context::convert_list`. See the [library guide](lib/README.mbt.md) for checked
examples covering conversion, mounts, absolute paths, lists, and typed errors.

The executable entry point is `main.mbt` in the repository root. Run the local
CLI with Wasm or Native:

```sh
moon run --target wasm . -- -h
moon run --target wasm . -- -u 'C:\work\demo.txt'
moon run --target native . -- -w --root 'C:\cygwin64' /usr/bin
```

The CLI supports explicit mounts and cwd, path lists, UTF-8 file/stdin records,
and structured failure diagnostics. See the [CLI contract](docs/04-api-and-cli.md)
for options and the [validation index](docs/README.md) for the hosts and backends
actually tested. Root and host packages support Wasm and Native; the pure library
and CLI parser also compile for Wasm GC and JavaScript.

After publication and namespace verification, users will run:

```sh
moonx ZSeanYves/cygpath -h
moonx ZSeanYves/cygpath -u 'C:\work\demo.txt'
```

Use `moonx ZSeanYves/cygpath@<published-version>` to pin a release. The public
conversion library lives in `lib/`, imported as `ZSeanYves/cygpath/lib`. No release
has been published or verified through registry retrieval. Real Windows
Cygwin/MSYS2 differential acceptance remains a separate gate.

## Development

```sh
moon check --target all --deny-warn
moon test
moon test --target native --deny-warn
moon info --target all
moon fmt
```

Run MoonBit commands serially. Behavioral tests must accompany implemented features; an empty test run does not establish correctness. Agent-authored automation uses `.mbtx`.

[`scripts/check_cli.mbtx`](scripts/check_cli.mbtx) compares built Wasm and Native
executables against byte-exact [portable CLI fixtures](testdata/contracts/README.md).
The [validation roadmap](docs/05-validation-and-roadmap.md) preserves the separate
Windows oracle and publication gates. The three-host CI workflow is included
in the source; its presence does not establish a successful remote run.

The module name remains `ZSeanYves/cygpath`; the GitHub repository is [moonbit-community/cygpath](https://github.com/moonbit-community/cygpath). The GitHub organization does not determine the Mooncakes publishing namespace. Verify the account and package coordinates before publishing.

## License

This project uses [Apache-2.0](LICENSE). No upstream implementation has been copied into the project. The port independently implements observable behavior; see [upstream references and scope](docs/01-upstream-and-scope.md) for provenance and source-introduction rules.
