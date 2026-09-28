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
  let original = parse_path(path, from)
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
      return decode_windows_filename("//" + text[8:].to_owned())
    }
    return decode_windows_filename(text)
  }
  let rendered = output.render(to)
  if from == Windows && to == Posix {
    decode_windows_filename(rendered)
  } else {
    rendered
  }
}
