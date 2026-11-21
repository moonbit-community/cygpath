///|
async test "byte-valued POSIX records use the selected mount for native lookup and mode" {
  let context = @lib.Context::new(mounts=[
    @lib.Mount::new("/", "C:/root"),
    @lib.Mount::new("/\uF0FF", "D:/literal", text_mode=true),
  ])
  let path = @filename.decode(b"/\xff/")
  let inspect : async (String) -> NativeEntity = name => {
    assert_eq(name, "C:\\root\\\uF0FF\\")
    Found(None)
  }
  let lookup : async (String, Bool, LookupPurpose) -> (NativeEntity, String) = (
    name,
    directory,
    _,
  ) => {
    assert_true(directory)
    (inspect(name), "")
  }
  assert_eq(
    checked_windows_path(context, path, Posix, false, inspect, lookup),
    Ok("C:\\root\\\uF0FF\\"),
  )
  assert_false(installed_mode(context, path, inspect~))
}

///|
async test "network traversal checks the cancelled entity and follows its resolved directory" {
  let ctx = @lib.Context::new(mounts=[
    @lib.Mount::new("/dest", "C:/target", text_mode=true),
  ])
  let checked = []
  let inspect : async (String) -> NativeEntity = path => {
    checked.push(path)
    match path {
      "\\\\old\\share" => Found(Some(Directory))
      "\\\\old\\share\\file" => Found(Some(Regular))
      "\\\\old\\share\\missing" => Found(None)
      "\\\\old\\share\\link" => Follow("C:/target/sub", "")
      "C:\\target\\sub" => Found(Some(Directory))
      "C:\\target\\item" => Found(Some(Regular))
      _ => fail("unexpected path " + path)
    }
  }
  let servers = []
  let server_lookup : async (String) -> Bool = name => {
    servers.push(name)
    name == "old"
  }
  assert_eq(
    checked_parents(ctx, "//old/./../new", inspect, server_lookup~),
    "//new",
  )
  assert_eq(
    checked_parents(ctx, "//old/share/../../new", inspect, server_lookup~),
    "//new",
  )
  assert_eq(
    checked_parents(ctx, "//old/share/..", inspect, server_lookup~),
    "//old/",
  )
  assert_true(
    installed_mode(ctx, "//old/share/link/../item", inspect~, server_lookup~),
  )
  for
    (name, reason) in [
      ("//no/../new", "No such file or directory"),
      ("//old/share/missing/../next", "No such file or directory"),
      ("//old/share/file/../next", "Not a directory"),
    ] {
    try checked_parents(ctx, name, inspect, server_lookup~) catch {
      LookupErrno(actual) => assert_eq(actual, reason)
      err => raise err
    } noraise {
      _ => fail("accepted invalid parent " + name)
    }
  }
  assert_eq(servers, ["old", "no"])
  assert_eq(checked, [
    "\\\\old\\share", "\\\\old\\share", "\\\\old\\share\\link", "C:\\target\\sub",
    "C:\\target\\item", "\\\\old\\share\\missing", "\\\\old\\share\\file",
  ])
}

///|
async test "virtual conversion and mode do not inspect native files" {
  let context = mounted_context("C:/cygwin", "", "", Some("C:/cygwin/dev"))
  let inspect : async (String) -> NativeEntity = name => {
    fail("unexpected filesystem lookup: " + name)
  }
  let lookup : async (String, Bool, LookupPurpose) -> (NativeEntity, String) = (
    name,
    _,
    _,
  ) => fail("unexpected filesystem lookup: " + name)
  assert_eq(
    checked_windows_path(context, "tty", Posix, false, inspect, lookup),
    Ok("/dev/tty"),
  )
  assert_false(installed_mode(context, "/dev/ptmx", inspect~))
  for name in ["//", "\\\\", "//localhost", "//tsclient/", "\\\\wsl$"] {
    assert_false(installed_mode(context, name, inspect~))
    assert_eq(
      installed_filename(context, name, inspect~),
      Some(@lib.nt_null_path),
    )
    assert_true(is_virtual_input(context, name))
  }
  assert_true(is_virtual_input(context, "///proc/net"))
  assert_false(is_virtual_input(context, "//server/share"))
  assert_eq(
    checked_windows_path(
      context,
      "/proc/net/../version",
      Posix,
      false,
      inspect,
      lookup,
    ),
    Ok("/proc/version"),
  )
  assert_eq(
    checked_windows_path(context, "/proc/.", Posix, false, inspect, lookup),
    Ok("/proc\\"),
  )
  assert_false(installed_mode(context, "/proc/meminfo", inspect~))
  assert_eq(
    checked_windows_path(
      context,
      "/proc/cygdrive/",
      Posix,
      false,
      inspect,
      lookup,
    ),
    Ok("C:\\cygwin\\cygdrive\\"),
  )
  assert_false(installed_mode(context, "/cygdrive", inspect~))
  assert_eq(installed_filename(context, "/proc/cygdrive", inspect~), None)
  assert_eq(
    stream_file_until("/cygdrive", installation=context, _ => {
      fail("virtual directory supplied input")
    }),
    0,
  )
  assert_eq(
    checked_windows_path(context, "ptmx/../x", Posix, true, inspect, lookup),
    Err("Not a directory"),
  )
  try installed_filename(context, "/dev/tty", inspect~) catch {
    InstallationError(_) => ()
    err => raise err
  } noraise {
    _ => fail("returned a native file path for a Cygwin terminal")
  }
}

///|
async test "installed relative output uses the operand's mount when comparing cwd" {
  let context = mounted_context(
    "C:/root",
    "D:/Work /origin ntfs binary\nD:/WORK /fold ntfs posix=0\n/fold /bound none bind\nD:/WORK /strict ntfs posix=1\nD:/Workshop /neighbor ntfs posix=0",
    "",
    Some("D:/Work"),
  )
  let inspect : async (String) -> NativeEntity = _ => Found(Some(Directory))
  let lookup : async (String, Bool, LookupPurpose) -> (NativeEntity, String) = (
    path,
    _,
    _,
  ) => {
    if path.has_suffix("\\tool") {
      (Found(Some(Regular)), ".exe")
    } else {
      (Found(Some(Directory)), "")
    }
  }
  for
    (input, absolute, expected) in [
      ("../fold/Leaf", false, "Leaf"),
      ("../fold/Leaf/", false, "Leaf\\"),
      ("../fold/.", false, ".\\"),
      ("../bound/tool", false, "tool.exe"),
      ("../strict/Leaf", false, "D:\\WORK\\Leaf"),
      ("../neighbor/Leaf", false, "D:\\Workshop\\Leaf"),
      ("../fold/Leaf", true, "D:\\WORK\\Leaf"),
      ("/fold/Leaf", false, "D:\\WORK\\Leaf"),
    ] {
    assert_eq(
      checked_windows_path(context, input, Posix, absolute, inspect, lookup),
      Ok(expected),
    )
  }
}

///|
async test "ordinary shell links and unreadable files retain their path spelling" {
  let dir = @fs.tmpdir(prefix="cygpath-shortcuts-")
  defer @fs.remove(dir, recursive=true)
  let base = plain_native(@fs.realpath(dir)) + "/item"
  let shortcut = base + ".lnk"
  let clsid = b"L\x00\x00\x00\x01\x14\x02\x00\x00\x00\x00\x00\xc0\x00\x00\x00\x00\x00\x00F"
  fn header(flags : Byte, show : Byte) -> Bytes {
    clsid +
    Bytes::from_array([flags]) +
    Bytes::make(39, 0) +
    Bytes::from_array([show]) +
    Bytes::make(15, 0)
  }
  let target = b"\x06\x00target\x06\x00target"
  for
    data in [
      clsid,
      header(0x8c, 1) + target,
      header(0x0c, 3) + target,
      header(0x0c, 1) + b"\x00\x00",
      header(0x0d, 1) + b"\xff\xff",
      header(0x0c, 1) + target + Bytes::make(262144, 0),
    ] {
    @fs.write_binary(shortcut, data)
    let (named, suffix) = windows_entity(shortcut, false, WindowsOutput)
    assert_true(named is Found(Some(Regular)))
    assert_eq(suffix, "")
    let (implicit, suffix) = windows_entity(base, false, WindowsOutput)
    assert_true(implicit is Found(None))
    assert_eq(suffix, "")
  }
  @fs.write_binary(shortcut, b"!<symlink>target")
  assert_true(native_entity(base) is Found(None))
  @fs.write_binary(shortcut, b"IntxLNKx is plain text")
  assert_true(native_entity(shortcut) is Found(Some(Regular)))
  for
    data in [
      header(0x0c, 1) + target,
      header(0x0d, 1) + b"\x02\x00\x00\x00" + target,
    ] {
    @fs.write_binary(shortcut, data)
    let file = @fs.open(shortcut, mode=ReadOnly)
    defer file.close()
    assert_eq(
      possible_cygwin_link(shortcut, file, false),
      !(@async.platform is Windows),
    )
    assert_eq(file.read_all(), data)
  }
  if !(@async.platform is Windows) {
    @fs.chmod(shortcut, 0)
    if !@fs.can_read(shortcut) {
      assert_true(native_entity(shortcut) is Found(Some(Regular)))
    }
  }
}

///|
async test "installed mode uses filesystem entities and effective fstab flags" {
  let tmp = @fs.tmpdir(prefix="cygpath-mode-")
  defer @fs.remove(tmp, recursive=true)
  let base = plain_native(@fs.realpath(tmp))
  @fs.mkdir(base + "/text")
  @fs.mkdir(base + "/binary")
  @fs.write_binary(base + "/text/plain", b"abc")
  @fs.write_binary(base + "/text/cookie", b"!<symlink>target")
  @fs.symlink(base + "/binary/link", target=base + "/text")
  @fs.mkdir(base + "/text/deep")
  @fs.symlink(base + "/binary/nested-link", target=base + "/text/deep")
  let context = mounted_context(
    "C:/",
    "C:/text /text ntfs text\nC:/binary /binary ntfs binary\nC:/binary /text/nested ntfs binary\n/text /alias none bind",
    "",
    Some("C:/binary"),
  )
  fn test_path(native : String) -> String raise {
    let path = plain_native(native)
    guard path.has_prefix("C:/") else { fail("unexpected test path " + path) }
    base + "/" + path[3:].to_owned()
  }
  fn remap(entity : NativeEntity) -> NativeEntity {
    match entity {
      Follow(target, tail) =>
        Follow(
          "C:/" + target[base.length():].trim_start(chars="/").to_owned(),
          tail,
        )
      Found(_) => entity
    }
  }
  async fn inspect(native : String) -> NativeEntity {
    remap(native_entity(test_path(native)))
  }
  async fn lookup(
    native : String,
    directory : Bool,
    purpose : LookupPurpose,
  ) -> (NativeEntity, String) {
    let (entity, suffix) = windows_entity(test_path(native), directory, purpose)
    (remap(entity), suffix)
  }
  let read_lookup : async (String, Bool) -> (NativeEntity, String) = (
    native,
    dir,
  ) => lookup(native, dir, FileInput)
  for
    name in [
      "app.exe", "file.txt.exe", "exact", "exact.exe", "absent.exe.exe", "note.lnk",
    ] {
    @fs.write_binary(base + "/binary/" + name, b"regular")
  }
  @fs.mkdir(base + "/binary/folder.exe")
  let parent = "a".repeat(125) + "/" + "b".repeat(125)
  @fs.mkdir(base + "/binary/" + "a".repeat(125))
  @fs.mkdir(base + "/binary/" + parent)
  for name in ["abc.exe", "abcd.exe"] {
    @fs.write_binary(base + "/binary/" + parent + "/" + name, b"file")
  }
  @fs.symlink(
    base + "/binary/" + parent + "/longlink",
    target=base + "/text/plain",
  )
  let win_parent = parent.replace_all(old="/", new="\\")
  let at_limit = "é".repeat(125) + "x"
  @fs.write_binary(base + "/binary/" + at_limit + ".exe", b"regular")
  for
    (path, expected) in [
      ("/text/plain", true),
      ("/text/missing", true),
      ("/alias/plain", true),
      ("/binary", false),
      ("C:/text/plain", false),
      ("../text/plain", true),
      ("link/plain", true),
      ("link/missing/file", true),
      ("link/nested/missing", false),
      ("link/../binary", false),
    ] {
    assert_eq(installed_mode(context, path, inspect~), expected)
  }
  for
    (path, absolute, expected) in [
      ("/binary/nested-link/../plain", false, "C:\\text\\plain"),
      ("////binary/nested-link/../plain", false, "C:\\text\\plain"),
      ("nested-link/../plain", false, "C:\\text\\plain"),
      ("link/../binary/Keep", false, "Keep"),
      ("link/../binary/Keep", true, "C:\\binary\\Keep"),
      ("nested-link/../../binary", false, "."),
      ("nested-link/..", false, "C:\\text\\"),
      ("nested-link/..", true, "C:\\text"),
      ("nested-link/../missing/", true, "C:\\text\\missing\\"),
      ("/binary/app", false, "C:\\binary\\app.exe"),
      ("app", false, "app.exe"),
      ("app/child", false, "app\\child"),
      ("file.txt", false, "file.txt.exe"),
      ("exact", false, "exact"),
      ("./".repeat(140) + "exact", false, "exact"),
      (parent + "/abc", false, win_parent + "\\abc.exe"),
      (parent + "/abcd", false, "\\\\?\\C:\\binary\\" + win_parent + "\\abcd"),
      (
        parent + "/abcd",
        true,
        "\\\\?\\C:\\binary\\" + win_parent + "\\abcd.exe",
      ),
      (parent + "/longlink", false, "C:\\text\\plain"),
      (
        parent + "/longlink",
        true,
        "\\\\?\\C:\\binary\\" + win_parent + "\\longlink",
      ),
      ("folder", false, "folder"),
      ("folder/child", false, "folder\\child"),
      ("absent.exe", false, "absent.exe"),
      ("note", false, "note"),
      (at_limit, false, at_limit + ".exe"),
      (at_limit + "x", false, at_limit + "x"),
      ("link", false, "link"),
      ("link/plain", false, "link\\plain"),
      ("link/deep/missing", false, "link\\deep\\missing"),
      ("link/missing", false, "C:\\text\\missing"),
      ("link/", true, "C:\\text"),
    ] {
    assert_eq(
      checked_windows_path(context, path, Posix, absolute, inspect, lookup),
      Ok(expected),
    )
  }
  assert_eq(
    checked_windows_path(
      context,
      "C:\\binary\\app",
      Windows,
      false,
      inspect,
      lookup,
    ),
    Ok("C:\\binary\\app.exe"),
  )
  assert_eq(
    checked_windows_path(
      context,
      "é".repeat(128),
      Posix,
      false,
      inspect,
      lookup,
    ),
    Err("File name too long"),
  )
  for
    (input, expected) in [
      ("/binary/nested-link/../plain", "C:\\text\\plain"),
      ("/binary/app", "C:\\binary\\app.exe"),
      ("file.txt", "C:\\binary\\file.txt.exe"),
      ("C:\\binary\\exact", "C:\\binary\\exact"),
      ("link", "C:\\text"),
      ("link/missing", "C:\\text\\missing"),
    ] {
    assert_eq(
      installed_filename(context, input, inspect~, lookup=read_lookup),
      Some(expected),
    )
  }
  for
    (path, expected) in [
      ("/binary/absent/../plain", "No such file or directory"),
      ("/text/plain/../child", "Not a directory"),
      ("/binary/app/.", "Not a directory"),
    ] {
    assert_eq(
      checked_windows_path(context, path, Posix, true, inspect, lookup),
      Err(expected),
    )
    try installed_filename(context, path, inspect~, lookup=read_lookup) catch {
      HostError::_ as err => assert_eq(err.diagnostic(), "cygpath: " + expected)
      err => raise err
    } noraise {
      _ => fail("opened an input through an invalid parent")
    }
  }
  assert_eq(
    checked_windows_path(
      context,
      "/binary/nested-link/../plain/",
      Posix,
      true,
      inspect,
      lookup,
    ),
    Err("Not a directory"),
  )
  for path in ["app/", "exact/child"] {
    assert_eq(
      checked_windows_path(context, path, Posix, false, inspect, lookup),
      Err("Not a directory"),
    )
  }
  for
    (path, message) in [
      ("/text/plain/", "Not a directory"),
      ("/text/plain/child", "Not a directory"),
      ("/text/plain/../other", "Not a directory"),
      ("/text/missing/../other", "No such file or directory"),
    ] {
    try installed_mode(context, path, inspect~) catch {
      LookupErrno(reason) => assert_eq(reason, message)
      err => raise err
    } noraise {
      _ => fail("expected an operand error: " + path)
    }
  }
  try installed_mode(context, "/text/cookie", inspect~) catch {
    InstallationError(_) => ()
    err => raise err
  } noraise {
    _ => fail("reported a mode without checking Cygwin link attributes")
  }
}

///|
async test "null device presence, binary mode and read semantics are independent of DOS aliases" {
  let dir = @fs.tmpdir(prefix="cygpath-null-")
  defer @fs.remove(dir, recursive=true)
  assert_eq(probe_device(dir), None)
  assert_eq(probe_device(dir + "/absent"), Some(false))
  let physical = if @async.platform is Windows {
    @lib.nt_null_path
  } else {
    "/dev/null"
  }
  assert_eq(probe_device(physical), Some(true))
  assert_eq(
    stream_file_until(physical, _ => fail("null device supplied a record")),
    0,
  )
  let ctx = mounted_context("C:/root", "", "", None, nt_null=true)
  assert_true(is_virtual_input(ctx, "/dev/./null"))
  assert_false(is_virtual_input(ctx, "/names"))
  assert_false(installed_mode(ctx, "/dev/random"))
  assert_eq(installed_filename(ctx, "/dev/null"), Some(@lib.nt_null_path))
  try installed_filename(ctx, "/dev/null/") catch {
    FileNotDirectory => ()
    err => raise err
  } noraise {
    _ => fail("accepted a trailing slash on the null device")
  }
  if @async.platform is Windows {
    assert_eq(
      stream_file_until("/dev/null", installation=ctx, _ => {
        fail("unexpected record")
      }),
      0,
    )
  }
  try installed_filename(ctx, "/dev/zero") catch {
    InstallationError(_) => ()
    err => raise err
  } noraise {
    _ => fail("routed a Cygwin zero stream to the NT null device")
  }
  let absent = @lib.Context::new(nt_null=false)
  try installed_filename(absent, "/dev/null") catch {
    NoSuchDeviceOrAddress => ()
    err => raise err
  } noraise {
    _ => fail("opened an absent NT device")
  }
}
