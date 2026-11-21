///|
/// Return command arguments without the runtime's executable prefix.
pub fn args() -> Array[String] {
  let raw = @env.args()
  if raw.is_empty() {
    []
  } else {
    raw[1:].to_owned()
  }
}

///|
/// The official reader treats each record as a C string after CRLF translation.
/// Keep its original bytes until the record's conversion direction is known.
fn visible_record(bytes : Bytes, terminated~ : Bool) -> Bytes? {
  if !terminated && bytes.is_empty() {
    return None
  }
  match bytes.find(b"\x00") {
    Some(end) => Some(bytes[:end].to_owned())
    None => Some(bytes)
  }
}

///|
fn utf8_record(
  bytes : Bytes,
  source : String,
  line : Int32,
) -> String raise HostError {
  @utf8.decode(bytes) catch {
    _ => raise InvalidEncoding(source~, line~)
  }
}

///|
async fn stream_record_bytes(
  reader : &@io.BinaryReader,
  source : String,
  consume : async (Bytes, Int32) -> Bool,
) -> Int32 {
  let pending = @buffer.Buffer()
  let mut count = 0
  let mut pending_cr = false
  async fn emit(terminated : Bool) -> Bool {
    let record = visible_record(pending.to_bytes(), terminated~)
    pending.reset()
    if record is Some(record) {
      // Caller failures propagate unchanged and stop before the next record.
      count += 1
      consume(record, count)
    } else {
      true
    }
  }
  async fn append(byte : Byte) -> Bool {
    if byte == b'\n' {
      emit(true)
    } else {
      pending.write_byte(byte)
      // The official fgets buffer is PATH_MAX * 2 + 1, with PATH_MAX=4096.
      // Apply this bound after text-mode CRLF translation, as the runtime does.
      if pending.length() == 8192 {
        emit(false)
      } else {
        true
      }
    }
  }
  let chunk : FixedArray[Byte] = FixedArray::make(4096, b'\x00')
  for ;; {
    let length = reader.read_into(chunk.mut_view()) catch {
      _ => raise ReadError(source~)
    }
    guard length > 0 else { break }
    for byte in chunk[:length] {
      if pending_cr {
        pending_cr = false
        if byte != b'\n' {
          if !append(b'\r') {
            return count
          }
        }
      }
      if byte == b'\r' {
        pending_cr = true
      } else if !append(byte) {
        return count
      }
    }
  }
  if pending_cr {
    if !append(b'\r') {
      return count
    }
  }
  let _ = emit(false)
  count
}

///|
/// Stream UTF-8 input records from a file, or stdin for `-`, and return the
/// number consumed. Records are bounded to 8192 bytes after CRLF translation,
/// matching the official text-file reader, and BOMs remain path content.
/// The callback runs before decoding the next record, and any callback failure
/// stops the stream immediately. Files are closed on success and failure.
pub async fn stream_file(
  path : String,
  consume : async (String) -> Unit,
) -> Int32 {
  stream_file_until(path, record => {
    consume(record)
    true
  })
}

///|
async fn open_host_input(path : String, probe_suffix : Bool) -> @fs.File {
  @fs.open(path, mode=ReadOnly) catch {
    @os_error.OsError(NotFound, ..) as missing if probe_suffix => {
      let native = if @async.platform is Windows {
        path.replace_all(old="\\", new="/")
      } else {
        path
      }
      let mut stem = native.trim_end(chars="/")
      while stem.has_suffix("/.") {
        stem = stem[:stem.length() - 2].trim_end(chars="/")
      }
      let base = stem.to_owned()
      let name = base
        .rev_split_once("/")
        .map(p => p.1.to_owned())
        .unwrap_or(base)
      // An exact dangling symlink still takes priority over a sibling .exe.
      guard !base.is_empty() &&
        native_kind(base) is None &&
        executable_candidate(base, name) is Some(_) else {
        raise missing
      }
      @fs.open(base + ".exe", mode=ReadOnly)
    }
    err => raise err
  }
}

///|
/// Stream records until EOF or until the callback returns false. The stopping
/// record is included in the count; later records are neither decoded nor run.
pub async fn stream_file_until(
  path : String,
  consume : async (String) -> Bool,
  installation? : @lib.Context,
) -> Int32 {
  let source = if path == "-" { "stdin" } else { path }
  stream_file_bytes_until(path, installation?, (bytes, line) => {
    consume(utf8_record(bytes, source, line))
  })
}

///|
pub async fn stream_file_bytes_until(
  path : String,
  consume : async (Bytes, Int32) -> Bool,
  installation? : @lib.Context,
  virtual_context? : @lib.Context,
) -> Int32 {
  if path == "-" {
    stream_record_bytes(@stdio.stdin, "stdin", consume)
  } else {
    let context = match (installation, virtual_context) {
      (None, Some(ctx)) if @async.platform is Windows &&
        is_virtual_input(ctx, path) => Some(ctx)
      _ => installation
    }
    let filename = if context is Some(context) && !path.is_empty() {
      // An empty virtual input supplies no fgets records.
      guard installed_filename(context, path) is Some(native) else { return 0 }
      native
    } else {
      path
    }
    let file = open_host_input(filename, context is None) catch {
      @os_error.OsError(NotFound, ..) => raise FileNotFound
      @os_error.OsError(AccessDenied, ..) => raise FileAccessDenied
      @os_error.OsError(NotDirectory, ..) => raise FileNotDirectory
      LookupErrno(reason) => raise input_path_error(path, reason)
      HostError::_ as err => raise err
      _ => raise ReadError(source=path)
    }
    defer file.close()
    if file.kind() is Directory {
      // Cygwin opens readable directories, then its fgets loop yields no records.
      return 0
    }
    let input = if @async.platform is Windows || installation is Some(_) {
      path.replace_all(old="\\", new="/")
    } else {
      path
    }
    if needs_directory(input) &&
      !(context is Some(_) && filename == @lib.nt_null_path) {
      raise FileNotDirectory
    }
    if installation is Some(_) && file.kind() is Regular {
      check_link_header(filename, file)
    }
    stream_record_bytes(file, path, consume)
  }
}

///|
/// Without an installation, Windows file input still uses Cygwin rules for
/// virtual entries and for POSIX traversal through a network share.
fn is_virtual_input(context : @lib.Context, path : String) -> Bool {
  let unc = path.replace_all(old="\\", new="/")
  if unc.has_prefix("//") && !unc.has_prefix("///") {
    if !path.contains_char('\\') && path.split("/").any(part => part == "..") {
      return true
    }
    return try (
      context.mode_candidate(input_name(path), from=Windows)
      is NetworkDirectory(_)
    ) catch {
      _ => false
    }
  }
  guard path.has_prefix("/") &&
    (!path.has_prefix("//") || path.has_prefix("///")) &&
    !path.contains_char('\\') else {
    return false
  }
  try context.mode_candidate(input_name(path), from=Posix) catch {
    @lib.NoSuchDeviceOrAddress
    | @lib.MissingContext(field="nt_null")
    | @lib.NotDirectory
    | @lib.PathNotFound
    | @lib.UnsupportedNamespace(_) => true
    _ => false
  } noraise {
    Virtual(..) | NetworkDirectory(_) | NullDevice(..) => true
    Filesystem(_, ..) => false
  }
}
