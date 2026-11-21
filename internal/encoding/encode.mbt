///|
pub(all) suberror EncodingError {
  UnsupportedCodePage(Int32)
  UnmappableCharacter(Int32)
}

///|
pub fn supported(codepage : Int32) -> Bool {
  match codepage {
    42
    | 50220..<=50222
    | 50225
    | 50227
    | 50229
    | 52936
    | 54936
    | 57002..<=57011
    | 65000
    | 65001 => true
    29001 => false
    _ => numeric_table(codepage) is Some(_)
  }
}

///|
fn numeric_table(codepage : Int32) -> (Bytes, Int32)? {
  match codepage {
    20932 => Some((cp_20932, 0x3f))
    20936 => Some((cp_20936, 0x3f))
    20949 | 51949 => Some((cp_20949, 0x3f))
    38598 => codepage_table(28598)
    55000 => Some((cp_55000, 0x20))
    55001 => Some((cp_55001, 0x20))
    55002 => Some((cp_55002, 0x20))
    55003 => Some((cp_55003, 0x20))
    55004 => Some((cp_55004, 0x20))
    _ => codepage_table(codepage)
  }
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
fn word(table : Bytes, offset : Int32) -> Int32 {
  (table[offset].to_int() << 8) | table[offset + 1].to_int()
}

///|
fn lookup(table : Bytes, scalar : Int32, fallback : Int32) -> Int32 {
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
/// Later Windows tables add best fits for entries absent from the archives.
/// Resolve the equivalent character through the same page (e.g. NBSP is
/// A0 on CP1252 and FF on CP437). Existing page-specific mappings win.
fn missing_best_fit(
  page : Int32,
  unit : Int32,
  table : Bytes,
  fallback : Int32,
) -> Int32 {
  let equivalent = match (page, unit) {
    (932, 0x3099 | 0x309a) => unit + 2
    (
      437
      | 720
      | 737
      | 775
      | 850
      | 852
      | 855
      | 857
      | 862
      | 866
      | 874
      | 1250..<=1258,
      _,
    ) =>
      match unit {
        0x2007 | 0x202f => 0xa0
        0x2000..<=0x2006 | 0x2008..<=0x200a => 0x20
        0x2010..<=0x2015 => 0x2d
        0x2018 | 0x2019 | 0x201b | 0x2032 | 0x2035 => 0x27
        0x201a => 0x2c
        0x201c..<=0x201f | 0x2033 | 0x2036 => 0x22
        0x2024 => 0x2e
        0x2044 => 0x2f
        0x20a4 => 0xa3
        0x2236 => 0x3a
        _ => return fallback
      }
    _ => return fallback
  }
  lookup(table, equivalent, fallback)
}

///|
/// Encode explicit numeric Windows code pages using frozen Microsoft best-fit
/// mapping data. No platform codec, locale detection, or FFI participates.
pub fn encode(text : String, codepage : Int32) -> Bytes raise EncodingError {
  if codepage == 42 {
    let output = @buffer.Buffer()
    for unit in text.code_units() {
      let value = unit.to_int()
      if !(value < 0x20 || value is (0xf020..<=0xf0ff)) {
        raise UnmappableCharacter(codepage)
      }
      output.write_byte(value.to_byte())
    }
    return output.to_bytes()
  }
  let (table, fallback) = match codepage {
    50220..<=50222 => return encode_iso2022_jp(text, codepage)
    50225 | 50227 | 50229 => return encode_iso2022_cn_kr(text, codepage)
    52936 => return encode_hz(text)
    54936 => return encode_gb18030(text)
    57002..<=57011 => return encode_iscii(text, codepage)
    65000 => return encode_utf7(text)
    65001 => return @utf8.encode(text)
    // The archived Europa 3 table exists, but Win32 conversion can fail.
    29001 => raise UnsupportedCodePage(codepage)
    _ =>
      numeric_table(codepage).unwrap_or_else(() => {
        raise UnsupportedCodePage(codepage)
      })
  }
  let output = @buffer.Buffer()
  // Windows' legacy tables map UTF-16 words independently. A supplementary
  // character therefore uses two default characters, one for each surrogate.
  for unit in text.code_units() {
    let mapped = lookup(table, unit.to_int(), -1)
    let encoded = if mapped < 0 {
      missing_best_fit(codepage, unit.to_int(), table, fallback)
    } else {
      mapped
    }
    if encoded > 255 {
      output.write_byte((encoded >> 8).to_byte())
    }
    output.write_byte((encoded & 255).to_byte())
  }
  output.to_bytes()
}
