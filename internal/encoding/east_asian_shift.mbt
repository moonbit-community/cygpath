///|
/// Entries marked |1 in windows-20949-2000.ucm require a best fit.
/// The Windows ISO-2022 converter disables best fits on its intermediate page.
fn wansung_best_fit(unit : Int32) -> Bool {
  unit
  is (0xa2..<=0xa3
  | 0xa5..<=0xa6
  | 0xa9
  | 0xab..<=0xac
  | 0xb5
  | 0xbb
  | 0xc0..<=0xc5
  | 0xc7..<=0xcf
  | 0xd1..<=0xd6
  | 0xd9..<=0xdd
  | 0xe0..<=0xe5
  | 0xe7..<=0xef
  | 0xf1..<=0xf6
  | 0xf9..<=0xfd
  | 0xff
  | 0x110
  | 0x20a9
  | 0x24b6..<=0x24cf
  | 0x3192..<=0x319f
  | 0x3220..<=0x3243
  | 0x3280..<=0x32b0
  | 0xfa0c
  | 0xfa10
  | 0xfa12
  | 0xfa15
  | 0xfa17
  | 0xfa19..<=0xfa1e
  | 0xfa22
  | 0xfa25..<=0xfa26
  | 0xfa2a..<=0xfa2d
  | 0xffa0..<=0xffbe
  | 0xffc2..<=0xffc7
  | 0xffca..<=0xffcf
  | 0xffd2..<=0xffd7
  | 0xffda..<=0xffdc)
}

///|
fn encode_iso2022_cn_kr(text : String, page : Int32) -> Bytes {
  let (table, designation) = match page {
    50225 => (cp_20949, b"\x1b$)C")
    50227 => (cp_20936, b"\x1b$)A")
    _ => (cp_20000, b"\x1b$)G")
  }
  let out = @buffer.Buffer()
  let mut last_plane = 0
  let mut shifted = false
  for unit in text.code_units() {
    let value = if (page == 50225 && wansung_best_fit(unit.to_int())) ||
      (page == 50229 && unit.to_int() is (0xfa0c | 0xfa0d)) {
      0x3f
    } else {
      lookup(table, unit.to_int(), 0x3f)
    }
    if value > 0xff {
      let plane = if (value & 0x80) == 0 { 2 } else { 1 }
      if plane != last_plane {
        out.write_bytes(if plane == 1 { designation } else { b"\x1b$*H" })
        last_plane = plane
      }
      if !shifted {
        out.write_byte(0x0e)
        shifted = true
      }
      out.write_byte(((value >> 8) & 0x7f).to_byte())
      out.write_byte((value & 0x7f).to_byte())
    } else {
      if shifted {
        out.write_byte(0x0f)
        shifted = false
      }
      out.write_byte(value.to_byte())
    }
  }
  if shifted {
    out.write_byte(0x0f)
  }
  out.to_bytes()
}

///|
/// The HZ converter consumes the NUL-terminated GB2312 byte stream in
/// pairs whenever the leading byte has its high bit set.
fn encode_hz(text : String) -> Bytes {
  let narrow = @buffer.Buffer()
  for unit in text.code_units() {
    let value = lookup(cp_20936, unit.to_int(), 0x3f)
    if value > 0xff {
      narrow.write_byte((value >> 8).to_byte())
    }
    narrow.write_byte(value.to_byte())
  }
  narrow.write_byte(0)
  let bytes = narrow.to_bytes()
  let out = @buffer.Buffer()
  let mut shifted = false
  for i = 0; i < bytes.length(); {
    let lead = bytes[i]
    if lead >= 0x80 {
      if !shifted {
        out.write_bytes(b"~{")
        shifted = true
      }
      out.write_byte(lead & 0x7f)
      out.write_byte(bytes[i + 1] & 0x7f)
      continue i + 2
    }
    if shifted {
      out.write_bytes(b"~}")
      shifted = false
    }
    if lead == b'~' {
      out.write_byte(b'~')
    }
    out.write_byte(lead)
    continue i + 1
  }
  let result = out.to_bytes()
  result[:result.length() - 1].to_owned()
}
