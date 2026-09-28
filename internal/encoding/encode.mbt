///|
pub(all) suberror UnsupportedCodePage {
  UnsupportedCodePage(Int)
}

///|
pub fn supported(codepage : Int) -> Bool {
  codepage == 65001 || codepage_table(codepage) is Some(_)
}

///|
fn join_chunks(chunks : Array[Bytes]) -> Bytes {
  let output = @buffer.Buffer()
  for chunk in chunks {
    output.write_bytes(chunk)
  }
  output.to_bytes()
}

///|
fn word(table : Bytes, offset : Int) -> Int {
  (table[offset].to_int() << 8) | table[offset + 1].to_int()
}

///|
fn lookup(table : Bytes, scalar : Int, fallback : Int) -> Int {
  for lower = 0, upper = table.length() / 4; lower < upper; {
    let middle = lower + (upper - lower) / 2
    let candidate = word(table, middle * 4)
    if scalar == candidate {
      return word(table, middle * 4 + 2)
    } else if scalar < candidate {
      continue lower, middle
    } else {
      continue middle + 1, upper
    }
  } nobreak {
    fallback
  }
}

///|
/// Encode explicit numeric Windows code pages using frozen Microsoft best-fit
/// mapping data. No platform codec, locale detection, or FFI participates.
pub fn encode(text : String, codepage : Int) -> Bytes raise UnsupportedCodePage {
  if codepage == 65001 {
    return @utf8.encode(text)
  }
  // Windows' WideCharToMultiByte rejects CP29001 (Europa 3) on the official
  // Cygwin/MSYS2 hosts exercised by the oracle. cygpath ignores that zero
  // return and still emits its record LF, so the pure byte adapter preserves
  // the observable empty payload while retaining the published table below.
  if codepage == 29001 {
    return b""
  }
  guard codepage_table(codepage) is Some((table, fallback)) else {
    raise UnsupportedCodePage(codepage)
  }
  let output = @buffer.Buffer()
  // Windows' legacy tables map UTF-16 words independently. A supplementary
  // character therefore uses two default characters, one for each surrogate.
  for unit in text.code_units() {
    let encoded = lookup(table, unit.to_int(), fallback)
    if encoded > 255 {
      output.write_byte((encoded >> 8).to_byte())
    }
    output.write_byte((encoded & 255).to_byte())
  }
  output.to_bytes()
}
