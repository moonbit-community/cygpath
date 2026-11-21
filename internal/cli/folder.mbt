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
      // The SDK reserves bits 8..15 for flags. Keep the high word when
      // extracting the ID, so 0x10024 cannot alias CSIDL_WINDOWS.
      let id = value & (0xff00).lnot()
      let shell_if_missing = (value & 0xc000) != 0
      match id {
        0x14 => FixedShellDirectory("Fonts", shell_if_missing~)
        0x24 => FixedShellDirectory("", shell_if_missing~)
        0x25 => FixedShellDirectory("System32", shell_if_missing~)
        0x29 => FixedShellDirectory("SysWOW64", shell_if_missing~)
        0x38 => FixedShellDirectory("Resources", shell_if_missing~)
        // Virtual namespaces and unassigned legacy IDs have no filesystem path.
        // 0x39 and 0x3a are real, machine-dependent Shell locations.
        0x01
        | 0x03
        | 0x04
        | 0x0a
        | 0x0c
        | 0x0f
        | 0x11
        | 0x12
        | 0x31..<=0x34
        | 0x3c
        | 0x3d
        | 0x3f..<_ => NoFolderPath
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
    NoFolderPath => return None
    WindowsRoot => ""
    SystemDirectory => "System32"
    FixedShellDirectory(name, ..) => name
  }
  guard resolve(child) is Some(native) else {
    match folder {
      FixedShellDirectory(_, shell_if_missing=false) => return None
      FixedShellDirectory(_, shell_if_missing=true) =>
        raise UnsupportedCapability(
          "missing system folder requires a Windows Shell query for CREATE or DONT_VERIFY",
        )
      _ => ()
    }
    raise UnsupportedCapability(
      "cannot obtain the system directory's filesystem spelling",
    )
  }
  if self.output_error is Some(reason) {
    raise UnsupportedCapability(reason)
  }
  guard self.to == Posix else {
    raise UnsupportedCapability(
      "Windows system-directory API spelling is unavailable",
    )
  }
  Some(
    self.context.windows_to_posix_bytes(native, unix_prefix=self.unix_prefix) catch {
      error => raise Conversion(error)
    },
  )
}
