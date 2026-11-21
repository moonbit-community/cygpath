///|
fn option_arity(option : String) -> Int32 raise CliError {
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
    | "-r"
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
    "--mount" | "--mount-case" | "--drive-cwd" => 2
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
    'r' => "-r"
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
priv enum ScannedOption {
  Found(String, Array[String])
  Failure(CliError)
}

///|
fn canonical_option(option : String) -> String raise CliError {
  let official = [
    "--unix", "--windows", "--mixed", "--path", "--absolute", "--proc-cygdrive",
    "--dos", "--short-name", "--long-name", "--root-local", "--mode", "--desktop",
    "--homeroot", "--mydocs", "--smprograms", "--sysdir", "--windir", "--allusers",
    "--option", "--ignore", "--help", "--version", "--type", "--codepage", "--folder",
    "--file", "--close",
  ]
  if official.contains(option) || is_project_option(option) {
    return option
  }
  let candidates = official.filter(name => name.has_prefix(option))
  match candidates {
    [name] => name
    [] => raise UnknownOption(option)
    _ => raise OptionError("ambiguous option -- " + option[2:].to_owned())
  }
}

///|
fn collect_options(
  args : Array[String],
) -> (Array[ScannedOption], Array[String]) {
  let options : Array[ScannedOption] = []
  let names : Array[String] = []
  try {
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
        let (raw_option, attached) = match token.split_once("=") {
          Some((option, value)) => (option.to_owned(), Some(value.to_owned()))
          None => (token, None)
        }
        let option = canonical_option(raw_option)
        let arity = option_arity(option)
        let values = match attached {
          Some(value) => {
            if arity == 0 {
              raise OptionError(
                "option doesn't take an argument -- " +
                raw_option[2:].to_owned(),
              )
            }
            [value]
          }
          None => []
        }
        let needed = arity - values.length()
        if i + needed >= args.length() {
          raise MissingValue(raw_option)
        }
        for n = 0; n < needed; n = n + 1 {
          values.push(args[i + 1 + n])
        }
        options.push(Found(option, values))
        if option is ("--help" | "--version") {
          return (options, names)
        }
        continue i + 1 + needed
      } else {
        let mut next = i + 1
        for offset = 1; offset < token.length(); {
          let option = short_option(
            token[offset],
            "-" + token[offset:offset + 1].to_owned(),
          )
          let arity = option_arity(option)
          if arity == 0 {
            options.push(Found(option, []))
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
                raise MissingValue("-" + token[offset:offset + 1].to_owned())
              }
              next = next + 1
              value
            }
            options.push(Found(option, [value]))
            break
          }
        }
        continue next
      }
    }
  } catch {
    error => options.push(Failure(error))
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
  parse_args_inner(args, false) catch {
    IgnoredUsage => ExitSuccess
    error => raise error
  }
}

///|
fn parse_record_args(args : Array[String]) -> Command raise CliError {
  parse_args_inner(args, true) catch {
    IgnoredUsage => ExitSuccess
    error => raise error
  }
}

///|
fn is_project_option(option : String) -> Bool {
  option
  is ("--from"
  | "--profile"
  | "--root"
  | "--mount"
  | "--mount-case"
  | "--drive-prefix"
  | "--posix-cwd"
  | "--windows-cwd"
  | "--drive-cwd")
}

///|
fn mount_case_key(posix : String) -> String {
  let key = posix.trim_end(chars="/").to_owned()
  if key.is_empty() {
    "/"
  } else {
    key
  }
}

///|
fn usage_error(ignore : Bool) -> CliError {
  if ignore {
    IgnoredUsage
  } else {
    Usage
  }
}

///|
fn scan_magnitude(
  digits : StringView,
  radix : UInt64,
  limit : UInt64,
  prefix~ : Bool = false,
) -> (UInt64, Bool)? {
  guard !digits.is_empty() else { return None }
  let mut number = 0UL
  let mut overflow = false
  for unit in digits.code_units() {
    let digit = match unit {
      '0'..<='9' => unit.to_int() - 48
      'a'..<='f' => unit.to_int() - 97 + 10
      'A'..<='F' => unit.to_int() - 65 + 10
      _ => 16
    }
    let digit = digit.to_uint64()
    if digit >= radix {
      if prefix {
        break
      }
      return None
    }
    if !overflow {
      if number > (limit - digit) / radix {
        number = limit
        overflow = true
      } else {
        number = number * radix + digit
      }
    }
  }
  Some((number, overflow))
}

///|
/// The two strtoul callers differ in radix and whether they inspect endptr.
fn option_ulong(text : String, hexadecimal~ : Bool) -> UInt64? {
  let value = text.trim_start(chars=" \t\r\n\u000B\u000C")
  let negative = value.has_prefix("-")
  let digits = if negative || value.has_prefix("+") { value[1:] } else { value }
  let digits = if hexadecimal &&
    (digits.has_prefix("0x") || digits.has_prefix("0X")) {
    digits[2:]
  } else {
    digits
  }
  guard scan_magnitude(
      digits,
      if hexadecimal {
        16UL
      } else {
        10UL
      },
      0xffffffffffffffffUL,
      prefix=hexadecimal,
    )
    is Some((number, overflow)) else {
    return if hexadecimal || text.is_empty() { Some(0UL) } else { None }
  }
  Some(if negative && !overflow { 0UL - number } else { number })
}

///|
fn numeric_codepage(text : String, ignore : Bool) -> Int32 raise CliError {
  guard option_ulong(text, hexadecimal=false) is Some(number) else {
    raise usage_error(ignore)
  }
  number.to_int()
}

///|
fn parse_args_inner(
  args : Array[String],
  from_file : Bool,
) -> Command raise CliError {
  let (options, names) = collect_options(args)
  let mut unix = false
  let mut windows = false
  let mut mixed = false
  let mut mode = false
  let mut from : String? = None
  let mut profile : String? = None
  let mut root : String? = None
  let mut drive_prefix : String? = None
  let mut posix_cwd : String? = None
  let mut windows_cwd : String? = None
  let mut file : String? = None
  let mut folder_option : String? = None
  let mut folder_id = ""
  let mounts : Array[(String, String)] = []
  let mount_cases : Map[String, @lib.MountCase] = Map([])
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
  for token in options {
    let (option, values) = match token {
      Found(option, values) => (option, values)
      Failure(error) => raise error
    }
    if from_file && is_project_option(option) && option != "--from" {
      raise InvalidOptions(
        option + " cannot change the fixed context in option records",
      )
    }
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
          raise usage_error(ignore)
        }
      }
      "--dos" => {
        windows = true
        short = true
      }
      "--short-name" => short = true
      "--long-name" => long = true
      "--root-local" => raise UnknownOption("--root-local")
      "-r" => root_local = true
      "--codepage" =>
        if values[0].to_upper() is ("UTF8" | "UTF-8") {
          codepage = 65001
          unavailable_codepage = None
        } else if values[0].to_upper() is ("ANSI" | "OEM") {
          unavailable_codepage = Some(values[0])
        } else {
          let number = numeric_codepage(values[0], ignore)
          // A zero UINT selects cygpath's default multibyte conversion.
          codepage = if number == 0 { 65001 } else { number }
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
      "--file" => {
        if from_file {
          raise usage_error(ignore)
        }
        file = Some(values[0])
      }
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
      "--mount-case" => {
        let policy : @lib.MountCase = match values[1] {
          "sensitive" => Sensitive
          "ascii-insensitive" => AsciiInsensitive
          "windows-insensitive" => WindowsInsensitive
          _ =>
            raise InvalidOptions(
              "--mount-case requires sensitive, ascii-insensitive, or windows-insensitive",
            )
        }
        let key = mount_case_key(values[0])
        if mount_cases.get(key) is Some(old) && old != policy {
          raise InvalidOptions("conflicting --mount-case for " + key)
        }
        mount_cases[key] = policy
      }
      "--drive-prefix" =>
        drive_prefix = repeated_value(drive_prefix, values[0], option)
      "--posix-cwd" => posix_cwd = repeated_value(posix_cwd, values[0], option)
      "--windows-cwd" =>
        windows_cwd = repeated_value(windows_cwd, values[0], option)
      "--drive-cwd" => {
        let drive = values[0]
        if drive.length() != 1 || !(drive[0] is ('a'..<='z' | 'A'..<='Z')) {
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
      "--mode" => mode = true
      "--allusers" => ()
      "--option" => {
        if from_file {
          raise usage_error(ignore)
        }
        file_options = true
      }
      "--close" =>
        // NULL denotes no object. Closing the process or thread pseudo handle
        // has no effect. Keep actual handles distinct from Wasm descriptors.
        match option_ulong(values[0], hexadecimal=true) {
          Some(0UL | 0xffffffffffffffffUL | 0xfffffffffffffffeUL) => ()
          _ =>
            raise UnsupportedCapability(
              "closing host process handles is not supported",
            )
        }
      "--folder" => {
        folder_option = Some(option)
        folder_id = values[0]
      }
      _ => folder_option = Some(option)
    }
  }
  if (short && long) || (short && root_local) || (long && root_local) {
    raise usage_error(ignore)
  }
  let outputs = (if unix { 1 } else { 0 }) +
    (if windows { 1 } else { 0 }) +
    (if mode { 1 } else { 0 })
  if outputs > (if file_options { 2 } else { 1 }) {
    raise usage_error(ignore)
  }
  let to : @lib.OutputFormat = if unix || (!windows && !file_options) {
    Posix
  } else if mixed {
    Mixed
  } else {
    Windows
  }
  if root_local && (!windows || mixed) {
    raise usage_error(ignore)
  }
  if (short || long) && !windows {
    raise usage_error(ignore)
  }
  if file_options && file is None {
    raise usage_error(ignore)
  }
  if file is Some(_) && !names.is_empty() {
    raise usage_error(ignore)
  }
  let source = match file {
    Some(path) => File(path)
    None if folder_option is Some(option) => {
      if !names.is_empty() {
        raise usage_error(ignore)
      }
      Folder(parse_system_folder(option, folder_id))
    }
    None => {
      if names.is_empty() {
        if ignore {
          raise IgnoredUsage
        } else {
          raise MissingInput
        }
      }
      Names(names)
    }
  }
  let output_error = if (!mode || source is Folder(_)) &&
    to != Posix &&
    unavailable_codepage is Some(page) {
    Some("code page " + page + " is not supported by the pure encoder")
  } else {
    None
  }
  if !(source is Folder(VirtualFolder)) && output_error is Some(reason) {
    raise UnsupportedCapability(reason)
  }
  for key, _ in mount_cases {
    if !mounts.any(pair => mount_case_key(pair.0) == key) {
      raise InvalidOptions("--mount-case has no matching mount: " + key)
    }
  }
  Convert({
    source,
    mode,
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
    mount_cases,
    posix_cwd,
    windows_cwd,
    drive_cwds,
    root_local,
    name_form: if short {
      Short
    } else if long {
      Long
    } else {
      Ordinary
    },
    file_options,
    codepage,
    output_error,
  })
}
