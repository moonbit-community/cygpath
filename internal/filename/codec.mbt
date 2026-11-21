///|
/// A NUL prefix distinguishes an undecodable byte from the literal U+F0xx
/// character. All callers first exclude the terminating NUL from the input.
pub fn write_byte(out : StringBuilder, byte : Int32) -> Unit {
  out.write_char('\u0000')
  out.write_char((0xF000 + byte).to_char().unwrap())
}

///|
// A CESU-8 surrogate unit has the form ED A0..BF 80..BF.
fn surrogate_at(bytes : BytesView, i : Int32) -> Int32? {
  guard i + 3 <= bytes.length() &&
    bytes[i] == 0xED &&
    bytes[i + 1] is (0xA0..<=0xBF) &&
    bytes[i + 2] is (0x80..<=0xBF) else {
    return None
  }
  Some(
    0xD000 |
    ((bytes[i + 1].to_int() & 0x3F) << 6) |
    (bytes[i + 2].to_int() & 0x3F),
  )
}

///|
fn cesu_pair(bytes : BytesView, i : Int32) -> Char? {
  guard surrogate_at(bytes, i) is Some(high) &&
    high < 0xDC00 &&
    surrogate_at(bytes, i + 3) is Some(low) &&
    low >= 0xDC00 else {
    return None
  }
  (0x10000 + ((high - 0xD800) << 10) + low - 0xDC00).to_char()
}

///|
/// Decode the UTF-8 scalars and retain each remaining byte for mount matching
/// and diagnostics. A NUL before a supplementary scalar preserves the
/// six-byte spelling of a pair that Newlib decodes into two UTF-16 units.
pub fn decode(bytes : BytesView) -> String {
  @utf8.decode(bytes) catch {
    @utf8.Malformed(bad) => {
      let out = StringBuilder()
      let prefix = bytes.length() - bad.length()
      out.write_string(@utf8.decode_lossy(bytes[:prefix]))
      for i = prefix; i < bytes.length(); {
        let lead = bytes[i].to_int()
        if lead == 0xED && cesu_pair(bytes, i) is Some(character) {
          out.write_char('\u0000')
          out.write_char(character)
          continue i + 6
        }
        let width = match lead {
          0..<=0x7F => 1
          0xC2..<=0xDF => 2
          0xE0..<=0xEF => 3
          0xF0..<=0xF4 => 4
          _ => 0
        }
        if width == 1 {
          out.write_char(lead.to_char().unwrap())
        } else {
          if width > 1 && i + width <= bytes.length() {
            if (Some(@utf8.decode(bytes[i:i + width])) catch { _ => None })
              is Some(text) {
              out.write_string(text)
              continue i + width
            }
          }
          write_byte(out, lead)
        }
        continue i + 1
      }
      out.to_string()
    }
  }
}

///|
pub fn native_name(spelling : String) -> String {
  if spelling.contains_char('\u0000') {
    spelling.replace_all(old="\u0000", new="")
  } else {
    spelling
  }
}

///|
pub fn contains_unpaired_surrogate(bytes : BytesView) -> Bool {
  for i = 0; i + 2 < bytes.length(); {
    if bytes[i] == 0xED && surrogate_at(bytes, i) is Some(_) {
      if cesu_pair(bytes, i) is Some(_) {
        continue i + 6
      }
      return true
    }
    continue i + 1
  }
  false
}

///|
/// The CLI wide input helper accepts UTF-8 and paired CESU-8. Arbitrary
/// high bytes can only be converted by the narrow filesystem API.
pub fn wide_name(spelling : String) -> String? {
  guard spelling.contains_char('\u0000') else { return Some(spelling) }
  for i in 0..<spelling.length() {
    if spelling[i] == 0 &&
      !(i + 2 < spelling.length() &&
      spelling[i + 1].is_leading_surrogate() &&
      spelling[i + 2].is_trailing_surrogate()) {
      return None
    }
  }
  Some(native_name(spelling))
}

///|
pub fn encode(spelling : String) -> Bytes {
  guard spelling.contains_char('\u0000') else { return @utf8.encode(spelling) }
  let out = @buffer.Buffer()
  for start = 0, i = 0; i < spelling.length(); {
    if spelling[i] == 0 &&
      i + 1 < spelling.length() &&
      spelling[i + 1].to_int() is (0xF080..<=0xF0FF) {
      out.write_string_utf8(spelling[start:i])
      out.write_byte(spelling[i + 1].to_int().to_byte())
      continue i + 2, i + 2
    }
    if spelling[i] == 0 &&
      i + 2 < spelling.length() &&
      spelling[i + 1].is_leading_surrogate() &&
      spelling[i + 2].is_trailing_surrogate() {
      out.write_string_utf8(spelling[start:i])
      for j in (i + 1)..<(i + 3) {
        let unit = spelling[j].to_int()
        out.write_byte(0xED)
        out.write_byte((0x80 | ((unit >> 6) & 0x3F)).to_byte())
        out.write_byte((0x80 | (unit & 0x3F)).to_byte())
      }
      continue i + 3, i + 3
    }
    continue start, i + 1
  } nobreak {
    out.write_string_utf8(spelling[start:])
  }
  out.to_bytes()
}
