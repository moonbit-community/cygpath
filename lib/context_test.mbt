///|
fn context_error(
  run : () -> Unit raise @lib.ConversionError,
) -> @lib.ConversionError raise {
  try run() catch {
    error => error
  } noraise {
    _ => fail("expected an invalid context")
  }
}

///|
test "root mappings require explicit aliases and mounts override cygdrive fallback" {
  let root = @lib.Mount::new("/", "C:\\cygwin64")
  let context = @lib.Context::new(mounts=[root])
  assert_eq(
    context.convert("/usr/bin", from=Posix, to=Windows),
    "C:\\cygwin64\\usr\\bin",
  )
  let aliased = @lib.Context::new(mounts=[
    root,
    @lib.Mount::new("/usr/bin", "C:\\cygwin64\\bin"),
  ])
  assert_eq(
    aliased.convert("/usr/bin", from=Posix, to=Windows),
    "C:\\cygwin64\\bin",
  )
  assert_eq(
    aliased.convert(
      "C:\\cygwin64\\bin",
      from=Windows,
      to=Posix,
      unix_prefix=ProcCygdrive,
    ),
    "/usr/bin",
  )
  assert_eq(
    context.convert("/devil/a", from=Posix, to=Windows),
    "C:\\cygwin64\\devil\\a",
  )
}

///|
test "mount matching prefers the longest complete component prefix" {
  let context = @lib.Context::new(mounts=[
    @lib.Mount::new("/", "C:\\root"),
    @lib.Mount::new("/usr", "D:\\tools"),
    @lib.Mount::new("/usr/bin", "E:\\bin"),
    @lib.Mount::new("/work", "C:\\work"),
  ])
  assert_eq(context.convert("/usr/bin/a", from=Posix, to=Windows), "E:\\bin\\a")
  assert_eq(
    context.convert("/usr/lib/a", from=Posix, to=Windows),
    "D:\\tools\\lib\\a",
  )
  assert_eq(
    context.convert("/usr2/a", from=Posix, to=Windows),
    "C:\\root\\usr2\\a",
  )
  assert_eq(context.convert("C:\\work\\a", from=Windows, to=Posix), "/work/a")
  assert_eq(
    context.convert("C:\\workspace\\a", from=Windows, to=Posix),
    "/cygdrive/c/workspace/a",
  )
  assert_eq(context.convert("D:\\tools\\a", from=Windows, to=Posix), "/usr/a")
}

///|
test "reverse aliases retain declaration order while longer targets still win" {
  let first = @lib.Mount::new("/first", "C:\\shared")
  let second = @lib.Mount::new("/second", "C:\\shared")
  let deep = @lib.Mount::new("/deep", "C:\\shared\\nested")
  let context = @lib.Context::new(mounts=[first, second, deep])
  assert_eq(
    context.convert("C:\\shared\\a", from=Windows, to=Posix),
    "/first/a",
  )
  assert_eq(
    context.convert("C:\\shared\\nested\\a", from=Windows, to=Posix),
    "/deep/a",
  )
  assert_eq(
    context.convert("/second/a", from=Posix, to=Windows),
    "C:\\shared\\a",
  )
  let reversed = @lib.Context::new(mounts=[second, deep, first])
  assert_eq(
    reversed.convert("C:\\shared\\a", from=Windows, to=Posix),
    "/second/a",
  )
  assert_eq(
    reversed.convert("C:\\shared\\nested\\a", from=Windows, to=Posix),
    "/deep/a",
  )
}

///|
test "mount comparison policies fold only ASCII and preserve remaining case" {
  let sensitive = @lib.Context::new(mounts=[
    @lib.Mount::new("/work", "C:\\Work"),
  ])
  assert_eq(
    sensitive.convert("c:\\Work\\File", from=Windows, to=Posix),
    "/work/File",
  )
  assert_eq(
    sensitive.convert("C:\\work\\File", from=Windows, to=Posix),
    "/cygdrive/c/work/File",
  )
  let insensitive = @lib.Context::new(mounts=[
    @lib.Mount::new("/Tools", "C:\\Work", case=AsciiInsensitive),
    @lib.Mount::new("/unicode", "D:\\Ä", case=AsciiInsensitive),
  ])
  assert_eq(
    insensitive.convert("/tools/File", from=Posix, to=Windows),
    "C:\\Work\\File",
  )
  assert_eq(
    insensitive.convert("c:\\WORK\\File", from=Windows, to=Posix),
    "/Tools/File",
  )
  assert_eq(
    insensitive.convert("D:\\ä\\File", from=Windows, to=Posix),
    "/cygdrive/d/ä/File",
  )
}

///|
test "UNC mounts match server share and component boundaries under their policy" {
  let context = @lib.Context::new(mounts=[
    @lib.Mount::new(
      "/network",
      "\\\\Server\\Share\\base",
      case=AsciiInsensitive,
    ),
  ])
  assert_eq(
    context.convert("/network/a", from=Posix, to=Windows),
    "\\\\Server\\Share\\base\\a",
  )
  assert_eq(
    context.convert("\\\\server\\share\\BASE\\a", from=Windows, to=Posix),
    "/network/a",
  )
  assert_eq(
    context.convert("\\\\server\\share\\base2\\a", from=Windows, to=Posix),
    "//server/share/base2/a",
  )
  assert_eq(
    context.convert("\\\\server\\share2\\base\\a", from=Windows, to=Posix),
    "//server/share2/base/a",
  )
}

///|
test "profiles and custom drive prefixes are explicit" {
  let cygwin = @lib.Context::new()
  let msys = @lib.Context::new(profile=Msys2)
  let custom = @lib.Context::new(drive_prefix="/drives/")
  assert_eq(msys.convert("/c/a", from=Posix, to=Windows), "C:\\a")
  assert_eq(msys.convert("C:\\a", from=Windows, to=Posix), "/c/a")
  assert_eq(custom.convert("C:\\a", from=Windows, to=Posix), "/drives/c/a")
  assert_eq(custom.convert("/drives/d/a", from=Posix, to=Mixed), "D:/a")
  assert_eq(custom.convert("/proc/cygdrive/d/a", from=Posix, to=Mixed), "D:/a")
  assert_eq(
    msys.convert("C:\\a", from=Windows, to=Posix, unix_prefix=ProcCygdrive),
    "/proc/cygdrive/c/a",
  )
  for path in ["/c/a", "/mnt/c/a"] {
    assert_true(
      conversion_error(() => cygwin.convert(path, from=Posix, to=Windows))
      is @lib.MissingContext(field="root or mount"),
    )
  }
  for path in ["/cygdrive", "/cygdrive/cc/a"] {
    assert_true(
      conversion_error(() => cygwin.convert(path, from=Posix, to=Windows))
      is @lib.InvalidPath(reason=_, offset=_),
    )
  }
}

///|
test "invalid mount paths and virtual namespaces are rejected at construction" {
  for
    posix in [
      "relative", "/a/./b", "/a/../b", "/dev", "/dev/null", "/proc/cygdrive/c",
    ] {
    assert_true(
      context_error(() => ignore(@lib.Mount::new(posix, "C:\\root")))
      is @lib.InvalidContext(field="mount.posix", reason=_),
    )
  }
  for
    windows in [
      "relative", "C:root", "\\root", "C:\\a\\..\\b", "//server", "\\\\?\\GLOBALROOT\\Device",
    ] {
    assert_true(
      context_error(() => ignore(@lib.Mount::new("/root", windows)))
      is @lib.InvalidContext(field="mount.windows", reason=_),
    )
  }
  let normalized = @lib.Context::new(mounts=[
    @lib.Mount::new("/root/", "C:\\root\\"),
  ])
  assert_eq(
    normalized.convert("/root/a", from=Posix, to=Windows),
    "C:\\root\\a",
  )
}

///|
test "invalid prefixes duplicate mounts and drive-subtree overlaps are rejected" {
  for
    prefix in [
      "relative", "/a/../b", "/a/./b", "/dev", "/proc", "/proc/cygdrive",
    ] {
    assert_true(
      context_error(() => ignore(@lib.Context::new(drive_prefix=prefix)))
      is @lib.InvalidContext(field="drive_prefix", reason=_),
    )
  }
  assert_true(
    context_error(() => {
      ignore(
        @lib.Context::new(mounts=[
          @lib.Mount::new("/same", "C:\\one"),
          @lib.Mount::new("/same/", "D:\\two"),
        ]),
      )
    })
    is @lib.InvalidContext(field="mounts[1]", reason=_),
  )
  for posix in ["/cygdrive", "/cygdrive/c", "/cygdrive/c/a"] {
    assert_true(
      context_error(() => {
        ignore(@lib.Context::new(mounts=[@lib.Mount::new(posix, "C:\\root")]))
      })
      is @lib.InvalidContext(field="mounts[0]", reason=_),
    )
  }
  for posix in ["/c", "/C/a"] {
    assert_true(
      context_error(() => {
        ignore(
          @lib.Context::new(drive_prefix="/", mounts=[
            @lib.Mount::new(posix, "D:\\root"),
          ]),
        )
      })
      is @lib.InvalidContext(field="mounts[0]", reason=_),
    )
  }
  let root_prefix = @lib.Context::new(drive_prefix="/", mounts=[
    @lib.Mount::new("/", "D:\\root"),
    @lib.Mount::new("/usr", "E:\\tools"),
  ])
  assert_eq(root_prefix.convert("/c/a", from=Posix, to=Windows), "C:\\a")
  assert_eq(
    root_prefix.convert("/usr/a", from=Posix, to=Windows),
    "E:\\tools\\a",
  )
  assert_eq(
    root_prefix.convert("/other/a", from=Posix, to=Windows),
    "D:\\root\\other\\a",
  )
}

///|
test "cwd validation is explicit and per-drive entries agree with their keys" {
  assert_true(
    context_error(() => ignore(@lib.Context::new(posix_cwd="relative")))
    is @lib.InvalidContext(field="posix_cwd", reason=_),
  )
  assert_true(
    context_error(() => ignore(@lib.Context::new(posix_cwd="/dev/null")))
    is @lib.InvalidContext(field="posix_cwd", reason=_),
  )
  for cwd in ["relative", "C:work", "\\work"] {
    assert_true(
      context_error(() => ignore(@lib.Context::new(windows_cwd=cwd)))
      is @lib.InvalidContext(field="windows_cwd", reason=_),
    )
  }
  for
    entries in [
      { "CC": "C:\\work" },
      { "1": "C:\\work" },
      { "C": "D:\\work" },
      { "C": "\\\\server\\share" },
      { "C": "C:\\work", "c": "C:\\other" },
    ] {
    assert_true(
      context_error(() => ignore(@lib.Context::new(drive_cwds=entries)))
      is @lib.InvalidContext(field=_, reason=_),
    )
  }
  let context = @lib.Context::new(posix_cwd="/cygdrive/c/a/../work", drive_cwds={
    "c": "c:\\a\\..\\work",
  })
  assert_eq(
    context.convert("a", from=Posix, to=Windows, absolute=true),
    "C:\\work\\a",
  )
  assert_eq(context.convert("C:a", from=Windows, to=Posix), "/cygdrive/c/a")
}

///|
test "context snapshots caller mounts and drive-relative paths ignore drive cwd" {
  let mounts = [@lib.Mount::new("/original", "C:\\root")]
  let drive_cwds = { "C": "C:\\before" }
  let context = @lib.Context::new(mounts~, drive_cwds~)
  mounts[0] = @lib.Mount::new("/changed", "D:\\root")
  mounts.push(@lib.Mount::new("/later", "C:\\root"))
  drive_cwds["C"] = "C:\\after"
  drive_cwds["D"] = "D:\\later"
  assert_eq(
    context.convert("/original/a", from=Posix, to=Windows),
    "C:\\root\\a",
  )
  assert_eq(
    context.convert("C:\\root\\a", from=Windows, to=Posix),
    "/original/a",
  )
  assert_eq(context.convert("C:a", from=Windows, to=Posix), "/cygdrive/c/a")
  assert_eq(context.convert("D:a", from=Windows, to=Posix), "/cygdrive/d/a")
}

///|
test "adding an unrelated mount does not change unmatched conversions" {
  let base = @lib.Context::new(mounts=[@lib.Mount::new("/work", "C:\\work")])
  let extended = @lib.Context::new(mounts=[
    @lib.Mount::new("/unrelated", "E:\\unrelated"),
    @lib.Mount::new("/work", "C:\\work"),
  ])
  for path in ["C:\\work\\a", "D:\\other", "\\\\server\\share\\a"] {
    assert_eq(
      base.convert(path, from=Windows, to=Posix),
      extended.convert(path, from=Windows, to=Posix),
    )
  }
}
