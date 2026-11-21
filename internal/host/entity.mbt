///|
priv suberror LookupErrno {
  LookupErrno(String)
}

///|
priv enum NativeEntity {
  Found(@fs.FileKind?)
  Follow(String, String)
}

///|
#derive(Eq)
priv enum LookupPurpose {
  WindowsOutput
  LongAbsolute
  FileInput
}

///|
fn plain_native(path : String) -> String {
  let path = path.replace_all(old="\\", new="/")
  if path.has_prefix("//?/UNC/") {
    "//" + path[8:].to_owned()
  } else if path.has_prefix("//?/") {
    path[4:].to_owned()
  } else {
    path
  }
}

///|
/// The Windows host passes paths straight to the Win32 file APIs. Use the
/// extended spelling for long, already-qualified names (including UNC).
fn host_io_path(path : String) -> String {
  if !(@async.platform is Windows) || path.length() < 248 {
    return path
  }
  let win = path.replace_all(old="/", new="\\")
  if win.has_prefix("\\\\?\\") || win.has_prefix("\\\\.\\") {
    return win
  }
  if win.split("\\").any(part => part is ("." | "..")) {
    return path
  }
  if win.has_prefix("\\\\") {
    "\\\\?\\UNC\\" + win[2:].to_owned()
  } else if win[0] is ('a'..<='z' | 'A'..<='Z') && win[1:3] == ":\\" {
    "\\\\?\\" + win
  } else {
    path
  }
}

///|
pub async fn nt_null_presence() -> Bool? {
  guard @async.platform is Windows else { return None }
  probe_device(@lib.nt_null_path)
}

///|
/// A successful address lookup confirms an ordinary Cygwin network directory.
/// moonrun's AI_ADDRCONFIG can filter out a family accepted by Cygwin.
pub async fn network_server_exists(server : String) -> Bool {
  guard @async.platform is Windows else {
    raise NameLookupUnavailable("network server lookup requires a Windows host")
  }
  guard !(server is ("tsclient" | "wsl$")) else {
    raise NameLookupUnavailable(
      "Windows network provider lookup required for " + @debug.to_string(server),
    )
  }
  let host = @filename.native_name(server).split("@").next().unwrap()
  try {
    // Addr::resolve parses IP literals itself and accepts some spellings
    // beyond the documented Winsock numeric-address forms.
    try @socket.IpAddr(host) catch {
      @socket.InvalidAddr => ignore(@socket.Addr::resolve(host, port=0))
      err => raise err
    } noraise {
      ip => {
        let canonical = ip.to_string().trim(chars="[]")
        guard !host.contains_char('%') &&
          canonical.equal_ignore_ascii_case(host) else {
          raise NameLookupUnavailable(
            "Windows numeric address lookup required for " +
            @debug.to_string(server),
          )
        }
      }
    }
    true
  } catch {
    @socket.ResolveHostnameError(_) =>
      raise NameLookupUnavailable(
        "Windows host resolver could not confirm " + @debug.to_string(server),
      )
    @os_error.OsError(_, ..) =>
      raise NameLookupUnavailable(
        "cannot query Windows host resolver for " + @debug.to_string(server),
      )
    err => raise err
  }
}

///|
async fn probe_device(path : String) -> Bool? {
  try @fs.kind(host_io_path(path)) catch {
    @os_error.OsError(NotFound, ..) => return Some(false)
    @os_error.OsError(_, ..) => return None
    err => raise err
  } noraise {
    CharDevice => Some(true)
    _ => None
  }
}

///|
fn native_root_end(path : String) -> Int32 {
  if path.has_prefix("//") {
    let start = path[2:]
    guard start.find("/") is Some(server_end) else { return path.length() }
    let share = server_end + 3
    return match path[share:].find("/") {
      Some(end) => share + end
      None => path.length()
    }
  }
  if path.length() >= 3 && path[1] == ':' && path[2] == '/' {
    3
  } else {
    1
  }
}

///|
async fn native_kind(path : String) -> @fs.FileKind? {
  if !(@async.platform is Windows) && path.has_prefix("//") {
    raise NameLookupUnavailable("network share lookup requires a Windows host")
  }
  Some(@fs.kind(host_io_path(path), follow_symlink=false)) catch {
    @os_error.OsError(NotFound, ..) => None
    @os_error.OsError(NotDirectory, ..) => raise LookupErrno("Not a directory")
    @os_error.OsError(AccessDenied, ..) =>
      raise LookupErrno("Permission denied")
    _ =>
      raise InstallationError("cannot inspect path: " + @debug.to_string(path))
  }
}

///|
fn shortcut_word(bytes : BytesView, offset : Int32) -> Int32 {
  bytes[offset].to_int() | (bytes[offset + 1].to_int() << 8)
}

///|
async fn possible_cygwin_link(
  path : String,
  file : @fs.File,
  appended : Bool,
) -> Bool {
  let reader = file.at(0)
  let prefix = reader.peek_exactly(9)
  // A suffix found only by adding .lnk must be a Cygwin shortcut.
  // System-file cookies are considered only for an actual operand name.
  if !appended && prefix.has_prefix(b"IntxLNK\x01") {
    // The Interix target starts at offset 8 and contains little-endian words.
    let start = reader.peek_exactly(10)
    return shortcut_word(start, 8) != 0
  }
  if !appended && prefix == b"!<symlink" {
    let first = reader.peek_exactly(11)
    guard first.has_prefix(b"!<symlink>") && first[10] != 0 else {
      return false
    }
    let size = file.size()
    if first[10] == 0xff && size >= 12 && reader.peek_exactly(12)[11] == 0xfe {
      return shortcut_word(reader.peek_exactly(14), 12) != 0
    }
    // The legacy narrow target, including its terminator, fits in PATH_MAX.
    return size - 10 <= 4096
  }
  guard prefix.has_prefix(b"L\x00\x00\x00") &&
    path.to_lower().has_suffix(".lnk") else {
    return false
  }
  let header = reader.peek_exactly(76)
  guard header[4:20] ==
    b"\x01\x14\x02\x00\x00\x00\x00\x00\xc0\x00\x00\x00\x00\x00\x00F" &&
    header[20] is (0x0c | 0x0d) &&
    header[21:24] == b"\x00\x00\x00" &&
    header[60:64] == b"\x01\x00\x00\x00" else {
    return false
  }
  let has_id_list = header[20] == 0x0d
  let size = file.size()
  guard size > 76 && size <= 262144 else { return false }
  let data = reader.peek_exactly(size.to_int())[76:]
  guard data.length() >= 2 else { return false }
  let desc = if has_id_list { 2 + shortcut_word(data, 0) } else { 0 }
  guard desc + 2 <= data.length() else { return false }
  let length = shortcut_word(data, desc)
  guard length > 0 && desc + 2 + length <= data.length() else { return false }
  // Windows GENERIC_WRITE succeeds only for a writable regular file.
  // A denied open can also result from an ACL or a sharing restriction.
  !(@async.platform is Windows &&
  (@fs.can_write(host_io_path(path)) catch {
    @os_error.OsError(_, ..) => false
    err => raise err
  }))
}

///|
async fn check_link_header(
  path : String,
  file : @fs.File,
  appended~ : Bool = false,
) -> Unit {
  let possible = possible_cygwin_link(path, file, appended) catch {
    @io.UnexpectedEof => false
    @io.ReaderError::_ | @os_error.OsError(_, ..) =>
      raise InstallationError(
        "cannot check Cygwin link attributes: " + @debug.to_string(path),
      )
    err => raise err
  }
  if possible {
    raise InstallationError(
      "Cygwin link attributes unavailable: " + @debug.to_string(path),
    )
  }
}

///|
async fn check_cygwin_link(path : String, appended~ : Bool = false) -> Unit {
  let file = @fs.open(host_io_path(path), mode=ReadOnly) catch {
    @os_error.OsError(AccessDenied, ..) => return
    _ =>
      raise InstallationError(
        "cannot check Cygwin link attributes: " + @debug.to_string(path),
      )
  }
  defer file.close()
  check_link_header(path, file, appended~)
}

///|
async fn native_link(path : String, tail : String) -> NativeEntity {
  let target = @fs.realpath(host_io_path(path)) catch {
    _ =>
      raise InstallationError(
        "cannot resolve native link: " + @debug.to_string(path),
      )
  }
  Follow(plain_native(target), tail)
}

///|
// Called only when the exact entry is absent. The suffix scanner measures
// the basename in bytes and allows a single four-byte executable suffix.
async fn executable_candidate(exe : String, name : String) -> @fs.FileKind? {
  let extension = name.rev_split_once(".").map(p => p.1).unwrap_or("")
  if name.is_empty() ||
    name is ("." | "..") ||
    extension.equal_ignore_ascii_case("exe") ||
    extension.equal_ignore_ascii_case("lnk") {
    return None
  }
  match native_kind(exe) {
    Some(Regular) => Some(Regular)
    Some(SymLink) =>
      if (@fs.kind(host_io_path(exe)) catch {
          _ =>
            raise InstallationError(
              "cannot determine executable link type: " + @debug.to_string(exe),
            )
        }) ==
        Directory {
        None
      } else {
        Some(SymLink)
      }
    _ => None
  }
}

///|
fn needs_directory(path : String) -> Bool {
  path is ("." | "..") ||
  path.has_suffix("/") ||
  path.has_suffix("/.") ||
  path.has_suffix("/..")
}

///|
/// cygwin_conv_path tests the complete name first. It visits parents only
/// when the leaf is missing. Only the final component gets the .exe probe.
async fn windows_entity(
  native : String,
  need_directory : Bool,
  purpose : LookupPurpose,
  mapped? : @lib.NativePath,
) -> (NativeEntity, String) {
  let path = plain_native(native)
  let root = native_root_end(path)
  let end = path.trim_end(chars="/").length().max(root)
  for length = end, parents = 0 {
    let current = path[:length].to_owned()
    let leaf = length == end
    let name = current
      .rev_split_once("/")
      .map(p => p.1.to_owned())
      .unwrap_or(current)
    let size = match mapped {
      Some(entry) => entry.basename_bytes(parents~).unwrap_or(0)
      None => @utf8.encode(name).length()
    }
    fn with_suffix(suffix : String) -> String raise {
      match mapped {
        Some(entry) => entry.windows_name(parents~, suffix~)
        None => current + suffix
      }
    }
    if size > 255 {
      raise LookupErrno("File name too long")
    }
    let mut kind = native_kind(current)
    let mut suffix = ""
    if kind is None && length > root && size <= 251 {
      if leaf && purpose != LongAbsolute {
        kind = executable_candidate(with_suffix(".exe"), name)
        if kind is Some(_) {
          suffix = ".exe"
        }
      }
      if kind is None {
        let lnk = with_suffix(".lnk")
        if native_kind(lnk) is Some(Regular) {
          check_cygwin_link(lnk, appended=true)
        }
      }
    }
    match kind {
      Some(SymLink) => {
        if leaf && !need_directory && purpose == WindowsOutput {
          return (Found(kind), suffix)
        }
        let tail = path[length:end].trim_start(chars="/").to_owned()
        return (
          native_link(
            if suffix.is_empty() {
              current
            } else {
              with_suffix(suffix)
            },
            tail,
          ),
          "",
        )
      }
      Some(Regular) => {
        // Input checks the opened file's header, preserving open-time errno.
        if purpose != FileInput || !leaf || need_directory {
          check_cygwin_link(
            if suffix.is_empty() {
              current
            } else {
              with_suffix(suffix)
            },
          )
        }
        if !leaf || need_directory {
          raise LookupErrno("Not a directory")
        }
        return (Found(kind), suffix)
      }
      Some(Directory) => return (Found(if leaf { kind } else { None }), "")
      Some(_) =>
        raise InstallationError(
          "unsupported path type: " + @debug.to_string(current),
        )
      None if length <= root => return (Found(None), "")
      None =>
        continue current.rev_find("/").unwrap_or(root).max(root), parents + 1
    }
  }
}

///|
async fn mapped_windows_entity(
  entry : @lib.NativePath,
  directory : Bool,
  purpose : LookupPurpose,
) -> (NativeEntity, String) {
  windows_entity(entry.windows_name(), directory, purpose, mapped=entry)
}

///|
async fn native_entity(native : String) -> NativeEntity {
  let path = plain_native(native)
  let parts = path
    .split("/")
    .filter(part => !part.is_empty())
    .map(part => part.to_owned())
    .to_array()
  let (root, start) = if path.has_prefix("//") && parts.length() >= 2 {
    ("//" + parts[0] + "/" + parts[1] + "/", 2)
  } else if parts.get(0) is Some(drive) && drive.has_suffix(":") {
    (drive + "/", 1)
  } else {
    ("/", 0)
  }
  let mut current = root
  let mut kind = native_kind(current)
  for index in start..<parts.length() {
    if kind is Some(previous) && previous != Directory {
      raise LookupErrno("Not a directory")
    }
    current = current.trim_end(chars="/").to_owned() + "/" + parts[index]
    if kind is None {
      continue
    }
    kind = native_kind(current)
    if kind is None {
      if native_kind(current + ".lnk") is Some(Regular) {
        check_cygwin_link(current + ".lnk", appended=true)
      }
      continue
    }
    if kind is Some(SymLink) {
      return native_link(current, parts[index + 1:].join("/"))
    }
    if kind is Some(Regular) {
      check_cygwin_link(current)
    } else if kind != Some(Directory) {
      raise InstallationError(
        "unsupported path type: " + @debug.to_string(current),
      )
    }
  }
  Found(kind)
}

///|
fn input_name(path : String) -> @lib.PathInput {
  if path.contains_char('\u0000') {
    Narrow(@filename.encode(path))
  } else {
    Text(path)
  }
}

///|
fn is_posix_root(
  context : @lib.Context,
  path : String,
) -> Bool raise @lib.ConversionError {
  if path.has_prefix("//") && !path.has_prefix("///") {
    return false
  }
  let result = context.convert(
    input_name(path),
    from=Posix,
    to=Posix,
    absolute=true,
  ) catch {
    @lib.UnrepresentablePath(reason="POSIX filename is not valid UTF-8", ..) =>
      return false
    err => raise err
  }
  result == "/"
}

///|
fn lookup_target(
  context : @lib.Context,
  path : String,
  from : @lib.InputSyntax,
) -> @lib.PathTarget[@lib.NativePath] raise {
  context.lookup_target(input_name(path), from~) catch {
    @lib.InvalidDrivePrefix | @lib.EmptyPath | @lib.PathNotFound =>
      raise LookupErrno("No such file or directory")
    @lib.PathTooLong(_) => raise LookupErrno("File name too long")
    @lib.NotDirectory => raise LookupErrno("Not a directory")
    @lib.NoSuchDeviceOrAddress => raise LookupErrno("No such device or address")
    @lib.MissingContext(field="nt_null") =>
      raise NameLookupUnavailable(
        "the Windows NT null device could not be observed",
      )
    @lib.TooManyLinks => raise LookupErrno("Too many levels of symbolic links")
    err => raise InstallationError(@debug.to_string(err))
  }
}

///|
fn link_operand(
  context : @lib.Context,
  target : String,
  tail : String,
  followed : Int32,
) -> String raise {
  if followed == 10 {
    raise LookupErrno("Too many levels of symbolic links")
  }
  let path = @filename.decode(
    context.windows_to_posix_bytes(target) catch {
      err =>
        raise InstallationError(
          "cannot map native link target: " + @debug.to_string(err),
        )
    },
  )
  if tail.is_empty() {
    path
  } else {
    path.trim_end(chars="/").to_owned() + "/" + tail
  }
}

///|
async fn locate_entity(
  context : @lib.Context,
  path : String,
  from : @lib.InputSyntax,
  inspect : async (String) -> NativeEntity,
  server_lookup? : async (String) -> Bool,
) -> (Bool?, Bool, String) {
  let mut path = path
  let mut syntax = from
  for followed = 0; ; followed = followed + 1 {
    let (native, text_mode) = match lookup_target(context, path, syntax) {
      Virtual(directory~) => return (Some(directory), false, path)
      NetworkDirectory(None) => return (Some(true), false, path)
      NetworkDirectory(Some(server)) => {
        let exists = server_lookup is Some(resolve) && resolve(server)
        return (if exists { Some(true) } else { None }, false, path)
      }
      NullDevice(..) => return (Some(false), false, path)
      Filesystem(native, text_mode~) => {
        if native.basename_bytes().unwrap_or(0) > 255 {
          raise LookupErrno("File name too long")
        }
        (native.windows_name(), text_mode)
      }
    }
    match inspect(native) {
      Found(kind) => return (kind.map(k => k == Directory), text_mode, path)
      Follow(target, tail) => {
        path = link_operand(context, target, tail, followed)
        syntax = Posix
      }
    }
  }
}

///|
/// POSIX validates a named directory before cancelling it with '..'.
/// Consecutive or leading '..' components ascend an already established path.
async fn checked_parents(
  context : @lib.Context,
  operand : String,
  inspect : async (String) -> NativeEntity,
  server_lookup~ : async (String) -> Bool = network_server_exists,
) -> String {
  if !operand.split("/").any(part => part == "..") {
    return operand
  }
  let network = operand.has_prefix("//") && !operand.has_prefix("///")
  let mut prefix = if network {
    "//"
  } else if operand.has_prefix("/") {
    "/"
  } else {
    "."
  }
  let mut check_parent = false
  for part in operand.split("/") {
    match part {
      "" | "." => continue
      ".." => {
        if check_parent {
          let (kind, _, resolved) = locate_entity(
            context,
            prefix,
            Posix,
            inspect,
            server_lookup~,
          ) catch {
            LookupErrno("No such device or address" | "File name too long") =>
              raise LookupErrno("No such file or directory")
            err => raise err
          }
          match kind {
            Some(true) => prefix = resolved
            None => raise LookupErrno("No such file or directory")
            _ => raise LookupErrno("Not a directory")
          }
        }
        check_parent = false
        if prefix.has_prefix("//") && !prefix.has_prefix("///") {
          let stem = prefix.trim_end(chars="/")
          prefix = match stem.rev_find("/") {
            Some(i) if i > 1 => stem[:i].to_owned()
            _ => "//"
          }
          continue
        }
      }
      _ => check_parent = true
    }
    prefix = if prefix == "//" {
      prefix + part.to_owned()
    } else {
      prefix.trim_end(chars="/").to_owned() + "/" + part.to_owned()
    }
  }
  if !prefix.has_suffix("/") &&
    (
      operand.has_suffix("/") ||
      operand.has_suffix("/.") ||
      (network && operand.has_suffix("/.."))
    ) {
    prefix + "/"
  } else {
    prefix
  }
}

///|
/// Resolve a Windows-output operand using the supplied mount context and
/// host filesystem. An absolute network operand needs no local root mapping.
pub async fn convert_installed(
  context : @lib.Context,
  path : String,
  from : @lib.InputSyntax,
  absolute : Bool,
) -> Result[String, String] {
  checked_windows_path(
    context, path, from, absolute, native_entity, mapped_windows_entity,
  )
}

///|
pub let local_windows_lookup : (async (String, Bool) -> Result[String, String]?)? = if @async.platform
  is Windows {
  Some(local_windows_output)
} else {
  None
}

///|
/// Resolve native operands that can be anchored without an installation.
/// A followed link can re-enter POSIX mount lookup through its target.
async fn local_windows_output(
  path : String,
  absolute : Bool,
) -> Result[String, String]? {
  guard local_windows_context(path) is Some(context) else { return None }
  Some(
    checked_windows_path(context, path, Windows, absolute, native_entity, (
      native,
      directory,
      purpose,
    ) => {
      let (entity, suffix) = mapped_windows_entity(native, directory, purpose)
      if entity is Follow(_, _) {
        raise InstallationError(
          "a selected Cygwin installation is required for a link target",
        )
      }
      (entity, suffix)
    }),
  )
}

///|
async fn checked_windows_path(
  context : @lib.Context,
  path : String,
  from : @lib.InputSyntax,
  absolute : Bool,
  inspect : async (String) -> NativeEntity,
  lookup : async (@lib.NativePath, Bool, LookupPurpose) -> (
    NativeEntity,
    String,
  ),
) -> Result[String, String] {
  try {
    async fn checked_operand() -> String {
      if from == Posix {
        checked_parents(context, path, inspect)
      } else {
        path
      }
    }
    let checked = checked_operand()
    let operand = if from == Windows {
      path.replace_all(old="\\", new="/")
    } else {
      path
    }
    let directory = needs_directory(operand) &&
      !(from == Posix && is_posix_root(context, checked))
    for source = checked, syntax = from, followed = 0, purpose = WindowsOutput {
      let full_output = absolute || purpose == LongAbsolute
      let native = match
        context.lookup_target(input_name(source), from=syntax) {
        Filesystem(name, ..) => name
        Virtual(..) | NetworkDirectory(_) | NullDevice(..) => {
          if followed == 0 {
            return Ok(
              context.convert(
                input_name(source),
                from=syntax,
                to=Windows,
                absolute=full_output,
              ),
            )
          }
          let name = context.convert(
            input_name(source),
            from=syntax,
            to=Windows,
            absolute=true,
          )
          return Ok(
            if directory && !full_output && !name.has_suffix("\\") {
              name + "\\"
            } else {
              name
            },
          )
        }
      }
      let (entity, suffix) = lookup(native, directory, purpose)
      match entity {
        Follow(target, tail) => {
          let next = link_operand(context, target, tail, followed)
          continue next, Posix, followed + 1, purpose
        }
        Found(kind) => {
          let keep_separator = directory && (!full_output || kind is None)
          let plain = plain_native(native.windows_name(suffix~))
          let end = plain
            .trim_end(chars="/")
            .length()
            .max(native_root_end(plain))
          let full = plain[:end].to_owned()
          let selected = if keep_separator && !full.has_suffix("/") {
            full + "/"
          } else {
            full
          }
          let result = context.convert(selected, from=Windows, to=Windows)
          if followed > 0 || full_output {
            return Ok(result)
          }
          let drive = from == Windows &&
            operand.length() >= 2 &&
            operand[1] == ':'
          if from == Windows &&
            (
              (drive && !operand[2:].has_prefix("/")) ||
              (operand.has_prefix("/") && !operand.has_prefix("//"))
            ) {
            let direct = context.convert(
              input_name(path),
              from=Windows,
              to=Windows,
            )
            let bare = direct.trim_end(chars="\\").to_owned() + suffix
            return Ok(
              if keep_separator || bare.is_empty() {
                bare + "\\"
              } else {
                bare
              },
            )
          }
          if operand.has_prefix("/") || drive {
            return Ok(result)
          }
          if context.relative_windows_name(
              input_name(source),
              from=syntax,
              suffix~,
            )
            is Some(stem) {
            let relative = stem +
              (if keep_separator && path != "." { "\\" } else { "" })
            if relative.length() < 260 {
              return Ok(relative)
            }
            // The wide conversion retries the original operand without the
            // executable suffix list and follows the final reparse point.
            continue checked_operand(), from, 0, LongAbsolute
          }
          return Ok(result)
        }
      }
    }
  } catch {
    LookupErrno(reason) => Err(reason)
    err => raise err
  }
}
