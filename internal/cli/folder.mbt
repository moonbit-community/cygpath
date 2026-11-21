///|
/// Cygwin scans a signed C integer with %i and requires the entire argument.
/// The underlying strtol uses a 64-bit long, then scanf stores a 32-bit int.
fn folder_id(text : String) -> Int32 raise CliError {
  let token = text.trim_start(chars=" \t\r\n\u000B\u000C")
  let negative = token.has_prefix("-")
  let token = if negative || token.has_prefix("+") { token[1:] } else { token }
  let (radix, digits) = if token.has_prefix("0x") || token.has_prefix("0X") {
    (16UL, token[2:])
  } else if token.has_prefix("0") {
    (8UL, token)
  } else {
    (10UL, token)
  }
  let limit = if negative {
    9223372036854775808UL
  } else {
    9223372036854775807UL
  }
  guard scan_magnitude(digits, radix, limit) is Some((magnitude, _)) else {
    raise InvalidFolderId(text)
  }
  let value = (if negative { 0UL - magnitude } else { magnitude }).to_int()
  guard value >= 0 else { raise InvalidFolderId(text) }
  value
}

///|
fn parse_system_folder(
  option : String,
  id : String,
) -> SystemFolder raise CliError {
  match option {
    "--windir" => WindowsRoot
    "--sysdir" => SystemDirectory
    "--folder" => {
      let value = folder_id(id)
      // NO_ALIAS and DONT_UNEXPAND still select the same absolute path for
      // these fixed directories. Other flags can change filesystem lookup.
      match value & (0x3000).lnot() {
        0x14 => FixedShellDirectory("Fonts")
        0x24 => FixedShellDirectory("")
        0x25 => FixedShellDirectory("System32")
        0x29 => FixedShellDirectory("SysWOW64")
        0x38 => FixedShellDirectory("Resources")
        // CSIDL flags do not give these virtual namespaces a filesystem path.
        _ if (value & 0xffff07ff)
          is (0x01 | 0x03 | 0x04 | 0x0a | 0x11 | 0x12 | 0x31 | 0x3d) =>
          VirtualFolder
        _ =>
          raise UnsupportedCapability(
            option + " requires Windows system-directory queries",
          )
      }
    }
    _ =>
      raise UnsupportedCapability(
        option + " requires Windows system-directory queries",
      )
  }
}

///|
pub async fn Converter::folder_output(
  self : Converter,
  folder : SystemFolder,
  resolve : async (String) -> String?,
) -> Bytes? {
  let child = match folder {
    VirtualFolder => return None
    WindowsRoot => ""
    SystemDirectory => "System32"
    FixedShellDirectory(name) => name
  }
  guard self.to == Posix else {
    raise UnsupportedCapability(
      "Windows system-directory API spelling is unavailable",
    )
  }
  guard resolve(child) is Some(native) else {
    if folder is FixedShellDirectory(_) {
      return None
    }
    raise UnsupportedCapability(
      "cannot obtain the system directory's filesystem spelling",
    )
  }
  Some(
    self.context.windows_to_posix_bytes(native, unix_prefix=self.unix_prefix) catch {
      error => raise Conversion(error)
    },
  )
}
