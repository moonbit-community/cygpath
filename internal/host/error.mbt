///|
/// Stable host-boundary failures. Runtime-specific error strings are not part
/// of the command's portable diagnostic contract.
pub(all) suberror HostError {
  FileNotFound
  FileAccessDenied
  FileNotDirectory
  NoSuchDeviceOrAddress
  FileLinkLoop
  FileNameTooLong
  ReadError(source~ : String)
  WriteError(stream~ : String)
  InvalidEncoding(source~ : String, line~ : Int32)
  InstallationError(String)
  NameLookupUnavailable(String)
}

///|
/// Format one diagnostic without a trailing LF. Quote supplied names so a
/// filename containing a control character cannot forge an extra message.
pub fn HostError::diagnostic(self : HostError) -> String {
  match self {
    NameLookupUnavailable(reason) =>
      "cygpath: unsupported-capability: " + reason
    InstallationError(reason) => "cygpath: installation context: " + reason
    FileNotFound => "cygpath: No such file or directory"
    FileAccessDenied => "cygpath: Permission denied"
    FileNotDirectory => "cygpath: Not a directory"
    NoSuchDeviceOrAddress => "cygpath: No such device or address"
    FileLinkLoop => "cygpath: Too many levels of symbolic links"
    FileNameTooLong => "cygpath: File name too long"
    ReadError(source~) =>
      "cygpath: input-read-error: cannot read \{@debug.to_string(source)}"
    WriteError(stream~) =>
      "cygpath: output-write-error: cannot write \{@debug.to_string(stream)}"
    InvalidEncoding(source~, line~) =>
      "cygpath: invalid-encoding: invalid UTF-8 in \{@debug.to_string(source)} at line \{line}"
  }
}

///|
fn input_path_error(path : String, reason : String) -> HostError {
  match reason {
    "No such file or directory" => FileNotFound
    "Not a directory" => FileNotDirectory
    "No such device or address" => NoSuchDeviceOrAddress
    "Too many levels of symbolic links" => FileLinkLoop
    "Permission denied" => FileAccessDenied
    "File name too long" => FileNameTooLong
    _ => ReadError(source=path)
  }
}

///|
pub fn HostError::exit_code(_self : HostError) -> Int32 {
  1
}
