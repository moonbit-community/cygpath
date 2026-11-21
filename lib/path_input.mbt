///|
/// Unicode operands and narrow C.UTF-8 filenames from a POSIX byte stream.
pub(all) enum PathInput {
  Text(String)
  Narrow(Bytes)
}

///|
pub trait ToPathInput {
  fn to_path_input(Self) -> PathInput
}

///|
pub impl ToPathInput for String with fn to_path_input(self) {
  Text(self)
}

///|
pub impl ToPathInput for Bytes with fn to_path_input(self) {
  Narrow(self)
}

///|
pub impl ToPathInput for PathInput with fn to_path_input(self) {
  self
}

///|
fn PathInput::spelling(self : PathInput) -> String raise ConversionError {
  match self {
    Text(text) => {
      validate_text(text)
      text
    }
    Narrow(bytes) => {
      if bytes.find(b"\x00") is Some(offset) {
        raise InvalidPath(reason="NUL in path", offset~)
      }
      if @filename.contains_unpaired_surrogate(bytes) {
        raise UnrepresentablePath(
          component="CESU-8",
          reason="isolated UTF-16 surrogate unit",
        )
      }
      @filename.decode(bytes)
    }
  }
}
