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
test "ISO-2022-KR designates once and shifts back at ASCII and record end" {
  assert_true(@encoding.supported(50225))
  assert_eq(@encoding.encode("ASCII~", 50225), b"ASCII~")
  assert_eq(
    @encoding.encode("A한글/한 B", 50225),
    b"A\x1b$)C\x0eGQ1[\x0f/\x0eGQ\x0f B",
  )
  assert_eq(@encoding.encode("한", 50225), b"\x1b$)C\x0eGQ\x0f")
  assert_eq(@encoding.encode("₩힣😀", 50225), b"????")
}

///|
test "HZ-GB-2312 separates GB runs from literal tilde escapes" {
  assert_true(@encoding.supported(52936))
  assert_eq(@encoding.encode("~{}~", 52936), b"~~{}~~")
  assert_eq(@encoding.encode("A中文~中文B", 52936), b"A~{VPND~}~~~{VPND~}B")
  assert_eq(@encoding.encode("文", 52936), b"~{ND~}")
  assert_eq(@encoding.encode("丂€😀\u{f8f5}", 52936), b"????~{\x1e")
}

///|
test "the Japanese ISO-2022 selectors preserve their distinct kana transitions" {
  assert_eq(@encoding.encode("日ｶ本", 50220), b"\x1b$BF|%+K\\\x1b(B")
  assert_eq(
    @encoding.encode("日ｶ本", 50221),
    b"\x1b$BF|\x1b(I6\x1b$BK\\\x1b(B",
  )
  assert_eq(
    @encoding.encode("日ｶ本", 50222),
    b"\x1b$BF|\x1b(J\x0e6\x1b$BK\\\x1b(B",
  )
  assert_eq(@encoding.encode("ｶﾞ", 50220), b"\x1b$B%+!+\x1b(B")
  assert_eq(@encoding.encode("Aｶ", 50222), b"A\x1b(J\x0e6\x1b(B")
  for page in [50220, 50221, 50222] {
    assert_true(@encoding.supported(page))
    assert_eq(
      @encoding.encode("丂髙①😀", page),
      b"\x1b$(D0!t)\x1b$B-!\x1b(B??",
    )
  }
}

///|
test "numeric pages match the Windows NLS scalar captures" {
  for
    (page, expected) in [
      (50220, 0x5a266094U),
      (50221, 0x1a62ec0bU),
      (50222, 0x9509ec57U),
      (50225, 0xf130ffcdU),
      (50227, 0xdabfa81aU),
      (50229, 0x46d74693U),
      (52936, 0xeb8eb3e8U),
      (55000, 0xe995b31dU),
      (55001, 0xad4a30eaU),
      (55002, 0x84a31c09U),
      (55003, 0x4ef14212U),
      (55004, 0x6aa72978U),
      (57002, 0xe60ed2b0U),
      (57003, 0x3d46605cU),
      (57004, 0xec2fddeeU),
      (57005, 0xaa054c10U),
      (57006, 0xcb4c3458U),
      (57007, 0x0c281650U),
      (57008, 0x144a2bf4U),
      (57009, 0x1e9b042aU),
      (57010, 0x2016e60aU),
      (57011, 0x3f6653ecU),
    ] {
    let terminator = @encoding.encode("\u{0}", page)
    assert_eq(terminator.length(), 1)
    let mut hash = 2166136261U
    for value in 0..<0x10000 {
      guard value.to_char() is Some(ch) else { continue }
      let encoded = @encoding.encode(
        if value == 0 {
          ""
        } else {
          ch.to_string()
        },
        page,
      )
      hash = (hash ^ (encoded.length() + 1).reinterpret_as_uint()) * 16777619U
      for byte in encoded {
        hash = (hash ^ byte.to_uint()) * 16777619U
      }
      hash = (hash ^ terminator[0].to_uint()) * 16777619U
    }
    assert_eq((page, hash), (page, expected))
  }
}

///|
test "Windows GSM encodes each UTF-16 unit and preserves zero and escape codes" {
  assert_eq(@encoding.encode("A@B", 55000), b"A\x00B")
  assert_eq(@encoding.encode("A😀B", 55000), b"A  B")
  assert_eq(@encoding.encode("ÁãĞış", 55002), b"\x1b\x0e\x1b{   ")
  assert_eq(@encoding.encode("A@B", 55004), b" \x00 ")
}

///|
test "ISCII preserves the selected script and consumes one joiner after virama" {
  assert_eq(
    @encoding.encode("ক€খ😀ग", 57002),
    b"\xefC\xb3?\xb4??\xefB\xb5",
  )
  assert_eq(@encoding.encode("অঅ", 57003), b"\xa4\xa4")
  assert_eq(@encoding.encode("অঅ", 57006), b"\xefC\xa4\xa4")
  assert_eq(
    @encoding.encode("क्\u{200c}क्\u{200d}क", 57002),
    b"\xb3\xe8\xe8\xb3\xe8\xe9\xb3",
  )
  assert_eq(
    @encoding.encode("ক্\u{200d}\u{200c}ক", 57003),
    b"\xb3\xe8\xe9?\xb3",
  )
  assert_eq(
    @encoding.encode("क़ॐ॒॑॰", 57002),
    b"\xb3\xe9\xa1\xe9?\xf0\xb8\xf0\xbf",
  )
}

///|
test "Chinese designation is reused across ASCII and switches between CNS planes" {
  assert_eq(
    @encoding.encode("A中文~中文B", 50227),
    b"A\x1b$)A\x0eVPND\x0f~\x0eVPND\x0fB",
  )
  assert_eq(
    @encoding.encode("中万中", 50229),
    b"\x1b$)G\x0eDc\x1b$*H!&\x1b$)GDc\x0f",
  )
}

///|
test "Windows JIS, GB2312 and Wansung use their own mappings" {
  assert_eq(
    @encoding.encode("日ｶ丂髙№\u{e000}\u{e3ac}", 20932),
    b"\xc6\xfc\x8e\xb6\xb0\x21\xf4\x29\xad\xe2\xf5\xa1\xf5\x21",
  )
  // CP20936 can decode two byte sequences as ∥. Only A1 CE is emitted.
  assert_eq(@encoding.encode("中∥", 20936), b"\xd6\xd0\xa1\xce")
  assert_eq(
    @encoding.encode("한글₩¢힣", 20949),
    b"\xc7\xd1\xb1\xdb\\\xa1\xcb?",
  )
  for page in [20932, 20936, 20949] {
    assert_true(@encoding.supported(page))
    assert_eq(@encoding.encode("😀", page), b"??")
  }
}

///|
test "installed Windows NLS tables agree over every valid BMP scalar" {
  let bmp = StringBuilder()
  for scalar in 0..<0x10000 {
    if scalar.to_char() is Some(c) {
      bmp.write_char(c)
    }
  }
  let text = bmp.to_string()
  // FNV-1a over each Windows Server 2022 Nano NLS output in scalar order.
  for
    (page, expected) in [
      (437, 0x82dfd698U),
      (708, 0xaef7f238U),
      (720, 0x7afd9fe6U),
      (737, 0xebd30d14U),
      (775, 0x5d483687U),
      (850, 0x680aa08eU),
      (852, 0xc11b9129U),
      (855, 0xd0ae84b0U),
      (857, 0x9c1f1f35U),
      (858, 0xd3d048d0U),
      (860, 0x0a0c799dU),
      (861, 0x767acfd7U),
      (862, 0xbf348f70U),
      (863, 0x9ecf74dbU),
      (864, 0x95506d02U),
      (865, 0x960e2fc6U),
      (866, 0x44d7cd56U),
      (869, 0x01937867U),
      (874, 0x1339a051U),
      (932, 0x47bf5357U),
      (936, 0x8dbef818U),
      (949, 0xa6083006U),
      (950, 0x1575a607U),
      (1250, 0x1c24ef27U),
      (1251, 0xe9c66bd4U),
      (1252, 0xeec5e75dU),
      (1253, 0x7c077eaaU),
      (1254, 0x39b8ca9cU),
      (1255, 0x8d18fd6dU),
      (1256, 0xcff516ccU),
      (1257, 0x2c5fb691U),
      (1258, 0xbe206427U),
      (1361, 0xbf2eeabdU),
      (20000, 0x286cc1d5U),
      (20001, 0xa44b07c2U),
      (20002, 0x45228007U),
      (20003, 0x526a1cebU),
      (20004, 0xa6e767d0U),
      (20005, 0x6d2b152dU),
      (20127, 0x019da4ebU),
      (20261, 0xa14c75abU),
      (20866, 0x076fd5f0U),
      (20932, 0xff267cdcU),
      (20936, 0xc21cef27U),
      (20949, 0xf10b7290U),
      (21866, 0x86fd1ebeU),
      (28591, 0x02292c81U),
      (28592, 0x29c79432U),
      (28593, 0xb47f1856U),
      (28594, 0xf8444e9eU),
      (28595, 0xec8869aeU),
      (28596, 0x6012a72bU),
      (28597, 0x7789186fU),
      (28598, 0xc3d634e8U),
      (28599, 0xaaa802eeU),
      (28605, 0xb510e9a3U),
      (38598, 0xc3d634e8U),
      (51949, 0xf10b7290U),
    ] {
    let mut hash = 2166136261U
    for byte in @encoding.encode(text, page) {
      hash = (hash ^ byte.to_uint()) * 16777619U
    }
    assert_eq((page, hash), (page, expected))
  }
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
test "CP_SYMBOL maps its full byte repertoire and rejects other characters" {
  let symbols = StringBuilder()
  for byte in 0..<256 {
    let scalar = if byte < 32 { byte } else { 0xf000 + byte }
    symbols.write_char(scalar.to_char().unwrap())
  }
  assert_eq(
    @encoding.encode(symbols.to_string(), 42),
    Bytes::makei(256, i => i.to_byte()),
  )
  for text in [" ", "\u{f01f}", "\u{f100}", "\u{f041}X", "😀"] {
    try @encoding.encode(text, 42) catch {
      @encoding.UnmappableCharacter(42) => ()
      err => raise err
    } noraise {
      _ => fail("encoded input outside the Windows Symbol repertoire")
    }
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

///|
test "CP29001 rejects undefined upstream conversion output" {
  assert_true(!@encoding.supported(29001))
  for input in ["", "C:/ASCII", "/usr/éĀ中文日本한글ไทย"] {
    try {
      ignore(@encoding.encode(input, 29001))
      fail("an observed empty payload must not become a compatibility rule")
    } catch {
      @encoding.UnsupportedCodePage(29001) => ()
      _ => fail("expected UnsupportedCodePage(29001)")
    }
  }
}

///|
test "Windows UTF-7 direct characters, shift boundaries, and UTF-16 units" {
  assert_true(@encoding.supported(65000))
  assert_eq(@encoding.encode("", 65000), b"")
  assert_eq(
    @encoding.encode("AZaz09'(),-./:? \t\r\n\u0000", 65000),
    b"AZaz09'(),-./:? \t\r\n\x00",
  )
  assert_eq(
    @encoding.encode("é+éé/ééé!", 65000),
    b"+AOk-+-+AOkA6Q-/+AOkA6QDpACE-",
  )
  assert_eq(@encoding.encode("~\\-++", 65000), b"+AH4AXA--+-+-")
  assert_eq(@encoding.encode("😀", 65000), b"+2D3eAA-")
  let pair = "😀"
  assert_eq(
    @encoding.encode(pair.unsafe_substring(start=0, end=1), 65000),
    b"+2D0-",
  )
  assert_eq(
    @encoding.encode(pair.unsafe_substring(start=1, end=2), 65000),
    b"+3gA-",
  )
}

///|
test "CP54936 covers the Windows GB18030-2000 repertoire" {
  assert_true(@encoding.supported(54936))
  assert_eq(
    @encoding.encode("A€中\u{1e3f}\u{e7c7}\u{fe10}\u{e78d}", 54936),
    b"A\xa2\xe3\xd6\xd0\x81\x35\xf4\x37\xa8\xbc\x84\x31\x82\x36\xa6\xd9",
  )
  assert_eq(
    @encoding.encode("\u{ffff}\u{10000}\u{10ffff}", 54936),
    b"\x84\x31\xa4\x39\x90\x30\x81\x30\xe3\x32\x9a\x35",
  )
  for start in 0..<2 {
    let lone = "😀".unsafe_substring(start~, end=start + 1)
    assert_eq(@encoding.encode(lone, 54936), b"\x84\x31\xa4\x37")
  }
  // FNV-1a of Python 3.14's gb18030 encoding of each valid BMP scalar in order.
  let bmp = StringBuilder()
  for scalar in 0..<0x10000 {
    if scalar.to_char() is Some(c) {
      bmp.write_char(c)
    }
  }
  let mut hash = 2166136261U
  for byte in @encoding.encode(bmp.to_string(), 54936) {
    hash = (hash ^ byte.to_uint()) * 16777619U
  }
  assert_eq(hash, 0x6ed0ef95U)
}

///|
test "official Windows captures resolve ambiguous WCTABLE entries" {
  assert_eq(@encoding.encode("\u{05b8}", 10005), b"\xde")
  assert_eq(@encoding.encode("\u{2225}", 10008), b"\xa1\xce")
  assert_eq(@encoding.encode("#^`~¤", 20269), b"\xa6\xc3\xc1\xc4\xa8")
  assert_eq(@encoding.encode("Ÿ", 20924), b"\xe8")
}
