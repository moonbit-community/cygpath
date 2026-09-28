///|
test "explicit Windows code pages preserve their distinct byte mappings" {
  assert_eq(@encoding.encode("C:/café/€", 1252), b"C:/caf\xe9/\x80")
  assert_eq(@encoding.encode("C:/中文", 936), b"C:/\xd6\xd0\xce\xc4")
  assert_eq(@encoding.encode("C:/中文", 950), b"C:/\xa4\xa4\xa4\xe5")
  assert_eq(@encoding.encode("C:/日本/¥", 932), b"C:/\x93\xfa\x96\x7b/\x5c")
  assert_eq(@encoding.encode("C:/한글", 949), b"C:/\xc7\xd1\xb1\xdb")
  assert_eq(@encoding.encode("C:/ไทย", 874), b"C:/\xe4\xb7\xc2")
}

///|
test "best fit, missing characters, and UTF-8 are explicit policies" {
  assert_eq(@encoding.encode("Ａ", 1252), b"A")
  assert_eq(@encoding.encode("中文", 1252), b"??")
  assert_eq(@encoding.encode("€😀", 65001), b"\xe2\x82\xac\xf0\x9f\x98\x80")
  assert_true(!@encoding.supported(0))
  assert_true(!@encoding.supported(123456))
  assert_true(@encoding.supported(1361))
  assert_true(@encoding.supported(1258))
  try {
    ignore(@encoding.encode("x", 0))
    fail("an unspecified host ANSI page must not be guessed")
  } catch {
    @encoding.UnsupportedCodePage(0) => ()
    _ => fail("wrong encoding error")
  }
}

///|
test "legacy output replaces each UTF-16 surrogate while UTF-8 preserves scalars" {
  for
    page in [
      874, 932, 936, 949, 950, 1250, 1251, 1252, 1253, 1254, 1255, 1256, 1257, 1258,
      1361,
    ] {
    assert_eq(@encoding.encode("x😀y𐀀z", page), b"x??y??z")
  }
  assert_eq(@encoding.encode("😀", 65001), b"\xf0\x9f\x98\x80")
}

///|
test "OEM and KOI8 mappings retain code-page-specific characters and best fits" {
  assert_eq(@encoding.encode("éøα", 437), b"\x82o\xe0")
  assert_eq(@encoding.encode("éøα", 850), b"\x82\x9ba")
  assert_eq(@encoding.encode("Жяé", 866), b"\x86\xefe")
  assert_eq(@encoding.encode("Жя", 20866), b"\xf6\xd1")
}

///|
test "Windows ASCII and ISO encoders use the published best-fit mappings" {
  assert_eq(@encoding.encode("éĀＡ\u{a0}", 20127), b"eAA ")
  assert_eq(@encoding.encode("éĀＡ\u{a0}", 28591), b"\xe9AA\xa0")
  assert_eq(@encoding.encode("€", 28605), b"\xa4")
  for page in [437, 850, 866, 20127, 28591] {
    assert_eq(@encoding.encode("中😀", page), b"???")
  }
}

///|
test "EBCDIC defaults and control bytes are data rather than ASCII assumptions" {
  assert_eq(@encoding.encode("A?\n😀", 37), b"\xc1\x6f\x25\x6f\x6f")
}

///|
test "Macintosh and T61 mappings retain their distinct single and double bytes" {
  assert_eq(@encoding.encode("é¥", 10000), b"\x8e\xb4")
  assert_eq(@encoding.encode("日本¥", 10001), b"\x93\xfa\x96\x7b\x81\x8f")
  assert_eq(@encoding.encode("한글", 10003), b"\xc7\xd1\xb1\xdb")
  assert_eq(@encoding.encode("é", 20261), b"\xc2e")
}
