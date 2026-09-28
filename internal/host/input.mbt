///|
/// Return command arguments without the runtime's executable prefix.
/// This boundary supports the Wasm and Native runtime conventions only.
pub fn args() -> Array[String] {
  let raw = @env.args()
  if raw.is_empty() {
    []
  } else {
    raw[1:].to_owned()
  }
}

///|
/// Decode one text-mode record after CRLF translation. A UTF-8 BOM remains
/// path content. The official byte reader interprets each record as a C string,
/// so bytes after its first NUL do not belong to the path.
fn decode_record(
  bytes : Bytes,
  terminated~ : Bool,
  source~ : String,
  line~ : Int,
) -> String? raise HostError {
  if !terminated && bytes.is_empty() {
    return None
  }
  let mut end = bytes.length()
  for i = 0; i < bytes.length(); i = i + 1 {
    if bytes[i] == b'\x00' {
      end = i
      break
    }
  }
  let text = @utf8.decode(bytes[:end], ignore_bom=false) catch {
    _ => raise InvalidEncoding(source~, line~)
  }
  Some(text)
}

///|
async fn stream_reader_until(
  reader : &@io.Reader,
  source : String,
  consume : async (String) -> Bool,
) -> Int {
  let pending = @buffer.Buffer()
  let mut count = 0
  let mut pending_cr = false
  async fn emit(terminated : Bool) -> Bool {
    let record = decode_record(
      pending.to_bytes(),
      terminated~,
      source~,
      line=count + 1,
    )
    pending.reset()
    if record is Some(record) {
      // Caller failures propagate unchanged and stop before the next record.
      count += 1
      consume(record)
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
  for ;; {
    let chunk = reader.read_some(max_len=4096) catch {
      _ => raise ReadError(source~)
    }
    guard chunk is Some(chunk) else { break }
    for byte in chunk {
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
) -> Int {
  stream_file_until(path, record => {
    consume(record)
    true
  })
}

///|
/// Stream records until EOF or until the callback returns false. The stopping
/// record is included in the count; later records are neither decoded nor run.
pub async fn stream_file_until(
  path : String,
  consume : async (String) -> Bool,
) -> Int {
  if path == "-" {
    stream_reader_until(@stdio.stdin, "stdin", consume)
  } else {
    let file = @fs.open(path, mode=ReadOnly) catch {
      @os_error.OSError(_) as error if error.is_ENOENT() => raise FileNotFound
      @os_error.OSError(_) as error if error.is_EACCES() =>
        raise FileAccessDenied
      @os_error.OSError(_) as error if error.is_ENOTDIR() =>
        raise FileNotDirectory
      _ => raise ReadError(source=path)
    }
    defer file.close()
    stream_reader_until(file, path, consume)
  }
}
