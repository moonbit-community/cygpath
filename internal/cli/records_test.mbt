///|
test "root-local output covers ordinary drive UNC and list behavior" {
  let drive = request(["-wr", "--root=C:/root", "/name"]).prepare()
  assert_eq(drive.convert("/name"), "\\\\?\\C:\\root\\name")
  assert_eq(
    drive.convert("//server/share/name"),
    "\\\\?\\UNC\\server\\share\\name",
  )
  assert_eq(drive.convert("relative"), "\\\\?\\relative")
  assert_eq(
    request(["-wrp", "/cygdrive/c/name"]).prepare().convert("/cygdrive/c/name"),
    "C:\\name",
  )
}

///|
test "file option records retain state across plain lines and reset on options" {
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
    is Output("/cygdrive/c/outside"),
  )
  assert_true(
    converter.convert_file_record("C:/again") is Output("/cygdrive/c/again"),
  )
  assert_true(converter.convert_file_record("-h") is Stop(_))
}

///|
test "file option operands are one string and empty handling follows per-line flags" {
  let converter = request(["-of-"]).prepare()
  assert_true(converter.convert_file_record("-wi ") is Skip)
  assert_true(converter.convert_file_record("") is Skip)
  assert_true(converter.convert_file_record("-wC1252 a") is Output("a"))
  assert_eq(converter.codepage(), 1252)
  assert_true(
    converter.convert_file_record("-uC932 C:/a") is Output("/cygdrive/c/a"),
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
test "option records reject context construction while retaining explicit source grammar" {
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
