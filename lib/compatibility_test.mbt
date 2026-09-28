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
}
