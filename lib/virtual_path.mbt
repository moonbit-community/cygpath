///|
priv enum VirtualNode {
  Directory
  ProcFile
  Terminal
  NullDevice
  Missing
}

///|
/// Win32 spelling returned by cygwin_conv_path before the CLI looks up DOS aliases.
pub let nt_null_path : String = "\\\\.\\GLOBALROOT\\Device\\Null"

///|
/// Numbered devices use canonical decimal suffixes. Disk partitions start
/// at one; an unnumbered disk names the whole drive.
fn runtime_device_name(name : String) -> Bool {
  match name {
    "disk"
    | "tty"
    | "ptmx"
    | "console"
    | "conin"
    | "conout"
    | "fd"
    | "stdin"
    | "stdout"
    | "stderr" => return true
    _ if null_backed_device(name) => return true
    _ => ()
  }
  let stem = name.trim_end(chars="0123456789")
  let digits = name[stem.length():]
  let (lowest, highest) = match stem {
    "cons" | "pty" | "ttyS" | "st" | "nst" => (0, 127)
    "com" => (1, 16)
    "fd" | "sr" | "scd" => (0, 15)
    _ if stem.has_prefix("sd") => {
      let drive = stem[2:]
      let valid = match drive.length() {
        1 => drive[0] is ('a'..<='z')
        2 =>
          (drive[0] is ('a'..<='c') && drive[1] is ('a'..<='z')) ||
          (drive[0] == 'd' && drive[1] is ('a'..<='x'))
        _ => false
      }
      if !valid || digits.is_empty() {
        return valid
      }
      (1, 63)
    }
    _ => return false
  }
  if digits.is_empty() ||
    digits.length() > 3 ||
    (digits.length() > 1 && digits[0] == '0') {
    return false
  }
  let mut n = 0
  for digit in digits {
    n = n * 10 + digit.to_int() - '0'.to_int()
  }
  n >= lowest && n <= highest
}

///|
fn null_backed_device(name : String) -> Bool {
  name
  is ("null"
  | "zero"
  | "full"
  | "random"
  | "urandom"
  | "windows"
  | "mixer"
  | "dsp"
  | "clipboard")
}

///|
// The pinned Cygwin and MSYS2 proc handlers identify these entries by name.
// Process IDs, aliases, network interfaces and IPC services need runtime state.
fn virtual_node(parts : Array[String]) -> VirtualNode? {
  match parts {
    ["dev", "tty" | "ptmx"] => Some(Terminal)
    ["dev", name] if null_backed_device(name) => Some(NullDevice)
    ["proc"] => Some(Directory)
    ["proc", "net" | "sysvipc" | "registry" | "registry32" | "registry64"] =>
      Some(Directory)
    [
      "proc",
      "version"
      | "meminfo"
      | "cpuinfo"
      | "stat"
      | "uptime"
      | "loadavg"
      | "partitions"
      | "swaps"
      | "devices"
      | "filesystems"
      | "codesets"
      | "locales"
      | "misc",
    ] => Some(ProcFile)
    ["proc", "net", "if_inet6", ..] => None
    ["proc", "sysvipc", "shm" | "msg" | "sem", ..] => None
    ["proc", "net" | "sysvipc", ..] => Some(Missing)
    ["proc", "registry" | "registry32" | "registry64", hive] =>
      // The registry handler lists these hive directories in each view.
      // Preserve the caller's casing in the output name.
      if [
          "HKEY_CLASSES_ROOT", "HKEY_CURRENT_CONFIG", "HKEY_CURRENT_USER", "HKEY_LOCAL_MACHINE",
          "HKEY_USERS", "HKEY_PERFORMANCE_DATA",
        ].any(name => hive.equal_ignore_ascii_case(name)) {
        Some(Directory)
      } else {
        None
      }
    [
      "proc",
      "self"
      | "mounts"
      | "cygdrive"
      | "sys"
      | "registry"
      | "registry32"
      | "registry64",
      ..,
    ] => None
    ["proc", name, ..] => {
      let text = name.trim_start(chars=" \t\n\r\u000B\u000C")
      let digits = if text.has_prefix("+") || text.has_prefix("-") {
        text[1:]
      } else {
        text
      }
      if !digits.is_empty() && digits.iter().all(c => c is ('0'..<='9')) {
        None
      } else {
        Some(Missing)
      }
    }
    _ => None
  }
}

///|
fn Context::virtual_spelling(
  self : Context,
  path : ParsedPath,
  input : String,
  relative~ : Bool,
  absolute~ : Bool,
  to~ : OutputFormat,
) -> String {
  if to != Posix && virtual_node(path.components) is Some(NullDevice) {
    return if to == Mixed {
      nt_null_path.replace_all(old="\\", new="/")
    } else {
      nt_null_path
    }
  }
  let name = if relative &&
    !absolute &&
    to != Posix &&
    self.posix_cwd is Some(base) &&
    base.root == PosixRoot &&
    virtual_node(base.components) is Some(Directory) &&
    components_match(base.components, path.components, Sensitive) {
    let suffix = path.components[base.components.length():]
    if suffix.is_empty() {
      "."
    } else {
      suffix.join("/")
    }
  } else {
    "/" + path.components.join("/")
  }
  let directory_suffix = input.has_suffix("/") ||
    input.has_suffix("/.") ||
    input.has_suffix("/..") ||
    input == ".."
  if to == Posix {
    if path.trailing {
      name + "/"
    } else {
      name
    }
  } else if directory_suffix && !absolute {
    name + (if to == Windows { "\\" } else { "/" })
  } else {
    name
  }
}
