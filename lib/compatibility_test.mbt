///|
test "ordinary extended namespaces retain ordinary drive and UNC semantics" {
  let context = @lib.Context::new()
  for path in ["\\\\?\\C:\\name", "\\??\\C:\\name", "//?/C:/name"] {
    assert_eq(context.convert(path, from=Windows, to=Posix), "/cygdrive/c/name")
    assert_eq(context.convert(path, from=Windows, to=Windows), "C:\\name")
  }
  for
    (path, posix) in [
      ("\\\\?\\UNC\\server\\share\\name", "//server/share/name"),
      ("\\??\\UNC\\server\\share\\name", "/??/UNC/server/share/name"),
    ] {
    assert_eq(context.convert(path, from=Windows, to=Posix), posix)
    assert_eq(
      context.convert(path, from=Windows, to=Mixed),
      "//server/share/name",
    )
  }
}

///|
test "unmatched Windows UNC spelling preserves traversal and terminal separators" {
  let context = @lib.Context::new()
  for
    name in [
      "//server/share", "//server/share/", "//server/share/../file", "//server/share/a/../b",
      "//server/share/./a", "//server/share//a",
    ] {
    assert_eq(context.convert(name, from=Windows, to=Posix), name)
    assert_eq(
      context.convert(
        name.replace_all(old="/", new="\\"),
        from=Windows,
        to=Posix,
      ),
      name,
    )
  }
  let mounted = @lib.Context::new(mounts=[
    @lib.Mount::new("/net", "//server/share"),
  ])
  assert_eq(
    mounted.convert("//server/share/a/../b", from=Windows, to=Posix),
    "/net/b",
  )
  for
    name in [
      "//server/else/../share/b", "//other/../server//share/b", "\\\\?\\UNC\\server\\share\\b",
      "\\??\\UNC\\server\\share\\b",
    ] {
    assert_eq(mounted.convert(name, from=Windows, to=Posix), "/net/b")
  }
  for
    (name, expected) in [
      ("//server/share/.", "/net"),
      ("//server/share/a/b/..", "/net/a/"),
      ("//server/share/a/../", "/net/"),
      ("//server/other/../miss", "//server/other/../miss"),
    ] {
    assert_eq(mounted.convert(name, from=Windows, to=Posix), expected)
  }
  assert_eq(
    mounted.convert_list(
      "\\\\?\\UNC\\server\\miss;\\\\?\\UNC\\server\\share\\ok",
      from=Windows,
      to=Posix,
    ),
    "//?/UNC/server/miss:/net/ok",
  )
  let cwd = @lib.Context::new(windows_cwd="//server/old/base", mounts=[
    @lib.Mount::new("/net", "//server/share"),
  ])
  assert_eq(
    cwd.convert("../../share/ok", from=Windows, to=Posix, absolute=true),
    "/net/ok",
  )
  assert_eq(
    cwd.convert("../../miss/ok", from=Windows, to=Posix, absolute=true),
    "../../miss/ok",
  )
}

///|
test "Windows lookup distinguishes terminal dot normalization from explicit separators" {
  let context = @lib.Context::new(windows_cwd="D:/work", mounts=[
    @lib.Mount::new("/", "C:/root"),
  ])
  for
    (name, output) in [
      ("C:/root/", "//"),
      ("C:/root/.", "/"),
      ("C:/root/d/.", "/d/"),
      ("D:/work/x/..", "/cygdrive/d/work/"),
      ("D:/x/..", "/cygdrive/d"),
      ("///x", "///x"),
      ("\\\\\\x", "/cygdrive/d/x"),
    ] {
    assert_eq(context.convert(name, from=Windows, to=Posix), output)
  }
  let msys = @lib.Context::new(profile=Msys2, mounts=[
    @lib.Mount::new("/", "C:/root"),
  ])
  assert_eq(msys.convert("C:/root/", from=Windows, to=Posix), "/")
}

///|
test "Windows to POSIX keeps non-NUL filename characters and relative spelling" {
  let context = @lib.Context::new()
  for
    name in [
      "CON", "a:b", "trail.", "a b ", "line\nbreak", "line\rbreak", "a*?<>|\"b",
    ] {
    assert_eq(
      context.convert("C:/" + name, from=Windows, to=Posix),
      "/cygdrive/c/" + name,
    )
  }
  assert_eq(context.convert("a\\\\.\\b", from=Windows, to=Posix), "a//./b")
}

///|
test "filename private-use encoding is reversible without changing Unicode names" {
  let context = @lib.Context::new()
  let plain = "\"*:<>?|\u0001\t\r\n"
  let encoded = "\uF022\uF02A\uF03A\uF03C\uF03E\uF03F\uF07C\uF001\uF009\uF00D\uF00A"
  assert_eq(
    context.convert("/cygdrive/c/" + plain, from=Posix, to=Windows),
    "C:\\" + encoded,
  )
  assert_eq(
    context.convert("C:/" + encoded, from=Windows, to=Posix),
    "/cygdrive/c/" + plain,
  )
  assert_eq(
    context.convert("C:/\uF020\uF02E\uF041😀", from=Windows, to=Posix),
    "/cygdrive/c/ .\uF041😀",
  )
  assert_eq(
    context.convert("C:/" + plain, from=Windows, to=Mixed),
    "C:/" + encoded,
  )
  assert_eq(
    context.convert("C:/parent/\uF02E\uF02E/file", from=Windows, to=Posix),
    "/cygdrive/c/file",
  )
}

///|
test "Windows filename bytes survive mount matching, fallback and list conversion" {
  let context = @lib.Context::new(mounts=[
    @lib.Mount::new("/\uF0FF", "D:/é", case=WindowsInsensitive),
  ])
  assert_eq(
    context.windows_to_posix_bytes("D:/\uF0C3\uF089/\uF0FF"),
    b"/\xef\x83\xbf/\xff",
  )
  assert_eq(
    context.convert("D:/\uF0C3\uF0A9", from=Windows, to=Posix),
    "/\uF0FF",
  )
  assert_eq(
    context.windows_to_posix_bytes(
      ";\uF080;;//server/x/\uF0FE;D:/é;",
      list=true,
    ),
    b"\x80://server/x/\xfe:/\xef\x83\xbf",
  )
  assert_eq(
    context.convert("C:/\uF0FF/../x", from=Windows, to=Posix),
    "/cygdrive/c/x",
  )
  assert_eq(
    context.windows_to_posix_bytes(
      "\uF0EF\uF083\uF0BF\uF0C0\uF080\uF0ED\uF0A0\uF080\uF0F0\uF09F\uF098\uF080",
    ),
    b"\xef\x83\xbf\xc0\x80\xed\xa0\x80\xf0\x9f\x98\x80",
  )
  try context.convert_list("ok;;\uF0FF", from=Windows, to=Posix) catch {
    @lib.ListEntryError(
      index=2,
      @lib.UnrepresentablePath(component="\uF0FF", ..),
    ) => ()
    error => raise error
  } noraise {
    _ => fail("invalid UTF-8 returned as text")
  }
}

///|
test "CESU-8 pairs retain narrow mount boundaries and render as a single scalar" {
  let context = @lib.Context::new(mounts=[
    @lib.Mount::new("/", "C:/root"),
    @lib.Mount::new("/😀", "D:/canonical", case=WindowsInsensitive),
    @lib.Mount::new("/ⱯⱯ/😀", "E:/balanced", case=WindowsInsensitive),
  ])
  let pair = b"\xed\xa0\xbd\xed\xb8\x80"
  assert_eq(context.convert(b"/" + pair, from=Posix, to=Mixed), "C:/root/😀")
  assert_eq(context.convert("/😀", from=Posix, to=Mixed), "D:/canonical")
  assert_eq(
    context.convert(b"/\xc9\x90\xc9\x90/" + pair, from=Posix, to=Mixed),
    "E:/balanced",
  )
  assert_eq(
    context.convert(b"D:/name" + pair, from=Windows, to=Posix),
    "/cygdrive/d/name😀",
  )
  // Six actual byte escapes in a Windows filename still reach stdout unchanged.
  assert_eq(
    context.windows_to_posix_bytes("\uF0ED\uF0A0\uF0BD\uF0ED\uF0B8\uF080"),
    pair,
  )
  for isolated in [b"\xed\xa0\xbd", b"\xed\xb8\x80", pair + b"\xed\xb0\x80"] {
    try context.convert(isolated, from=Posix, to=Mixed) catch {
      @lib.UnrepresentablePath(..) => ()
      err => raise err
    } noraise {
      _ => fail("isolated surrogate accepted")
    }
  }
}

///|
test "narrow Windows-output filenames count native units and preserve byte identity in mounts" {
  let context = @lib.Context::new(windows_cwd="C:/work", mounts=[
    @lib.Mount::new("/", "C:/work"),
    @lib.Mount::new("/\uF0FF", "D:/literal", case=WindowsInsensitive),
  ])
  assert_eq(context.convert(b"/\xff", from=Posix, to=Mixed), "C:/work/\uF0FF")
  assert_eq(
    context.convert(b"/\xef\x83\xbf", from=Posix, to=Mixed),
    "D:/literal",
  )
  assert_eq(context.relative_windows_name(b"/\xff", from=Posix), Some("\uF0FF"))
  assert_true(
    context.mode_candidate(b"/\xff", from=Posix)
    is Filesystem("C:\\work\\\uF0FF", ..),
  )
  assert_eq(
    context.convert(Bytes::make(255, b'\xff'), from=Posix, to=Windows),
    "\uF0FF".repeat(255),
  )
  try context.convert(Bytes::make(256, b'\xff'), from=Posix, to=Windows) catch {
    @lib.PathTooLong(_) => ()
    e => raise e
  } noraise {
    _ => fail("overlong native component")
  }
  assert_eq(
    context.convert(b"\xf0\x9f\x98x", from=Posix, to=Mixed),
    "\uF0F0\uF09F\uF098x",
  )
  try context.convert(b"a\x00b", from=Posix, to=Mixed) catch {
    @lib.InvalidPath(offset=1, ..) => ()
    e => raise e
  } noraise {
    _ => fail("embedded NUL")
  }
}

///|
test "POSIX spelling in Windows to POSIX input bypasses drive and mount resolution" {
  let context = @lib.Context::new(windows_cwd="D:/cwd")
  for input in ["/", "/dev/null", "/a/../b", "/a//b/", "/proc/self"] {
    assert_eq(context.convert(input, from=Windows, to=Posix), input)
    assert_eq(
      context.convert(input, from=Windows, to=Posix, absolute=true),
      input,
    )
  }
  assert_eq(context.convert("/a\\b", from=Windows, to=Posix), "/a/b")
  assert_eq(context.convert("\\a", from=Windows, to=Posix), "/cygdrive/d/a")
}

///|
test "ordinary long paths gain extended prefixes at the UTF-16 boundary" {
  let context = @lib.Context::new(posix_cwd="/cygdrive/c/base")
  for length in [259, 260, 261] {
    let path = "C:/folder/" + "a".repeat(120) + "/" + "b".repeat(length - 131)
    assert_eq(path.length(), length)
    let mixed = if length < 260 { path } else { "//?/" + path }
    assert_eq(context.convert(path, from=Windows, to=Mixed), mixed)
    assert_eq(
      context.convert(path, from=Windows, to=Windows),
      mixed.replace_all(old="/", new="\\"),
    )
  }
  let relative = "a".repeat(130) + "/" + "b".repeat(130)
  assert_eq(
    context.convert(relative, from=Posix, to=Mixed),
    "//?/C:/base/" + relative,
  )
  let unc = "//server/share/" + "a".repeat(120) + "/" + "b".repeat(130)
  assert_eq(
    context.convert(unc, from=Windows, to=Mixed),
    "//?/UNC/" + unc[2:].to_owned(),
  )
}

///|
test "overlong filename components retain the official conversion error" {
  let context = @lib.Context::new()
  let path = "C:\\" + "a".repeat(256)
  try context.convert(path, from=Windows, to=Mixed) catch {
    @lib.PathTooLong(original) => assert_eq(original, path)
    _ => fail("unexpected error for an overlong filename component")
  } noraise {
    _ => fail("overlong filename component was accepted")
  }
}

///|
test "POSIX output accepts long components in arguments and fixed-size records" {
  let context = @lib.Context::new()
  let chunk = "C:\\" + "a".repeat(8189)
  assert_eq(chunk.length(), 8192)
  assert_eq(
    context.convert(chunk, from=Windows, to=Posix),
    "/cygdrive/c/" + "a".repeat(8189),
  )
  let remainder = "a".repeat(311) + "\\tail"
  assert_eq(
    context.convert(remainder, from=Windows, to=Posix),
    "a".repeat(311) + "/tail",
  )
  assert_eq(
    context.convert_list(chunk + ";D:/tail", from=Windows, to=Posix),
    "/cygdrive/c/" + "a".repeat(8189) + ":/cygdrive/d/tail",
  )
  let ordinary = "/folder/" + "a".repeat(256)
  assert_eq(context.convert(ordinary, from=Posix, to=Posix), ordinary)
  assert_true(
    conversion_error(() => {
      context.convert_list("C:/ok;" + chunk, from=Windows, to=Mixed)
    })
    is @lib.ListEntryError(index=1, @lib.PathTooLong(_)),
  )
}

///|
test "an invalid drive beneath a custom prefix has a typed lexical failure" {
  let context = @lib.Context::new(drive_prefix="/p3-drives", mounts=[
    @lib.Mount::new("/", "C:/root"),
  ])
  assert_eq(
    context.convert("/p3-drives/c/file", from=Posix, to=Windows),
    "C:\\file",
  )
  assert_true(
    conversion_error(() => {
      context.convert("/p3-drives/cat/file", from=Posix, to=Windows)
    })
    is @lib.InvalidDrivePrefix,
  )
  assert_eq(
    context.convert("/p3-drives-extra/cat/file", from=Posix, to=Windows),
    "C:\\root\\p3-drives-extra\\cat\\file",
  )
}
