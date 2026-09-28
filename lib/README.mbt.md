# Portable path conversion

Import `ZSeanYves/cygpath/lib` to use the library. The examples below are compiled
as blackbox documentation tests against the public API.

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
`/cygdrive/c/...`. A custom `drive_prefix` is also supported.

## Supply the environment explicitly

Ordinary POSIX-rooted paths outside a drive prefix require a matching mount
when converted to Windows or Mixed output. POSIX-to-POSIX conversion and
complete UNC paths do not require mounts. Relative paths need a cwd only when
requesting absolute output, except Windows drive-relative/rooted paths
converted to POSIX, which also need drive context.

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

Mounts use the longest matching component prefix. Equal-length reverse aliases
keep declaration order. `case=AsciiInsensitive` enables ASCII-only matching;
the default is `Sensitive`. Context construction copies collections, and all
fields of `Context` and `Mount` are private.

`windows_cwd` supplies an absolute Windows cwd. `drive_cwds` maps a single drive
letter to an absolute cwd on that same drive, for example
`drive_cwds={ "C": "C:\\work" }`. Explicit per-drive entries take precedence over
a matching `windows_cwd`.

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

The library performs lexical conversion, not file-system resolution. It does
not follow symlinks, look up short/long filenames, or infer system directories.
Device and extended namespaces are rejected. Invalid UTF-16, NUL, and ordinary
Windows names that cannot be represented are rejected rather than repaired.
There is no fixed 260-character path limit.

See [path semantics](../docs/03-path-semantics.md) for exact rules and
[validation status](../docs/README.md) for what has actually been executed.
Passing the portable contract tests does not establish full Cygwin/MSYS2
compatibility; real Windows differential verification is a separate stage.
