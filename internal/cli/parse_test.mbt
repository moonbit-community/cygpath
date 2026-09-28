///|
fn request(args : Array[String]) -> @cli.Request raise @cli.CliError {
  match @cli.parse_args(args) {
    Convert(request) => request
    _ => raise @cli.InvalidOptions("test expected a conversion request")
  }
}

///|
fn parse_failure(args : Array[String]) -> @cli.CliError raise {
  try @cli.parse_args(args) catch {
    error => error
  } noraise {
    _ => fail("expected an argument failure")
  }
}

///|
test "help and version do not construct or inspect context" {
  assert_true(@cli.parse_args(["-h", "--root", "relative"]) is Help)
  assert_true(@cli.parse_args(["--version", "--file", "missing"]) is Version)
  assert_true(@cli.parse_args(["-h", "--bad"]) is Help)
  assert_true(@cli.parse_args(["-hV"]) is Help)
  assert_true(@cli.parse_args(["-help"]) is Help)
  assert_true(@cli.parse_args(["-uw", "-h"]) is Help)
  assert_true(parse_failure(["--bad", "-h"]) is UnknownOption(_))
  assert_true(@cli.help_text().has_suffix("\n"))
  assert_eq(
    @cli.version_text(),
    "cygpath (MoonBit) 0.1.0\nProfiles: cygwin, msys2\n",
  )
}

///|
test "short bundles attached values and long equal values" {
  let converter = request(["-am", "--from=windows", "C:\\a\\..\\b"]).prepare()
  assert_eq(converter.convert("C:\\a\\..\\b"), "C:/b")
  assert_eq(request(["-tmixed", "a"]).prepare().convert("a"), "a")
  assert_eq(request(["--type=windows", "a/b"]).prepare().convert("a/b"), "a\\b")
  assert_eq(
    request(["-t", "unix", "C:/a"]).prepare().convert("C:/a"),
    "/cygdrive/c/a",
  )
  assert_true(request(["-finput.txt"]).input() is File("input.txt"))
  assert_true(request(["--file=-"]).input() is File("-"))
}

///|
test "GNU argument permutation and double dash preserve operand order" {
  assert_true(request(["name", "-w", "--"]).input() is Names(["name"]))
  assert_true(
    request(["--", "-w", "--help"]).input() is Names(["-w", "--help"]),
  )
  assert_true(request(["-"]).input() is Names(["-"]))
  assert_eq(request(["a/b", "-w"]).prepare().convert("a/b"), "a\\b")
  assert_true(
    request(["a", "-w", "b", "--", "-u"]).input() is Names(["a", "b", "-u"]),
  )
  assert_true(parse_failure(["--"]) is MissingInput)
}

///|
test "argument storage is isolated from caller mutation" {
  let args = ["-u", "C:/original"]
  let parsed = request(args)
  args[1] = "C:/changed"
  guard parsed.input() is Names(names) else { fail("expected names") }
  names[0] = "another change"
  assert_true(parsed.input() is Names(["C:/original"]))
}

///|
test "all value options diagnose a missing operand" {
  for
    option in [
      "-t", "-f", "-C", "-F", "-c", "--type", "--file", "--codepage", "--folder",
      "--close", "--from", "--profile", "--root", "--mount", "--drive-prefix", "--posix-cwd",
      "--windows-cwd", "--drive-cwd",
    ] {
    assert_true(parse_failure([option]) is MissingValue(_))
  }
  assert_true(parse_failure(["--mount", "/x"]) is MissingValue("--mount"))
  assert_true(
    parse_failure(["--drive-cwd", "C"]) is MissingValue("--drive-cwd"),
  )
  assert_true(parse_failure(["--unix=yes"]) is InvalidOptions(_))
}

///|
test "identical output formats repeat and conflicting formats fail" {
  assert_eq(
    request(["-uu", "--type=unix", "C:/x"]).prepare().convert("C:/x"),
    "/cygdrive/c/x",
  )
  for args in [["-uw", "x"], ["-t", "invalid", "x"]] {
    assert_true(parse_failure(args) is InvalidOptions(_))
  }
  assert_true(parse_failure(["--profile=other", "x"]) is InvalidOptions(_))
  for
    options in [
      ["-mw", "a/b"],
      ["-wm", "a/b"],
      ["-m", "--type=windows", "a/b"],
      ["-t=MiXeD", "a/b"],
    ] {
    assert_eq(request(options).prepare().convert("a/b"), "a/b")
  }
  assert_true(parse_failure(["--from=auto", "x"]) is InvalidOptions(_))
  assert_true(
    parse_failure(["--from=windows", "--from=posix", "x"]) is InvalidOptions(_),
  )
}

///|
test "every unavailable option is recognized" {
  for
    option in [
      "-d", "-s", "-l", "-M", "-D", "-H", "-O", "-P", "-S", "-W", "--dos", "--short-name",
      "--long-name", "--mode", "--desktop", "--homeroot", "--mydocs", "--smprograms",
      "--sysdir", "--windir",
    ] {
    assert_true(parse_failure(["-w", option, "x"]) is UnsupportedCapability(_))
  }
  for
    args in [
      ["-t", "dos", "x"],
      ["--type=dos", "x"],
      ["-F", "1"],
      ["--folder=1"],
      ["-c", "1"],
      ["--close=1"],
      ["-wC", "ANSI", "x"],
      ["-w", "--codepage=0", "x"],
    ] {
    assert_true(parse_failure(args) is UnsupportedCapability(_))
  }
  assert_true(parse_failure(["--unknown"]) is UnknownOption("--unknown"))
  assert_true(parse_failure(["-z"]) is UnknownOption("-z"))
}

///|
test "namespace and filename mode conflicts precede unsupported errors" {
  for flags in ["-rs", "-rl", "-sl", "-dl", "-dr"] {
    assert_true(parse_failure([flags, "x"]) is InvalidOptions(_))
  }
  assert_eq(request(["-wU", "a/b"]).prepare().convert("a/b"), "a\\b")
  assert_eq(request(["-mU", "a/b"]).prepare().convert("a/b"), "a/b")
  assert_true(parse_failure(["-ur", "x"]) is InvalidOptions(_))
  assert_true(parse_failure(["-mr", "x"]) is InvalidOptions(_))
}

///|
test "pure code page selection affects Windows output only" {
  for page in ["UTF8", "utf-8", "65001"] {
    assert_eq(request(["-m", "-C", page, "a"]).prepare().convert("a"), "a")
    assert_eq(request(["-u", "-C", page, "C:/a"]).prepare().codepage(), 65001)
  }
  for
    (page, number) in [
      ("1252", 1252),
      ("932", 932),
      ("936", 936),
      ("1361", 1361),
    ] {
    assert_eq(request(["-w", "-C", page, "a"]).prepare().codepage(), number)
    assert_eq(request(["-u", "-C", page, "C:/a"]).prepare().codepage(), 65001)
  }
  for page in ["ANSI", "OEM", "0", "999999"] {
    assert_eq(
      request(["-u", "-C", page, "C:/a"]).prepare().convert("C:/a"),
      "/cygdrive/c/a",
    )
  }
  assert_eq(request(["-wCANSI", "-C1252", "a"]).prepare().codepage(), 1252)
  assert_eq(request(["-wA", "a/b"]).prepare().convert("a/b"), "a\\b")
  assert_true(
    parse_failure(["-w", "-C", "OEM", "x"]) is UnsupportedCapability(_),
  )
}

///|
test "file and NAME are mutually exclusive and ignore suppresses empty operands" {
  assert_true(parse_failure([]) is MissingInput)
  let empty = request(["-i"])
  assert_true(empty.ignore_missing())
  assert_true(empty.input() is Names([]))
  assert_true(parse_failure(["-f", "-", "name"]) is InvalidOptions(_))
  assert_true(parse_failure(["-i", "--unknown"]) is UnknownOption(_))
  assert_true(request(["-i", ""]).prepare().convert_operand("") is Skip)
  try request([""]).prepare().convert("") catch {
    error => {
      assert_eq(error.exit_code(), 1)
      assert_eq(error.diagnostic(), "cygpath: can't convert empty path")
    }
  } noraise {
    _ => fail("accepted an empty path without ignore")
  }
}
