///|
/// An ATR designates the script for subsequent Indic characters, including
/// across ASCII and unmappable input. Windows ends the name in the active script.
fn encode_iscii(text : String, page : Int32) -> Bytes {
  let output = @buffer.Buffer()
  let mut script = page - 57000
  let mut after_virama = false
  for unit in text.code_units() {
    let value = unit.to_int()
    let mapping = if value is (0x901..<=0xd6f) {
      word(iscii_table, (value - 0x901) * 2)
    } else {
      0
    }
    if mapping == 0 {
      let byte = match value {
        0..<0xa0 => value
        0x200c if after_virama => 0xe8
        0x200d if after_virama => 0xe9
        _ => 0x3f
      }
      output.write_byte(byte.to_byte())
      after_virama = false
      continue
    }
    // The packed descriptor stores a trailing-byte selector, script and first byte.
    let next_script = (mapping >> 8) & 0xf
    if next_script != script {
      output.write_byte(0xef)
      output.write_byte((0x40 + next_script).to_byte())
      script = next_script
    }
    let first = mapping.to_byte()
    output.write_byte(first)
    after_virama = first == 0xe8
    match mapping >> 12 {
      1 => output.write_byte(0xe9)
      2 => output.write_byte(0xb8)
      3 => output.write_byte(0xbf)
      _ => ()
    }
  }
  output.to_bytes()
}
