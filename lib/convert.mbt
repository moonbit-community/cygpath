///|
/// The Windows-output conversion checks component length. Windows-to-POSIX
/// conversion remains lexical and accepts longer components, including the
/// records produced by cygpath's fixed-size file-input buffer.
fn validate_component_lengths(path : String) -> Unit raise ConversionError {
  let text = path.replace_all(old="\\", new="/")
  for component in text.split("/") {
    if component.length() > 255 {
      raise PathTooLong(path)
    }
  }
}

///|
fn validate_options(
  to : OutputFormat,
  prefix : UnixPrefix,
) -> Unit raise ConversionError {
  if prefix == ProcCygdrive && to != Posix {
    raise InvalidOptions("ProcCygdrive requires POSIX output")
  }
}

///|
/// Converts one nonempty path using explicit source grammar and context.
/// Absolute paths are normalized lexically; no file-system resolution occurs.
pub fn Context::convert(
  self : Context,
  path : String,
  from~ : InputSyntax,
  to~ : OutputFormat,
  absolute? : Bool = false,
  unix_prefix? : UnixPrefix = Configured,
) -> String raise ConversionError {
  validate_options(to, unix_prefix)
  if to != Posix {
    validate_component_lengths(path)
  }
  let path = if from == Windows && to == Posix {
    decode_windows_filename(path)
  } else {
    path
  }
  let original = parse_path(path, from)
  if from == Windows &&
    to == Posix &&
    original.root == WindowsRooted &&
    path.has_prefix("/") {
    // A single forward slash is already POSIX spelling. Cygwin preserves the
    // original spelling in its unmatched non-drive conversion branch.
    return path.replace_all(old="\\", new="/")
  }
  let parsed = self.resolve(original, from, to, absolute)
  let output = if to == Posix {
    if from == Windows || parsed.root is Unc(_, _) {
      self.to_posix(parsed, unix_prefix)
    } else {
      validate_posix_namespace(parsed)
      parsed
    }
  } else if from == Posix {
    self.to_windows(parsed)
  } else {
    parsed
  }
  if from == Windows &&
    to == Posix &&
    (output.root is Unc(_, _) || (original.root == Relative && !absolute)) {
    // Unmatched UNC names and relative Windows inputs are slashified by
    // Cygwin without canonicalizing their original component spelling.
    let text = path.replace_all(old="\\", new="/")
    if text.has_prefix("//?/UNC/") || text.has_prefix("/??/UNC/") {
      return "//" + text[8:].to_owned()
    }
    return text
  }
  let rendered = output.render(to)
  if to != Posix &&
    !absolute &&
    output.root is (Relative | DriveRelative(_)) &&
    rendered.length() >= 260 {
    return self.convert(path, from~, to~, absolute=true, unix_prefix~)
  }
  rendered
}
