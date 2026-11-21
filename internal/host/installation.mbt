///|
priv struct InstallMount {
  path : String
  mount : @lib.Mount
  source : String
  flags : @hashset.HashSet[String]
}

///|
async fn installed_filename(
  context : @lib.Context,
  path : String,
  inspect~ : async (@lib.NativePath) -> NativeEntity = mapped_native_entity,
  lookup~ : async (@lib.NativePath, Bool) -> (NativeEntity, String) = (
    native,
    directory,
  ) => mapped_windows_entity(native, directory, FileInput),
) -> String? {
  let windows = path.contains_char('\\') || absolute_drive_name(path)
  let directory = needs_directory(
    if windows {
      path.replace_all(old="\\", new="/")
    } else {
      path
    },
  )
  let from : @lib.InputSyntax = if windows { Windows } else { Posix }
  try {
    let checked = if windows {
      if mixed_input_parents(path) is Some(prefix) {
        ignore(checked_parents(context, prefix, inspect))
      }
      path
    } else {
      checked_parents(context, path, inspect)
    }
    for operand = checked, syntax = from, links = 0 {
      match lookup_target(context, operand, syntax) {
        Virtual(directory=true) => return None
        // The network directory's read-only open uses the NT null object,
        // including when an individual server name did not resolve.
        NetworkDirectory(_) | NullDevice(native_input=true) =>
          return Some(@lib.nt_null_path)
        Virtual(directory=false) | NullDevice(native_input=false) =>
          raise InstallationError(
            "reading a Cygwin virtual path requires its runtime",
          )
        Filesystem(native, ..) => {
          let (entry, suffix) = lookup(native, directory)
          match entry {
            Found(_) => return Some(native.windows_name(suffix~))
            Follow(target, tail) =>
              continue link_operand(context, target, tail, links),
                Posix,
                links + 1
          }
        }
      }
    }
  } catch {
    LookupErrno(reason) => raise input_path_error(path, reason)
    err => raise err
  }
}

///|
priv struct InstallTable {
  profile : @lib.Profile
  entries : Array[InstallMount]
  mut prefix : String
  mut drive_flags : @hashset.HashSet[String]
  mut drive_system : Bool
  temp : async () -> String
  nt_null : Bool?
}

///|
fn InstallTable::context(
  self : InstallTable,
  cwd : String?,
) -> @lib.Context raise @lib.ConversionError {
  let mounts = self.entries.map(entry => entry.mount)
  let drive_text_mode = self.drive_flags.contains("text")
  let drive_dos_names = self.drive_flags.contains("dos")
  let drive_case : @lib.MountCase = if self.drive_flags.contains("posix=0") {
    WindowsInsensitive
  } else {
    Sensitive
  }
  let base = @lib.Context::new(
    profile=self.profile,
    nt_null?=self.nt_null,
    mounts~,
    drive_prefix_bytes=@filename.encode(self.prefix),
    drive_text_mode~,
    drive_dos_names~,
    drive_case~,
  )
  guard cwd is Some(cwd) else { return base }
  base.with_native_cwd(cwd)
}

///|
async fn InstallTable::add(
  self : InstallTable,
  path : String,
  source : String,
  system~ : Bool,
  flags~ : @hashset.HashSet[String],
  usertemp~ : Bool = false,
) -> Bool {
  let slot = for index, old in self.entries {
    if old.path != path {
      continue
    }
    if !system && old.mount.system == Some(true) {
      return true
    }
    if old.mount.system != Some(system) {
      continue
    }
    if old.flags.contains("immutable") {
      if !flags.contains("override") {
        return true
      }
      flags.add("immutable")
    }
    break index
  } nobreak {
    self.entries.length()
  }
  // A failed insertion at MAX_MOUNTS stops this fstab. Updating an existing
  // slot is still possible when the next file starts.
  if slot == 64 {
    return false
  }
  let source = if usertemp { (self.temp)() } else { source }
  let entry = {
    path,
    mount: @lib.Mount::new(
      input_name(path),
      input_name(source),
      system~,
      case=if flags.contains("posix=0") {
        WindowsInsensitive
      } else {
        Sensitive
      },
      text_mode=flags.contains("text"),
      dos_names=flags.contains("dos"),
    ),
    source,
    flags,
  }
  if slot == self.entries.length() {
    self.entries.push(entry)
  } else {
    self.entries[slot] = entry
  }
  true
}

///|
fn fstab_components(path : StringView) -> String {
  let parts : Array[String] = []
  for part in path.split("/") {
    match part {
      "" | "." => ()
      ".." => ignore(parts.pop())
      _ => parts.push(part.to_owned())
    }
  }
  parts.join("/")
}

///|
/// Upstream checks the initial byte of each UNC field for mount admission.
fn fstab_unc_share(path : String) -> Bool {
  fn valid_initial(unit : UInt16, excluded : String) -> Bool {
    // A zero here marks a retained high byte in the decoded field.
    unit == 0 ||
    (
      unit >= 32 &&
      unit != 127 &&
      !excluded.iter().any(ch => ch.to_int() == unit.to_int())
    )
  }
  path.has_prefix("//") &&
  path.length() > 2 &&
  valid_initial(path[2], ",~:!@#$%^&'.(){} ") &&
  path[3:].find("/") is Some(index) &&
  index + 4 < path.length() &&
  valid_initial(path[index + 4], "\"/\\[]:|<>+=;,?*")
}

///|
/// The native fstab field is normalized lexically before mount table lookup.
/// A drive root or the initial UNC separator bounds parent traversal.
fn fstab_source(source : String) -> String? raise HostError {
  let path = source.replace_all(old="\\", new="/")
  let extended = path.has_prefix("//?/") || path.has_prefix("/??/")
  let body = if extended { path[4:] } else { path[:] }
  if body.length() >= 2 &&
    body[0] is ('A'..<='Z' | 'a'..<='z') &&
    body[1] == ':' {
    guard body.length() == 2 || body[2] == '/' else { return None }
    return Some(
      body[:1].to_owned().to_upper() + ":/" + fstab_components(body[2:]),
    )
  }
  if extended {
    guard body.has_prefix("UNC/") else { return None }
    return Some("//" + fstab_components(body[4:]))
  }
  if (path.has_prefix("//./") || path.has_prefix("/?./")) &&
    path.length() > 4 &&
    path[4] is ('A'..<='Z' | 'a'..<='z') {
    raise InstallationError(
      "unsupported device mount source " + @debug.to_string(source),
    )
  }
  guard fstab_unc_share(path) else { return None }
  if path.has_prefix("///") {
    raise InstallationError(
      "mount source needs the runtime's current drive: " +
      @debug.to_string(source),
    )
  }
  Some("//" + fstab_components(path[2:]))
}

///|
async fn InstallTable::read_fstab(
  self : InstallTable,
  text : String,
  user~ : Bool,
  inspect : async (@lib.NativePath) -> NativeEntity,
) -> Unit {
  for raw in text.split("\n") {
    let row = raw.trim_end(chars="\r").trim_start(chars=" \t")
    if row.is_empty() || row.has_prefix("#") {
      continue
    }
    let fields = row
      .to_owned()
      .replace_all(old="\t", new=" ")
      .split(" ")
      .filter(field => !field.is_empty())
      .take(4)
      .map(field => field.to_owned())
      .to_array()
    // MSYS2's two-field form installs a system, case-insensitive mount
    // even in the per-user fstab. It branches only at end of line.
    let (source, target, kind, options, per_user) = match fields {
      [source, target, kind, options] => (source, target, kind, options, user)
      [source, target] if self.profile == Msys2 &&
        !row.has_suffix(" ") &&
        !row.has_suffix("\t") => (source, target, "", "posix=0,noacl", false)
      _ => continue
    }
    let mut system = true
    let mut flags : @hashset.HashSet[String] = @hashset.from_array([])
    if kind == "cygdrive" {
      flags.add("posix=0")
    }
    if kind == "usertemp" {
      flags.add("immutable")
    }
    let mut known = true
    let options = if options.has_suffix(",") {
      options[:options.length() - 1]
    } else {
      options[:]
    }
    for flag in options.split(",") {
      match flag {
        "user" => system = false
        "nouser" => system = true
        "posix=1" => flags.remove("posix=0")
        "binary" => flags.remove("text")
        "acl" => flags.remove("noacl")
        "auto" | "nosuid" => ()
        "bind"
        | "override"
        | "posix=0"
        | "cygexec"
        | "dos"
        | "exec"
        | "ihash"
        | "noacl"
        | "notexec"
        | "sparse"
        | "text" => flags.add(flag.to_owned())
        _ => known = false
      }
    }
    if !known {
      continue
    }
    let target = target.replace_all(old="\\040", new=" ")
    let mut source = source.replace_all(old="\\040", new=" ")
    if flags.contains("bind") {
      let context = self.context(None)
      let (native, origin) = context.resolve_bind_source_bytes(
        @filename.encode(source),
      ) catch {
        @lib.UnsupportedNamespace(reason) =>
          raise InstallationError("unsupported bind source: " + reason)
        _ => continue
      }
      if flags.length() == 1 {
        let (inherited, owner) = match origin {
          Some(index) => {
            let entry = self.entries[index]
            (entry.flags, entry.mount.system == Some(true))
          }
          None => (self.drive_flags, self.drive_system)
        }
        flags = inherited.copy()
        flags.remove("immutable")
        flags.add("bind")
        system = owner
      }
      source = @filename.decode(native)
    }
    let system = !per_user && system
    if kind == "cygdrive" {
      self.prefix = target.replace_all(old="\\", new="/")
      self.drive_flags = flags
      self.drive_system = system
      continue
    }
    if !target.has_prefix("/") ||
      target.contains_char('\\') ||
      fstab_unc_share(target) {
      continue
    }
    if kind != "usertemp" {
      guard fstab_source(source) is Some(native) else { continue }
      source = native
    }
    if target.has_prefix("//") && !target.has_prefix("///") {
      raise InstallationError(
        "unsupported network mount point " + @debug.to_string(target),
      )
    }
    let target = if target.split("/").any(part => part == "..") {
      checked_parents(
        self.context(None),
        "/" + target.trim_start(chars="/").to_owned(),
        inspect,
      ) catch {
        LookupErrno(_) => continue
        err => raise err
      }
    } else {
      target
    }
    let key = "/" + fstab_components(target[:])
    let room = self.add(
      key,
      source,
      system~,
      flags~,
      usertemp=kind == "usertemp",
    ) catch {
      @lib.ConversionError::_ as err =>
        raise InstallationError(
          @debug.to_string(key) + ": " + @debug.to_string(err),
        )
      err => raise err
    }
    if !room {
      break
    }
  }
}

///|
async fn mounted_context(
  root : String,
  system : String,
  user : String,
  cwd : String?,
  temp~ : async () -> String? = () => None,
  nt_null? : Bool,
  profile~ : @lib.Profile = Cygwin,
  inspect~ : async (@lib.NativePath) -> NativeEntity = mapped_native_entity,
) -> @lib.Context {
  let table : InstallTable = {
    profile,
    entries: [],
    // Both runtimes start here. MSYS2's distributed fstab sets it to "/".
    prefix: "/cygdrive",
    drive_flags: @hashset.from_array(["posix=0"]),
    drive_system: false,
    temp: () => usertemp_source(temp(), cwd),
    nt_null,
  }
  ignore(
    table.add("/", root, system=true, flags=@hashset.from_array(["immutable"])),
  )
  table.read_fstab(system, user=false, inspect)
  let base = table.entries[0].source
    .replace_all(old="\\", new="/")
    .trim_end(chars="/")
  let automatic = match profile {
    Cygwin => [("/usr/bin", "/bin"), ("/usr/lib", "/lib")]
    Msys2 => [("/bin", "/usr/bin")]
  }
  for (path, suffix) in automatic {
    if !table.entries.any(entry => entry.path == path) {
      ignore(
        table.add(
          path,
          base.to_owned() + suffix,
          system=true,
          flags=@hashset.from_array([]),
        ),
      )
    }
  }
  table.read_fstab(user, user=true, inspect)
  table.context(cwd)
}

///|
async fn optional_fstab(path : String) -> String {
  let bytes = @fs.read_binary(path) catch {
    @os_error.OsError(NotFound, ..) => return ""
    _ => raise ReadError(source=path)
  }
  let end = bytes.find(b"\x00").unwrap_or(bytes.length())
  @filename.decode(bytes[:end])
}

///|
fn windows_temp(get : (String) -> String?) -> String? {
  for key in ["TMP", "TEMP", "USERPROFILE"] {
    // GetTempPathW checks the raw environment value in UTF-16 units.
    if get(key) is Some(value) && !value.is_empty() && value.length() <= 260 {
      return Some(value)
    }
  }
  None
}

///|
/// GetTempPathW qualifies even a nonexistent directory. Keep the observed
/// process cwd separate from Cygwin's drive-relative operand rules.
fn usertemp_source(
  value : String?,
  cwd : String?,
  get~ : (String) -> String? = @env.get_env_var,
) -> String raise HostError {
  guard value is Some(value) else {
    raise InstallationError(
      "Windows temporary directory unavailable for usertemp",
    )
  }
  let path = value.replace_all(old="\\", new="/")
  let drive = path.length() >= 2 &&
    path[0] is ('a'..<='z' | 'A'..<='Z') &&
    path[1] == ':'
  if path.has_prefix("//?/") || path.has_prefix("//./") {
    guard fstab_source(path) is Some(source) else {
      raise InstallationError("unsupported Windows device path for usertemp")
    }
    return source
  }
  let absolute = if path.has_prefix("//") || (drive && path[2:].has_prefix("/")) {
    path
  } else {
    guard cwd is Some(cwd) && !cwd.is_empty() else {
      raise InstallationError(
        "relative usertemp path requires the Windows working directory",
      )
    }
    let cwd = cwd.replace_all(old="\\", new="/")
    if drive {
      let device = path[:2]
      let base = if cwd.length() >= 3 &&
        cwd[2] == '/' &&
        cwd[:2].equal_ignore_ascii_case(device) {
        cwd
      } else {
        let key = "=" + device.to_owned().to_upper()
        match get(key) {
          None => device.to_owned().to_upper()
          Some(entry) if entry.length() >= 3 &&
            entry[:2].equal_ignore_ascii_case(device) &&
            entry[2] is ('/' | '\\') => entry.replace_all(old="\\", new="/")
          Some(_) =>
            raise InstallationError("invalid Windows drive directory " + key)
        }
      }
      base + "/" + path[2:].to_owned()
    } else if path.has_prefix("/") {
      cwd[:native_root_end(cwd)].trim_end(chars="/").to_owned() + path
    } else {
      cwd + "/" + path
    }
  }
  let root = native_root_end(absolute)
  guard root >= 3 && (!absolute.has_prefix("//") || fstab_unc_share(absolute)) else {
    raise InstallationError("unsupported Windows root for usertemp")
  }
  // Win32 bounds ".." at the drive or UNC share, before Cygwin adds the mount.
  let parts : Array[String] = []
  for part in absolute[root:].split("/") {
    match part {
      "" | "." => ()
      ".." => ignore(parts.pop())
      _ if part.has_suffix(".") && !part.has_suffix("..") =>
        parts.push(part[:part.length() - 1].to_owned())
      _ => parts.push(part.to_owned())
    }
  }
  let tail = parts.join("/")
  let tail = if absolute.has_suffix("/") {
    tail[:]
  } else {
    tail.trim_end(chars=". ")
  }
  let prefix = absolute[:root].trim_end(chars="/")
  let source = prefix.to_owned() + "/" + tail.to_owned()
  guard source.length() <= 260 else {
    raise InstallationError(
      "qualified Windows temporary directory exceeds 260 UTF-16 units",
    )
  }
  source
}

///|
async fn load_installation(
  root : String,
  directory : String,
  username : String?,
  cwd : String?,
  profile~ : @lib.Profile = Cygwin,
  nt_null? : Bool,
) -> @lib.Context {
  let system = optional_fstab(directory + "/etc/fstab")
  let user = match username {
    Some(name) if !name.is_empty() => {
      if name == "." ||
        name == ".." ||
        name.iter().any(ch => ch is ('/' | '\\' | ':' | '\u0000')) {
        raise InstallationError("invalid account filename for fstab.d")
      }
      optional_fstab(directory + "/etc/fstab.d/" + name)
    }
    _ => ""
  }
  mounted_context(root, system, user, cwd, nt_null?, profile~, temp=() => {
    match windows_temp(@env.get_env_var) {
      Some(path) => Some(path)
      None => system_folder("")
    }
  }) catch {
    @lib.ConversionError::_ as err =>
      raise InstallationError(@debug.to_string(err))
    err => raise err
  }
}

///|
pub async fn installation_context(profile : @lib.Profile) -> @lib.Context? {
  guard @env.get_env_var("CYGPATH_ROOT") is Some(root) && !root.is_empty() else {
    return None
  }
  guard @async.platform is Windows else {
    raise InstallationError("CYGPATH_ROOT requires a Windows host")
  }
  ignore(@lib.Mount::new("/", root)) catch {
    err => raise InstallationError(@debug.to_string(err))
  }
  let (runtime, relative) = match profile {
    Cygwin => ("Cygwin", "/bin/cygwin1.dll")
    Msys2 => ("MSYS2", "/usr/bin/msys-2.0.dll")
  }
  let dll = root + relative
  let kind = @fs.kind(dll) catch {
    _ =>
      raise InstallationError(
        "cannot access " + runtime + " runtime: " + @debug.to_string(dll),
      )
  }
  guard kind is Regular else {
    raise InstallationError(
      "expected " + runtime + " runtime at " + @debug.to_string(dll),
    )
  }
  let nt_null = nt_null_presence()
  Some(
    load_installation(
      root,
      root,
      @env.get_env_var("CYGPATH_USER"),
      @env.current_dir(),
      profile~,
      nt_null?,
    ),
  )
}
