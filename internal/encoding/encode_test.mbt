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
