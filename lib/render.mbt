///|
fn ParsedPath::render(
  self : ParsedPath,
  format : OutputFormat,
) -> String raise ConversionError {
  let sep = if format == Windows { "\\" } else { "/" }
  let parts = if format == Posix {
    self.components
  } else {
    self.components.map(encode_windows_component)
  }
  let body = parts.join(sep)
  let result = match self.root {
    Relative => if body.is_empty() { "." } else { body }
    PosixRoot | WindowsRooted => sep + body
    DriveAbsolute(drive) => drive + ":" + sep + body
    DriveRelative(drive) => drive + ":" + body
    Unc(server, share) => {
      let root = sep + sep + server + sep + share
      // A share root has a root separator even when the input omitted it.
      root + sep + body
    }
  }
  let result = if self.trailing && !result.has_suffix(sep) {
    result + sep
  } else {
    result
  }
  if format != Posix && result.length() >= 260 {
    match self.root {
      DriveAbsolute(_) => sep + sep + "?" + sep + result
      Unc(_, _) => sep + sep + "?" + sep + "UNC" + result[1:].to_owned()
      _ => result
    }
  } else {
    result
  }
}
