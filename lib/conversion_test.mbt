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
test "fixed proc paths preserve virtual names and distinguish missing entries" {
  let context = @lib.Context::new(posix_cwd="/proc", mounts=[
    @lib.Mount::new("/", "C:/root"),
  ])
  for
    entry in [
      "codesets", "cpuinfo", "devices", "filesystems", "loadavg", "locales", "meminfo",
      "misc", "partitions", "stat", "swaps", "uptime", "version",
    ] {
    let name = "/proc/" + entry
    assert_eq(context.convert(name, from=Posix, to=Windows), name)
    assert_eq(context.convert(entry, from=Posix, to=Windows), entry)
    assert_eq(
      context.convert(entry, from=Posix, to=Windows, absolute=true),
      name,
    )
  }
  assert_eq(
    context.convert("../outside", from=Posix, to=Mixed),
    "C:/root/outside",
  )
  assert_eq(context.convert("net/.", from=Posix, to=Windows), "net\\")
  assert_eq(context.convert("/proc/net/..", from=Posix, to=Mixed), "/proc/")
  assert_eq(
    context.convert("/proc/net/..", from=Posix, to=Windows, absolute=true),
    "/proc",
  )
  let hive = "/proc/registry64/hkey_current_user"
  assert_eq(context.convert(hive, from=Posix, to=Windows), hive)
  for name in ["/proc/version/.", "/proc/uptime/", "/proc/stat/../version"] {
    assert_true(
      conversion_error(() => context.convert(name, from=Posix, to=Windows))
      is @lib.NotDirectory,
    )
  }
  for
    name in [
      "/proc/VERSION", "/proc/version/child", "/proc/absent/../version", "/proc/net/absent",
    ] {
    assert_true(
      conversion_error(() => context.convert(name, from=Posix, to=Windows))
      is @lib.PathNotFound,
    )
  }
  for
    name in [
      "/proc/123/fd/1",
      "/proc/self/../version",
      "/proc/net/if_inet6",
      "/proc/sysvipc/sem",
      hive + "/Software",
    ] {
    assert_true(
      conversion_error(() => context.convert(name, from=Posix, to=Windows))
      is @lib.UnsupportedNamespace(_),
    )
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
  assert_eq(context.convert("/a", from=Windows, to=Posix), "/a")
  assert_eq(context.convert("/a", from=Posix, to=Windows), "C:\\root\\a")
  assert_eq(context.convert("C:/a\\b", from=Windows, to=Mixed), "C:/a/b")
  assert_eq(context.convert("a\\b", from=Posix, to=Posix), "a\\b")
  assert_true(
    conversion_error(() => context.convert("a\\b", from=Posix, to=Windows))
    is @lib.UnrepresentablePath(component="a\\b", reason=_),
  )
  assert_eq(context.convert("C:/a", from=Posix, to=Windows), "C\uF03A\\a")
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
    "//server/b/",
  )
  assert_eq(context.convert("C:\\", from=Windows, to=Windows), "C:\\")
  assert_eq(
    context.convert("//server/share", from=Posix, to=Windows),
    "\\\\server\\share",
  )
  assert_eq(context.convert("./", from=Posix, to=Windows), ".\\")
  assert_eq(context.convert("../", from=Posix, to=Windows), "..\\")
}

///|
test "POSIX root mapping distinguishes structural and optional separators" {
  for profile in [@lib.Cygwin, @lib.Msys2] {
    let directory = @lib.Context::new(profile~, mounts=[
      @lib.Mount::new("/", "C:\\root"),
    ])
    assert_eq(
      directory.convert("/", from=Posix, to=Windows),
      if profile == Msys2 {
        "C:\\root\\"
      } else {
        "C:\\root"
      },
    )
    assert_eq(
      directory.convert("/", from=Posix, to=Mixed),
      if profile == Msys2 {
        "C:/root/"
      } else {
        "C:/root"
      },
    )
    assert_eq(directory.convert("/", from=Posix, to=Posix), "/")
    for input in ["/folder/", "/folder//"] {
      assert_eq(
        directory.convert(input, from=Posix, to=Windows),
        "C:\\root\\folder\\",
      )
    }
    for input in ["/folder/../", "/folder//..//"] {
      assert_eq(directory.convert(input, from=Posix, to=Windows), "C:\\root\\")
    }
    for
      (target, windows, mixed) in [
        ("C:\\", "C:\\", "C:/"),
        (
          "//server/share",
          if profile == Msys2 {
            "\\\\server\\share\\"
          } else {
            "\\\\server\\share"
          },
          if profile == Msys2 {
            "//server/share/"
          } else {
            "//server/share"
          },
        ),
      ] {
      let root = @lib.Context::new(profile~, mounts=[
        @lib.Mount::new("/", target),
      ])
      assert_eq(root.convert("/", from=Posix, to=Windows), windows)
      assert_eq(root.convert("/", from=Posix, to=Mixed), mixed)
    }
  }
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
test "drive-relative conversion follows Cygwin root anchoring" {
  let empty = @lib.Context::new()
  assert_eq(empty.convert("c:a", from=Windows, to=Mixed), "C:a")
  assert_eq(empty.convert("c:", from=Windows, to=Windows), "C:")
  assert_eq(empty.convert("\\a", from=Windows, to=Mixed), "/a")
  assert_eq(empty.convert("C:a", from=Windows, to=Posix), "C:a")
  assert_eq(empty.convert("c:a/../b", from=Windows, to=Posix), "c:a/../b")
  assert_eq(
    empty.convert("C:a", from=Windows, to=Posix, absolute=true),
    "/cygdrive/c/a",
  )
  assert_true(
    conversion_error(() => empty.convert("\\a", from=Windows, to=Posix))
    is @lib.MissingContext(field="windows_cwd drive"),
  )
  let context = @lib.Context::new(windows_cwd="C:\\fallback", drive_cwds={
    "c": "C:\\work",
    "D": "D:\\other",
  })
  assert_eq(context.convert("C:a", from=Windows, to=Posix), "C:a")
  assert_eq(context.convert("C:", from=Windows, to=Posix), "/cygdrive/c")
  assert_eq(
    context.convert("D:../a", from=Windows, to=Windows, absolute=true),
    "D:\\a",
  )
  assert_eq(context.convert("\\a", from=Windows, to=Posix), "/cygdrive/c/a")
  let fallback = @lib.Context::new(windows_cwd="C:\\fallback")
  assert_eq(fallback.convert("c:a", from=Windows, to=Posix), "c:a")
  assert_eq(fallback.convert("D:a", from=Windows, to=Posix), "D:a")
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
  assert_eq(context.convert("C:a", from=Windows, to=Posix), "C:a")
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
test "Windows filename output encodes punctuation and preserves ordinary names" {
  let context = @lib.Context::new()
  for component in ["a\\b"] {
    let error = conversion_error(() => {
      context.convert(component, from=Posix, to=Windows)
    })
    assert_true(
      error is @lib.UnrepresentablePath(component=actual, reason=_) &&
      actual == component,
    )
  }
  for
    component in [
      "COM0", "COM10", "LPT10", "CONSOLE", ".hidden", "a;b", "name.", "name ", "CON",
      "con.txt", "COM1",
    ] {
    assert_eq(context.convert(component, from=Posix, to=Windows), component)
  }
}

///|
test "null-backed devices use the observed NT object before CLI alias lookup" {
  let present = @lib.Context::new(nt_null=true, posix_cwd="/dev")
  let missing = @lib.Context::new(nt_null=false)
  for
    name in [
      "null", "zero", "full", "random", "urandom", "windows", "mixer", "dsp", "clipboard",
    ] {
    let path = "/dev/" + name
    assert_eq(
      present.convert(name, from=Posix, to=Windows),
      "\\\\.\\GLOBALROOT\\Device\\Null",
    )
    assert_eq(
      present.convert(path, from=Posix, to=Mixed),
      "//./GLOBALROOT/Device/Null",
    )
    assert_eq(present.convert(path, from=Posix, to=Posix), path)
    assert_true(
      present.mode_candidate(path, from=Posix) is NullDevice(native_input=x) &&
      x == (name == "null"),
    )
    assert_true(
      conversion_error(() => missing.convert(path, from=Posix, to=Windows))
      is NoSuchDeviceOrAddress,
    )
    assert_true(
      conversion_error(() => present.convert(path + "/", from=Posix, to=Windows))
      is NotDirectory,
    )
  }
  assert_true(
    conversion_error(() => {
      missing.convert("/dev/null/../x", from=Posix, to=Windows)
    })
    is PathNotFound,
  )
}

///|
test "namespace handling is explicit and does not masquerade as disk paths" {
  let context = @lib.Context::new(mounts=[@lib.Mount::new("/", "C:\\root")])
  assert_true(
    conversion_error(() => {
      context.convert(
        "\\\\?\\GLOBALROOT\\Device\\Harddisk0",
        from=Windows,
        to=Posix,
      )
    })
    is @lib.MissingContext(field="windows_cwd drive"),
  )
  assert_eq(context.convert("\\\\.\\COM1", from=Windows, to=Posix), "//./COM1")
  assert_eq(context.convert("//server", from=Windows, to=Posix), "//server")
  assert_true(
    conversion_error(() => context.convert("/proc/self", from=Posix, to=Windows))
    is @lib.UnsupportedNamespace(_),
  )
  assert_true(
    conversion_error(() => context.convert("/dev/null", from=Posix, to=Windows))
    is @lib.MissingContext(field="nt_null"),
  )
  assert_eq(
    context.convert("/proc/cygdrive", from=Posix, to=Windows),
    "C:\\root\\cygdrive",
  )
  assert_true(
    conversion_error(() => {
      context.convert("/proc/cygdrive/cc/a", from=Posix, to=Windows)
    })
    is @lib.InvalidDrivePrefix,
  )
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
    "/cygdrive/c:/cygdrive/d/a:/cygdrive/c",
  )
  assert_eq(context.convert_list("a:b:a", from=Posix, to=Windows), "a;b;a")
  assert_eq(
    context.convert_list("C:\\a;D:\\b", from=Windows, to=Mixed),
    "C:/a;D:/b",
  )
  assert_eq(
    context.convert_list("\"C:\\a\"", from=Windows, to=Posix),
    "\"C:/a\"",
  )
}

///|
test "list errors retain the original index and output delimiters follow cygpath" {
  let context = @lib.Context::new()
  assert_true(
    conversion_error(() => {
      context.convert_list(";C:\\ok;;\\??\\GLOBALROOT", from=Windows, to=Posix)
    })
    is @lib.ListEntryError(index=3, @lib.InvalidWindowsPrefix),
  )
  assert_eq(context.convert("a;b", from=Posix, to=Windows), "a;b")
  assert_eq(context.convert_list("ok:a;b", from=Posix, to=Windows), "ok;a;b")
  let colon_mount = @lib.Context::new(mounts=[
    @lib.Mount::new("/a:b", "C:\\work"),
  ])
  assert_eq(colon_mount.convert("C:\\work", from=Windows, to=Posix), "/a:b")
  assert_eq(
    colon_mount.convert_list(";C:\\work", from=Windows, to=Posix),
    "/a:b",
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
