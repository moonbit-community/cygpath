# Portable path conversion

Import `ZSeanYves/cygpath/lib` to use the pure MoonBit library. It performs no
filesystem, environment, registry, process, or platform-FFI access. The examples
below are compiled as blackbox documentation tests against the public API.
The module root is the separate command-line executable.

```text
import {
  "ZSeanYves/cygpath/lib" @cygpath,
}
```

The tests use `@lib`, the alias provided for this package's blackbox tests. Use
your chosen import alias, such as `@cygpath`, in application code.

## Convert one path

Source grammar and output format are explicit. The default context uses the
Cygwin drive prefix and never inspects the machine running the conversion.

```mbt check
///|
test "documented basic conversion" {
  let context = @lib.Context::new()
  assert_eq(
    context.convert("C:\\work\\demo.txt", from=Windows, to=Posix),
    "/cygdrive/c/work/demo.txt",
  )
  assert_eq(
    context.convert("/cygdrive/d/project", from=Posix, to=Mixed),
    "D:/project",
  )
}
```

Windows output uses backslashes; Mixed output uses forward slashes with Windows
semantics. `Context::new(profile=Msys2)` selects `/c/...` drive paths instead of
`/cygdrive/c/...`, and also selects MSYS2 mount ordering and mapped-root trailing
separators. A custom `drive_prefix` changes the prefix without changing those
other profile rules. No profile is inferred from the host.

`convert` requires `from` and `to`. Its optional `absolute` defaults to false;
`unix_prefix=ProcCygdrive` selects `/proc/cygdrive` for unmatched drive-to-POSIX
fallback, while explicit mounts still take precedence. Requesting that prefix
with non-POSIX output raises `InvalidOptions`.

## Supply the environment explicitly

Ordinary POSIX-rooted paths outside a drive prefix require a matching mount
when converted to Windows or Mixed output. POSIX-to-POSIX conversion and
complete UNC paths do not require mounts. Ordinary relative paths need a cwd
when requesting absolute output, or when long Windows output requires absolute
rendering. Windows current-drive-rooted input such as `\name` needs a
drive-absolute `windows_cwd` for POSIX/absolute conversion. Drive-relative input
such as `C:name` uses the separate drive-root rule below.

```mbt check
///|
test "documented mounts and absolute paths" {
  let context = @lib.Context::new(
    mounts=[
      @lib.Mount::new("/", "C:\\cygwin64"),
      @lib.Mount::new("/usr/bin", "C:\\cygwin64\\bin"),
    ],
    posix_cwd="/home/user",
  )
  assert_eq(
    context.convert("/usr/bin/tool", from=Posix, to=Windows),
    "C:\\cygwin64\\bin\\tool",
  )
  assert_eq(
    context.convert("../work", from=Posix, to=Mixed, absolute=true),
    "C:/cygwin64/home/work",
  )
}
```

Mounts match whole component prefixes. Cygwin chooses the longest matching
component prefix and preserves declaration priority for equal reverse aliases.
MSYS2 reproduces its pinned runtime's native-length/POSIX-prefix ordering and
reverse length-difference ordering; nested mounts therefore need not use the
Cygwin winner. See [mapping rules](../docs/03-path-semantics.md#4-mapping-profile-ordering-and-case)
for the exact profile distinction. `case=AsciiInsensitive` enables ASCII-only
comparison; the default is `Sensitive`. Context construction copies collections,
and all fields of `Context` and `Mount` are private.

Mount points and targets must be absolute and dot-free. Duplicate POSIX mount
points, virtual mount points, and overlap with reserved drive branches are
rejected. `Mount::new` accepts drive-absolute or complete UNC targets, including
their supported ordinary extended spellings. A root mount does not synthesize
`/usr/bin`, `/usr/lib`, or other aliases.

`windows_cwd` supplies an absolute Windows cwd. `drive_cwds` maps a single drive
letter to an absolute cwd on that same drive, for example
`drive_cwds={ "C": "C:\\work" }`. This parameter is validated metadata only;
it does not override resolution. Explicit Windows `C:name` becomes
`/cygdrive/c/name` for POSIX output and `C:\name` with absolute Windows output,
regardless of the supplied per-drive cwd. Without absolute resolution,
Windows/Mixed output preserves drive-relative syntax.

The CLI has an additional natural-recognition layer. In particular, bare-drive
and absolute Windows-output CLI operands can take a literal POSIX-relative
branch; use explicit library source syntax for the rules described here.

## Convert a PATH list

```mbt check
///|
test "documented list conversion" {
  let context = @lib.Context::new()
  assert_eq(
    context.convert_list("C:\\bin;;D:\\tools;", from=Windows, to=Posix),
    "/cygdrive/c/bin:/cygdrive/d/tools",
  )
  assert_eq(
    context.convert_list(
      "/cygdrive/c/bin::/cygdrive/d/tools",
      from=Posix,
      to=Mixed,
    ),
    "C:/bin;.;D:/tools",
  )
}
```

Windows lists use `;`, POSIX lists use `:`. Empty entries are deliberately
asymmetric: Windows-to-POSIX skips them, while POSIX-to-Windows converts them as
`.`. Same-syntax list conversions preserve empty entries. A list fails as a
whole if any member is invalid; `ListEntryError` reports its original zero-based
index and underlying `ConversionError`.

`convert_list` has the same `absolute` and `unix_prefix` options as `convert`.
Its `recognize_windows` option defaults to false. Setting it to true recognizes
backslash-containing Windows members after a POSIX list has already been split;
it never changes the declared delimiter. No shell/CSV quoting is decoded, and
target delimiters inside path content are not escaped. Use arrays of individually
converted paths when a lossless structured representation is required.

An empty list is allowed by the library's member rules; an empty single path
raises `EmptyPath`. The CLI separately rejects or skips empty operands before
list conversion.

## Errors and limits

Conversion raises the public `ConversionError` type. Callers can match error
constructors; they do not need to parse messages.

```mbt check
///|
test "documented missing-context error" {
  let context = @lib.Context::new()
  try context.convert("/usr/bin", from=Posix, to=Windows) catch {
    @lib.MissingContext(field="root or mount") => ()
    error => fail("unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("expected missing mount context")
  }
}
```

The other error constructors are `PathTooLong(original)`, `InvalidDrivePrefix`,
`InvalidPath(reason~, offset~)`, `InvalidContext(field~, reason~)`,
`UnsupportedNamespace(kind)`, `UnrepresentablePath(component~, reason~)`,
`InvalidOptions(reason)`, and `ListEntryError(index~, cause)`. Offsets and list
indices are zero-based. [The generated interface](pkg.generated.mbti) records
their exact signatures. Formatting diagnostics and selecting process exit
codes belong to the CLI, not this library.

The library performs lexical conversion. It does not follow symlinks, query
8.3 short/long filenames, restore actual filesystem case, or infer system
directories. Complete ordinary extended drive/UNC forms such as
`\\?\C:\name` and `\\?\UNC\server\share\name` are supported; device and
incomplete UNC namespaces are rejected. NUL and unpaired UTF-16 are errors.

Windows filename rendering maps ASCII controls and `" * : < > ? |` into
Cygwin's U+F000 private-use range. Windows-to-POSIX reverses those mappings,
including encoded spaces/dots, while preserving unrelated Unicode. Ordinary
reserved-name spellings and trailing dots/spaces remain text. A literal
backslash in an explicitly POSIX filename component is unrepresentable in
ordinary Windows output. Strings undergo no Unicode normalization or variable,
tilde, glob, or URI expansion.

Windows/Mixed conversion rejects input components longer than 255 UTF-16 units.
POSIX output does not apply that component check. Ordinary Windows drive/UNC
results at the 260-unit threshold receive extended prefixes; long relative
Windows output may require explicit cwd to become absolute. There is no blanket
260-character rejection. This does not promise unlimited Windows filesystem
path support.

Some spelling rules intentionally preserve input: Windows-to-POSIX `/a/../b`
remains that spelling, unmatched UNC tails retain traversal/separators, and
relative paths retain dots without absolute resolution. Explicit POSIX input
instead uses POSIX normalization. Cygwin maps bare `/` to an ordinary mounted
directory without an extra slash; MSYS2 retains its observed trailing separator.

See [path semantics](../docs/03-path-semantics.md) for exact rules and
[validation status](../docs/README.md) for what has actually been executed.
P3's frozen pure MoonBit, explicit-context matrix passed real Windows differential
verification at `b32dd7448658bc251b216ba93a5c120ef54fdbc9`; the
[report](../docs/09-remote-validation.md) preserves the exact programs and scope.
This is a verified subset, not full Cygwin/MSYS2 runtime compatibility. Registry
publication and version-pinned `moonx` acceptance remain separate release work.
