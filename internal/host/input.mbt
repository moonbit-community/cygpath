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
/// Decode one buffered record. The caller has consumed LF when `terminated`
/// is true; only then may the preceding CR be removed. A BOM is metadata only
/// at byte zero of the whole input. A BOM-only file contains no records.
fn decode_record(
  bytes : Bytes,
  first~ : Bool,
  terminated~ : Bool,
  source~ : String,
  line~ : Int,
) -> String? raise HostError {
  let start = if first &&
    bytes.length() >= 3 &&
    bytes[0] == b'\xef' &&
    bytes[1] == b'\xbb' &&
    bytes[2] == b'\xbf' {
    3
  } else {
    0
  }
  let end = if terminated &&
    bytes.length() > start &&
    bytes[bytes.length() - 1] == b'\r' {
    bytes.length() - 1
  } else {
    bytes.length()
  }
  if !terminated && start == end {
    return None
  }
  let text = @utf8.decode(bytes[start:end], ignore_bom=false) catch {
    _ => raise InvalidEncoding(source~, line~)
  }
  Some(text)
}

///|
async fn stream_reader(
  reader : &@io.Reader,
  source : String,
  consume : async (String) -> Unit,
) -> Int {
  let pending = @buffer.Buffer()
  let mut count = 0
  for ;; {
    let chunk = reader.read_some(max_len=4096) catch {
      _ => raise ReadError(source~)
    }
    guard chunk is Some(chunk) else { break }
    for byte in chunk {
      if byte == b'\n' {
        let record = decode_record(
          pending.to_bytes(),
          first=count == 0,
          terminated=true,
          source~,
          line=count + 1,
        )
        pending.reset()
        if record is Some(record) {
          // Keep this outside the read-error handler: caller failures must
          // propagate unchanged and prevent processing any later record.
          consume(record)
          count += 1
        }
      } else {
        pending.write_byte(byte)
      }
    }
  }
  if decode_record(
      pending.to_bytes(),
      first=count == 0,
      terminated=false,
      source~,
      line=count + 1,
    )
    is Some(record) {
    consume(record)
    count += 1
  }
  count
}

///|
/// Stream UTF-8 input records from a file, or stdin for `-`, and return the
/// number consumed. Memory use is bounded by the longest individual record.
/// The callback runs before decoding the next record, and any callback failure
/// stops the stream immediately. Files are closed on success and failure.
pub async fn stream_file(
  path : String,
  consume : async (String) -> Unit,
) -> Int {
  if path == "-" {
    stream_reader(@stdio.stdin, "stdin", consume)
  } else {
    let file = @fs.open(path, mode=ReadOnly) catch {
      _ => raise ReadError(source=path)
    }
    defer file.close()
    stream_reader(file, path, consume)
  }
}
