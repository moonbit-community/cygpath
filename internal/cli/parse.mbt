///|
fn option_arity(option : String) -> Int raise CliError {
  match option {
    "--unix"
    | "--windows"
    | "--mixed"
    | "--path"
    | "--absolute"
    | "--proc-cygdrive"
    | "--dos"
    | "--short-name"
    | "--long-name"
    | "--root-local"
    | "--mode"
    | "--desktop"
    | "--homeroot"
    | "--mydocs"
    | "--smprograms"
    | "--sysdir"
    | "--windir"
    | "--allusers"
    | "--option"
    | "--ignore"
    | "--help"
    | "--version" => 0
    "--type"
    | "--codepage"
    | "--folder"
    | "--file"
    | "--close"
    | "--from"
    | "--profile"
    | "--root"
    | "--drive-prefix"
    | "--posix-cwd"
    | "--windows-cwd" => 1
    "--mount" | "--drive-cwd" => 2
    _ => raise UnknownOption(option)
  }
}

///|
fn short_option(unit : UInt16, token : String) -> String raise CliError {
  match unit {
    'u' => "--unix"
    'w' => "--windows"
    'm' => "--mixed"
    't' => "--type"
    'p' => "--path"
    'a' => "--absolute"
    'U' => "--proc-cygdrive"
    'd' => "--dos"
    's' => "--short-name"
    'l' => "--long-name"
    'r' => "--root-local"
    'C' => "--codepage"
    'M' => "--mode"
    'D' => "--desktop"
    'H' => "--homeroot"
    'O' => "--mydocs"
    'P' => "--smprograms"
    'S' => "--sysdir"
    'W' => "--windir"
    'F' => "--folder"
    'A' => "--allusers"
    'f' => "--file"
    'o' => "--option"
    'i' => "--ignore"
    'c' => "--close"
    'h' => "--help"
    'V' => "--version"
    _ => raise UnknownOption(token)
  }
}

///|
fn collect_options(
  args : Array[String],
) -> (Array[(String, Array[String])], Array[String]) raise CliError {
  let options : Array[(String, Array[String])] = []
  let names : Array[String] = []
  for i = 0; i < args.length(); {
    let token = args[i]
    if token == "--" {
      for j = i + 1; j < args.length(); j = j + 1 {
        names.push(args[j])
      }
      break
    }
    if token == "-" || !token.has_prefix("-") {
      names.push(token)
      continue i + 1
    }
    if token.has_prefix("--") {
      let (option, attached) = match token.split_once("=") {
        Some((option, value)) => (option.to_owned(), Some(value.to_owned()))
        None => (token, None)
      }
      let arity = option_arity(option)
      let values = match attached {
        Some(value) => {
          if arity == 0 {
            raise InvalidOptions(option + " does not accept a value")
          }
          [value]
        }
        None => []
      }
      let needed = arity - values.length()
      if i + needed >= args.length() {
        raise MissingValue(option)
      }
      for n = 0; n < needed; n = n + 1 {
        values.push(args[i + 1 + n])
      }
      options.push((option, values))
      if option is ("--help" | "--version") {
        return (options, names)
      }
      continue i + 1 + needed
    } else {
      let mut next = i + 1
      for offset = 1; offset < token.length(); {
        let option = short_option(token[offset], token)
        let arity = option_arity(option)
        if arity == 0 {
          options.push((option, []))
          if option is ("--help" | "--version") {
            return (options, names)
          }
          continue offset + 1
        } else {
          // All short options take at most one operand. The rest of a bundle
          // is that operand, not another sequence of flags.
          let value = if offset + 1 < token.length() {
            token[offset + 1:].to_owned()
          } else {
            guard args.get(next) is Some(value) else {
              raise MissingValue(option)
            }
            next = next + 1
            value
          }
          options.push((option, [value]))
          break
        }
      }
      continue next
    }
  }
  (options, names)
}

///|
fn repeated_value(
  previous : String?,
  value : String,
  option : String,
) -> String? raise CliError {
  if previous is Some(old) && old != value {
    raise InvalidOptions("conflicting values for " + option)
  }
  Some(value)
}

///|
/// Parses argv after the executable name. No environment or I/O is consulted.
/// Identical scalar declarations are accepted; conflicting declarations fail.
pub fn parse_args(args : Array[String]) -> Command raise CliError {
  let (options, names) = collect_options(args)
  let mut unix = false
  let mut windows = false
  let mut mixed = false
  let mut from : String? = None
  let mut profile : String? = None
  let mut root : String? = None
  let mut drive_prefix : String? = None
  let mut posix_cwd : String? = None
  let mut windows_cwd : String? = None
  let mut file : String? = None
  let mounts : Array[(String, String)] = []
  let drive_cwds : Map[String, String] = Map([])
  let mut absolute = false
  let mut list = false
  let mut proc_cygdrive = false
  let mut ignore = false
  let mut short = false
  let mut long = false
  let mut root_local = false
  let mut codepage = 65001
  let mut unavailable_codepage : String? = None
  let mut file_options = false
  let unsupported : Array[String] = []
  for (option, values) in options {
    match option {
      "--unix" => unix = true
      "--windows" => windows = true
      "--mixed" => {
        windows = true
        mixed = true
      }
      "--type" => {
        let value = values[0]
          .strip_prefix("=")
          .unwrap_or(values[0][:])
          .to_owned()
          .to_lower()
        if value == "dos" {
          windows = true
          short = true
          unsupported.push("short names require Windows filesystem queries")
        } else if value is ("unix" | "windows" | "mixed") {
          if value == "unix" {
            unix = true
          } else {
            windows = true
          }
          if value == "mixed" {
            mixed = true
          }
        } else {
          raise InvalidOptions("unknown output type " + value)
        }
      }
      "--dos" => {
        windows = true
        short = true
        unsupported.push("short names require Windows filesystem queries")
      }
      "--short-name" => {
        short = true
        unsupported.push("short names require Windows filesystem queries")
      }
      "--long-name" => {
        long = true
        unsupported.push("long names require Windows filesystem queries")
      }
      "--root-local" => root_local = true
      "--codepage" =>
        if values[0].to_upper() is ("UTF8" | "UTF-8") {
          codepage = 65001
          unavailable_codepage = None
        } else if values[0].to_upper() is ("ANSI" | "OEM") {
          unavailable_codepage = Some(values[0])
        } else {
          codepage = @string.parse_int(values[0]) catch {
            _ => raise InvalidOptions("invalid code page " + values[0])
          }
          unavailable_codepage = if @encoding.supported(codepage) {
            None
          } else {
            Some(values[0])
          }
        }
      "--absolute" => absolute = true
      "--path" => list = true
      "--proc-cygdrive" => proc_cygdrive = true
      "--ignore" => ignore = true
      "--help" => return Help
      "--version" => return Version
      "--file" => file = repeated_value(file, values[0], option)
      "--from" => {
        if !(values[0] is ("windows" | "posix")) {
          raise InvalidOptions("--from requires windows or posix")
        }
        from = repeated_value(from, values[0], option)
      }
      "--profile" => {
        if !(values[0] is ("cygwin" | "msys2")) {
          raise InvalidOptions("--profile requires cygwin or msys2")
        }
        profile = repeated_value(profile, values[0], option)
      }
      "--root" => {
        if root is None {
          mounts.push(("/", values[0]))
        }
        root = repeated_value(root, values[0], option)
      }
      "--mount" => mounts.push((values[0], values[1]))
      "--drive-prefix" =>
        drive_prefix = repeated_value(drive_prefix, values[0], option)
      "--posix-cwd" => posix_cwd = repeated_value(posix_cwd, values[0], option)
      "--windows-cwd" =>
        windows_cwd = repeated_value(windows_cwd, values[0], option)
      "--drive-cwd" => {
        let drive = values[0]
        if drive.length() != 1 || !(drive[0] is ('a'..='z' | 'A'..='Z')) {
          raise InvalidOptions(
            "--drive-cwd requires a single ASCII drive letter",
          )
        }
        let drive = drive.to_upper()
        if drive_cwds.contains(drive) {
          raise InvalidOptions("duplicate --drive-cwd for " + drive)
        }
        drive_cwds[drive] = values[1]
      }
      "--mode" => unsupported.push("file modes require the Cygwin runtime")
      "--allusers" => ()
      "--option" => file_options = true
      "--close" =>
        unsupported.push("closing host process handles is not supported")
      _ =>
        unsupported.push(option + " requires Windows system-directory queries")
    }
  }
  if (short && long) || (short && root_local) || (long && root_local) {
    raise InvalidOptions("--short-name, --long-name and --root-local conflict")
  }
  if unix && windows && !file_options {
    raise InvalidOptions("conflicting output formats")
  }
  let to : @lib.OutputFormat = if unix || (!windows && !file_options) {
    Posix
  } else if mixed {
    Mixed
  } else {
    Windows
  }
  if root_local && to != Windows {
    raise InvalidOptions(
      "root-local requires Windows output without mixed mode",
    )
  }
  if (short || long) && !windows {
    raise InvalidOptions("short and long names require Windows output")
  }
  if to != Posix && unavailable_codepage is Some(page) {
    raise UnsupportedCapability(
      "code page " + page + " is not supported by the pure encoder",
    )
  }
  if unsupported.get(0) is Some(reason) {
    raise UnsupportedCapability(reason)
  }
  if file_options && file is None {
    raise InvalidOptions("--option requires --file")
  }
  if file is Some(_) && !names.is_empty() {
    raise InvalidOptions("--file cannot be combined with NAME arguments")
  }
  let source = match file {
    Some(path) => File(path)
    None => {
      if names.is_empty() && !ignore {
        raise MissingInput
      }
      Names(names)
    }
  }
  Convert({
    source,
    from: match from {
      Some("windows") => Some(@lib.Windows)
      Some(_) => Some(@lib.Posix)
      None => None
    },
    to,
    absolute,
    list,
    unix_prefix: if proc_cygdrive {
      ProcCygdrive
    } else {
      Configured
    },
    ignore,
    profile: if profile == Some("msys2") {
      Msys2
    } else {
      Cygwin
    },
    drive_prefix,
    mounts,
    posix_cwd,
    windows_cwd,
    drive_cwds,
    root_local,
    file_options,
    codepage,
  })
}
