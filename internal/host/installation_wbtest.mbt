///|
async test "fstab posix=0 applies Windows case mapping to mounts and bind sources" {
  let context = mounted_context(
    "C:/install",
    "D:/É /Ä ntfs posix=0,text\n/ä/sub /Ω none bind\n",
    "",
    None,
  )
  assert_eq(context.convert("/ω/Leaf", from=Posix, to=Mixed), "D:/É/sub/Leaf")
  assert_eq(context.convert("D:/é/File", from=Windows, to=Posix), "/Ä/File")
}

///|
async test "installation defaults use the two automatic mounts and physical cwd" {
  let context = mounted_context("C:\\cygwin", "", "", Some("C:\\cygwin\\bin"))
  let lookup : async (@lib.NativePath, Bool) -> (NativeEntity, String) = (_, _) => {
    (Found(None), "")
  }
  assert_eq(
    context.convert("C:\\cygwin\\bin\\sh", from=Windows, to=Posix),
    "/usr/bin/sh",
  )
  assert_eq(
    context.convert("/usr/lib/file", from=Posix, to=Mixed),
    "C:/cygwin/lib/file",
  )
  assert_eq(
    context.convert("./sh", from=Posix, to=Mixed, absolute=true),
    "C:/cygwin/bin/sh",
  )
  assert_eq(
    context.convert("./sh", from=Windows, to=Posix, absolute=true),
    "/usr/bin/sh",
  )
  assert_eq(
    installed_filename(context, "../lib/data", lookup~),
    Some("C:\\cygwin\\lib\\data"),
  )
  assert_eq(
    installed_filename(context, "/etc/names", lookup~),
    Some("C:\\cygwin\\etc\\names"),
  )
  assert_eq(
    installed_filename(context, "/cygdrive/d/input", lookup~),
    Some("D:\\input"),
  )
  assert_eq(
    installed_filename(context, "C:records", lookup~),
    Some("C:\\cygwin\\bin\\C\uF03Arecords"),
  )
  assert_eq(installed_filename(context, "D:\\name", lookup~), Some("D:\\name"))
}

///|
async test "system and user mount precedence, escapes and last case flag" {
  let system = "# installed mounts\r\nD:/ignored / ntfs binary\r\nD:/new / ntfs override\r\nE:/With\\040Space\t/tools\tntfs\tuser,posix=0\t0 0\nG:/bin /usr/bin ntfs binary\nnone /vol cygdrive binary,user\nZ:/bad /bad ntfs bogus\n"
  let user = "X:/denied /usr/bin ntfs override\nY:/user /tools ntfs posix=1,posix=0\n"
  let initial = mounted_context("C:/install", system, "", None)
  assert_eq(
    initial.convert("/TOOLS/x", from=Posix, to=Mixed),
    "E:/With Space/x",
  )
  let context = mounted_context("C:/install", system, user, None)
  assert_eq(context.convert("/usr/bin/sh", from=Posix, to=Mixed), "G:/bin/sh")
  assert_eq(context.convert("/usr/lib/x", from=Posix, to=Mixed), "D:/new/lib/x")
  assert_eq(
    context.convert("/Tools/file", from=Posix, to=Mixed),
    "Y:/user/file",
  )
  assert_eq(
    context.convert("F:\\hello", from=Windows, to=Posix),
    "/vol/f/hello",
  )
  assert_eq(context.convert("/bad", from=Posix, to=Mixed), "D:/new/bad")
}

///|
async test "fstab retains both owners and binds to the row selected by each profile" {
  let system = "U:/long/source /both ntfs user,text\nS:/s /both ntfs binary,posix=0\n/both/child /saved none bind\n"
  for profile in [@lib.Cygwin, Msys2] {
    let ctx = mounted_context("C:/root", system, "", None, profile~)
    let (winner, text) = if profile == Cygwin {
      ("U:/long/source", true)
    } else {
      ("S:/s", false)
    }
    assert_eq(ctx.convert("/both/file", from=Posix, to=Mixed), winner + "/file")
    assert_eq(ctx.convert("/BOTH/file", from=Posix, to=Mixed), "S:/s/file")
    assert_eq(
      ctx.convert("/saved/file", from=Posix, to=Mixed),
      winner + "/child/file",
    )
    assert_true(
      ctx.mode_candidate("/saved/file", from=Posix)
      is Filesystem(_, text_mode=value) &&
      value == text,
    )
    for path in ["U:/long/source/file", "S:/s/file"] {
      assert_eq(ctx.convert(path, from=Windows, to=Posix), "/both/file")
    }
    let changed = mounted_context(
      "C:/root",
      system,
      "V:/new-user/source /both ntfs binary",
      None,
      profile~,
    )
    assert_eq(
      changed.convert("V:/new-user/source/x", from=Windows, to=Posix),
      "/both/x",
    )
    assert_eq(changed.convert("S:/s/x", from=Windows, to=Posix), "/both/x")
    assert_eq(
      changed.convert("/saved/file", from=Posix, to=Mixed),
      winner + "/child/file",
    )
  }
}

///|
async test "a full runtime mount table stops the current file and permits later replacements" {
  // Root plus 63 entries fills the shared table. An additional entry stops
  // this file before its drive declaration. The user file updates an old row.
  let system = StringBuilder()
  for i in 0..<63 {
    system.write_string("D:/p\{i} /p\{i} ntfs user\n")
  }
  system.write_string(
    "relative /ignored ntfs binary\nnone /vol cygdrive binary\nE:/extra /extra ntfs binary\nnone /late cygdrive binary\n",
  )
  for profile in [@lib.Cygwin, Msys2] {
    let ctx = mounted_context(
      "C:/root",
      system.to_string(),
      "Z:/replacement /p62 ntfs text",
      None,
      profile~,
    )
    assert_eq(ctx.convert("/extra", from=Posix, to=Mixed), "C:/root/extra")
    assert_eq(
      ctx.convert("/p62/item", from=Posix, to=Mixed),
      "Z:/replacement/item",
    )
    assert_eq(ctx.convert("T:/item", from=Windows, to=Posix), "/vol/t/item")
  }
}

///|
async test "invalid fstab sources leave later drive and UNC mounts available" {
  let rows =
    #|D:relative /bad ntfs binary
    #|//server /bad ntfs binary
    #|//server//share /bad ntfs binary
    #|//?/Volume{abc} /bad ntfs binary
    #|d:/absent/.././tools//bin /tools ntfs binary
    #|\??\UNC\server\old\..\new /network ntfs binary
    #|//?/e: /drive ntfs binary
    #|f:/../.. /clamped ntfs binary
  for profile in [@lib.Cygwin, Msys2] {
    let ctx = mounted_context("C:/root", rows, "", None, profile~)
    for
      (point, native) in [
        ("/bad/x", "C:/root/bad/x"),
        ("/tools/x", "D:/tools/bin/x"),
        ("/network/x", "//server/new/x"),
        ("/drive/x", "E:/x"),
        ("/clamped/x", "F:/x"),
      ] {
      assert_eq(ctx.convert(point, from=Posix, to=Mixed), native)
    }
  }
}

///|
async test "fstab checks a cancelled POSIX directory against earlier mounts" {
  let rows =
    #|D:/mount /first ntfs binary
    #|E:/missing /first/missing/../bad ntfs binary
    #|E:/file /first/file/../bad ntfs binary
    #|E:/backslash /bad\point ntfs binary
    #|E:/valid /first/dir/../point ntfs binary
    #|E:/via-link /first/link/../alias ntfs binary
  for profile in [@lib.Cygwin, Msys2] {
    let ctx = mounted_context("C:/root", rows, "", None, profile~, inspect=native => {
      match plain_native(native.windows_name()) {
        "D:/mount/missing" => Found(None)
        "D:/mount/file" => Found(Some(Regular))
        "D:/mount/dir" | "C:/root/actual/deep" => Found(Some(Directory))
        "D:/mount/link" => Follow("C:/root/actual/deep", "")
        other => fail("unexpected fstab directory lookup " + other)
      }
    })
    for
      (point, expected) in [
        ("/first/bad/x", "D:/mount/bad/x"),
        ("/first/point/x", "E:/valid/x"),
        ("/first/alias/x", "D:/mount/alias/x"),
        ("/actual/alias/x", "E:/via-link/x"),
      ] {
      assert_eq(ctx.convert(point, from=Posix, to=Mixed), expected)
    }
  }
}

///|
async test "a drive-prefix mount remains available in reverse when the drive wins forward" {
  for (profile, prefix) in [(@lib.Cygwin, "/cygdrive"), (Msys2, "")] {
    let branch = prefix + "/c/alias"
    let table = "none " +
      (if prefix.is_empty() { "/" } else { prefix }) +
      " cygdrive binary\nZ:/other " +
      branch +
      " ntfs text\n"
    let ctx = mounted_context("D:/root", table, "", None, profile~)
    assert_eq(
      ctx.convert(branch + "/file", from=Posix, to=Mixed),
      "C:/alias/file",
    )
    assert_eq(
      ctx.convert("Z:/other/file", from=Windows, to=Posix),
      branch + "/file",
    )
    assert_true(
      ctx.mode_candidate(branch + "/file", from=Posix)
      is Filesystem(_, text_mode=false),
    )
  }
}

///|
async test "fstab retains reverse device mounts and binds ordinary dev files" {
  let rows =
    #|D:/files /dev/local ntfs text
    #|E:/shadow /dev/tty ntfs text
    #|/dev/tty /ignored none bind
    #|/dev/local/sub /copy none bind
    #|/dev/tty/sub /literal none bind
    #|none /dev/drives cygdrive binary
  for profile in [@lib.Cygwin, Msys2] {
    let ctx = mounted_context("C:/install", rows, "", None, profile~)
    assert_eq(
      ctx.convert("E:/shadow/file", from=Windows, to=Posix),
      "/dev/tty/file",
    )
    assert_eq(ctx.convert("/dev/tty", from=Posix, to=Mixed), "/dev/tty")
    assert_eq(
      ctx.convert("/ignored", from=Posix, to=Mixed),
      "C:/install/ignored",
    )
    assert_eq(ctx.convert("/copy/x", from=Posix, to=Mixed), "D:/files/sub/x")
    assert_eq(
      ctx.convert("/literal/x", from=Posix, to=Mixed),
      "E:/shadow/sub/x",
    )
    assert_true(
      ctx.mode_candidate("/copy/x", from=Posix) is Filesystem(_, text_mode=true),
    )
    assert_eq(ctx.convert("/dev/drives/z/x", from=Posix, to=Mixed), "Z:/x")
    assert_eq(ctx.convert("Z:/x", from=Windows, to=Posix), "/dev/drives/z/x")
  }
}

///|
async test "fstab bind captures preceding mappings and their effective options" {
  let system =
    #|/later/frozen /early none bind
    #|D:/Shared /later ntfs user,posix=0
    #|/LATER/first\040dir /a//./alias none bind
    #|/a/ALIAS/sub /chain none bind,text,binary,auto,
    #|/later /own none bind,text,posix=1
    #|/cygdrive/f/data /drive none bind
    #|/cygdrive/not-a-drive /ignored none bind
    #|/proc/cygdrive/f/data /ignored-proc none bind
    #|/usr/lib /before-auto none bind
  let user =
    #|/usr/lib /after-auto none bind
    #|Z:/user /a/alias ntfs binary
    #|Z:/blocked /own ntfs binary
  let context = mounted_context("C:/install", system, user, None)
  for
    (path, expected) in [
      ("/early/x", "C:/install/later/frozen/x"),
      ("/a/alias", "Z:/user"),
      ("/CHAIN/x", "D:/Shared/first dir/sub/x"),
      ("/own/x", "D:/Shared/x"),
      ("/OWN/x", "C:/install/OWN/x"),
      ("/DRIVE/x", "F:/data/x"),
      ("/ignored/x", "C:/install/ignored/x"),
      ("/ignored-proc/x", "C:/install/ignored-proc/x"),
      ("/before-auto/x", "C:/install/usr/lib/x"),
      ("/after-auto/x", "C:/install/lib/x"),
    ] {
    assert_eq(context.convert(path, from=Posix, to=Mixed), expected)
  }
}

///|
async test "installation loader reads optional layers and narrow mount fields" {
  let dir = @fs.tmpdir(prefix="cygpath-install-")
  defer @fs.remove(dir, recursive=true)
  let empty = load_installation("C:/install", dir, None, None)
  assert_eq(empty.convert("/etc", from=Posix, to=Mixed), "C:/install/etc")
  @fs.mkdir(dir + "/etc/fstab.d", recursive=true)
  @fs.write_text(dir + "/etc/fstab", "D:/shared /src ntfs user\n")
  @fs.write_text(dir + "/etc/fstab.d/alice", "E:/mine /src ntfs binary\n")
  let loaded = load_installation(
    "C:/install",
    dir,
    Some("alice"),
    Some("E:/mine"),
  )
  assert_eq(
    loaded.convert("a", from=Windows, to=Posix, absolute=true),
    "/src/a",
  )
  try load_installation("C:/install", dir, Some("../fstab"), None) catch {
    InstallationError(_) => ()
    err => raise err
  } noraise {
    _ => fail("account path escaped the per-user directory")
  }
  @fs.write_binary(
    dir + "/etc/fstab",
    b"# caf\xe9\nD:/store-\xff /point-\xfe ntfs posix=0,text\nnone /drive-\xfd cygdrive binary\n",
  )
  @fs.write_binary(
    dir + "/etc/fstab.d/alice",
    b"/POINT-\xfe/child /bound none bind\n",
  )
  let bytes = load_installation("C:/install", dir, Some("alice"), None)
  assert_eq(
    bytes.windows_to_posix_bytes("D:/STORE-\uF0FF/file"),
    b"/point-\xfe/file",
  )
  assert_eq(
    bytes.convert("/bound/file", from=Posix, to=Mixed),
    "D:/store-\uF0FF/child/file",
  )
  assert_eq(
    bytes.convert(b"/POINT-\xfe/file", from=Posix, to=Mixed),
    "D:/store-\uF0FF/file",
  )
  assert_eq(
    bytes.convert("/point-\uF0FE/file", from=Posix, to=Mixed),
    "C:/install/point-\uF0FE/file",
  )
  assert_eq(bytes.windows_to_posix_bytes("Z:/file"), b"/drive-\xfd/z/file")
}

///|
async test "MSYS2 reads its drive prefix, automatic bin and two-field mounts from installation state" {
  let dir = @fs.tmpdir(prefix="cygpath-msys-")
  defer @fs.remove(dir, recursive=true)
  let empty = load_installation("C:/msys64", dir, None, None, profile=Msys2)
  assert_eq(
    empty.convert("D:/leaf", from=Windows, to=Posix),
    "/cygdrive/d/leaf",
  )
  assert_eq(
    empty.convert("/bin/sh", from=Posix, to=Mixed),
    "C:/msys64/usr/bin/sh",
  )
  assert_eq(
    empty.convert("/usr/lib", from=Posix, to=Mixed),
    "C:/msys64/usr/lib",
  )
  @fs.mkdir(dir + "/etc/fstab.d", recursive=true)
  @fs.write_text(
    dir + "/etc/fstab",
    "none / cygdrive binary,posix=0,noacl,user 0 0\r\nD:/A\\040B /tools\r\nD:/skip /ignored \r\nE:/sys /layer ntfs binary\r\n",
  )
  @fs.write_text(dir + "/etc/fstab.d/alice", "F:/user /layer\n")
  let ctx = load_installation(
    "C:/msys64",
    dir,
    Some("alice"),
    Some("C:/msys64/usr/bin"),
    profile=Msys2,
  )
  for
    (input, expected) in [
      ("/bin/sh", "C:/msys64/usr/bin/sh"),
      ("/TOOLS/cc", "D:/A B/cc"),
      ("/ignored", "C:/msys64/ignored"),
      ("/layer/file", "F:/user/file"),
      ("/d/dir", "D:/dir"),
    ] {
    assert_eq(ctx.convert(input, from=Posix, to=Mixed), expected)
  }
  assert_eq(
    ctx.convert(".", from=Windows, to=Posix, absolute=true),
    "/usr/bin/",
  )
  assert_eq(ctx.convert("D:/leaf", from=Windows, to=Posix), "/d/leaf")
  @fs.write_text(dir + "/etc/fstab", "E:/root / ntfs override\nX:/utils /bin\n")
  let custom = load_installation("C:/msys64", dir, None, None, profile=Msys2)
  assert_eq(custom.convert("/bin/sh", from=Posix, to=Mixed), "X:/utils/sh")
  assert_eq(
    custom.convert("/usr/bin/sh", from=Posix, to=Mixed),
    "E:/root/usr/bin/sh",
  )
  let cyg = load_installation("C:/msys64", dir, None, None)
  assert_eq(cyg.convert("/bin/sh", from=Posix, to=Mixed), "E:/root/bin/sh")
}

///|
async test "MSYS2 installation reproduces the five recorded default Windows path probes" {
  // Raw observations from the msys2/default job in Windows oracle run 36385821354.
  let ctx = mounted_context(
    "C:/cygpath-msys2/msys64",
    "none / cygdrive binary,posix=0,noacl,user 0 0",
    "",
    Some("C:/cygpath-ci/msys2/cwd"),
    profile=Msys2,
  )
  assert_eq(
    ctx.convert(".", from=Windows, to=Posix, absolute=true),
    "/c/cygpath-ci/msys2/cwd/",
  )
  assert_eq(
    ctx.convert(".", from=Posix, to=Windows, absolute=true),
    "C:\\cygpath-ci\\msys2\\cwd",
  )
  assert_eq(
    ctx.convert("/", from=Posix, to=Windows),
    "C:\\cygpath-msys2\\msys64\\",
  )
  assert_eq(
    ctx.convert("/usr/bin", from=Posix, to=Windows),
    "C:\\cygpath-msys2\\msys64\\usr\\bin",
  )
  assert_eq(ctx.convert("C:\\", from=Windows, to=Posix), "/c/")
}

///|
async test "usertemp selects the first available Windows temp path" {
  let vars : Map[String, String] = {
    "TMP": "",
    "TEMP": "T:/x",
    "USERPROFILE": "U:/u",
  }
  assert_eq(windows_temp(key => vars.get(key)), Some("T:/x"))
  vars["TMP"] = "X:/y"
  assert_eq(windows_temp(key => vars.get(key)), Some("X:/y"))
  let limit = "😀".repeat(130)
  vars["TMP"] = limit
  assert_eq(windows_temp(key => vars.get(key)), Some(limit))
  vars["TMP"] = limit + "z"
  vars["TEMP"] = limit + "z"
  assert_eq(windows_temp(key => vars.get(key)), Some("U:/u"))
  vars.remove("USERPROFILE")
  assert_eq(windows_temp(key => vars.get(key)), None)
  let table = "none /tmp usertemp user,posix=0\nD:/ignored /tmp ntfs user\n"
  let context = mounted_context("C:/install", table, "", None, temp=() => {
    Some("T:/User Temp")
  })
  assert_eq(context.convert("/TMP/a", from=Posix, to=Mixed), "T:/User Temp/a")
  try mounted_context("C:/install", table, "", None) catch {
    InstallationError(_) => ()
    err => raise err
  } noraise {
    _ => fail("missing Windows temp was guessed")
  }
  try
    mounted_context("C:/install", table, "", None, temp=() => Some("T:"))
  catch {
    InstallationError(_) => ()
    err => raise err
  } noraise {
    _ => fail("drive-relative Windows temp was guessed")
  }
}

///|
async test "usertemp qualifies nonexistent names against a Windows cwd" {
  let table = "none /temporary usertemp binary"
  for profile in [@lib.Profile::Cygwin, Msys2] {
    for
      (cwd, temp, expected) in [
        ("C:/work/base", "..\\cache", "C:/work/cache"),
        ("C:/work/base", "c:missing", "C:/work/base/missing"),
        ("C:/work/base", "C:", "C:/work/base"),
        ("C:/work/base", "\\cache", "C:/cache"),
        ("C:/work/base", "T:\\old\\..\\not-created", "T:/not-created"),
        ("C:/work/base", "T:\\dir.\\missing. ", "T:/dir/missing"),
        ("C:/work/base", "\\\\server\\share\\..\\cache", "//server/share/cache"),
        ("//server/share/work", "..\\..\\cache", "//server/share/cache"),
        ("//server/share/work", "\\cache", "//server/share/cache"),
      ] {
      let context = mounted_context(
        "C:/install",
        table,
        "",
        Some(cwd),
        temp=() => Some(temp),
        profile~,
      )
      assert_eq(
        context.convert("/temporary/file", from=Posix, to=Mixed),
        expected + "/file",
      )
    }
  }
  try
    usertemp_source(
      Some("segment/".repeat(30) + "z"),
      Some("C:/qualified/working/directory"),
    )
  catch {
    InstallationError(message) =>
      assert_eq(
        message, "qualified Windows temporary directory exceeds 260 UTF-16 units",
      )
    err => raise err
  } noraise {
    _ => fail("oversize qualified temp directory was accepted")
  }
  let drives : Map[String, String] = { "=C:": "C:/stale", "=D:": "D:\\other" }
  for
    (value, expected) in [
      ("C:cache", "C:/work/cache"),
      ("d:cache", "D:/other/cache"),
      ("E:cache", "E:/cache"),
    ] {
    assert_eq(
      usertemp_source(Some(value), Some("C:/work"), get=key => drives.get(key)),
      expected,
    )
  }
  drives["=E:"] = "F:/other"
  try
    usertemp_source(Some("E:cache"), Some("C:/work"), get=key => drives.get(key))
  catch {
    InstallationError(_) => ()
    err => raise err
  } noraise {
    _ => fail("invalid per-drive environment entry was used")
  }
}

///|
async test "usertemp only requests the host path for an admitted mount" {
  for profile in [@lib.Profile::Cygwin, Msys2] {
    let mut queries = 0
    let temp : async () -> String? = () => {
      queries += 1
      Some("R:/Operating System")
    }
    let context = mounted_context(
      "C:/install",
      "none /temporary usertemp binary",
      "none /temporary usertemp binary",
      None,
      profile~,
      temp~,
    )
    assert_eq(
      context.convert("/temporary/file", from=Posix, to=Mixed),
      "R:/Operating System/file",
    )
    assert_eq(queries, 1)
    ignore(
      mounted_context(
        "C:/install",
        "D:/other /tmp ntfs binary",
        "",
        None,
        profile~,
        temp~,
      ),
    )
    assert_eq(queries, 1)
  }
}

///|
async test "fixed system folders keep a final link's directory entry" {
  let tmp = @fs.tmpdir(prefix="cygpath-fixed-")
  defer @fs.remove(tmp, recursive=true)
  let root = plain_native(@fs.realpath(tmp))
  @fs.mkdir(root + "/Store")
  @fs.symlink(root + "/Fonts", target=root + "/Store")
  @fs.write_binary(root + "/Resources", b"file")
  assert_eq(fixed_directory_name(root, ""), Some(root))
  assert_eq(fixed_directory_name(root, "Store"), Some(root + "/Store"))
  assert_eq(fixed_directory_name(root, "Fonts"), Some(root + "/Fonts"))
  assert_eq(fixed_directory_name(root, "Resources"), None)
  assert_eq(fixed_directory_name(root, "missing"), None)
  assert_eq(primary_entry_name(root, "fONTS"), Some("Fonts"))
  if !@fs.exists(root + "/fonts") {
    @fs.mkdir(root + "/fonts")
    assert_eq(primary_entry_name(root, "fONTS"), None)
    assert_eq(primary_entry_name(root, "fonts"), Some("fonts"))
  } else {
    assert_eq(fixed_directory_name(root, "fONTS"), Some(root + "/Fonts"))
    assert_eq(long_component(root + "/fONTS", "fONTS"), "Fonts")
  }
}
