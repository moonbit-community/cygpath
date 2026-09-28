///|
async fn stream_reader(
  reader : &@io.Reader,
  source : String,
  consume : async (String) -> Unit,
) -> Int {
  stream_reader_until(reader, source, record => {
    consume(record)
    true
  })
}

///|
test "record decoding preserves whitespace after text-mode translation" {
  assert_eq(
    decode_record(b" C:\\work \r", terminated=true, source="test", line=1),
    Some(" C:\\work \r"),
  )
  assert_eq(
    decode_record(b"tail\r", terminated=false, source="test", line=1),
    Some("tail\r"),
  )
  assert_eq(
    decode_record(b"a\rb", terminated=true, source="test", line=1),
    Some("a\rb"),
  )
}

///|
test "empty input and empty records remain distinguishable" {
  assert_eq(decode_record(b"", terminated=false, source="test", line=1), None)
  assert_eq(
    decode_record(b"", terminated=true, source="test", line=1),
    Some(""),
  )
  assert_eq(
    decode_record(b"\x00", terminated=false, source="test", line=1),
    Some(""),
  )
}

///|
test "NUL ends the path without decoding discarded bytes" {
  assert_eq(
    decode_record(
      b"C:\\one\x00\xffignored",
      terminated=false,
      source="test",
      line=1,
    ),
    Some("C:\\one"),
  )
}

///|
test "BOM remains path content at every byte position" {
  assert_eq(
    decode_record(b"\xef\xbb\xbf", terminated=false, source="test", line=1),
    Some("\uFEFF"),
  )
  assert_eq(
    decode_record(b"\xef\xbb\xbf", terminated=true, source="test", line=1),
    Some("\uFEFF"),
  )
  assert_eq(
    decode_record(b"\xef\xbb\xbfx", terminated=false, source="test", line=1),
    Some("\uFEFFx"),
  )
  assert_eq(
    decode_record(b"\xef\xbb\xbfx", terminated=false, source="test", line=2),
    Some("\uFEFFx"),
  )
  assert_eq(
    decode_record(b"x\xef\xbb\xbf", terminated=false, source="test", line=1),
    Some("x\uFEFF"),
  )
}

///|
test "malformed UTF-8 is rejected instead of replaced" {
  for
    bytes in [
      b"\xff", b"\xc0\xaf", b"\xed\xa0\x80", b"\xf4\x90\x80\x80", b"\xef\xbb",
    ] {
    try decode_record(bytes, terminated=false, source="input", line=3) catch {
      InvalidEncoding(source~, line~) => {
        assert_eq(source, "input")
        assert_eq(line, 3)
      }
      _ => fail("expected InvalidEncoding")
    } noraise {
      _ => fail("invalid UTF-8 was accepted")
    }
  }
}

///|
async test "streaming handles chunked BOM Unicode CRLF and final record" {
  let reader = @io.MemoryReader() <| writer => {
    for chunk in [b"\xef", b"\xbb\xbf A\r", b"\n\xe6", b"\x96\x87\n\nlast"] {
      writer.write(chunk)
      @async.sleep(1)
    }
  }
  defer reader.close()
  let records = []
  let count = stream_reader(reader, "test", record => records.push(record))
  assert_eq(count, 4)
  assert_eq(records, ["\uFEFF A", "文", "", "last"])
}

///|
async test "text-mode translation preserves lone and doubled carriage returns" {
  let reader = @io.MemoryReader() <| writer => {
    for chunk in [b"a\r", b"\n\r\r", b"\nb\rc\nlast\r"] {
      writer.write(chunk)
      @async.sleep(1)
    }
  }
  defer reader.close()
  let records = []
  assert_eq(stream_reader(reader, "test", record => records.push(record)), 4)
  assert_eq(records, ["a", "\r", "b\rc", "last\r"])
}

///|
async test "official fgets limit applies after CRLF translation" {
  for
    (size, suffix, lengths) in [
      (8191, b"\r\n", [8191]),
      (8192, b"\r\n", [8192, 0]),
      (8193, b"", [8192, 1]),
    ] {
    let reader = @io.MemoryReader() <| writer => {
      writer.write(Bytes::make(size, b'a'))
      writer.write(suffix)
    }
    defer reader.close()
    let actual = []
    let _ = stream_reader(reader, "test", record => actual.push(record.length()))
    assert_eq(actual, lengths)
  }
}

///|
async test "streaming has no phantom record after a trailing newline" {
  for
    (data, expected) in [
      (b"", 0),
      (b"\xef\xbb\xbf", 1),
      (b"\n", 1),
      (b"a\n", 1),
    ] {
    let reader = @io.MemoryReader(writer => writer.write(data))
    defer reader.close()
    let records = []
    assert_eq(
      stream_reader(reader, "test", record => records.push(record)),
      expected,
    )
    assert_eq(records.length(), expected)
  }
}

///|
async test "callback failure preserves earlier records and stops before later decoding" {
  let reader = @io.MemoryReader(writer => writer.write(b"good\nstop\n\xff\n"))
  defer reader.close()
  let records = []
  try
    stream_reader(reader, "test", record => {
      if record == "stop" {
        raise Failure("callback failed")
      }
      records.push(record)
    })
  catch {
    Failure(message) => assert_eq(message, "callback failed")
    _ => fail("callback failure was changed")
  } noraise {
    _ => fail("callback failure was swallowed")
  }
  assert_eq(records, ["good"])
}

///|
async test "successful callback stop prevents later malformed input decoding" {
  let reader = @io.MemoryReader(writer => writer.write(b"good\nstop\n\xff\n"))
  defer reader.close()
  let records = []
  assert_eq(
    stream_reader_until(reader, "test", record => {
      records.push(record)
      record != "stop"
    }),
    2,
  )
  assert_eq(records, ["good", "stop"])
}

///|
async test "invalid encoding reports its record and preserves prior output" {
  let reader = @io.MemoryReader(writer => writer.write(b"good\n\xff\nlater\n"))
  defer reader.close()
  let records = []
  try stream_reader(reader, "test", record => records.push(record)) catch {
    InvalidEncoding(source~, line~) => {
      assert_eq(source, "test")
      assert_eq(line, 2)
    }
    _ => fail("expected InvalidEncoding")
  } noraise {
    _ => fail("invalid encoding was accepted")
  }
  assert_eq(records, ["good"])
}

///|
async test "reader failures receive a stable host category" {
  let reader = @io.MemoryReader(_ => raise Failure("runtime-specific reason"))
  defer reader.close()
  try stream_reader(reader, "test", _ => ()) catch {
    ReadError(source~) => assert_eq(source, "test")
    _ => fail("expected ReadError")
  } noraise {
    _ => fail("read failure was swallowed")
  }
}

///|
async test "missing input files use the official portable errno diagnostic" {
  let directory = @fs.tmpdir(prefix="cygpath-host-")
  defer @fs.rmdir(directory, recursive=true)
  try stream_file(directory + "/absent", _ => ()) catch {
    FileNotFound as error => {
      assert_eq(error.diagnostic(), "cygpath: No such file or directory")
      assert_eq(error.exit_code(), 1)
    }
    _ => fail("expected FileNotFound")
  } noraise {
    _ => fail("missing file was accepted")
  }
}
