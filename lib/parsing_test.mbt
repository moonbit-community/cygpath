///|
test "POSIX names do not inherit the Windows NT namespace" {
  let context = @lib.Context::new()
  assert_eq(context.convert("/??/name", from=Posix, to=Posix), "/??/name")
  assert_eq(
    context.convert("\\??\\C:\\name", from=Windows, to=Posix),
    "/cygdrive/c/name",
  )
}

///|
test "UNC lookup accepts incomplete names while mount targets require a share" {
  let context = @lib.Context::new()
  for path in ["///server/share", "//server//share", "//server/", "//"] {
    assert_eq(context.convert(path, from=Windows, to=Posix), path)
    try @lib.Mount::new("/net", path) catch {
      @lib.InvalidContext(field="mount.windows", reason=_) => ()
      error => fail("unexpected mount error: \{Repr(error)}")
    } noraise {
      _ => fail("accepted an invalid UNC mount")
    }
  }
  assert_eq(
    context.convert("//server/share//a", from=Windows, to=Posix),
    "//server/share//a",
  )
}

///|
test "POSIX leading slashes distinguish local paths from the network root" {
  let ctx = @lib.Context::new(mounts=[@lib.Mount::new("/", "C:/root")])
  assert_eq(ctx.convert("///", from=Posix, to=Windows), "C:\\root")
  assert_eq(
    ctx.convert("////etc//names", from=Posix, to=Mixed),
    "C:/root/etc/names",
  )
  assert_eq(ctx.convert("//", from=Posix, to=Windows, absolute=true), "\\\\")
  assert_eq(ctx.convert("\\\\", from=Windows, to=Mixed), "//")
  assert_eq(
    ctx.convert("//host///share/file", from=Posix, to=Mixed),
    "//host/share/file",
  )
  assert_eq(
    ctx.convert("\\\\host\\\\share\\file", from=Windows, to=Mixed),
    "//host/share/file",
  )
  assert_eq(
    ctx.convert_list("//:////proc/version", from=Posix, to=Windows),
    "\\\\;/proc/version",
  )
  assert_eq(
    ctx.convert("///etc//names", from=Windows, to=Posix),
    "///etc//names",
  )
}

///|
test "bare network servers only need presence for absolute Windows directory spelling" {
  let ctx = @lib.Context::new()
  let online = ctx.with_network_server("files", present=true)
  let offline = online.with_network_server("files", present=false)
  for path in ["//files/", "//files/.", "//files///.//"] {
    assert_eq(ctx.convert(path, from=Posix, to=Windows), "\\\\files\\")
    assert_eq(
      online.convert(path, from=Posix, to=Mixed, absolute=true),
      "//files",
    )
    assert_eq(
      offline.convert(path, from=Posix, to=Mixed, absolute=true),
      "//files/",
    )
  }
  assert_eq(
    ctx.convert("//files", from=Posix, to=Windows, absolute=true),
    "\\\\files",
  )
  assert_eq(ctx.convert("//a?b.", from=Posix, to=Windows), "\\\\a\uF03Fb.")
  assert_eq(
    ctx.convert("//files/.//./docs/a", from=Posix, to=Mixed),
    "//files/docs/a",
  )
  assert_eq(
    online.convert("\\\\files\\.", from=Windows, to=Mixed, absolute=true),
    "//files",
  )
  assert_eq(
    ctx.convert("//files/", from=Posix, to=Posix, absolute=true),
    "//files/",
  )
  let mixed = offline.with_network_server("dav@SSL@443", present=true)
  assert_eq(
    mixed.convert_list(
      "//dav@SSL@443/://files/",
      from=Posix,
      to=Mixed,
      absolute=true,
    ),
    "//dav@SSL@443;//files/",
  )
  try ctx.convert("//files/", from=Posix, to=Windows, absolute=true) catch {
    @lib.NetworkServerLookup("files") => ()
    err => raise err
  } noraise {
    _ => fail("lost unknown server presence")
  }
}

///|
test "UNC parents can cross both names and stop at the network root" {
  let ctx = @lib.Context::new(windows_cwd="//old/share/base")
  for
    (path, expected) in [
      ("\\\\old\\..\\host", "//host"),
      ("\\\\old\\share\\..\\..\\host\\data\\item", "//host/data/item"),
      ("\\\\old\\share\\..", "//old/"),
      ("\\\\old\\..\\..\\..", "//"),
      ("\\\\?\\UNC\\old\\..\\host\\a?b", "//host/a\uF03Fb"),
    ] {
    assert_eq(ctx.convert(path, from=Windows, to=Mixed), expected)
  }
  assert_eq(
    ctx.convert("..\\..\\..\\host\\data", from=Windows, to=Mixed, absolute=true),
    "//host/data",
  )
  let observed = ctx.with_network_server("old", present=true)
  assert_eq(observed.convert("//old/./../host", from=Posix, to=Mixed), "//host")
  assert_eq(ctx.convert("//../../..", from=Posix, to=Mixed), "//")
  let absent = ctx.with_network_server("old", present=false)
  try absent.convert("//old/../host", from=Posix, to=Mixed) catch {
    @lib.PathNotFound => ()
    err => raise err
  } noraise {
    _ => fail("cancelled a missing server")
  }
}

///|
test "mount case policy cannot overlap the reserved drive prefix" {
  let mount = @lib.Mount::new("/CYGDRIVE/c", "D:/alias", case=AsciiInsensitive)
  try @lib.Context::new(mounts=[mount]) catch {
    @lib.InvalidContext(field="mounts[0]", reason=_) => ()
    error => fail("unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("expected drive-prefix conflict")
  }
}

///|
test "device-name detection preserves supplementary Unicode scalars" {
  let context = @lib.Context::new()
  for name in ["😀😀", "ab😀", "😀ab", "A😀B"] {
    assert_eq(
      context.convert("C:/" + name, from=Windows, to=Posix),
      "/cygdrive/c/" + name,
    )
    assert_eq(
      context.convert("/cygdrive/c/" + name, from=Posix, to=Mixed),
      "C:/" + name,
    )
  }
}
