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
  Folder(SystemFolder)
}

///|
pub(all) enum SystemFolder {
  WindowsRoot
  SystemDirectory
  FixedShellDirectory(String)
  VirtualFolder
}

///|
#derive(Eq)
priv enum NameForm {
  Ordinary
  Long
  Short
}

///|
/// Parsed command state. Context is constructed only for conversion requests.
pub struct Request {
  priv source : InputSource
  priv mode : Bool
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
  priv name_form : NameForm
  priv file_options : Bool
  priv codepage : Int32
  priv output_error : String?
}

///|
pub struct Converter {
  context : @lib.Context
  server_lookup : (async (String) -> Bool)?
  priv installed : Bool
  priv lookup : (async (@lib.Context, String, @lib.InputSyntax, Bool) -> Result[
    String,
    String,
  ])?
  priv mut mode : Bool
  priv mut from : @lib.InputSyntax?
  priv mut to : @lib.OutputFormat
  priv mut absolute : Bool
  priv mut list : Bool
  priv mut unix_prefix : @lib.UnixPrefix
  priv mut root_local : Bool
  priv mut name_form : NameForm
  priv mut ignore : Bool
  priv mut codepage : Int32
  priv mut output_error : String?
  priv file_options : Bool
}

///|
pub(all) enum RecordAction {
  Output(String)
  OutputBytes(Bytes)
  QueryMode(String)
  QueryFolder(SystemFolder)
  Skip
  Stop(String)
}

///|
pub fn Request::per_line_options(self : Request) -> Bool {
  self.file_options
}

///|
pub fn Converter::codepage(self : Converter) -> Int32 {
  if self.to == Posix {
    65001
  } else {
    self.codepage
  }
}

///|
fn encode_name(text : String, page : Int32) -> Bytes raise CliError {
  let bytes = @encoding.encode(text, page) catch {
    @encoding.UnmappableCharacter(page) => raise UnrepresentableName(page)
    @encoding.UnsupportedCodePage(page) =>
      raise UnsupportedCapability(
        "code page " +
        page.to_string() +
        " is not supported by the pure encoder",
      )
  }
  match bytes[:].find(b"\x00") {
    Some(end) => bytes[:end].to_owned()
    None => bytes
  }
}

///|
// The cygpath CLI includes the terminating NUL when comparing a wide
// argument with MAX_PATH. Only a literal backslash UNC gets the UNC prefix.
fn wide_name_path(path : String) -> String {
  if path.length() >= 259 && !path.has_prefix("\\\\?\\") {
    if path.has_prefix("\\\\") {
      "\\\\?\\UNC" + path[1:].to_owned()
    } else {
      "\\\\?\\" + path
    }
  } else {
    path
  }
}

///|
async fn encoded_long_names(
  bytes : Bytes,
  page : Int32,
  list : Bool,
  expand : async (String) -> String,
) -> Bytes {
  // cygpath decodes the first encoded path under its current locale, then
  // calls GetLongPathNameW and encodes the result with the same page.
  let narrow = @utf8.decode(bytes, ignore_bom=false) catch {
    _ =>
      raise UnsupportedCapability(
        "long-name input is invalid in the UTF-8 locale",
      )
  }
  let names = if list {
    narrow.split(";").map(s => s.to_owned()).to_array()
  } else {
    [narrow]
  }
  let out = @buffer.Buffer()
  for index, name in names {
    if index > 0 {
      out.write_byte(b';')
    }
    out.write_bytes(encode_name(expand(wide_name_path(name)), page))
  }
  out.to_bytes()
}

///|
async fn encoded_short_names(
  bytes : Bytes,
  page : Int32,
  list : Bool,
  shorten : async (String) -> String?,
) -> Bytes {
  let names : Array[String] = []
  for start = 0 {
    let end = if list {
      start + bytes[start:].find(b";").unwrap_or(bytes.length() - start)
    } else {
      bytes.length()
    }
    let name = @utf8.decode(bytes[start:end], ignore_bom=false) catch {
      _ =>
        raise UnsupportedCapability(
          "short-name input is invalid in the UTF-8 locale",
        )
    }
    guard shorten(wide_name_path(name)) is Some(short) else {
      raise ShortNameFailure(name)
    }
    names.push(short)
    if end == bytes.length() {
      break
    }
    continue end + 1
  }
  // The short-name list is joined in UTF-16 before the final encoding.
  encode_name(names.join(";"), page)
}

///|
fn trim_name_prefix(bytes : Bytes) -> Bytes {
  // Single-name output drops the extended prefix if the encoded result
  // fits MAX_PATH. The upstream list branch keeps each result verbatim.
  if bytes.has_prefix(b"\\\\?\\") {
    if bytes.length() > 5 && bytes[5] == b':' && bytes.length() < 264 {
      return bytes[4:].to_owned()
    } else if bytes.has_prefix(b"\\\\?\\UNC\\") && bytes.length() < 266 {
      return b"\\" + bytes[7:].to_owned()
    }
  }
  bytes
}

///|
/// get_device_name compares the already encoded output with ASCII NT device
/// prefixes. A list is split on encoded byte 0x3b before that comparison.
fn needs_device_alias(bytes : Bytes, list~ : Bool, mixed~ : Bool) -> Bool {
  let (device, global) = if mixed {
    (b"/device/", b"//./globalroot/device/")
  } else {
    (b"\\device\\", b"\\\\.\\globalroot\\device\\")
  }
  fn starts(path : BytesView, lower : Bytes) -> Bool {
    guard path.length() >= lower.length() else { return false }
    for i in 0..<lower.length() {
      let b = path[i]
      if b != lower[i] &&
        !(b is (b'A'..<=b'Z') && b.to_int() + 32 == lower[i].to_int()) {
        return false
      }
    }
    true
  }
  for path = bytes[:] {
    if starts(path, device) || starts(path, global) {
      return true
    }
    guard list && path.find(b";") is Some(end) else { return false }
    continue path[end + 1:]
  }
}

///|
pub async fn Converter::encode_output(
  self : Converter,
  text : String,
  expand? : async (String) -> String,
  shorten? : async (String) -> String?,
) -> Bytes {
  let page = self.codepage()
  let bytes = encode_name(text, page)
  if self.to != Posix &&
    needs_device_alias(
      bytes,
      list=self.list,
      mixed=self.operand_format() == Mixed,
    ) {
    raise UnsupportedCapability(
      "DOS device alias lookup requires the Windows Object Manager directories",
    )
  }
  let bytes = match (self.name_form, self.to) {
    (Ordinary, _) | (_, Posix) => bytes
    (Long, _) => {
      guard expand is Some(expand) else {
        raise UnsupportedCapability("long-name lookup requires a Windows host")
      }
      encoded_long_names(bytes, page, self.list, expand)
    }
    (Short, _) => {
      guard shorten is Some(shorten) else {
        raise UnsupportedCapability("short-name lookup requires a Windows host")
      }
      encoded_short_names(bytes, page, self.list, shorten)
    }
  }
  let bytes = if !self.list && !self.root_local && self.to != Posix {
    trim_name_prefix(bytes)
  } else {
    bytes
  }
  if self.to == Mixed && self.operand_format() == Windows {
    return Bytes::makei(bytes.length(), i => {
      if bytes[i] == b'\\' {
        b'/'
      } else {
        bytes[i]
      }
    })
  }
  if self.root_local && !self.list && !bytes.has_prefix(b"\\\\?\\") {
    if bytes.has_prefix(b"\\\\") {
      b"\\\\?\\UNC" + bytes[1:].to_owned()
    } else {
      b"\\\\?\\" + bytes
    }
  } else {
    bytes
  }
}

///|
pub fn Request::input(self : Request) -> InputSource {
  match self.source {
    Names(names) => Names(names.copy())
    File(file) => File(file)
    Folder(folder) => Folder(folder)
  }
}

///|
pub fn Request::ignore_missing(self : Request) -> Bool {
  self.ignore
}

///|
/// Without an installed cwd or mounts, a null-backed device can only be
/// reached through an explicit POSIX name. File records may supply it later.
pub fn Request::needs_device_probe(self : Request) -> Bool {
  let posix_lookup = self.mode || self.to != Posix || self.from is Some(Posix)
  match self.source {
    Names(paths) => posix_lookup && paths.any(path => path.contains("/dev/"))
    File(path) => path.contains("/dev/") || self.file_options || posix_lookup
    Folder(_) => false
  }
}

///|
pub fn Request::installation_profile(self : Request) -> @lib.Profile? {
  if !(self.source is Folder(VirtualFolder)) &&
    self.mounts.is_empty() &&
    self.drive_prefix is None &&
    self.posix_cwd is None &&
    self.windows_cwd is None &&
    self.drive_cwds.is_empty() {
    Some(self.profile)
  } else {
    None
  }
}

///|
pub fn Request::prepare(
  self : Request,
  installation? : @lib.Context,
  nt_null? : Bool,
  server_lookup? : async (String) -> Bool,
  lookup? : async (@lib.Context, String, @lib.InputSyntax, Bool) -> Result[
    String,
    String,
  ],
) -> Converter raise CliError {
  let automatic = self.installation_profile() is Some(_)
  let installation = if automatic { installation } else { None }
  let context = if installation is Some(context) {
    context
  } else {
    try {
      let mounts = self.mounts.map(pair => {
        @lib.Mount::new(
          pair.0,
          pair.1,
          case=self.mount_cases.get(mount_case_key(pair.0)).unwrap_or(Sensitive),
        )
      })
      @lib.Context::new(
        profile=self.profile,
        nt_null?,
        drive_prefix?=self.drive_prefix,
        mounts~,
        posix_cwd?=self.posix_cwd,
        windows_cwd?=self.windows_cwd,
        drive_cwds=self.drive_cwds,
      )
    } catch {
      error => raise Conversion(error)
    }
  }
  {
    context,
    server_lookup: if automatic {
      server_lookup
    } else {
      None
    },
    installed: installation is Some(_),
    lookup: if automatic {
      lookup
    } else {
      None
    },
    mode: self.mode,
    from: self.from,
    to: self.to,
    absolute: self.absolute,
    list: self.list,
    unix_prefix: self.unix_prefix,
    root_local: self.root_local,
    name_form: self.name_form,
    ignore: self.ignore,
    codepage: self.codepage,
    output_error: self.output_error,
    file_options: self.file_options,
  }
}

///|
fn recognizable_windows(path : String) -> Bool {
  let prefix = path.replace_all(old="\\", new="/")
  path.contains_char('\\') ||
  prefix.has_prefix("//?/") ||
  prefix.has_prefix("//./") ||
  (path.length() >= 2 && path[0] is ('a'..<='z' | 'A'..<='Z') && path[1] == ':')
}

///|
fn Converter::input_options(
  self : Converter,
  path : String,
) -> (@lib.InputSyntax, Bool) {
  let drive_relative = path.length() >= 2 &&
    path[0] is ('a'..<='z' | 'A'..<='Z') &&
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
  (from, absolute)
}

///|
pub fn Converter::convert(
  self : Converter,
  path : String,
) -> String raise CliError {
  self.convert_as(path, self.to)
}

///|
// When mixed output needs a byte-level conversion, preserve native spelling
// through encoding. A Cygwin terminal name already contains forward slashes.
fn Converter::operand_format(self : Converter) -> @lib.OutputFormat {
  if self.to == Mixed &&
    (self.name_form != Ordinary || self.codepage() != 65001) {
    Windows
  } else {
    self.to
  }
}

///|
fn Converter::convert_as(
  self : Converter,
  path : String,
  to : @lib.OutputFormat,
) -> String raise CliError {
  if path.is_empty() {
    raise Conversion(@lib.EmptyPath)
  }
  let (from, absolute) = self.input_options(path)
  try {
    if self.list {
      self.context.convert_list(
        path,
        from~,
        to~,
        absolute~,
        recognize_windows=self.from is None,
        unix_prefix=if self.to == Posix { self.unix_prefix } else { Configured },
      )
    } else {
      self.context.convert(
        if from == Windows && to == Posix {
          wide_name_path(path)
        } else {
          path
        },
        from~,
        to~,
        absolute~,
        unix_prefix=if self.to == Posix { self.unix_prefix } else { Configured },
      )
    }
  } catch {
    error => raise self.operand_error(path, error)
  }
}

///|
fn Converter::operand_error(
  self : Converter,
  path : String,
  cause : @lib.ConversionError,
) -> CliError {
  match operand_errno(cause) {
    None => Conversion(cause)
    Some(_) if self.list => ListConversion(path, cause)
    Some(reason) => PathErrno(path, reason)
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
pub async fn Converter::convert_file_record(
  self : Converter,
  record : String,
) -> RecordAction {
  self.file_record(record, None)
}

///|
pub async fn Converter::convert_file_bytes(
  self : Converter,
  record : Bytes,
  source~ : String,
  line~ : Int32,
) -> RecordAction {
  let spelling = @filename.decode(record)
  if spelling.contains_char('\u0000') &&
    @filename.contains_unpaired_surrogate(record) {
    raise InvalidFileEncoding(source~, line~)
  }
  self.file_record(
    spelling,
    if spelling.contains_char('\u0000') {
      Some(InvalidFileEncoding(source~, line~))
    } else {
      None
    },
  )
}

///|
async fn Converter::file_record(
  self : Converter,
  record : String,
  invalid : CliError?,
) -> RecordAction {
  if self.file_options && record.has_prefix("-") {
    let args = file_option_arguments(record)
    if invalid is Some(error) && args[0].contains_char('\u0000') {
      raise error
    }
    match parse_record_args(args) {
      Help => return Stop(help_text())
      Version => return Stop(version_text())
      ExitSuccess => return Stop("")
      Convert(request) => {
        self.mode = request.mode
        self.from = request.from
        self.to = request.to
        self.absolute = request.absolute
        self.list = request.list
        self.unix_prefix = request.unix_prefix
        self.root_local = request.root_local
        self.name_form = request.name_form
        self.ignore = request.ignore
        self.codepage = request.codepage
        self.output_error = request.output_error
        match request.input() {
          Folder(folder) => return QueryFolder(folder)
          Names([]) => return Skip
          Names([path]) => return self.convert_name(path, invalid)
          _ => raise InvalidOptions("expected one path in an option record")
        }
      }
    }
  }
  self.convert_name(record, invalid)
}

///|
pub async fn Converter::convert_operand(
  self : Converter,
  path : String,
) -> RecordAction {
  self.convert_name(path, None)
}

///|
async fn Converter::convert_name(
  self : Converter,
  original : String,
  invalid : CliError?,
) -> RecordAction {
  if self.mode {
    return QueryMode(original)
  }
  let path = if self.to == Posix && invalid is Some(error) {
    guard @filename.wide_name(original) is Some(wide) else { raise error }
    wide
  } else {
    original
  }
  if path.is_empty() && self.ignore {
    return Skip
  }
  if self.output_error is Some(reason) {
    raise UnsupportedCapability(reason)
  }
  let (from, absolute) = self.input_options(path)
  if self.to == Posix && from == Windows && !path.is_empty() {
    let name = if self.list { path } else { wide_name_path(path) }
    return OutputBytes(
      self.context.windows_to_posix_bytes(
        name,
        absolute~,
        unix_prefix=self.unix_prefix,
        list=self.list,
      ) catch {
        error => raise self.operand_error(original, error)
      },
    )
  }
  let network_parent = path.contains("//") && path.contains("/..")
  let host_lookup = self.lookup is Some(_) && (self.installed || network_parent)
  let server_lookup = self.server_lookup is Some(_) &&
    (absolute || network_parent)
  if (!host_lookup && !server_lookup && invalid is None) ||
    self.to == Posix ||
    path.is_empty() {
    return Output(self.convert_as(path, self.operand_format()))
  }
  let entries = if self.list {
    path
    .split(if from == Windows { ";" } else { ":" })
    .map(s => s.to_owned())
    .to_array()
  } else {
    [path]
  }
  let output : Array[String] = []
  for index, entry in entries {
    if self.list && from == Windows && entry.is_empty() {
      output.push("")
      continue
    }
    let value = if entry.is_empty() { "." } else { entry }
    let syntax : @lib.InputSyntax = if self.list &&
      self.from is None &&
      value.contains_char('\\') {
      Windows
    } else {
      from
    }
    let full = absolute ||
      (
        self.list &&
        self.from is None &&
        syntax == Windows &&
        value.has_prefix("\\") &&
        !value.has_prefix("\\\\")
      )
    async fn convert_entry(context : @lib.Context) -> Result[String, String] {
      match self.lookup {
        Some(resolve) if self.installed ||
          (
            syntax == Posix &&
            value.has_prefix("//") &&
            !value.has_prefix("///") &&
            value.split("/").any(part => part == "..")
          ) => resolve(context, value, syntax, full)
        _ =>
          Ok(
            context.convert(
              if invalid is Some(_) {
                @lib.PathInput::Narrow(@filename.encode(value))
              } else {
                Text(value)
              },
              from=syntax,
              to=self.operand_format(),
              absolute=full,
            ),
          )
      }
    }
    let result = try {
      for context = self.context {
        try convert_entry(context) catch {
          @lib.NetworkServerLookup(server) if self.server_lookup
            is Some(resolve) =>
            continue context.with_network_server(
                server,
                present=resolve(server),
              )
          err => raise err
        } noraise {
          result => break result
        }
      }
    } catch {
      @lib.ConversionError::_ as cause =>
        raise self.operand_error(
          path,
          if self.list {
            @lib.ListEntryError(index~, cause)
          } else {
            cause
          },
        )
      err => raise err
    }
    match result {
      Err(reason) =>
        raise PathErrno(
          path,
          if self.list {
            "Unknown error -1"
          } else {
            reason
          },
        )
      Ok(native) =>
        output.push(
          if self.operand_format() == Mixed {
            native.replace_all(old="\\", new="/")
          } else {
            native
          },
        )
    }
  }
  Output(output.join(";"))
}
