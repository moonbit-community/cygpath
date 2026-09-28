///|
test "ordinary extended namespaces retain ordinary drive and UNC semantics" {
  let context = @lib.Context::new()
  for path in ["\\\\?\\C:\\name", "\\??\\C:\\name", "//?/C:/name"] {
    assert_eq(context.convert(path, from=Windows, to=Posix), "/cygdrive/c/name")
    assert_eq(context.convert(path, from=Windows, to=Windows), "C:\\name")
  }
  for
    path in [
      "\\\\?\\UNC\\server\\share\\name", "\\??\\UNC\\server\\share\\name",
    ] {
    assert_eq(
      context.convert(path, from=Windows, to=Posix),
      "//server/share/name",
    )
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
