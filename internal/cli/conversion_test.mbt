///|
test "default syntax and single Windows recognition are deterministic" {
  assert_eq(
    request(["C:/work"]).prepare().convert("C:/work"),
    "/cygdrive/c/work",
  )
  assert_eq(request(["-w", "C:/work"]).prepare().convert("C:/work"), "C:\\work")
  assert_eq(request(["-w", "a/b"]).prepare().convert("a/b"), "a\\b")
  assert_eq(
    request(["-u", "--from=posix", "/usr/bin"]).prepare().convert("/usr/bin"),
    "/usr/bin",
  )
  assert_eq(
    request(["-m", "--from=windows", "C:a"]).prepare().convert("C:a"),
    "C:a",
  )
  assert_eq(
    request(["-w", "--windows-cwd=C:/cwd", "\\name"])
    .prepare()
    .convert("\\name"),
    "C:\\name",
  )
  assert_eq(
    request(["-w", "/\\?/C:/name"]).prepare().convert("/\\?/C:/name"),
    "C:\\name",
  )
  assert_eq(
    request(["-u", "/usr/bin"]).prepare().convert("/usr/bin"),
    "/usr/bin",
  )
  assert_eq(
    request(["-u", "/dev/null"]).prepare().convert("/dev/null"),
    "/dev/null",
  )
  assert_eq(request(["-au", "/a/../b"]).prepare().convert("/a/../b"), "/a/../b")
  assert_eq(request(["-w", "a\\b"]).prepare().convert("a\\b"), "a\\b")
}

///|
test "root mounts explicit aliases and fallback profiles" {
  let converter = request([
    "-w", "--root", "C:/cygwin64", "--mount", "/usr/bin", "C:/cygwin64/bin", "/usr/bin/tool",
  ]).prepare()
  assert_eq(converter.convert("/usr/bin/tool"), "C:\\cygwin64\\bin\\tool")
  assert_eq(converter.convert("/usr/lib"), "C:\\cygwin64\\usr\\lib")
  assert_eq(
    request(["--profile=msys2", "C:/work"]).prepare().convert("C:/work"),
    "/c/work",
  )
  assert_eq(
    request(["--drive-prefix=/drives", "C:/work"]).prepare().convert("C:/work"),
    "/drives/c/work",
  )
  let proc = request(["-U", "--mount", "/work", "C:/work", "C:/work"]).prepare()
  assert_eq(proc.convert("C:/work"), "/work")
  assert_eq(proc.convert("D:/work"), "/proc/cygdrive/d/work")
}

///|
test "absolute conversion uses only supplied cwd and drive state" {
  let posix = request([
    "-aw", "--root=C:/cygwin64", "--posix-cwd=/home/user", "../work",
  ]).prepare()
  assert_eq(posix.convert("../work"), "C:\\cygwin64\\home\\work")
  let windows = request([
    "-au", "--windows-cwd=C:/work", "--drive-cwd", "D", "D:/other", "name",
  ]).prepare()
  assert_eq(windows.convert("name"), "/cygdrive/c/work/name")
  assert_eq(windows.convert("D:name"), "/cygdrive/d/name")
  assert_true(
    parse_failure(["--drive-cwd", "C", "C:/a", "--drive-cwd", "c", "C:/b", "x"])
    is InvalidOptions(_),
  )
}

///|
test "context validation occurs before conversion and retains its category" {
  try request(["--root=relative", "C:/work"]).prepare() catch {
    error => {
      assert_eq(error.exit_code(), 1)
      assert_true(error.diagnostic().contains("invalid-context:"))
    }
  } noraise {
    _ => fail("expected invalid context")
  }
  try request(["-au", "name"]).prepare().convert("name") catch {
    error => {
      assert_eq(error.exit_code(), 1)
      assert_true(error.diagnostic().contains("missing-context:"))
    }
  } noraise {
    _ => fail("expected missing cwd")
  }
}

///|
test "lists have one input syntax and fail atomically" {
  let windows = request(["-pu", "C:/a;;D:/b"]).prepare()
  assert_eq(windows.convert("C:/a;;D:/b"), "/cygdrive/c/a:/cygdrive/d/b")
  let posix = request(["-pm", "--from=posix", "/cygdrive/c/a::/cygdrive/d/b"]).prepare()
  assert_eq(posix.convert("/cygdrive/c/a::/cygdrive/d/b"), "C:/a;.;D:/b")
  // A Windows-looking member never changes a list's declared/default syntax.
  assert_eq(
    request(["-pw", "--root=C:/cyg", "C:/a"]).prepare().convert("C:/a"),
    "C;C:\\cyg\\a",
  )
  try windows.convert("C:/good;\\\\.\\COM1") catch {
    error => {
      assert_eq(error.exit_code(), 2)
      assert_true(error.diagnostic().contains("list-entry: index 1:"))
    }
  } noraise {
    _ => fail("expected atomic list failure")
  }
}

///|
test "operand line breaks are preserved while diagnostics escape control text" {
  let converter = request(["--from=posix", "name"]).prepare()
  for text in ["line\nname", "line\rname", "\r\n"] {
    assert_eq(converter.convert(text), text)
  }
  let error = parse_failure(["--bad"])
  assert_eq(
    error.diagnostic(),
    "cygpath: unknown option -- bad\nTry `cygpath --help' for more information.",
  )
  assert_eq(error.exit_code(), 1)
}
