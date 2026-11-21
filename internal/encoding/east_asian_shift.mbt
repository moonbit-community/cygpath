///|
/// CP50225 designates KS X 1001 once per string. SO and SI switch sets
/// without repeating that designation on subsequent runs.
fn encode_iso2022_kr(text : String) -> Bytes {
  let out = @buffer.Buffer()
  let mut designated = false
  let mut shifted = false
  for unit in text.code_units() {
    let value = lookup(cp_949, unit.to_int(), 0x3f)
    let lead = value >> 8
    let trail = value & 0xff
    if lead is (0xa1..<=0xfe) && trail is (0xa1..<=0xfe) {
      if !designated {
        out.write_bytes(b"\x1b$)C")
        designated = true
      }
      if !shifted {
        out.write_byte(0x0e)
        shifted = true
      }
      out.write_byte((lead & 0x7f).to_byte())
      out.write_byte((trail & 0x7f).to_byte())
    } else {
      if shifted {
        out.write_byte(0x0f)
        shifted = false
      }
      out.write_byte(if value < 0x80 { value.to_byte() } else { b'?' })
    }
  }
  if shifted {
    out.write_byte(0x0f)
  }
  out.to_bytes()
}

///|
/// CP52936 uses the GB2312 portion of CP936. A literal tilde in
/// single-byte mode is escaped even when the string contains only ASCII.
fn encode_hz(text : String) -> Bytes {
  let out = @buffer.Buffer()
  let mut shifted = false
  for unit in text.code_units() {
    let value = lookup(cp_936, unit.to_int(), 0x3f)
    let lead = value >> 8
    let trail = value & 0xff
    if lead is (0xa1..<=0xf7) && trail is (0xa1..<=0xfe) {
      if !shifted {
        out.write_bytes(b"~{")
        shifted = true
      }
      out.write_byte((lead & 0x7f).to_byte())
      out.write_byte((trail & 0x7f).to_byte())
    } else {
      if shifted {
        out.write_bytes(b"~}")
        shifted = false
      }
      if value == 0x7e {
        out.write_byte(b'~')
      }
      out.write_byte(
        if value <= 0x80 || value == 0xff {
          value.to_byte()
        } else {
          b'?'
        },
      )
    }
  }
  if shifted {
    out.write_bytes(b"~}")
  }
  out.to_bytes()
}
