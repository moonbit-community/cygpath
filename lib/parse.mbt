///|
fn validate_text(path : String) -> Unit raise ConversionError {
  for i = 0; i < path.length(); {
    let unit = path[i]
    if unit == 0 {
      raise InvalidPath(reason="NUL in path", offset=i)
    }
    if unit.is_leading_surrogate() {
      guard i + 1 < path.length() && path[i + 1].is_trailing_surrogate() else {
        raise InvalidPath(reason="unpaired UTF-16 surrogate", offset=i)
      }
      continue i + 2
    } else if unit.is_trailing_surrogate() {
      raise InvalidPath(reason="unpaired UTF-16 surrogate", offset=i)
    } else {
      continue i + 1
    }
  }
}

///|
fn is_drive(value : String) -> Bool {
  value.length() == 1 && (value[0] is ('a'..='z') || value[0] is ('A'..='Z'))
}

///|
fn upper_drive(value : String) -> String {
  // Only called for a validated ASCII drive letter.
  value.to_upper()
}

///|
fn path_components(value : String) -> Array[String] {
  value.split("/").filter(s => !s.is_empty()).map(s => s.to_owned()).to_array()
}

///|
fn is_separator(unit : UInt16, syntax : InputSyntax) -> Bool {
  unit == '/' || (syntax == Windows && unit == '\\')
}

///|
fn parse_path(
  path : String,
  syntax : InputSyntax,
) -> ParsedPath raise ConversionError {
  guard !path.is_empty() else { raise EmptyPath }
  validate_text(path)
  // Classify namespaces before treating separators as ordinary components.
  if path.length() >= 3 &&
    is_separator(path[0], syntax) &&
    (path.length() == 3 || is_separator(path[3], syntax)) {
    if is_separator(path[1], syntax) {
      if path[2] == '?' {
        raise UnsupportedNamespace("extended")
      }
      if path[2] == '.' {
        raise UnsupportedNamespace("device")
      }
    } else if syntax == Windows && path[1] == '?' && path[2] == '?' {
      raise UnsupportedNamespace("device")
    }
  }
  let text = match syntax {
    Windows => path.replace_all(old="\\", new="/")
    Posix => path
  }
  let (root, components) = if text.has_prefix("//") {
    // Empty authority fields are errors, not redundant tail separators.
    let parts = text[2:].split("/").to_array()
    guard parts.length() >= 2 &&
      !parts[0].is_empty() &&
      !parts[1].is_empty() &&
      parts[0] != "." &&
      parts[0] != ".." &&
      parts[1] != "." &&
      parts[1] != ".." else {
      raise UnsupportedNamespace("incomplete UNC")
    }
    let server = parts[0].to_owned()
    let share = parts[1].to_owned()
    validate_windows_component(server, device_names=false)
    validate_windows_component(share, device_names=false)
    let tail = parts[2:]
      .iter()
      .filter(s => !s.is_empty())
      .map(s => s.to_owned())
      .to_array()
    (Unc(server, share), tail)
  } else if syntax == Windows && text.length() >= 2 && text[1] == ':' {
    let drive = text[:1].to_owned()
    guard is_drive(drive) else {
      raise InvalidPath(reason="drive letter must be ASCII A-Z", offset=0)
    }
    let drive = upper_drive(drive)
    if text.length() >= 3 && text[2] == '/' {
      (DriveAbsolute(drive), path_components(text[3:].to_owned()))
    } else {
      (DriveRelative(drive), path_components(text[2:].to_owned()))
    }
  } else if text.has_prefix("/") {
    let root = if syntax == Windows { WindowsRooted } else { PosixRoot }
    (root, path_components(text))
  } else {
    (Relative, path_components(text))
  }
  if syntax == Windows {
    for part in components {
      validate_windows_component(part)
    }
  }
  { root, components, trailing: text.has_suffix("/"), }
}

///|
fn validate_windows_component(
  component : String,
  device_names? : Bool = true,
) -> Unit raise ConversionError {
  if component == "." || component == ".." {
    return
  }
  if component.has_suffix(".") || component.has_suffix(" ") {
    raise UnrepresentablePath(component~, reason="trailing dot or space")
  }
  for c in component {
    if c.to_int() < 32 ||
      c is ('<' | '>' | ':' | '"' | '/' | '\\' | '|' | '?' | '*') {
      raise UnrepresentablePath(component~, reason="reserved Windows character")
    }
  }
  if device_names {
    let stem = match component.split_once(".") {
      Some((stem, _)) => stem.to_owned()
      None => component
    }
    let port_prefix = match stem.get_view(end=3) {
      Some(prefix) =>
        prefix.equal_ignore_ascii_case("COM") ||
        prefix.equal_ignore_ascii_case("LPT")
      None => false
    }
    let reserved = ["CON", "PRN", "AUX", "NUL"].any(name => {
        stem.equal_ignore_ascii_case(name)
      }) ||
      (
        stem.length() == 4 &&
        port_prefix &&
        stem[3] is ('1'..='9' | '¹' | '²' | '³')
      )
    if reserved {
      raise UnrepresentablePath(
        component~,
        reason="reserved Windows device name",
      )
    }
  }
}
