///|
pub(all) suberror CliError {
  UnknownOption(String)
  MissingValue(String)
  OptionError(String)
  InvalidOptions(String)
  UnsupportedCapability(String)
  MissingInput
  Usage
  IgnoredUsage
  InvalidRecord
  PathNotFound(String)
  Conversion(@lib.ConversionError)
}

///|
fn conversion_exit_code(error : @lib.ConversionError) -> Int {
  match error {
    @lib.EmptyPath => 1
    @lib.PathTooLong(_) | @lib.InvalidDrivePrefix => 1
    @lib.InvalidContext(..)
    | @lib.MissingContext(..)
    | @lib.InvalidOptions(_) => 1
    @lib.ListEntryError(index=_, cause) => conversion_exit_code(cause)
    _ => 2
  }
}

///|
pub fn CliError::exit_code(self : CliError) -> Int {
  match self {
    Conversion(error) => conversion_exit_code(error)
    InvalidRecord => 2
    IgnoredUsage => 0
    _ => 1
  }
}

///|
fn conversion_diagnostic(error : @lib.ConversionError) -> String {
  match error {
    @lib.EmptyPath => "can't convert empty path"
    @lib.PathTooLong(path) =>
      "error converting \"" + path + "\" - File name too long"
    @lib.InvalidDrivePrefix => "invalid-drive-prefix"
    @lib.InvalidPath(reason~, offset~) =>
      "invalid-path: UTF-16 offset \{offset}: " + reason.escape()
    @lib.InvalidContext(field~, reason~) =>
      "invalid-context: " + field.escape() + ": " + reason.escape()
    @lib.MissingContext(field~) => "missing-context: " + field.escape()
    @lib.UnsupportedNamespace(kind) => "unsupported-namespace: " + kind.escape()
    @lib.UnrepresentablePath(component~, reason~) =>
      "unrepresentable-path: " + component.escape() + ": " + reason.escape()
    @lib.InvalidOptions(reason) => "invalid-options: " + reason.escape()
    @lib.ListEntryError(index~, cause) =>
      "list-entry: index \{index}: " + conversion_diagnostic(cause)
  }
}

///|
fn invalid_drive_prefix(error : @lib.ConversionError) -> Bool {
  match error {
    @lib.InvalidDrivePrefix => true
    @lib.ListEntryError(index=_, cause) => invalid_drive_prefix(cause)
    _ => false
  }
}

///|
fn path_too_long(error : @lib.ConversionError) -> Bool {
  match error {
    @lib.PathTooLong(_) => true
    @lib.ListEntryError(index=_, cause) => path_too_long(cause)
    _ => false
  }
}

///|
/// A diagnostic without its final LF. Official option errors retain cygpath's
/// multiline usage protocol; project context errors use typed diagnostics.
pub fn CliError::diagnostic(self : CliError) -> String {
  match self {
    Usage | MissingInput => return official_usage_error()
    IgnoredUsage => return ""
    OptionError(detail) =>
      return "cygpath: " +
        detail +
        "\nTry `cygpath --help' for more information."
    UnknownOption("--root-local") =>
      return "Try `cygpath --help' for more information."
    UnknownOption(option) => {
      let option = if option.has_prefix("--") {
        option[2:].to_owned()
      } else {
        option[1:].to_owned()
      }
      return "cygpath: unknown option -- " +
        option +
        "\nTry `cygpath --help' for more information."
    }
    MissingValue(option) if !is_project_option(option) => {
      let option = if option.has_prefix("--") {
        option[2:].to_owned()
      } else {
        option[1:].to_owned()
      }
      return "cygpath: option requires an argument -- " +
        option +
        "\nTry `cygpath --help' for more information."
    }
    _ => ()
  }
  let detail = match self {
    UnknownOption(option) => "unknown-option: " + option.escape()
    OptionError(detail) => detail
    MissingValue(option) => "missing-value: " + option.escape()
    InvalidOptions(reason) => "invalid-options: " + reason.escape()
    UnsupportedCapability(reason) =>
      "unsupported-capability: " + reason.escape()
    MissingInput => "missing-input: supply a NAME or --file"
    Usage | IgnoredUsage => ""
    InvalidRecord => "invalid-record: embedded CR or LF is not allowed"
    PathNotFound(path) =>
      "error converting \"" + path + "\" - No such file or directory"
    Conversion(error) => conversion_diagnostic(error)
  }
  "cygpath: " + detail
}
