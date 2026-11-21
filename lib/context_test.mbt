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
test "bind mapping selects the source mount before native normalization" {
  let context = @lib.Context::new(mounts=[
    @lib.Mount::new("/", "C:/"),
    @lib.Mount::new("/src", "D:/nested/tree"),
  ])
  assert_eq(
    context.resolve_bind_source("/src/../out"),
    ("D:\\nested\\out", Some(1)),
  )
  assert_eq(
    context.resolve_bind_source("//server/share"),
    ("\\\\server\\share", None),
  )
  assert_eq(context.resolve_bind_source("/cygdrive/z"), ("Z:\\", None))
  let at_limit = "/" + "é".repeat(128)
  assert_eq(context.resolve_bind_source(at_limit).0, "C:\\" + "é".repeat(128))
  assert_true(
    context_error(() => ignore(context.resolve_bind_source(at_limit + "x")))
    is PathTooLong(_),
  )
  assert_true(
    context_error(() => ignore(context.resolve_bind_source("relative")))
    is InvalidOptions(_),
  )
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
test "eight installed system aliases use the Cygwin runtime's pivot on a native-name tie" {
  let mounts = Array::makei(8, i => {
    @lib.Mount::new("/m\{i}", "D:/same", system=true)
  })
  let context = @lib.Context::new(mounts~)
  assert_eq(context.convert("D:/same/leaf", from=Windows, to=Posix), "/m4/leaf")
}

///|
test "sensitive and ASCII-insensitive mount policies preserve remaining case" {
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
test "Windows mount case matches UTF-16 units at a UTF-8 prefix boundary" {
  for profile in [@lib.Cygwin, @lib.Msys2] {
    let context = @lib.Context::new(profile~, drive_prefix="/vol", mounts=[
      @lib.Mount::new("/ÄΣ", "D:/ÄΣ", case=WindowsInsensitive),
      @lib.Mount::new("/wide", "//Ɐ/share/ɐ", case=WindowsInsensitive),
      @lib.Mount::new("/short", "E:/ɐ", case=WindowsInsensitive),
      @lib.Mount::new("/deseret", "F:/𐐀", case=WindowsInsensitive),
    ])
    assert_eq(
      context.convert("/äσ/MiXeD", from=Posix, to=Mixed),
      "D:/ÄΣ/MiXeD",
    )
    assert_eq(
      context.convert("D:/äσ/File", from=Windows, to=Posix),
      "/ÄΣ/File",
    )
    for input in ["äς", "äσx", "A\u{308}σ"] {
      assert_eq(
        context.convert("D:/" + input, from=Windows, to=Posix),
        "/vol/d/" + input,
      )
    }
    assert_eq(
      context.convert("E:/Ɐ/File", from=Windows, to=Posix),
      "/vol/e/Ɐ/File",
    )
    assert_eq(
      context.convert("//ɐ/share/Ɐ/File", from=Windows, to=Posix),
      "/wide/File",
    )
    assert_eq(
      context.convert("F:/𐐨/File", from=Windows, to=Posix),
      "/vol/f/𐐨/File",
    )
  }
  let context = @lib.Context::new(mounts=[
    @lib.Mount::new("/alias1", "D:/é", case=WindowsInsensitive),
    @lib.Mount::new("/alias2", "D:/É", case=WindowsInsensitive),
    @lib.Mount::new("/deep", "D:/é/nested", case=WindowsInsensitive),
  ])
  assert_eq(context.convert("D:/É", from=Windows, to=Posix), "/alias1")
  assert_eq(context.convert("D:/É/NESTED", from=Windows, to=Posix), "/deep")
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
test "proc cygdrive follows the configured prefix before parent traversal" {
  let mounts = [
    @lib.Mount::new("/", "C:/root"),
    @lib.Mount::new("/media", "D:/data", text_mode=true),
  ]
  let context = @lib.Context::new(
    drive_prefix="/media/drives",
    mounts~,
    posix_cwd="/proc",
  )
  for path in ["/media/drives", "/proc/cygdrive", "cygdrive"] {
    assert_eq(context.convert(path, from=Posix, to=Mixed), "D:/data/drives")
    assert_true(
      context.mode_candidate(path, from=Posix) is Virtual(directory=true),
    )
  }
  assert_eq(
    context.convert("/proc/cygdrive/.", from=Posix, to=Mixed),
    "D:/data/drives/",
  )
  assert_eq(
    context.convert("/proc/cygdrive/", from=Posix, to=Mixed, absolute=true),
    "D:/data/drives",
  )
  assert_eq(
    context.convert("/proc/cygdrive/../sibling", from=Posix, to=Mixed),
    "D:/data/sibling",
  )
  assert_eq(
    context.convert("/proc/cygdrive/d/archive", from=Posix, to=Mixed),
    "D:/archive",
  )
  assert_eq(
    context.convert("/proc/cygdrive/d", from=Windows, to=Posix),
    "/proc/cygdrive/d",
  )
  assert_true(
    conversion_error(() => {
      context.convert("/proc/cygdrive/bad/../d", from=Posix, to=Mixed)
    })
    is @lib.InvalidDrivePrefix,
  )
  let root_prefix = @lib.Context::new(drive_prefix="/", mounts~)
  assert_eq(
    root_prefix.convert("/proc/cygdrive/media/file", from=Posix, to=Mixed),
    "D:/data/file",
  )
  assert_eq(
    root_prefix.convert("/proc/cygdrive/proc/version", from=Posix, to=Windows),
    "/proc/version",
  )
  let links = "/proc/cygdrive".repeat(10)
  assert_eq(
    root_prefix.convert(links + "/leaf", from=Posix, to=Mixed),
    "C:/root/leaf",
  )
  assert_true(
    conversion_error(() => {
      root_prefix.convert(links + "/proc/cygdrive", from=Posix, to=Windows)
    })
    is @lib.TooManyLinks,
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
  assert_true(
    conversion_error(() => cygwin.convert("/cygdrive", from=Posix, to=Windows))
    is @lib.MissingContext(field="root or mount"),
  )
  assert_true(
    conversion_error(() => {
      cygwin.convert("/cygdrive/cc/a", from=Posix, to=Windows)
    })
    is @lib.InvalidDrivePrefix,
  )
}

///|
test "invalid mount paths and virtual namespaces are rejected at construction" {
  for
    posix in [
      "relative", "/a/./b", "/a/../b", "/dev/null", "/dev/disk/by-id", "/proc/cygdrive/c",
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
test "physical dev entries follow mounts and preserve exact device name boundaries" {
  let ctx = @lib.Context::new(posix_cwd="/dev/local", mounts=[
    @lib.Mount::new("/", "C:/install"),
    @lib.Mount::new("/dev/local", "D:/files"),
  ])
  assert_eq(
    ctx.convert("leaf", from=Posix, to=Mixed, absolute=true),
    "D:/files/leaf",
  )
  for
    name in [
      "shm2", "diskette", "ttyS128", "ttyS00", "com0", "com17", "pty01", "st128",
      "fd16", "sr16", "scd16", "sddy", "sddx64", "sdz0", "sda01", "NULL", "ttyS１",
    ] {
    assert_eq(
      ctx.convert("/dev/" + name, from=Posix, to=Mixed),
      "C:/install/dev/" + name,
    )
  }
  for
    name in [
      "disk/by-id", "ttyS0", "ttyS127", "cons127", "com1", "com16", "pty127", "nst127",
      "fd0", "sr15", "scd15", "sda", "sdz9", "sdcz63", "sddx63", "stdin",
    ] {
    assert_true(
      context_error(() => {
        ignore(ctx.convert("/dev/" + name + "/../local", from=Posix, to=Mixed))
      })
      is @lib.UnsupportedNamespace(_),
    )
  }
}

///|
test "invalid prefixes duplicate mounts and drive-subtree overlaps are rejected" {
  let user = @lib.Mount::new("/same", "D:/user", system=false)
  let system = @lib.Mount::new("/same", "S:/sys", system=true)
  let plain = @lib.Mount::new("/same", "C:/explicit")
  for
    mounts in [
      [user, user],
      [plain, system],
      [system, plain],
      [user, system, user],
    ] {
    assert_true(
      context_error(() => ignore(@lib.Context::new(mounts~)))
      is InvalidContext(_),
    )
  }
  for
    prefix in [
      "relative", "/a/../b", "/a/./b", "/dev/disk", "/proc", "/proc/cygdrive",
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
  assert_eq(context.convert("C:a", from=Windows, to=Posix), "C:a")
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
  assert_eq(context.convert("C:a", from=Windows, to=Posix), "C:a")
  assert_eq(context.convert("D:a", from=Windows, to=Posix), "D:a")
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

///|
test "DOS mounts encode filename edges for conversion and filesystem lookup" {
  let ctx = @lib.Context::new(
    mounts=[@lib.Mount::new("/dos", "D:/work", dos_names=true)],
    drive_dos_names=true,
    posix_cwd="/dos",
    windows_cwd="D:/work",
  )
  assert_eq(
    ctx.convert("/dos/ a. / b.", from=Posix, to=Mixed),
    "D:/work/\uF020a\uF02E\uF020/\uF020b\uF02E",
  )
  assert_eq(ctx.convert(" a. / b.", from=Posix, to=Mixed), " a. / b\uF02E")
  assert_eq(
    ctx.convert("/cygdrive/d/work/name.", from=Posix, to=Mixed),
    "D:/work/name\uF02E",
  )
  assert_eq(
    ctx.convert("D:/work/name.", from=Windows, to=Mixed),
    "D:/work/name.",
  )
  assert_true(
    ctx.mode_candidate("/dos/records.", from=Posix)
    is Filesystem("D:\\work\\records\uF02E", text_mode=false),
  )
}

///|
test "text mount flags follow the selected path spelling, not a reverse alias" {
  let context = @lib.Context::new(
    mounts=[
      @lib.Mount::new("/", "C:/cygwin"),
      @lib.Mount::new("/txt", "D:/work", text_mode=true),
    ],
    drive_text_mode=true,
  )
  assert_true(
    context.mode_candidate("/txt/file", from=Posix)
    is Filesystem(_, text_mode=true),
  )
  assert_true(
    context.mode_candidate("D:/work/file", from=Windows)
    is Filesystem(_, text_mode=false),
  )
  assert_true(
    context.mode_candidate("/cygdrive/e/file", from=Posix)
    is Filesystem(_, text_mode=true),
  )
  assert_true(
    context.mode_candidate("//files/share/a", from=Windows)
    is Filesystem(_, text_mode=true),
  )
  assert_true(
    context.mode_candidate("/file", from=Posix)
    is Filesystem(_, text_mode=false),
  )
}

///|
test "native cwd comparison respects drive and UNC roots and the byte boundary" {
  let drive = @lib.Context::new(windows_cwd="D:/É/Σ")
  assert_eq(
    drive.relative_windows_name("/cygdrive/d/é/σ/TaIl", from=Posix),
    Some("TaIl"),
  )
  assert_eq(
    drive.relative_windows_name("/cygdrive/d/é/ς/TaIl", from=Posix),
    None,
  )
  assert_eq(
    drive.relative_windows_name("/cygdrive/e/É/Σ/TaIl", from=Posix),
    None,
  )
  let sensitive = @lib.Context::new(windows_cwd="D:/É", drive_case=Sensitive)
  assert_eq(sensitive.relative_windows_name("/cygdrive/d/é", from=Posix), None)
  let unc = @lib.Context::new(windows_cwd="//SERVER/Share/Dir")
  assert_eq(
    unc.relative_windows_name("//server/share/dir/Keep", from=Windows),
    Some("Keep"),
  )
  assert_eq(
    unc.relative_windows_name("//server/shared/dir/Keep", from=Windows),
    None,
  )
  let width = @lib.Context::new(windows_cwd="D:/Ɐ")
  assert_eq(width.relative_windows_name("/cygdrive/d/ɐ/x", from=Posix), None)
}
