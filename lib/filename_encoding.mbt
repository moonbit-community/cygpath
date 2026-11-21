///|
// Clean-room rules derived from Cygwin strfuncs.cc at b6e315143bf7:
// ordinary Windows filenames encode ASCII controls and seven punctuation
// characters into U+F000 plus the original ASCII value.
fn encoded_filename_character(character : Char) -> Bool {
  (character.to_int() > 0 && character.to_int() < 32) ||
  character is ('"' | '*' | ':' | '<' | '>' | '?' | '|')
}

///|
fn encode_windows_component(component : String) -> String raise ConversionError {
  let component = @filename.native_name(component)
  if component.contains_char('\\') {
    raise UnrepresentablePath(
      component~,
      reason="backslash in an explicit POSIX component",
    )
  }
  let output = StringBuilder()
  for character in component {
    output.write_char(
      if encoded_filename_character(character) {
        (0xF000 + character.to_int()).to_char().unwrap()
      } else {
        character
      },
    )
  }
  output.to_string()
}

///|
fn decode_windows_filename(
  path : String,
  start~ : Int32 = 0,
  rooted~ : Bool = false,
) -> String {
  let output = StringBuilder()
  if rooted {
    output.write_char('\\')
  }
  for i = start; i < path.length(); {
    let code = path[i].to_int()
    if code is (0xF080..<=0xF0FF) {
      // Adjacent byte escapes can spell one valid UTF-8 scalar. Decode it
      // before mount matching. Otherwise preserve exactly one byte and retry.
      let mut end = i + 1
      while end < path.length() && path[end].to_int() is (0xF080..<=0xF0FF) {
        end += 1
      }
      let run = Bytes::makei(end - i, j => path[i + j].to_int().to_byte())
      output.write_string(@filename.decode(run))
      continue end
    }
    if path[i].is_trailing_surrogate() {
      // The single-name prefix rewrite can leave the low half of a pair.
      // Newlib writes that UTF-16 unit as three bytes.
      @filename.write_byte(output, 0xED)
      @filename.write_byte(output, 0x80 | ((code >> 6) & 0x3F))
      @filename.write_byte(output, 0x80 | (code & 0x3F))
      continue i + 1
    }
    let character = path.get_char(i).unwrap()
    if code > 0xF000 && code <= 0xF07F {
      let plain = (code - 0xF000).to_char().unwrap()
      output.write_char(
        if encoded_filename_character(plain) || plain is (' ' | '.') {
          plain
        } else {
          character
        },
      )
    } else {
      output.write_char(character)
    }
    continue i + (if character.to_int() > 0xFFFF { 2 } else { 1 })
  }
  output.to_string()
}
