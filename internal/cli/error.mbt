///|
pub(all) suberror CliError {
  UnknownOption(String)
  MissingValue(String)
  InvalidOptions(String)
  UnsupportedCapability(String)
  MissingInput
  InvalidRecord
  Conversion(@lib.ConversionError)
}

///|
fn conversion_exit_code(error : @lib.ConversionError) -> Int {
  match error {
    @lib.EmptyPath => 1
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
    _ => 1
  }
}

///|
fn conversion_diagnostic(error : @lib.ConversionError) -> String {
  match error {
    @lib.EmptyPath => "can't convert empty path"
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
/// One diagnostic line, without its terminator. User-controlled text is escaped.
pub fn CliError::diagnostic(self : CliError) -> String {
  let detail = match self {
    UnknownOption(option) => "unknown-option: " + option.escape()
    MissingValue(option) => "missing-value: " + option.escape()
    InvalidOptions(reason) => "invalid-options: " + reason.escape()
    UnsupportedCapability(reason) =>
      "unsupported-capability: " + reason.escape()
    MissingInput => "missing-input: supply a NAME or --file"
    InvalidRecord => "invalid-record: embedded CR or LF is not allowed"
    Conversion(error) => conversion_diagnostic(error)
  }
  "cygpath: " + detail
}
