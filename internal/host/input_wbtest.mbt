///|
test "record decoding preserves spaces and only removes a CR before LF" {
  assert_eq(
    decode_record(
      b" C:\\work \r",
      first=true,
      terminated=true,
      source="test",
      line=1,
    ),
    Some(" C:\\work "),
  )
  assert_eq(
    decode_record(
      b"tail\r",
      first=true,
      terminated=false,
      source="test",
      line=1,
    ),
    Some("tail\r"),
  )
  assert_eq(
    decode_record(b"a\rb", first=true, terminated=true, source="test", line=1),
    Some("a\rb"),
  )
}

///|
test "empty input and empty records remain distinguishable" {
  assert_eq(
    decode_record(b"", first=true, terminated=false, source="test", line=1),
    None,
  )
  assert_eq(
    decode_record(b"", first=true, terminated=true, source="test", line=1),
    Some(""),
  )
  assert_eq(
    decode_record(b"\r", first=true, terminated=true, source="test", line=1),
    Some(""),
  )
}

///|
test "BOM is metadata only at the first byte position" {
  assert_eq(
    decode_record(
      b"\xef\xbb\xbf",
      first=true,
      terminated=false,
      source="test",
      line=1,
    ),
    None,
  )
  assert_eq(
    decode_record(
      b"\xef\xbb\xbf",
      first=true,
      terminated=true,
      source="test",
      line=1,
    ),
    Some(""),
  )
  assert_eq(
    decode_record(
      b"\xef\xbb\xbfx",
      first=true,
      terminated=false,
      source="test",
      line=1,
    ),
    Some("x"),
  )
  assert_eq(
    decode_record(
      b"\xef\xbb\xbfx",
      first=false,
      terminated=false,
      source="test",
      line=2,
    ),
    Some("\uFEFFx"),
  )
  assert_eq(
    decode_record(
      b"x\xef\xbb\xbf",
      first=true,
      terminated=false,
      source="test",
      line=1,
    ),
    Some("x\uFEFF"),
  )
}

///|
test "malformed UTF-8 is rejected instead of replaced" {
  for
    bytes in [
      b"\xff", b"\xc0\xaf", b"\xed\xa0\x80", b"\xf4\x90\x80\x80", b"\xef\xbb",
    ] {
    try
      decode_record(bytes, first=true, terminated=false, source="input", line=3)
    catch {
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
  assert_eq(records, [" A", "文", "", "last"])
}

///|
async test "streaming has no phantom record after a trailing newline" {
  for
    (data, expected) in [
      (b"", 0),
      (b"\xef\xbb\xbf", 0),
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
