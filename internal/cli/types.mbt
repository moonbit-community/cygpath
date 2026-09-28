///|
pub(all) enum Command {
  Help
  Version
  ExitSuccess
  Convert(Request)
}

///|
pub(all) enum InputSource {
  Names(Array[String])
  File(String)
}

///|
/// Parsed command state. Context is constructed only for conversion requests.
pub struct Request {
  priv source : InputSource
  priv from : @lib.InputSyntax?
  priv to : @lib.OutputFormat
  priv absolute : Bool
  priv list : Bool
  priv unix_prefix : @lib.UnixPrefix
  priv ignore : Bool
  priv profile : @lib.Profile
  priv drive_prefix : String?
  priv mounts : Array[(String, String)]
  priv mount_cases : Map[String, @lib.MountCase]
  priv posix_cwd : String?
  priv windows_cwd : String?
  priv drive_cwds : Map[String, String]
  priv root_local : Bool
  priv file_options : Bool
  priv codepage : Int
}

///|
pub struct Converter {
  priv context : @lib.Context
  priv mut from : @lib.InputSyntax?
  priv mut to : @lib.OutputFormat
  priv mut absolute : Bool
  priv mut list : Bool
  priv mut unix_prefix : @lib.UnixPrefix
  priv mut root_local : Bool
  priv mut ignore : Bool
  priv mut codepage : Int
  priv file_options : Bool
}

///|
pub(all) enum RecordAction {
  Output(String)
  Skip
  Stop(String)
}

///|
pub fn Request::per_line_options(self : Request) -> Bool {
  self.file_options
}

///|
pub fn Converter::codepage(self : Converter) -> Int {
  if self.to == Posix {
    65001
  } else {
    self.codepage
  }
}

///|
pub fn Request::input(self : Request) -> InputSource {
  match self.source {
    Names(names) => Names(names.copy())
    File(file) => File(file)
  }
}

///|
pub fn Request::ignore_missing(self : Request) -> Bool {
  self.ignore
}

///|
pub fn Request::prepare(self : Request) -> Converter raise CliError {
  let context = try {
    let mounts = self.mounts.map(pair => {
      @lib.Mount::new(
        pair.0,
        pair.1,
        case=self.mount_cases.get(mount_case_key(pair.0)).unwrap_or(Sensitive),
      )
    })
    @lib.Context::new(
      profile=self.profile,
      drive_prefix?=self.drive_prefix,
      mounts~,
      posix_cwd?=self.posix_cwd,
      windows_cwd?=self.windows_cwd,
      drive_cwds=self.drive_cwds,
    )
  } catch {
    error => raise Conversion(error)
  }
  {
    context,
    from: self.from,
    to: self.to,
    absolute: self.absolute,
    list: self.list,
    unix_prefix: self.unix_prefix,
    root_local: self.root_local,
    ignore: self.ignore,
    codepage: self.codepage,
    file_options: self.file_options,
  }
}

///|
fn recognizable_windows(path : String) -> Bool {
  let prefix = path.replace_all(old="\\", new="/")
  path.contains_char('\\') ||
  prefix.has_prefix("//?/") ||
  prefix.has_prefix("//./") ||
  (path.length() >= 2 && path[0] is ('a'..='z' | 'A'..='Z') && path[1] == ':')
}

///|
pub fn Converter::convert(
  self : Converter,
  path : String,
) -> String raise CliError {
  if path.is_empty() {
    raise Conversion(@lib.EmptyPath)
  }
  let drive_relative = path.length() >= 2 &&
    path[0] is ('a'..='z' | 'A'..='Z') &&
    path[1] == ':' &&
    (path.length() == 2 || !(path[2] is ('/' | '\\')))
  let literal_drive = self.from is None &&
    !self.list &&
    self.to != Posix &&
    drive_relative &&
    (self.absolute || path.length() == 2)
  let from = match self.from {
    Some(syntax) => syntax
    None =>
      if literal_drive {
        @lib.Posix
      } else if self.to == Posix || (!self.list && recognizable_windows(path)) {
        @lib.Windows
      } else {
        @lib.Posix
      }
  }
  let absolute = self.absolute ||
    literal_drive ||
    (
      self.from is None &&
      self.to != Posix &&
      path.has_prefix("\\") &&
      !path.has_prefix("\\\\")
    )
  let converted = try {
    if self.list {
      self.context.convert_list(
        path,
        from~,
        to=self.to,
        absolute~,
        recognize_windows=self.from is None,
        unix_prefix=if self.to == Posix { self.unix_prefix } else { Configured },
      )
    } else {
      self.context.convert(
        path,
        from~,
        to=self.to,
        absolute~,
        unix_prefix=if self.to == Posix { self.unix_prefix } else { Configured },
      )
    }
  } catch {
    error if self.list && (invalid_drive_prefix(error) || path_too_long(error)) =>
      // The upstream list wrapper assigns the nested conversion's -1 return
      // to errno. Preserve the structured cause while matching its diagnostic.
      raise ListConversion(path, error)
    error if invalid_drive_prefix(error) => raise PathNotFound(path)
    error if path_too_long(error) => raise Conversion(@lib.PathTooLong(path))
    error => raise Conversion(error)
  }
  if self.root_local && !self.list {
    if converted.has_prefix("\\\\?\\") {
      converted
    } else if converted.has_prefix("\\\\") {
      "\\\\?\\UNC\\" + converted[2:].to_owned()
    } else {
      "\\\\?\\" + converted
    }
  } else {
    converted
  }
}

///|
fn file_option_arguments(record : String) -> Array[String] {
  for index, character in record.iter2() {
    if character is (' ' | '\t' | '\r' | '\n' | '\u000B' | '\u000C') {
      let option = record[:index].to_owned()
      let rest = record[index:]
        .trim_start(chars=" \t\r\n\u000B\u000C")
        .to_owned()
      return [option, rest]
    }
  }
  [record]
}

///|
pub fn Converter::convert_file_record(
  self : Converter,
  record : String,
) -> RecordAction raise CliError {
  if self.file_options && record.has_prefix("-") {
    let args = file_option_arguments(record)
    match parse_record_args(args) {
      Help => return Stop(help_text())
      Version => return Stop(version_text())
      ExitSuccess => return Stop("")
      Convert(request) => {
        self.from = request.from
        self.to = request.to
        self.absolute = request.absolute
        self.list = request.list
        self.unix_prefix = request.unix_prefix
        self.root_local = request.root_local
        self.ignore = request.ignore
        self.codepage = request.codepage
        match request.input() {
          Names([]) => return Skip
          Names([path]) => return self.convert_operand(path)
          _ => raise InvalidOptions("expected one path in an option record")
        }
      }
    }
  }
  self.convert_operand(record)
}

///|
pub fn Converter::convert_operand(
  self : Converter,
  path : String,
) -> RecordAction raise CliError {
  if path.is_empty() && self.ignore {
    Skip
  } else {
    Output(self.convert(path))
  }
}
