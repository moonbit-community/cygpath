///|
/// Stable host-boundary failures. Runtime-specific error strings are not part
/// of the command's portable diagnostic contract.
pub(all) suberror HostError {
  ReadError(source~ : String)
  WriteError(stream~ : String)
  InvalidEncoding(source~ : String, line~ : Int)
}

///|
/// Format one diagnostic without a trailing LF. Quote supplied names so a
/// filename containing a control character cannot forge an extra message.
pub fn HostError::diagnostic(self : HostError) -> String {
  match self {
    ReadError(source~) =>
      "cygpath: input-read-error: cannot read \{@debug.to_string(source)}"
    WriteError(stream~) =>
      "cygpath: output-write-error: cannot write \{@debug.to_string(stream)}"
    InvalidEncoding(source~, line~) =>
      "cygpath: invalid-encoding: invalid UTF-8 in \{@debug.to_string(source)} at line \{line}"
  }
}

///|
pub fn HostError::exit_code(_self : HostError) -> Int {
  1
}
