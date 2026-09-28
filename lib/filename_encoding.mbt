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
fn decode_windows_filename(path : String) -> String {
  let output = StringBuilder()
  for character in path {
    let code = character.to_int()
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
  }
  output.to_string()
}
