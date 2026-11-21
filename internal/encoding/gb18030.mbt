///|
fn write_gb18030_pointer(output : @buffer.Buffer, pointer : Int32) -> Unit {
  output.write_byte((0x81 + pointer / 12600).to_byte())
  output.write_byte((0x30 + pointer / 1260 % 10).to_byte())
  output.write_byte((0x81 + pointer / 10 % 126).to_byte())
  output.write_byte((0x30 + pointer % 10).to_byte())
}

///|
fn encode_gb18030(text : String) -> Bytes {
  let output = @buffer.Buffer()
  for character in text {
    let scalar = match character.to_int() {
      0xd800..<0xe000 => 0xfffd
      value => value
    }
    if scalar < 0x80 {
      output.write_byte(scalar.to_byte())
    } else if scalar >= 0x10000 {
      write_gb18030_pointer(output, 189000 + scalar - 0x10000)
    } else {
      // Each BMP run starts at a UTF-16 word and either shares CP936,
      // specifies a single byte pair, or starts a range of four-byte pointers.
      let run = for lower = 0, upper = gb18030_runs.length() / 4; lower + 1 <
                   upper; {
        let middle = (lower + upper) / 2
        if word(gb18030_runs, middle * 4) <= scalar {
          continue middle, upper
        } else {
          continue lower, middle
        }
      } nobreak {
        lower * 4
      }
      let descriptor = word(gb18030_runs, run + 2)
      if descriptor <= 0x99fb {
        write_gb18030_pointer(
          output,
          descriptor + scalar - word(gb18030_runs, run),
        )
      } else {
        let pair = if descriptor == 0xffff {
          lookup(cp_936, scalar, 0x3f)
        } else {
          descriptor
        }
        output.write_byte((pair >> 8).to_byte())
        output.write_byte(pair.to_byte())
      }
    }
  }
  output.to_bytes()
}
