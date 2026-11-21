///|
async test "Windows GSM conversion must fit before the CLI can print a name" {
  let converter = request(["-wC55000", "name"]).prepare()
  assert_eq(converter.encode_output("a@" + "^".repeat(16382) + "x"), b"a")
  try converter.encode_output("a@" + "^".repeat(16383)) catch {
    @cli.UnsupportedCapability(reason) =>
      assert_eq(reason, "Windows GSM conversion exceeds the output buffer")
    err => raise err
  } noraise {
    _ => fail("expected GSM capacity error")
  }
}

///|
async test "installed Windows output looks up individual names in records and lists" {
  let visited : Array[String] = []
  let lookup : async (@lib.Context, String, @lib.InputSyntax, Bool) -> Result[
    String,
    String,
  ] = (context, path, from, absolute) => {
    visited.push(path)
    if path == "/missing/../x" {
      return Err("No such file or directory")
    }
    assert_true(!absolute)
    if path == "/link/../Keep" {
      Ok("D:\\Target\\Keep")
    } else {
      Ok(context.convert(path, from~, to=Windows, absolute~))
    }
  }
  let installation = @lib.Context::new(mounts=[@lib.Mount::new("/", "C:/root")])
  let converter = request(["-of-"]).prepare(installation~, lookup~)
  assert_true(
    converter.convert_file_record("-m /link/../Keep")
    is Output("D:/Target/Keep"),
  )
  guard converter.convert_file_record("-wr /link/../Keep") is Output(name) else {
    fail("expected Windows path")
  }
  assert_eq(converter.encode_output(name), b"\\\\?\\D:\\Target\\Keep")
  assert_true(
    converter.convert_file_record("-mp :/link/../Keep:/end")
    is Output(".;D:/Target/Keep;C:/root/end"),
  )
  assert_true(
    converter.convert_file_record("-u /link/../Keep")
    is OutputBytes(b"/link/../Keep"),
  )
  assert_eq(visited, [
    "/link/../Keep", "/link/../Keep", ".", "/link/../Keep", "/end",
  ])
  let windows = request(["--from", "windows", "-mp", "placeholder"]).prepare(
    installation~,
    lookup~,
  )
  assert_true(
    windows.convert_operand("C:\\one;;D:\\two;") is Output("C:/one;;D:/two;"),
  )
  for
    (record, expected) in [
      (
        "-w /missing/../x", "cygpath: error converting \"/missing/../x\" - No such file or directory",
      ),
      (
        "-wp /one:/missing/../x", "cygpath: error converting \"/one:/missing/../x\" - Unknown error -1",
      ),
    ] {
    try converter.convert_file_record(record) catch {
      @cli.CliError::_ as err => assert_eq(err.diagnostic(), expected)
      err => raise err
    } noraise {
      _ => fail("accepted invalid parent")
    }
  }
}

///|
async test "server observations apply to the current absolute directory operand" {
  let seen = []
  let server_lookup : async (String) -> Bool = server => {
    seen.push(server)
    server == "up"
  }
  let converter = request(["-of-"]).prepare(server_lookup~)
  assert_true(converter.convert_file_record("-m //down/") is Output("//down/"))
  assert_true(converter.convert_file_record("-am //down") is Output("//down"))
  assert_true(
    converter.convert_file_record("-amp //up/://down/")
    is Output("//up;//down/"),
  )
  assert_true(
    converter.convert_file_record("-M //tsclient/") is QueryMode("//tsclient/"),
  )
  let ctx = @lib.Context::new()
  let installed = request(["-am", "//up/"]).prepare(
    installation=ctx,
    server_lookup~,
    lookup=(context, path, from, absolute) => {
      Ok(context.convert(path, from~, absolute~, to=Windows))
    },
  )
  assert_true(installed.convert_operand("//up/") is Output("//up"))
  assert_true(
    converter.convert_file_record("-am //up/../down/") is Output("//down/"),
  )
  let explicit = request(["--root=C:/offline", "-am", "//up/"]).prepare(
    server_lookup~,
  )
  try explicit.convert_operand("//up/") catch {
    @cli.Conversion(@lib.NetworkServerLookup("up")) => ()
    err => raise err
  } noraise {
    _ => fail("an explicit mount context performed a host lookup")
  }
  assert_eq(seen, ["up", "down", "up", "up", "down"])
}

///|
async test "root-local output covers ordinary drive UNC and list behavior" {
  let drive = request(["-wr", "--root=C:/root", "/name"]).prepare()
  assert_eq(
    drive.encode_output(drive.convert("/name")),
    b"\\\\?\\C:\\root\\name",
  )
  assert_eq(
    drive.encode_output(drive.convert("//server/share/name")),
    b"\\\\?\\UNC\\server\\share\\name",
  )
  assert_eq(drive.encode_output(drive.convert("relative")), b"\\\\?\\relative")
  let list = request(["-wrp", "/cygdrive/c/name"]).prepare()
  assert_eq(list.encode_output(list.convert("/cygdrive/c/name")), b"C:\\name")
}

///|
async test "best-fit drive and UNC prefixes use the encoded byte limit" {
  let converter = request(["-wC1252", "name"]).prepare()
  for
    (input, prefix, trimmed) in [
      ("＼＼？＼Ｃ：＼", "\\\\?\\C:\\", "C:\\"),
      (
        "＼＼？＼ＵＮＣ＼ｓ＼ｖ＼", "\\\\?\\UNC\\s\\v\\", "\\\\s\\v\\",
      ),
    ] {
    for size in [259, 260] {
      let tail = size - trimmed.length()
      let expected = (if size < 260 { trimmed } else { prefix }) +
        "x".repeat(tail)
      assert_eq(
        converter.encode_output(input + "ｘ".repeat(tail)),
        @utf8.encode(expected),
      )
    }
  }
}

///|
async test "long lookup operates on encoded names and resets between file options" {
  let seen : Array[String] = []
  let expand : async (String) -> String = name => {
    seen.push(name)
    if name == "SMALL~1" {
      "Long name"
    } else {
      name
    }
  }
  let converter = request(["-of-"]).prepare()
  for
    (record, expected) in [
      ("-mlp SMALL~1:dir/file", b"Long name;dir/file"),
      ("SMALL~1", b"Long name"),
      ("-wlC65000 +", b"+--"),
      ("-w SMALL~1", b"SMALL~1"),
    ] {
    guard converter.convert_file_record(record) is Output(text) else {
      fail("expected output")
    }
    assert_eq(converter.encode_output(text, expand~), expected)
  }
  assert_eq(seen, ["SMALL~1", "dir\\file", "SMALL~1", "+-"])
  let path = "C:\\" + "x".repeat(256)
  let long = request(["-wl", path]).prepare()
  assert_eq(long.encode_output(path, expand~), @utf8.encode(path))
  assert_eq(seen.last(), Some("\\\\?\\" + path))
  let legacy = request(["-wlC1252", "é"]).prepare()
  try legacy.encode_output("é", expand~) catch {
    @cli.UnsupportedCapability(_) => ()
    err => raise err
  } noraise {
    _ => fail("invalid UTF-8 reached long-name lookup")
  }
}

///|
async test "DOS lookup encodes the whole list and reports its first failing member" {
  let seen : Array[String] = []
  let shorten : async (String) -> String? = name => {
    seen.push(name)
    if name == "missing" {
      None
    } else {
      Some(name)
    }
  }
  for option in ["-d", "-ws", "--dos", "--type=dos", "-tdos"] {
    let converter = request([option, "x"]).prepare()
    assert_eq(converter.encode_output("\\\\?\\D:\\X", shorten~), b"D:\\X")
  }
  seen.clear()
  let mixed = request(["-msp", "x"]).prepare()
  assert_eq(mixed.encode_output("a\\b;c", shorten~), b"a/b;c")
  try mixed.encode_output("first;missing;later", shorten~) catch {
    @cli.ShortNameFailure(name) as err => {
      assert_eq(name, "missing")
      assert_eq(err.exit_code(), 2)
      assert_eq(
        err.diagnostic(),
        "cygpath: cannot create short name of missing",
      )
    }
    err => raise err
  } noraise {
    _ => fail("missing member should fail the list")
  }
  assert_eq(seen, ["a\\b", "c", "first", "missing"])
  // EBCDIC encodes the separator with a different byte. Cygwin searches
  // for a literal narrow ';' before the second encoding pass.
  let ebcdic = request(["-dpC37", "x"]).prepare()
  // In CP37 spaces encode to '@' and ';' to '^'.
  try ebcdic.encode_output(" ; ", shorten=_ => None) catch {
    @cli.ShortNameFailure(name) => assert_eq(name, "@^@")
    err => raise err
  } noraise {
    _ => fail("expected the complete encoded member")
  }
  // U+009B supplies a literal 0x3B in the first pass. The separator
  // inserted between the two results must then be encoded as 0x5E.
  assert_eq(
    ebcdic.encode_output(" \u009B ", shorten=_ => Some("A")),
    b"\xC1\x5E\xC1",
  )
}

///|
async test "file option records retain state across plain lines and reset on options" {
  let converter = request(["-of-", "--root=C:/root"]).prepare()
  assert_true(
    converter.convert_file_record("/first") is Output("C:\\root\\first"),
  )
  assert_true(
    converter.convert_file_record("-m /next with spaces")
    is Output("C:/root/next with spaces"),
  )
  assert_true(
    converter.convert_file_record("/plain") is Output("C:/root/plain"),
  )
  assert_true(
    converter.convert_file_record("-u C:/outside")
    is OutputBytes(b"/cygdrive/c/outside"),
  )
  assert_true(
    converter.convert_file_record("C:/again")
    is OutputBytes(b"/cygdrive/c/again"),
  )
  assert_true(converter.convert_file_record("-h") is Stop(_))
}

///|
async test "file option operands are one string and empty handling follows per-line flags" {
  let converter = request(["-of-"]).prepare()
  assert_true(converter.convert_file_record("-wi ") is Skip)
  assert_true(converter.convert_file_record("") is Skip)
  assert_true(converter.convert_file_record("-wC1252 a") is Output("a"))
  assert_eq(converter.codepage(), 1252)
  assert_true(
    converter.convert_file_record("-uC932 C:/a")
    is OutputBytes(b"/cygdrive/c/a"),
  )
  assert_eq(converter.codepage(), 65001)
  assert_true(converter.convert_file_record("-i") is Stop(""))
  for record in ["-w", "-f file", "-o path", "-t windows /path"] {
    try converter.convert_file_record(record) catch {
      _ => ()
    } noraise {
      _ => fail("accepted an invalid option record: " + record)
    }
  }
}

///|
async test "option records reject context construction while retaining explicit source grammar" {
  let converter = request(["-of-", "--root=C:/root"]).prepare()
  for
    (option, record) in [
      ("--profile", "--profile=msys2 C:/name"),
      ("--root", "--root=D:/alt /name"),
      ("--mount", "--mount=/alt D:/alt"),
      ("--mount-case", "--mount-case=/alt sensitive"),
      ("--drive-prefix", "--drive-prefix=/drives C:/name"),
      ("--posix-cwd", "--posix-cwd=/alt name"),
      ("--windows-cwd", "--windows-cwd=D:/alt name"),
      ("--drive-cwd", "--drive-cwd=D D:/alt"),
    ] {
    try converter.convert_file_record(record) catch {
      @cli.InvalidOptions(reason) =>
        assert_eq(
          reason,
          option + " cannot change the fixed context in option records",
        )
      _ => fail("expected an explicit fixed-context error for " + option)
    } noraise {
      _ => fail("silently accepted context option " + option)
    }
    assert_eq(converter.convert("/name"), "C:\\root\\name")
  }
  assert_true(
    converter.convert_file_record("--from=posix /a/../b") is Output("/b"),
  )
}

///|
test "native source recognition distinguishes DOS-relative output from absolute requests" {
  let context_args = [
    "--root=C:/root", "--posix-cwd=/cygdrive/c/cwd", "--windows-cwd=C:/cwd",
  ]
  assert_eq(
    request(context_args + ["-w", "C:child"]).prepare().convert("C:child"),
    "C:child",
  )
  assert_eq(
    request(context_args + ["-aw", "C:child"]).prepare().convert("C:child"),
    "C:\\cwd\\C\uF03Achild",
  )
  assert_eq(
    request(context_args + ["-w", "C:"]).prepare().convert("C:"),
    "C:\\cwd\\C\uF03A",
  )
  assert_eq(
    request(context_args + ["-wp", "C:\\one;;D:\\two;"])
    .prepare()
    .convert("C:\\one;;D:\\two;"),
    "C;C:\\one;;D;C:\\two;",
  )
}

///|
test "official option failures keep exact diagnostic protocol" {
  assert_eq(
    parse_failure(["-f"]).diagnostic(),
    "cygpath: option requires an argument -- f\nTry `cygpath --help' for more information.",
  )
  assert_eq(
    parse_failure(["-w", "--root-local", "a"]).diagnostic(),
    "Try `cygpath --help' for more information.",
  )
  let usage = parse_failure(["-uw", "a"]).diagnostic()
  assert_true(usage.has_prefix("Usage: cygpath (-d|-m|-u|-w|-t TYPE)"))
  assert_true(usage.has_suffix("Try `cygpath --help' for more information."))
  assert_eq(usage, parse_failure(["-u"]).diagnostic())
  assert_true(parse_failure(["-tinvalid", "--unknown"]) is Usage)
  assert_true(@cli.parse_args(["-i", "-tinvalid", "--unknown"]) is ExitSuccess)
  assert_true(parse_failure(["--unknown", "-tinvalid"]) is UnknownOption(_))
  assert_eq(
    request(["--uni", "C:/a"]).prepare().convert("C:/a"),
    "/cygdrive/c/a",
  )
  assert_eq(
    parse_failure(["--win", "a"]).diagnostic(),
    "cygpath: ambiguous option -- win\nTry `cygpath --help' for more information.",
  )
  assert_true(parse_failure(["--roo", "a"]) is UnknownOption("--root-local"))
}

///|
test "mount comparison policy is explicit order-independent and ASCII-only" {
  let converter = request([
    "--mount-case", "/Tools/", "ascii-insensitive", "--mount", "/Tools", "C:/Mixed",
    "-u", "c:/MIXED/File",
  ]).prepare()
  assert_eq(converter.convert("c:/MIXED/File"), "/Tools/File")
  assert_eq(
    request([
      "-w", "--mount", "/Tools", "C:/Mixed", "--mount-case", "/Tools", "ascii-insensitive",
      "/tools/File",
    ])
    .prepare()
    .convert("/tools/File"),
    "C:\\Mixed\\File",
  )
  assert_true(
    parse_failure(["--mount-case", "/missing", "sensitive", "a"])
    is InvalidOptions(_),
  )
  assert_true(
    parse_failure(["--mount-case", "/Tools", "unicode-insensitive", "a"])
    is InvalidOptions(_),
  )
}

///|
async test "mount mode is its own output selector, including option records" {
  for flags in ["-Mu", "-Mw", "-Mm", "-Mr"] {
    assert_true(parse_failure([flags, "x"]) is Usage)
  }
  assert_true(parse_failure(["-Mwuof-"]) is Usage)
  let modes = request(["-MipC9999", "x"]).prepare()
  assert_true(modes.convert_operand("") is QueryMode(""))
  assert_true(modes.convert_operand("a:b") is QueryMode("a:b"))
  let records = request(["-Mwof-"]).prepare()
  assert_true(records.convert_file_record("first") is QueryMode("first"))
  assert_true(
    records.convert_file_record("-u C:/x") is OutputBytes(b"/cygdrive/c/x"),
  )
  assert_true(records.convert_file_record("-M next") is QueryMode("next"))
  assert_true(records.convert_file_record("last") is QueryMode("last"))
}

///|
async test "folder actions use Windows syntax, single-path mounts and per-record options" {
  let converter = request(["--mount", "/win", "D:/WiN", "-of-"]).prepare()
  let seen = []
  let resolve : async (String) -> String? = child => {
    seen.push(child)
    match child {
      "" => Some("D:/WiN")
      "Resources" => None
      _ => Some("D:/WiN/" + child)
    }
  }
  guard converter.convert_file_record("-upF0x25") is QueryFolder(folder) else {
    fail("expected system directory")
  }
  assert_eq(converter.folder_output(folder, resolve), Some(b"/win/System32"))
  guard converter.convert_file_record("-UW") is QueryFolder(folder) else {
    fail("expected Windows directory")
  }
  assert_eq(converter.folder_output(folder, resolve), Some(b"/win"))
  for
    (record, expected) in [
      ("-uF0x14", Some(b"/win/Fonts")),
      ("-uF41", Some(b"/win/SysWOW64")),
      ("-uF0x1029", Some(b"/win/SysWOW64")),
      ("-uF0x2025", Some(b"/win/System32")),
      ("-uF0x3024", Some(b"/win")),
      ("-uF070", None),
      ("-wF0x403d", None),
    ] {
    guard converter.convert_file_record(record) is QueryFolder(folder) else {
      fail("expected folder query")
    }
    assert_eq(converter.folder_output(folder, resolve), expected)
  }
  guard converter.convert_file_record("-wdF17") is QueryFolder(folder) else {
    fail("expected virtual shell folder")
  }
  assert_eq(converter.folder_output(folder, resolve), None)
  guard converter.convert_file_record("D:/next") is Output(native) else {
    fail("expected a name after the folder selector")
  }
  let shorten : async (String) -> String? = name => Some(name + ".DOS")
  assert_eq(converter.encode_output(native, shorten~), b"D:\\next.DOS")
  assert_eq(seen, [
    "System32", "", "Fonts", "SysWOW64", "SysWOW64", "System32", "", "Resources",
  ])
  assert_true(
    converter.convert_file_record("-m /win/next") is Output("D:/WiN/next"),
  )
  assert_true(
    converter.convert_file_record("/win/last") is Output("D:/WiN/last"),
  )
}

///|
async test "device alias lookup uses the encoded bytes for each Windows output member" {
  assert_false(request(["-u", "/dev/null"]).needs_device_probe())
  assert_false(request(["-w", "/ordinary/file"]).needs_device_probe())
  assert_true(request(["-M", "/dev/null"]).needs_device_probe())
  assert_true(request(["-uf", "/dev/null"]).needs_device_probe())
  assert_true(request(["-of-"]).needs_device_probe())
  let ctx = @lib.Context::new(nt_null=true)
  for
    (flags, value) in [
      ("-w", "/dev/null"),
      ("-m", "/dev/zero"),
      ("-wp", "/dev/tty:/dev/null"),
    ] {
    let converter = request([flags, value]).prepare(installation=ctx)
    guard converter.convert_operand(value) is Output(text) else {
      fail("expected a device path")
    }
    try converter.encode_output(text) catch {
      @cli.UnsupportedCapability(_) => ()
      err => raise err
    } noraise {
      _ => fail("returned the NT path as a DOS alias")
    }
  }
  let cp37 = request(["-mC37", "/dev/null"]).prepare(nt_null=true)
  guard cp37.convert_operand("/dev/null") is Output(text) else {
    fail("expected a device path")
  }
  // IBM037 encoding of the runtime spelling. Neither an ASCII device prefix
  // nor an ASCII backslash remains for the two subsequent CLI passes.
  assert_eq(
    cp37.encode_output(text),
    b"\xe0\xe0\x4b\xe0\xc7\xd3\xd6\xc2\xc1\xd3\xd9\xd6\xd6\xe3\xe0\xc4\x85\xa5\x89\x83\x85\xe0\xd5\xa4\x93\x93",
  )
}
