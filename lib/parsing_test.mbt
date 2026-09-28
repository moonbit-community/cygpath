///|
test "POSIX names do not inherit the Windows NT namespace" {
  let context = @lib.Context::new()
  assert_eq(context.convert("/??/name", from=Posix, to=Posix), "/??/name")
  try context.convert("\\??\\C:\\name", from=Windows, to=Posix) catch {
    @lib.UnsupportedNamespace("device") => ()
    error => fail("unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("expected device namespace rejection")
  }
}

///|
test "UNC authority fields cannot be empty" {
  let context = @lib.Context::new()
  for path in ["///server/share", "//server//share", "//server/", "//"] {
    try context.convert(path, from=Windows, to=Posix) catch {
      @lib.UnsupportedNamespace(_) => ()
      error => fail("unexpected error: \{Repr(error)}")
    } noraise {
      _ => fail("accepted an empty UNC authority field")
    }
    try @lib.Mount::new("/net", path) catch {
      @lib.InvalidContext(field="mount.windows", reason=_) => ()
      error => fail("unexpected mount error: \{Repr(error)}")
    } noraise {
      _ => fail("accepted an invalid UNC mount")
    }
  }
  assert_eq(
    context.convert("//server/share//a", from=Windows, to=Posix),
    "//server/share/a",
  )
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
