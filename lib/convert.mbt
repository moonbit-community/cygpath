///|
/// The Windows-output conversion checks component length. Windows-to-POSIX
/// conversion remains lexical and accepts longer components, including the
/// records produced by cygpath's fixed-size file-input buffer.
fn validate_component_lengths(path : String) -> Unit raise ConversionError {
  let text = path.replace_all(old="\\", new="/")
  for component in text.split("/") {
    if component.length() > 255 &&
      @filename.native_name(component.to_owned()).length() > 255 {
      raise PathTooLong(path)
    }
  }
}

///|
fn validate_options(
  to : OutputFormat,
  prefix : UnixPrefix,
) -> Unit raise ConversionError {
  if prefix == ProcCygdrive && to != Posix {
    raise InvalidOptions("ProcCygdrive requires POSIX output")
  }
}

///|
fn network_lookup_path(
  parts : Array[String],
  tail : StringView,
) -> ParsedPath? raise ConversionError {
  let path = normalize_network(
    parts,
    tail.split("/").map(part => part.to_owned()),
    trailing=tail.has_suffix("/"),
  )
  if path.root is Unc(_, _) {
    Some(path)
  } else {
    None
  }
}

///|
// Windows normalizes the entire network name before looking for a mount.
// Without a matching mount Cygwin returns its original slashified spelling.
fn Context::windows_to_posix(
  self : Context,
  input : String,
  absolute : Bool,
  prefix : UnixPrefix,
  single~ : Bool,
) -> String raise ConversionError {
  validate_text(input)
  // The single-name wide API checks for a drive colon after the prefix.
  // Otherwise it replaces the third UTF-16 unit with a backslash, as for
  // UNC\server. The prefix added by the CLI can also contain a relative name.
  let path = if single && input.has_prefix("\\\\?\\") {
    if input.length() > 5 && input[5] == ':' {
      decode_windows_filename(input, start=4)
    } else if input.length() >= 7 {
      decode_windows_filename(input, start=7, rooted=true)
    } else {
      raise UnsupportedNamespace("incomplete extended path")
    }
  } else {
    decode_windows_filename(input)
  }
  let text = path.replace_all(old="\\", new="/")
  let extended = text.has_prefix("//?/") || text.has_prefix("/??/")
  let extended_unc = extended && text[4:].has_prefix("UNC/")
  if extended &&
    !extended_unc &&
    !(text.length() >= 6 &&
    text[4] is ('a'..<='z' | 'A'..<='Z') &&
    text[5] == ':' &&
    (text.length() == 6 || text[6] == '/')) {
    raise InvalidWindowsPrefix
  }
  let resolved = if extended_unc ||
    (!extended && text.has_prefix("//") && !text.has_prefix("///")) {
    let start = if extended { 8 } else { 2 }
    if !extended && text.has_prefix("//./") {
      return text
    }
    guard network_lookup_path([], text[start:]) is Some(network) else {
      return text
    }
    network
  } else {
    // Three or more leading separators collapse to the last one. A forward
    // slash there has no drive. A backslash uses the current drive.
    let start = if text.has_prefix("///") {
      text.length() - text.trim_start(chars="/").length() - 1
    } else {
      0
    }
    if !extended && path.get_char(start) == Some('/') {
      return text
    }
    let original = parse_validated_path(path[start:].to_owned(), Windows)
    if original.root == Relative && !absolute {
      return text
    }
    if original.root == Relative &&
      self.windows_cwd is Some({ root: Unc(server, share), components, .. }) {
      let base = [server, share]
      base.append(components)
      guard network_lookup_path(base, text[:]) is Some(network) else {
        return text
      }
      network
    } else {
      self.resolve(original, Windows, Posix, absolute)
    }
  }
  let terminal_dot = text is ("." | "..") ||
    text.has_suffix("/.") ||
    text.has_suffix("/..")
  let mapped = self.to_posix(resolved, prefix, terminal_dot~)
  if mapped.root is Unc(_, _) {
    text
  } else if self.profile == Cygwin &&
    mapped.root == PosixRoot &&
    mapped.components.is_empty() &&
    mapped.trailing {
    "//"
  } else {
    mapped.render(Posix)
  }
}

///|
fn filename_text(
  spelling : String,
  original : String,
) -> String raise ConversionError {
  if spelling.contains_char('\u0000') {
    raise UnrepresentablePath(
      component=original,
      reason="POSIX filename is not valid UTF-8",
    )
  }
  spelling
}

///|
/// Returns the POSIX filename bytes in the C.UTF-8 locale. Byte-valued
/// Windows filename escapes may produce output outside UTF-8.
pub fn Context::windows_to_posix_bytes(
  self : Context,
  path : String,
  absolute~ : Bool = false,
  unix_prefix~ : UnixPrefix = Configured,
  list~ : Bool = false,
) -> Bytes raise ConversionError {
  let spelling = if list {
    self.windows_posix_list(path, absolute, unix_prefix, allow_bytes=true)
  } else {
    self.windows_to_posix(path, absolute, unix_prefix, single=true)
  }
  @filename.encode(spelling)
}

///|
/// Converts one nonempty path using explicit source grammar and context.
/// Absolute paths are normalized lexically; no file-system resolution occurs.
pub fn[P : ToPathInput] Context::convert(
  self : Context,
  operand : P,
  from~ : InputSyntax,
  to~ : OutputFormat,
  absolute~ : Bool = false,
  unix_prefix~ : UnixPrefix = Configured,
) -> String raise ConversionError {
  validate_options(to, unix_prefix)
  let path = operand.to_path_input().spelling()
  if from == Windows && to == Posix {
    guard @filename.wide_name(path) is Some(wide) else {
      raise UnrepresentablePath(
        component=@filename.native_name(path),
        reason="invalid multibyte Windows input",
      )
    }
    return filename_text(
      self.windows_to_posix(wide, absolute, unix_prefix, single=true),
      path,
    )
  }
  if to != Posix {
    validate_component_lengths(path)
  }
  let original = parse_validated_path(path, from)
  let parsed = self.resolve(original, from, to, absolute)
  if parsed.root is NetworkServer(server) &&
    absolute &&
    to != Posix &&
    parsed.trailing {
    guard self.network_servers.get(server) is Some(present) else {
      raise NetworkServerLookup(server)
    }
    return { ..parsed, trailing: !present, }.render(to)
  }
  if from == Posix &&
    parsed.root == PosixRoot &&
    virtual_node(parsed.components) is Some(_) {
    let spelling = self.virtual_spelling(
      parsed,
      path,
      relative=original.root == Relative,
      absolute~,
      to~,
    )
    return if to == Posix {
      filename_text(spelling, path)
    } else {
      @filename.native_name(spelling)
    }
  }
  let output = if to == Posix {
    if parsed.root is Unc(_, _) {
      self.to_posix(parsed, unix_prefix)
    } else {
      validate_posix_namespace(parsed)
      parsed
    }
  } else if from == Posix {
    let mapped = self.map_posix_mount(parsed).0
    if self.is_drive_directory(parsed) {
      let directory_suffix = original.trailing ||
        original.components.last() is Some("." | "..")
      { ..mapped, trailing: !absolute && directory_suffix, }
    } else if absolute &&
      self.profile == Msys2 &&
      parsed.root == PosixRoot &&
      parsed.components.is_empty() {
      { ..mapped, trailing: false, }
    } else {
      mapped
    }
  } else {
    parsed
  }
  let rendered = output.render(to)
  if to != Posix &&
    !absolute &&
    output.root is (Relative | DriveRelative(_)) &&
    rendered.length() >= 260 {
    return self.convert(operand, from~, to~, absolute=true, unix_prefix~)
  }
  if to == Posix {
    filename_text(rendered, path)
  } else {
    rendered
  }
}
