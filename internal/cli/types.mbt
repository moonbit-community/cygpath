///|
pub(all) enum Command {
  Help
  Version
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
  priv posix_cwd : String?
  priv windows_cwd : String?
  priv drive_cwds : Map[String, String]
}

///|
pub struct Converter {
  priv context : @lib.Context
  priv from : @lib.InputSyntax?
  priv to : @lib.OutputFormat
  priv absolute : Bool
  priv list : Bool
  priv unix_prefix : @lib.UnixPrefix
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
    let mounts = self.mounts.map(pair => @lib.Mount::new(pair.0, pair.1))
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
  }
}

///|
fn recognizable_windows(path : String) -> Bool {
  let prefix = path.replace_all(old="\\", new="/")
  path.has_prefix("\\") ||
  prefix.has_prefix("//?/") ||
  prefix.has_prefix("//./") ||
  (path.length() >= 2 && path[0] is ('a'..='z' | 'A'..='Z') && path[1] == ':')
}

///|
pub fn Converter::convert(
  self : Converter,
  path : String,
) -> String raise CliError {
  if path.contains_char('\r') || path.contains_char('\n') {
    raise InvalidRecord
  }
  let from = match self.from {
    Some(syntax) => syntax
    None =>
      if self.to == Posix || (!self.list && recognizable_windows(path)) {
        @lib.Windows
      } else {
        @lib.Posix
      }
  }
  let converted = try {
    if self.list {
      self.context.convert_list(
        path,
        from~,
        to=self.to,
        absolute=self.absolute,
        unix_prefix=self.unix_prefix,
      )
    } else {
      self.context.convert(
        path,
        from~,
        to=self.to,
        absolute=self.absolute,
        unix_prefix=self.unix_prefix,
      )
    }
  } catch {
    error => raise Conversion(error)
  }
  if converted.contains_char('\r') || converted.contains_char('\n') {
    raise InvalidRecord
  }
  converted
}
