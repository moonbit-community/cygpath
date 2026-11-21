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
  assert_eq(dos_component("FILE.TXT"), Some(true))
  assert_eq(dos_component("FILE~1"), Some(true))
  assert_eq(dos_component("Report.backup"), Some(false))
  assert_eq(dos_component("École"), None)
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
    _ => fail("a primary name does not establish the alternate spelling")
  }
}
