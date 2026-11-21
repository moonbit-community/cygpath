///|
#derive(Eq)
priv enum JisSet {
  Ascii
  Kana
  Kanji
}

///|
/// Shift-JIS IBM extensions have a second spelling in the JIS rows.
/// The offsets and exceptional pairs follow the Microsoft ISO-2022 encoder.
fn jis_pair(sjis : Int32) -> Int32 {
  let pair = match sjis {
    0xfa40..<=0xfa49 => sjis - 0xb51
    0xfa4a..<=0xfa53 => sjis - 0x72f6
    0xfa54..<=0xfa57 => sjis - 0xb5b
    0xfa58 => 0x878a
    0xfa59 => 0x8782
    0xfa5a => 0x8784
    0xfa5b => 0x879a
    0xfa5c..<=0xfc4b => {
      let offset = match sjis & 0xff {
        0..<0x5c => 0xd5f
        0x80..<=0x9b => 0xd1d
        _ => 0xd1c
      }
      sjis - offset
    }
    _ => sjis
  }
  let lead = pair >> 8
  let trail = pair & 0xff
  let row = (lead - (if lead > 0x9f { 0xb1 } else { 0x71 })) * 2 + 1
  if trail >= 0x9f {
    ((row + 1) << 8) | (trail - 0x7e)
  } else {
    (row << 8) | (trail - (if trail > 0x7e { 0x20 } else { 0x1f }))
  }
}

///|
/// CP50220 widens each kana independently, including the two spacing marks.
let fullwidth_kana = "。「」、・ヲァィゥェォャュョッーアイウエオカキクケコサシスセソタチツテトナニヌネノハヒフヘホマミムメモヤユヨラリルレロワン゛゜"

///|
fn encode_iso2022_jp(text : String, page : Int32) -> Bytes {
  let out = @buffer.Buffer()
  let mut designated = JisSet::Ascii
  let mut shifted = false
  for unit in text.code_units() {
    let sjis = lookup(cp_932, unit.to_int(), 0x3f)
    let (set, value) = match sjis {
      0xa1..<=0xdf if page == 50220 => {
        let wide = fullwidth_kana[sjis - 0xa1].to_int()
        (Kanji, jis_pair(lookup(cp_932, wide, 0x3f)))
      }
      0xa1..<=0xdf => (Kana, sjis & 0x7f)
      0..<=0xff => (Ascii, sjis)
      _ => (Kanji, jis_pair(sjis))
    }
    // CP50222 invokes kana with SO/SI, preserving the designated ASCII
    // or kanji set underneath. CP50221 designates kana with an escape.
    if set == Kana && page == 50222 {
      if !shifted {
        out.write_byte(0x0e)
        shifted = true
      }
    } else {
      if shifted {
        out.write_byte(0x0f)
        shifted = false
      }
      if designated != set {
        out.write_bytes(
          match set {
            Ascii => b"\x1b(B"
            Kana => b"\x1b(I"
            Kanji => b"\x1b$B"
          },
        )
        designated = set
      }
    }
    if set == Kanji {
      out.write_byte((value >> 8).to_byte())
    }
    out.write_byte(value.to_byte())
  }
  if shifted {
    out.write_byte(0x0f)
  }
  if designated != Ascii {
    out.write_bytes(b"\x1b(B")
  }
  out.to_bytes()
}
