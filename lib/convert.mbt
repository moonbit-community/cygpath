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
  let parsed = self.resolve(parse_path(path, from), from, to, absolute)
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
  output.render(to)
}
