///|
fn measured_msys_mounts() -> Array[@lib.Mount] raise {
  // getmntent order captured in remote e9b7bec, MSYS2 custom context.
  // The default /usr/bin path is not a mount declaration in this installation.
  [
    @lib.Mount::new("/p3-alias-second", "C:/cygpath-ci/msys2/cwd/custom-shared"),
    @lib.Mount::new("/p3-mount/nested", "C:/cygpath-ci/msys2/cwd/custom-nested"),
    @lib.Mount::new("/", "C:/cygpath-msys2/msys64"),
    @lib.Mount::new("/p3-alias-first", "C:/cygpath-ci/msys2/cwd/custom-shared"),
    @lib.Mount::new("/p3-mount", "C:/cygpath-ci/msys2/cwd/custom-base"),
    @lib.Mount::new("/bin", "C:/cygpath-msys2/msys64/usr/bin"),
    @lib.Mount::new(
      "/P3Fold",
      "C:/cygpath-ci/msys2/cwd/custom-Fold",
      case=AsciiInsensitive,
    ),
    @lib.Mount::new(
      "/p3-alias-deep", "C:/cygpath-ci/msys2/cwd/custom-shared/deep",
    ),
  ]
}

///|
test "MSYS2 partial mount ordering reproduces the measured nested selection" {
  let mounts = measured_msys_mounts()
  let msys = @lib.Context::new(
    profile=Msys2,
    drive_prefix="/p3-drives",
    mounts~,
  )
  assert_eq(
    msys.convert("/p3-mount/nested", from=Posix, to=Windows),
    "C:\\cygpath-ci\\msys2\\cwd\\custom-base\\nested",
  )
  assert_eq(
    msys.convert("/p3-mount/nested/file", from=Posix, to=Windows),
    "C:\\cygpath-ci\\msys2\\cwd\\custom-base\\nested\\file",
  )
  let cygwin = @lib.Context::new(
    profile=Cygwin,
    drive_prefix="/p3-drives",
    mounts~,
  )
  assert_eq(
    cygwin.convert("/p3-mount/nested", from=Posix, to=Windows),
    "C:\\cygpath-ci\\msys2\\cwd\\custom-nested",
  )
}

///|
test "MSYS2 reverse mounts maximize resulting POSIX length" {
  let msys = @lib.Context::new(
    profile=Msys2,
    drive_prefix="/p3-drives",
    mounts=measured_msys_mounts(),
  )
  assert_eq(
    msys.convert(
      "C:/cygpath-ci/msys2/cwd/custom-shared/file",
      from=Windows,
      to=Posix,
    ),
    "/p3-alias-second/file",
  )
  assert_eq(
    msys.convert(
      "C:/cygpath-ci/msys2/cwd/custom-shared/deep/file",
      from=Windows,
      to=Posix,
    ),
    "/p3-alias-second/deep/file",
  )
  assert_eq(
    msys.convert("C:/cygpath-msys2/msys64/usr/bin/tool", from=Windows, to=Posix),
    "/usr/bin/tool",
  )
}

///|
test "MSYS2 UTF8 byte length and lexical ties decide reverse aliases" {
  let msys = @lib.Context::new(profile=Msys2, mounts=[
    @lib.Mount::new("/aa", "C:/shared"),
    @lib.Mount::new("/é", "C:/shared"),
    @lib.Mount::new("/zz", "D:/shared"),
    @lib.Mount::new("/éé", "D:/shared"),
  ])
  assert_eq(msys.convert("C:/shared/file", from=Windows, to=Posix), "/aa/file")
  assert_eq(
    msys.convert("D:/shared/file", from=Windows, to=Posix),
    "/éé/file",
  )
}

///|
test "MSYS2 default root and bin declarations preserve ordinary conversions" {
  let msys = @lib.Context::new(profile=Msys2, mounts=[
    @lib.Mount::new("/", "C:/msys64"),
    @lib.Mount::new("/bin", "C:/msys64/usr/bin"),
  ])
  assert_eq(
    msys.convert("/bin/tool", from=Posix, to=Windows),
    "C:\\msys64\\usr\\bin\\tool",
  )
  assert_eq(
    msys.convert("/usr/bin/tool", from=Posix, to=Windows),
    "C:\\msys64\\usr\\bin\\tool",
  )
  assert_eq(
    msys.convert("/usr/lib/file", from=Posix, to=Windows),
    "C:\\msys64\\usr\\lib\\file",
  )
  assert_eq(
    msys.convert("C:/msys64/usr/bin/tool", from=Windows, to=Posix),
    "/usr/bin/tool",
  )
}
