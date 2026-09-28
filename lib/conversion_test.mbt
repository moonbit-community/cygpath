///|
fn conversion_error(
  run : () -> String raise @lib.ConversionError,
) -> @lib.ConversionError raise {
  try run() catch {
    error => error
  } noraise {
    value => fail("expected a conversion error, got \{value}")
  }
}

///|
test "documented drive conversion vectors" {
  let context = @lib.Context::new()
  assert_eq(
    context.convert("C:\\work\\a.txt", from=Windows, to=Posix),
    "/cygdrive/c/work/a.txt",
  )
  assert_eq(
    context.convert("c:\\work\\a.txt", from=Windows, to=Mixed),
    "C:/work/a.txt",
  )
  assert_eq(context.convert("/cygdrive/d/a", from=Posix, to=Windows), "D:\\a")
  assert_eq(context.convert("/proc/cygdrive/d/a", from=Posix, to=Mixed), "D:/a")
  assert_eq(
    context.convert("D:\\a", from=Windows, to=Posix, unix_prefix=ProcCygdrive),
    "/proc/cygdrive/d/a",
  )
  assert_true(
    conversion_error(() => context.convert("/usr/bin", from=Posix, to=Windows))
    is @lib.MissingContext(field="root or mount"),
  )
}

///|
test "source grammar is explicit and independent of output style" {
  let context = @lib.Context::new(
    mounts=[@lib.Mount::new("/", "C:\\root")],
    windows_cwd="D:\\work",
  )
  assert_eq(context.convert("/a", from=Windows, to=Posix), "/cygdrive/d/a")
  assert_eq(context.convert("/a", from=Posix, to=Windows), "C:\\root\\a")
  assert_eq(context.convert("C:/a\\b", from=Windows, to=Mixed), "C:/a/b")
  assert_eq(context.convert("a\\b", from=Posix, to=Posix), "a\\b")
  assert_true(
    conversion_error(() => context.convert("a\\b", from=Posix, to=Windows))
    is @lib.UnrepresentablePath(component="a\\b", reason=_),
  )
  assert_true(
    conversion_error(() => context.convert("C:/a", from=Posix, to=Windows))
    is @lib.UnrepresentablePath(component="C:", reason=_),
  )
}

///|
test "ordinary relative paths preserve dot meaning and literal content" {
  let context = @lib.Context::new()
  assert_eq(context.convert("a/../b", from=Posix, to=Windows), "a\\..\\b")
  assert_eq(context.convert(".\\a\\..\\b", from=Windows, to=Posix), "./a/../b")
  assert_eq(context.convert("../a/./", from=Posix, to=Mixed), "../a/./")
  assert_eq(context.convert("~/a", from=Posix, to=Windows), "~\\a")
  assert_eq(context.convert("$HOME/a", from=Posix, to=Windows), "$HOME\\a")
  assert_eq(
    context.convert("%USERPROFILE%\\a", from=Windows, to=Posix),
    "%USERPROFILE%/a",
  )
  assert_eq(context.convert(" a b ", from=Posix, to=Posix), " a b ")
}

///|
test "absolute normalization cannot escape a root and retains trailing separators" {
  let context = @lib.Context::new()
  assert_eq(
    context.convert("c:\\a\\\\.\\b\\..\\", from=Windows, to=Mixed),
    "C:/a/",
  )
  assert_eq(context.convert("C:\\..\\..\\a", from=Windows, to=Windows), "C:\\a")
  assert_eq(context.convert("/a//./b/../../..", from=Posix, to=Posix), "/")
  assert_eq(
    context.convert("//server/share/a/../../b/", from=Posix, to=Posix),
    "//server/share/b/",
  )
  assert_eq(context.convert("C:\\", from=Windows, to=Windows), "C:\\")
  assert_eq(
    context.convert("//server/share", from=Posix, to=Windows),
    "\\\\server\\share\\",
  )
  assert_eq(context.convert("./", from=Posix, to=Windows), ".\\")
  assert_eq(context.convert("../", from=Posix, to=Windows), "..\\")
}

///|
test "absolute resolution consumes only the source syntax cwd" {
  let context = @lib.Context::new(
    posix_cwd="/cygdrive/c/work/base",
    windows_cwd="D:\\work\\base",
  )
  assert_eq(
    context.convert("../a", from=Posix, to=Windows, absolute=true),
    "C:\\work\\a",
  )
  assert_eq(
    context.convert("..\\a", from=Windows, to=Posix, absolute=true),
    "/cygdrive/d/work/a",
  )
  let empty = @lib.Context::new()
  assert_true(
    conversion_error(() => {
      empty.convert("a", from=Posix, to=Windows, absolute=true)
    })
    is @lib.MissingContext(field="posix_cwd"),
  )
  assert_true(
    conversion_error(() => {
      empty.convert("a", from=Windows, to=Posix, absolute=true)
    })
    is @lib.MissingContext(field="windows_cwd"),
  )
}

///|
test "drive relative and current-drive-root-relative paths need distinct context" {
  let empty = @lib.Context::new()
  assert_eq(empty.convert("c:a", from=Windows, to=Mixed), "C:a")
  assert_eq(empty.convert("c:", from=Windows, to=Windows), "C:")
  assert_eq(empty.convert("\\a", from=Windows, to=Mixed), "/a")
  assert_true(
    conversion_error(() => empty.convert("C:a", from=Windows, to=Posix))
    is @lib.MissingContext(field="drive_cwds[C]"),
  )
  assert_true(
    conversion_error(() => empty.convert("\\a", from=Windows, to=Posix))
    is @lib.MissingContext(field="windows_cwd drive"),
  )
  let context = @lib.Context::new(windows_cwd="C:\\fallback", drive_cwds={
    "c": "C:\\work",
    "D": "D:\\other",
  })
  assert_eq(
    context.convert("C:a", from=Windows, to=Posix),
    "/cygdrive/c/work/a",
  )
  assert_eq(context.convert("C:", from=Windows, to=Posix), "/cygdrive/c/work")
  assert_eq(
    context.convert("D:../a", from=Windows, to=Windows, absolute=true),
    "D:\\a",
  )
  assert_eq(context.convert("\\a", from=Windows, to=Posix), "/cygdrive/c/a")
  let fallback = @lib.Context::new(windows_cwd="C:\\fallback")
  assert_eq(
    fallback.convert("c:a", from=Windows, to=Posix),
    "/cygdrive/c/fallback/a",
  )
  assert_true(
    conversion_error(() => fallback.convert("D:a", from=Windows, to=Posix))
    is @lib.MissingContext(field="drive_cwds[D]"),
  )
}

///|
test "complete UNC paths and UNC cwd preserve the share boundary" {
  let context = @lib.Context::new(windows_cwd="\\\\server\\share\\base")
  assert_eq(
    context.convert("\\\\server\\share\\a", from=Windows, to=Posix),
    "//server/share/a",
  )
  assert_eq(
    context.convert("//server/share/a", from=Posix, to=Mixed),
    "//server/share/a",
  )
  assert_eq(
    context.convert("..\\a", from=Windows, to=Windows, absolute=true),
    "\\\\server\\share\\a",
  )
  assert_true(
    conversion_error(() => context.convert("\\a", from=Windows, to=Posix))
    is @lib.MissingContext(field="windows_cwd drive"),
  )
  assert_true(
    conversion_error(() => context.convert("C:a", from=Windows, to=Posix))
    is @lib.MissingContext(field="drive_cwds[C]"),
  )
}

///|
test "Unicode scalars are preserved without normalization and invalid text is rejected" {
  let context = @lib.Context::new()
  let name = "資料/😀/e\u0301/ spaced name"
  assert_eq(
    context.convert(name, from=Posix, to=Windows),
    "資料\\😀\\e\u0301\\ spaced name",
  )
  assert_eq(
    context.convert("C:\\" + name, from=Windows, to=Posix),
    "/cygdrive/c/" + name,
  )
  assert_true(
    conversion_error(() => context.convert("😀\u0000a", from=Posix, to=Posix))
    is @lib.InvalidPath(reason=_, offset=2),
  )
  for unit in [0xD800, 0xDC00] {
    let invalid = String::from_array(['a', unit.unsafe_to_char()])
    assert_true(
      conversion_error(() => context.convert(invalid, from=Posix, to=Posix))
      is @lib.InvalidPath(reason=_, offset=1),
    )
  }
}

///|
test "unrepresentable Windows components retain the original component" {
  let context = @lib.Context::new()
  for
    component in [
      "a:b", "a*b", "a?b", "a\\b", "a|b", "a<b", "a>b", "a\"b", "a\u0001b", "name.",
      "name ", "CON", "con.txt", "PRN", "AUX", "NUL", "COM1", "com9.txt", "LPT1",
      "lpt9.txt", "COM¹", "LPT²", "COM³",
    ] {
    let error = conversion_error(() => {
      context.convert(component, from=Posix, to=Windows)
    })
    assert_true(
      error is @lib.UnrepresentablePath(component=actual, reason=_) &&
      actual == component,
    )
  }
  for component in ["COM0", "COM10", "LPT10", "CONSOLE", ".hidden", "a;b"] {
    assert_eq(context.convert(component, from=Posix, to=Windows), component)
  }
}

///|
test "namespace handling is explicit and does not masquerade as disk paths" {
  let context = @lib.Context::new(mounts=[@lib.Mount::new("/", "C:\\root")])
  for
    path in [
      "\\\\?\\C:\\a", "\\\\?\\UNC\\server\\share\\a", "\\\\.\\COM1", "//server",
    ] {
    assert_true(
      conversion_error(() => context.convert(path, from=Windows, to=Posix))
      is @lib.UnsupportedNamespace(_),
    )
  }
  for
    path in ["/dev/null", "/proc/self", "/proc/cygdrive", "/proc/cygdrive/cc/a"] {
    assert_true(
      conversion_error(() => context.convert(path, from=Posix, to=Windows))
      is @lib.UnsupportedNamespace(_),
    )
  }
  assert_eq(
    context.convert("/proc/cygdrive/c/a", from=Posix, to=Windows),
    "C:\\a",
  )
  assert_true(
    conversion_error(() => {
      context.convert("C:\\a", from=Windows, to=Mixed, unix_prefix=ProcCygdrive)
    })
    is @lib.InvalidOptions(_),
  )
  assert_true(
    conversion_error(() => context.convert("", from=Windows, to=Posix))
    is @lib.EmptyPath,
  )
}

///|
test "list empty-member semantics differ by conversion direction" {
  let context = @lib.Context::new()
  assert_eq(
    context.convert_list("C:\\a;;D:\\b;", from=Windows, to=Posix),
    "/cygdrive/c/a:/cygdrive/d/b",
  )
  assert_eq(
    context.convert_list("/cygdrive/c/a::/cygdrive/d/b", from=Posix, to=Windows),
    "C:\\a;.;D:\\b",
  )
  assert_eq(context.convert_list("", from=Posix, to=Windows), ".")
  assert_eq(context.convert_list("::", from=Posix, to=Windows), ".;.;.")
  assert_eq(context.convert_list(";;", from=Windows, to=Posix), "")
  assert_eq(context.convert_list("", from=Windows, to=Posix), "")
  assert_eq(context.convert_list(";c:\\a;;", from=Windows, to=Mixed), ";C:/a;;")
  assert_eq(context.convert_list(":a::", from=Posix, to=Posix), ":a::")
  let absolute = @lib.Context::new(posix_cwd="/cygdrive/c/work")
  assert_eq(
    absolute.convert_list(":a:", from=Posix, to=Windows, absolute=true),
    "C:\\work;C:\\work\\a;C:\\work",
  )
}

///|
test "lists preserve order and use only the declared source delimiter" {
  let context = @lib.Context::new(drive_cwds={ "C": "C:\\work" })
  assert_eq(
    context.convert_list("C:;D:\\a;C:", from=Windows, to=Posix),
    "/cygdrive/c/work:/cygdrive/d/a:/cygdrive/c/work",
  )
  assert_eq(context.convert_list("a:b:a", from=Posix, to=Windows), "a;b;a")
  assert_eq(
    context.convert_list("C:\\a;D:\\b", from=Windows, to=Mixed),
    "C:/a;D:/b",
  )
  assert_true(
    conversion_error(() => {
      context.convert_list("\"C:\\a\"", from=Windows, to=Posix)
    })
    is @lib.ListEntryError(
      index=0,
      @lib.UnrepresentablePath(component=_, reason=_)
    ),
  )
}

///|
test "list errors retain the original index and reject lossy serialization" {
  let context = @lib.Context::new()
  assert_true(
    conversion_error(() => {
      context.convert_list(";C:\\ok;;D:a", from=Windows, to=Posix)
    })
    is @lib.ListEntryError(index=3, @lib.MissingContext(field="drive_cwds[D]")),
  )
  assert_eq(context.convert("a;b", from=Posix, to=Windows), "a;b")
  assert_true(
    conversion_error(() => {
      context.convert_list("ok:a;b", from=Posix, to=Windows)
    })
    is @lib.ListEntryError(
      index=1,
      @lib.UnrepresentablePath(component="a;b", reason=_)
    ),
  )
  let colon_mount = @lib.Context::new(mounts=[
    @lib.Mount::new("/a:b", "C:\\work"),
  ])
  assert_eq(colon_mount.convert("C:\\work", from=Windows, to=Posix), "/a:b")
  assert_true(
    conversion_error(() => {
      colon_mount.convert_list(";C:\\work", from=Windows, to=Posix)
    })
    is @lib.ListEntryError(
      index=1,
      @lib.UnrepresentablePath(component="/a:b", reason=_)
    ),
  )
}

///|
test "round trips hold for canonical unaliased representable absolute paths" {
  let context = @lib.Context::new(mounts=[@lib.Mount::new("/work", "C:\\work")])
  for
    windows in [
      "C:\\work\\a", "C:\\work\\a b\\😀", "D:\\other\\a", "\\\\server\\share\\a",
    ] {
    let posix = context.convert(windows, from=Windows, to=Posix)
    assert_eq(context.convert(posix, from=Posix, to=Windows), windows)
    assert_eq(context.convert(posix, from=Posix, to=Posix), posix)
    assert_eq(context.convert(windows, from=Windows, to=Posix), posix)
    assert_eq(
      context.convert(windows, from=Windows, to=Mixed),
      windows.replace_all(old="\\", new="/"),
    )
  }
}
