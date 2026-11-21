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
  InvalidFileEncoding(source~ : String, line~ : Int32)
  InvalidFolderId(String)
  UnrepresentableName(Int32)
  ShortNameFailure(String)
  PathErrno(String, String)
  ListConversion(String, @lib.ConversionError)
  Conversion(@lib.ConversionError)
}

///|
fn conversion_exit_code(error : @lib.ConversionError) -> Int32 {
  match error {
    @lib.EmptyPath => 1
    @lib.PathTooLong(_)
    | @lib.InvalidDrivePrefix
    | @lib.InvalidWindowsPrefix
    | @lib.NotDirectory
    | @lib.PathNotFound
    | @lib.NoSuchDeviceOrAddress
    | @lib.TooManyLinks => 1
    @lib.InvalidContext(..)
    | @lib.NetworkServerLookup(_)
    | @lib.MissingContext(..)
    | @lib.InvalidOptions(_) => 1
    @lib.ListEntryError(index=_, cause) => conversion_exit_code(cause)
    _ => 2
  }
}

///|
/// Official conversion errors quote the original narrow filename on stderr.
pub fn CliError::diagnostic_bytes(self : CliError) -> Bytes {
  match self {
    PathErrno(_, _) | ListConversion(_, _) =>
      @filename.encode(self.diagnostic())
    _ => @utf8.encode(self.diagnostic())
  }
}

///|
pub fn CliError::exit_code(self : CliError) -> Int32 {
  match self {
    Conversion(error) => conversion_exit_code(error)
    InvalidRecord | ShortNameFailure(_) => 2
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
    @lib.InvalidWindowsPrefix => "invalid-windows-prefix"
    @lib.NotDirectory => "Not a directory"
    @lib.PathNotFound => "No such file or directory"
    @lib.NoSuchDeviceOrAddress => "No such device or address"
    @lib.TooManyLinks => "Too many levels of symbolic links"
    @lib.InvalidPath(reason~, offset~) =>
      "invalid-path: UTF-16 offset \{offset}: " + reason.escape()
    @lib.InvalidContext(field~, reason~) =>
      "invalid-context: " + field.escape() + ": " + reason.escape()
    @lib.MissingContext(field~) => "missing-context: " + field.escape()
    @lib.NetworkServerLookup(server) =>
      "network server presence required for " + server.escape()
    @lib.UnsupportedNamespace(kind) => "unsupported-namespace: " + kind.escape()
    @lib.UnrepresentablePath(component~, reason~) =>
      "unrepresentable-path: " + component.escape() + ": " + reason.escape()
    @lib.InvalidOptions(reason) => "invalid-options: " + reason.escape()
    @lib.ListEntryError(index~, cause) =>
      "list-entry: index \{index}: " + conversion_diagnostic(cause)
  }
}

///|
fn operand_errno(error : @lib.ConversionError) -> String? {
  match error {
    @lib.InvalidWindowsPrefix => Some("Invalid argument")
    @lib.TooManyLinks => Some("Too many levels of symbolic links")
    @lib.InvalidDrivePrefix | @lib.PathNotFound =>
      Some("No such file or directory")
    @lib.NotDirectory => Some("Not a directory")
    @lib.NoSuchDeviceOrAddress => Some("No such device or address")
    @lib.PathTooLong(_) => Some("File name too long")
    @lib.ListEntryError(index=_, cause) => operand_errno(cause)
    _ => None
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
    InvalidFileEncoding(source~, line~) =>
      "invalid-encoding: invalid UTF-8 in " +
      source.escape() +
      " at line " +
      line.to_string()
    InvalidFolderId(id) => "syntax error in special folder ID " + id
    UnrepresentableName(page) =>
      "path cannot be encoded in code page " + page.to_string()
    ShortNameFailure(name) => "cannot create short name of " + name
    PathErrno(path, reason) => "error converting \"" + path + "\" - " + reason
    ListConversion(path, _) =>
      "error converting \"" + path + "\" - Unknown error -1"
    Conversion(error) => conversion_diagnostic(error)
  }
  "cygpath: " + detail
}
