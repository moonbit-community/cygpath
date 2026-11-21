///|
#derive(Eq)
priv enum JisSet {
  Ascii
  Kana
  Jis0208
  Jis0212
}

///|
/// CP50220 widens each kana independently, including the two spacing marks.
let fullwidth_kana = "。「」、・ヲァィゥェォャュョッーアイウエオカキクケコサシスセソタチツテトナニヌネノハヒフヘホマミムメモヤユヨラリルレロワン゛゜"

///|
fn encode_iso2022_jp(text : String, page : Int32) -> Bytes {
  let out = @buffer.Buffer()
  let mut designated = JisSet::Ascii
  for unit in text.code_units() {
    let code = lookup(cp_20932, unit.to_int(), 0x3f)
    let value = if page == 50220 && code is (0x8ea1..<=0x8edf) {
      lookup(cp_20932, fullwidth_kana[code - 0x8ea1].to_int(), 0x3f)
    } else {
      code
    }
    let set = match value {
      0..<=255 => Ascii
      0x8ea1..<=0x8edf => Kana
      _ if (value & 0x80) == 0 => Jis0212
      _ => Jis0208
    }
    if designated != set {
      out.write_bytes(
        match set {
          Ascii => b"\x1b(B"
          Kana if page == 50222 => b"\x1b(J\x0e"
          Kana => b"\x1b(I"
          Jis0208 => b"\x1b$B"
          Jis0212 => b"\x1b$(D"
        },
      )
      designated = set
    }
    if set is (Jis0208 | Jis0212) {
      out.write_byte(((value >> 8) & 0x7f).to_byte())
    }
    out.write_byte(
      if set == Ascii {
        value.to_byte()
      } else {
        (value & 0x7f).to_byte()
      },
    )
  }
  if designated != Ascii {
    out.write_bytes(b"\x1b(B")
  }
  out.to_bytes()
}
