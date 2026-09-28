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
  for record in ["-w", "-f file", "-o path", "-t windows /path"] {
    try converter.convert_file_record(record) catch {
      _ => ()
    } noraise {
      _ => fail("accepted an invalid option record: " + record)
    }
  }
}
