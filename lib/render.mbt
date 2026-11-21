///|
fn ParsedPath::render(
  self : ParsedPath,
  format : OutputFormat,
  dos_names~ : Bool = false,
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
    NetworkRoot => sep + sep
    NetworkServer(server) =>
      sep +
      sep +
      (if format == Posix { server } else { encode_windows_component(server) })
    DriveAbsolute(drive) => drive + ":" + sep + body
    DriveRelative(drive) => drive + ":" + body
    Unc(server, share) => {
      let root = if format == Posix {
        sep + sep + server + sep + share
      } else {
        sep +
        sep +
        encode_windows_component(server) +
        sep +
        encode_windows_component(share)
      }
      if body.is_empty() {
        root
      } else {
        root + sep + body
      }
    }
  }
  let result = if self.trailing && !result.has_suffix(sep) {
    result + sep
  } else {
    result
  }
  let result = if dos_names {
    dos_mount_spelling(result, self.root, format)
  } else {
    result
  }
  if format != Posix && result.length() >= 260 {
    match self.root {
      DriveAbsolute(_) => sep + sep + "?" + sep + result
      NetworkServer(_) | Unc(_, _) =>
        sep + sep + "?" + sep + "UNC" + result[1:].to_owned()
      _ => result
    }
  } else {
    result
  }
}

///|
/// A mapped filesystem path before Windows filename encoding.
pub struct NativePath {
  priv path : ParsedPath
  priv dos_names : Bool
}

///|
/// Returns the narrow byte length of a basename, counting parents from the leaf.
pub fn NativePath::basename_bytes(
  self : NativePath,
  parents~ : Int32 = 0,
) -> Int32? {
  if parents < 0 || parents >= self.path.components.length() {
    return None
  }
  let component = self.path.components[self.path.components.length() -
    parents -
    1]
  Some(@filename.encode(component).length())
}

///|
/// Renders the Windows spelling after appending a suffix to the selected entry.
pub fn NativePath::windows_name(
  self : NativePath,
  parents~ : Int32 = 0,
  suffix~ : String = "",
) -> String raise ConversionError {
  if parents == 0 && suffix.is_empty() {
    return self.path.render(Windows, dos_names=self.dos_names)
  }
  guard parents >= 0 && parents < self.path.components.length() else {
    raise InvalidOptions("no such filename component")
  }
  validate_suffix(suffix)
  let count = self.path.components.length() - parents
  let components = self.path.components[:count].to_owned()
  components[count - 1] = components[count - 1] + suffix
  { ..self.path, components, trailing: false, }.render(
    Windows,
    dos_names=self.dos_names,
  )
}

///|
fn validate_suffix(suffix : String) -> Unit raise ConversionError {
  validate_text(suffix)
  if suffix.contains_char('/') || suffix.contains_char('\\') {
    raise InvalidOptions("a filename suffix cannot contain a separator")
  }
}
