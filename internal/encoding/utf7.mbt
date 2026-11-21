///|
/// Windows passes through RFC 2152 set D, whitespace and NUL. A plus sign
/// terminates any shifted run and is always escaped separately.
fn utf7_direct(unit : UInt16) -> Bool {
  unit
  is ('A'..<='Z'
  | 'a'..<='z'
  | '0'..<='9'
  | '\''
  | '('
  | ')'
  | '+'
  | ','
  | '-'
  | '.'
  | '/'
  | ':'
  | '?'
  | '\t'
  | '\n'
  | '\r'
  | ' '
  | '\u0000')
}

///|
fn encode_utf7(text : String) -> Bytes {
  let out = @buffer.Buffer()
  for start = 0; start < text.length(); {
    let unit = text[start]
    if utf7_direct(unit) {
      out.write_byte(unit.to_byte())
      if unit == '+' {
        out.write_byte(b'-')
      }
      continue start + 1
    }
    let mut end = start + 1
    while end < text.length() && !utf7_direct(text[end]) {
      end += 1
    }
    let words = @utf16.encode(text[start:end], endianness=Big)
    out.write_byte(b'+')
    out.write_string_utf8(@base64.encode(words, padding=false))
    out.write_byte(b'-')
    continue end
  }
  out.to_bytes()
}
