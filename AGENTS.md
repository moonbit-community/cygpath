# Project Agents.md Guide

This is a [MoonBit](https://docs.moonbitlang.com) project.

You can browse and install extra skills here:
<https://github.com/moonbitlang/skills>

## Project Structure

- MoonBit packages are organized per directory; each directory contains a
  `moon.pkg` file listing its dependencies. Each package has its files and
  blackbox test files (ending in `_test.mbt`) and whitebox test files (ending in
  `_wbtest.mbt`).

- In the toplevel directory, there is a `moon.mod` file listing module
  metadata.

## Coding convention

- MoonBit code is organized in block style, each block is separated by `///|`,
  the order of each block is irrelevant. In some refactorings, you can process
  block by block independently.

- Try to keep deprecated blocks in file called `deprecated.mbt` in each
  directory.

## Tooling

- `moon fmt` is used to format your code properly.

- `moon ide` provides project navigation helpers like `peek-def`, `outline`, and
  `find-references`. See $moonbit-agent-guide for details.

- `moon info` is used to update the generated interface of the package, each
  package has a generated interface file `.mbti`, it is a brief formal
  description of the package. If nothing in `.mbti` changes, this means your
  change does not bring the visible changes to the external package users, it is
  typically a safe refactoring.

- In the last step, run `moon info && moon fmt` to update the interface and
  format the code. Check the diffs of `.mbti` file to see if the changes are
  expected.

- Run `moon test` to check tests pass. MoonBit supports snapshot testing; when
  changes affect outputs, run `moon test --update` to refresh snapshots.

- Prefer `assert_eq` or `assert_true(pattern is Pattern(...))` for results that
  are stable or very unlikely to change. For snapshot tests that record
  structured debugging output, derive `Debug` and use `debug_inspect`, rather
  than deriving `Show` for debugging. For solid, well-defined results (e.g.
  scientific computations), prefer assertion tests. You can use
  `moon coverage analyze > uncovered.log` to see which parts of your code are
  not covered by tests.

## cygpath project agreements

- Start with [docs/README.md](docs/README.md). Architecture documents distinguish
  planned behavior from implemented and verified behavior; do not claim planned
  capabilities as available.
- The root package is the executable, with `main.mbt` directly in the repository
  root, so users run `moonx ZSeanYves/cygpath <args>`. Keep this entry point thin.
- The public `lib/` package (`ZSeanYves/cygpath/lib`) owns conversion types and
  the portable engine. Keep filesystem, environment, process, CLI, and platform
  FFI access out of this library. Internal CLI code depends on `lib/`, never on
  the executable root package.
- The product must be pure MoonBit, including the CLI intended for `moonx`.
  Do not add C/C++ stubs, custom foreign imports, or shell/system-cygpath fallbacks.
  Use the same conversion rules for Wasm and Native; unsupported host capabilities
  must produce explicit errors. Standard MoonBit runtime I/O is allowed, with
  its cross-backend behavior verified at the host boundary.
- Host context is explicit. Do not guess a Cygwin installation root from the
  build machine or silently substitute MSYS2 drive-prefix rules for Cygwin rules.
- Add packages when their first real implementation arrives, following the
  dependency direction in [the architecture](docs/02-architecture.md). Public
  concrete types must not be owned by an `internal` package.
- Use `.mbtx` for agent-authored automation. Run MoonBit build/check/test/info/fmt
  commands serially to avoid competing for the same build lock.
- Before handoff run `moon check --target all --deny-warn`, `moon test`, then
  `moon info` and `moon fmt`; review generated interfaces. Zero tests only validate
  project setup, never conversion correctness.
- Keep `ZSeanYves/cygpath` until the publishing namespace is explicitly settled.
  Do not infer Mooncakes account ownership from the GitHub organization.
- Retain source provenance for behavior and fixtures. Do not copy upstream Cygwin
  implementation into this Apache-2.0 project as if it were Apache-licensed.
