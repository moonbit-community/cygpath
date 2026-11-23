///|
async test "long names preserve the root, separator spelling and queried links" {
  let visited : Array[String] = []
  let entry : async (String, String) -> String = (path, name) => {
    visited.push(path)
    if name == "REPORT~1" {
      "Report files"
    } else {
      name
    }
  }
  for
    root in [
      "", "D:", "D:\\", "\\", "\\\\server\\share\\", "\\\\?\\UNC\\server\\share\\",
      "\\\\?\\D:\\",
    ] {
    visited.clear()
    assert_eq(
      expand_long_components(root + ".\\REPORT~1/../Link/", entry),
      root + ".\\Report files/../Link/",
    )
    assert_eq(visited, [root + ".\\REPORT~1", root + ".\\REPORT~1/../Link"])
  }
  assert_true(is_ascii_short_component("FILE.TXT"))
  assert_true(is_ascii_short_component("FILE~1"))
  assert_false(is_ascii_short_component("Report.backup"))
  assert_false(is_ascii_short_component("École"))
  assert_false(is_ascii_short_component("Ab."))
  for name in ["A+B.txt", "A B.txt", "A😀bcdef", "Ωmega.txt", "Ab."] {
    assert_true(may_expand_long_component(name))
  }
  for name in [".abc", "A.B.C", "A😀bcdefg", "AB.ABCD"] {
    assert_false(may_expand_long_component(name))
  }
}

///|
async test "long lookup uses the entire original name when a component is missing" {
  let tmp = @fs.tmpdir(prefix="cygpath-long-")
  defer @fs.remove(tmp, recursive=true)
  let base = plain_native(@fs.realpath(tmp))
  @fs.mkdir(base + "/Destination")
  @fs.write_binary(base + "/Destination/Report.txt", b"test")
  @fs.symlink(base + "/Link", target=base + "/Destination")
  for part in ["Link/Report.txt", "Link/absent", "missing/Report.txt"] {
    let path = base + "/" + part
    assert_eq(long_name_on_disk(path), path)
  }
  let prefix = base.replace_all(old="/", new="\\") + "\\missing\\"
  let missing = prefix + "x".repeat(259 - prefix.length())
  assert_eq(missing.length(), 259)
  let wide = "\\\\?\\" + missing
  assert_eq(long_name_on_disk(wide), wide)
}

///|
async test "link alias lookup keeps the link entry and refuses ambiguous targets" {
  let tmp = @fs.tmpdir(prefix="cygpath-link-id-")
  defer @fs.remove(tmp, recursive=true)
  let dir = plain_native(@fs.realpath(tmp))
  let link = dir + "/Link"
  @fs.write_binary(dir + "/file", b"file")
  @fs.write_binary(dir + "/other", b"file")
  @fs.symlink(link, target=dir + "/file")
  @fs.symlink(dir + "/Elsewhere", target=dir + "/other")
  assert_eq(link_alias_entry(link, "Link"), Some("Link"))
  @fs.symlink(dir + "/Twin", target=dir + "/file")
  assert_eq(link_alias_entry(link, "Link"), None)
  assert_eq(long_component(link, "Link"), "Link")
}

///|
test "DOS eligibility checks every component after the volume or share" {
  for
    root in [
      "", "D:", "D:/", "//server/long share/", "\\\\?\\D:\\", "\\\\?\\UNC\\server\\long share\\",
    ] {
    assert_true(already_short_path(root + "ReAdMe.TxT"))
    assert_true(already_short_path(root + "DiR/FiLe~1.TxT"))
    assert_false(already_short_path(root + "Directory name/X.TXT"))
    assert_false(already_short_path(root + "DIR/X.more"))
    assert_false(already_short_path(root + "DIR/A B.TXT"))
  }
  assert_false(already_short_path("\\\\.\\PIPE\\short"))
  assert_false(already_short_path("\\\\?\\GLOBALROOT\\DEVICE"))
}

///|
async test "DOS lookup distinguishes missing paths from unavailable alias metadata" {
  let tmp = @fs.tmpdir(prefix="cygpath-short-")
  defer @fs.remove(tmp, recursive=true)
  @fs.write_binary(tmp + "/KNOWN.TXT", b"test")
  assert_eq(short_name_on_disk(tmp + "/missing"), None)
  assert_eq(short_name_on_disk(tmp + "/KNOWN.TXT/child"), None)
  try short_name_on_disk(tmp + "/KNOWN.TXT") catch {
    NameLookupUnavailable(_) => ()
    err => raise err
  } noraise {
    _ => fail("a long parent requires its own stored DOS alias")
  }
}
