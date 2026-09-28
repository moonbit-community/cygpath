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

///|
test "POSIX output uses the same long-component rules for arguments and records" {
  let converter = request(["-u", "-f", "-"]).prepare()
  let chunk = "C:\\" + "a".repeat(8189)
  let expected = "/cygdrive/c/" + "a".repeat(8189)
  assert_eq(converter.convert(chunk), expected)
  match converter.convert_file_record(chunk) {
    Output(value) => assert_eq(value, expected)
    _ => fail("expected a complete converted buffer chunk")
  }
  let remainder = "a".repeat(311) + "\\tail"
  match converter.convert_file_record(remainder) {
    Output(value) => assert_eq(value, "a".repeat(311) + "/tail")
    _ => fail("expected the remaining chunk to be converted independently")
  }
}

///|
test "Windows length failures quote the original operand without escaping it" {
  let converter = request(["-w", "-f", "-"]).prepare()
  let path = "C:\\" + "a".repeat(256)
  try converter.convert(path) catch {
    error => {
      assert_eq(error.exit_code(), 1)
      assert_eq(
        error.diagnostic(),
        "cygpath: error converting \"" + path + "\" - File name too long",
      )
    }
  } noraise {
    _ => fail("expected the Windows output length failure")
  }
  try converter.convert_file_record(path) catch {
    error => assert_eq(error.exit_code(), 1)
  } noraise {
    _ => fail("file records must retain Windows component-length validation")
  }
}

///|
test "a malformed configured drive path preserves the official operand diagnostic" {
  let converter = request([
    "-w", "--drive-prefix=/p3-drives", "--root=C:/root", "name",
  ]).prepare()
  let path = "/p3-drives/cat/file"
  try converter.convert(path) catch {
    error => {
      assert_true(error is @cli.PathNotFound(_))
      assert_eq(error.exit_code(), 1)
      assert_eq(
        error.diagnostic(),
        "cygpath: error converting \"/p3-drives/cat/file\" - No such file or directory",
      )
    }
  } noraise {
    _ => fail("expected malformed drive-prefix failure")
  }
}

///|
test "list length failure reports the whole original operand atomically" {
  let converter = request(["-wp", "name"]).prepare()
  let path = "/proc/cygdrive/c/ok:/proc/cygdrive/c/" + "a".repeat(256)
  try converter.convert(path) catch {
    error => {
      assert_true(
        error
        is @cli.ListConversion(
          _,
          @lib.ListEntryError(index=1, @lib.PathTooLong(_))
        ),
      )
      assert_eq(error.exit_code(), 1)
      assert_eq(
        error.diagnostic(),
        "cygpath: error converting \"" + path + "\" - Unknown error -1",
      )
    }
  } noraise {
    _ => fail("expected atomic list conversion failure")
  }
}

///|
test "list drive-prefix failure preserves its typed cause and wrapper diagnostic" {
  let converter = request(["-wp", "--drive-prefix=/p3-drives", "name"]).prepare()
  let path = "/p3-drives/c/ok:/p3-drives/cat/file"
  try converter.convert(path) catch {
    error => {
      assert_true(
        error
        is @cli.ListConversion(
          _,
          @lib.ListEntryError(index=1, @lib.InvalidDrivePrefix)
        ),
      )
      assert_eq(error.exit_code(), 1)
      assert_eq(
        error.diagnostic(),
        "cygpath: error converting \"" + path + "\" - Unknown error -1",
      )
    }
  } noraise {
    _ => fail("expected atomic list drive-prefix failure")
  }
}
