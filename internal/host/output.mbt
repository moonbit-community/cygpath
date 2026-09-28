///|
/// Write exactly the UTF-8 bytes of `text`, with no implicit newline or
/// platform newline translation. The caller supplies any LF record separator.
pub async fn write_stdout(text : String) -> Unit {
  write_stdout_bytes(@utf8.encode(text))
}

///|
/// Write already-encoded output bytes without implicit newline conversion.
pub async fn write_stdout_bytes(bytes : Bytes) -> Unit {
  @stdio.stdout.write(bytes) catch {
    _ => raise WriteError(stream="stdout")
  }
}

///|
/// Write a diagnostic as UTF-8 without implicit newline conversion.
pub async fn write_stderr(text : String) -> Unit {
  @stdio.stderr.write(@utf8.encode(text)) catch {
    _ => raise WriteError(stream="stderr")
  }
}

///|
/// Terminate with the command's already-classified exit status.
pub fn exit(code : Int) -> Unit {
  @sys.exit(code)
}
