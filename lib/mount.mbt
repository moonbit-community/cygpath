///|
fn mount_upper(unit : Int32) -> Int32 {
  for low = 0, high = mount_upper_ranges.length(); low < high; {
    let mid = (low + high) / 2
    let (first, last, stride, upper) = mount_upper_ranges[mid]
    if unit < first {
      continue low, mid
    } else if unit > last {
      continue mid + 1, high
    } else {
      return if (unit - first) % stride == 0 {
        upper + unit - first
      } else {
        unit
      }
    }
  } nobreak {
    unit
  }
}

///|
fn components_match(
  prefix : Array[String],
  path : Array[String],
  policy : MountCase,
  roots? : (PathRoot, PathRoot),
) -> Bool {
  if prefix.length() > path.length() {
    return false
  }
  // path_prefix_p checks the boundary at the byte length of the whole
  // mount prefix. Case pairs may use different numbers of UTF-8 bytes.
  let mut width_difference = 0
  fn equal(a : String, b : String) -> Bool {
    if a == b {
      return true
    }
    match policy {
      Sensitive => false
      AsciiInsensitive => a.equal_ignore_ascii_case(b)
      WindowsInsensitive => {
        // The wide comparison maps an invalid byte to U+F0xx. The narrow
        // boundary still counts one byte for it, even across components.
        let wide = @filename.native_name(b)
        if a.length() != wide.length() {
          return false
        }
        for i in 0..<a.length() {
          if a[i] != wide[i] &&
            mount_upper(a[i].to_int()) != mount_upper(wide[i].to_int()) {
            return false
          }
        }
        let size = if b.length() == wide.length() {
          mount_utf8_length(b)
        } else {
          @filename.encode(b).length()
        }
        width_difference += mount_utf8_length(a) - size
        true
      }
    }
  }
  match roots {
    Some((Unc(server, share), Unc(other_server, other_share))) =>
      if !equal(server, other_server) || !equal(share, other_share) {
        return false
      }
    Some((a, b)) if a != b => return false
    _ => ()
  }
  for i in 0..<prefix.length() {
    if !equal(prefix[i], path[i]) {
      return false
    }
  }
  width_difference == 0
}

///|
fn remount(
  path : ParsedPath,
  source : ParsedPath,
  target : ParsedPath,
) -> ParsedPath {
  let components = target.components.copy()
  components.append(path.components[source.components.length():])
  { root: target.root, components, trailing: path.trailing, }
}

///|
fn validate_posix_namespace(path : ParsedPath) -> Unit raise ConversionError {
  if path.root != PosixRoot || !is_reserved_posix_path(path.components) {
    return
  }
  raise UnsupportedNamespace("POSIX virtual path")
}

///|
fn drive_path(
  path : ParsedPath,
  prefix_length : Int32,
) -> ParsedPath raise ConversionError {
  guard path.components.get(prefix_length) is Some(drive) && is_drive(drive) else {
    raise InvalidDrivePrefix
  }
  {
    root: DriveAbsolute(upper_drive(drive)),
    components: path.components[prefix_length + 1:].to_owned(),
    trailing: path.trailing,
  }
}

///|
fn Context::map_posix_mount(
  self : Context,
  path : ParsedPath,
  dev_bind~ : Bool = false,
) -> (ParsedPath, Int32?) raise ConversionError {
  if path.root != PosixRoot {
    return (path, None)
  }
  if !dev_bind {
    validate_posix_namespace(path)
  }
  if self.drive_prefix.is_empty() {
    if path.components.get(0) is Some(drive) && is_drive(drive) {
      return (drive_path(path, 0), None)
    }
  } else if self.drive_prefix.length() < path.components.length() &&
    components_match(self.drive_prefix, path.components, Sensitive) {
    return (drive_path(path, self.drive_prefix.length()), None)
  }
  for index in self.posix_mounts {
    let mount = self.mounts[index]
    if components_match(mount.posix.components, path.components, mount.case) {
      let mapped = remount(path, mount.posix, mount.windows)
      if self.profile == Msys2 && path.components.is_empty() {
        return ({ ..mapped, trailing: true, }, Some(index))
      }
      return (mapped, Some(index))
    }
  }
  raise MissingContext(field="root or mount")
}

///|
fn Context::dos_names(
  self : Context,
  path : ParsedPath,
  mount : Int32?,
) -> Bool {
  match mount {
    Some(index) => self.mounts[index].dos_names
    None =>
      self.drive_dos_names && (path.root == PosixRoot || path.root is Unc(_, _))
  }
}

///|
fn Context::is_drive_directory(self : Context, path : ParsedPath) -> Bool {
  path.root == PosixRoot &&
  !self.drive_prefix.is_empty() &&
  path.components == self.drive_prefix
}

///|
/// Map an operand against the snapshot and return its Windows name relative
/// to the native working directory. A sibling, another volume or a virtual
/// entry has no such name. The caller applies any discovered filename suffix
/// and directory separator after this comparison.
pub fn[P : ToPathInput] Context::relative_windows_name(
  self : Context,
  operand : P,
  from~ : InputSyntax,
) -> String? raise ConversionError {
  let path = operand.to_path_input().spelling()
  validate_component_lengths(path)
  guard self.windows_cwd is Some(cwd) else { return None }
  let input = parse_validated_path(path, from)
  if input.root == Relative &&
    from == Posix &&
    self.resolve(input, from, Windows, false).is_absolute() {
    // Following a virtual link or leaving a virtual cwd produces a full name.
    return None
  }
  let parsed = self.resolve(input, from, Windows, true)
  if self.is_drive_directory(parsed) ||
    (parsed.root == PosixRoot && virtual_node(parsed.components) is Some(_)) {
    return None
  }
  let (native, mount) = self.map_posix_mount(parsed)
  let policy = match mount {
    Some(index) => self.mounts[index].case
    None if from == Posix || native.root is Unc(_, _) => self.drive_case
    None => Sensitive
  }
  let parts = native.components.map(encode_windows_component)
  guard components_match(
    cwd.components,
    parts,
    policy,
    roots=(cwd.root, native.root),
  ) else {
    return None
  }
  let name = if parts.length() == cwd.components.length() {
    "."
  } else {
    parts[cwd.components.length():].join("\\")
  }
  Some(
    if self.dos_names(parsed, mount) {
      dos_mount_spelling(name, Relative, Windows)
    } else {
      name
    },
  )
}

///|
/// Map an operand for a host mode query before following filesystem links.
pub fn[P : ToPathInput] Context::mode_candidate(
  self : Context,
  operand : P,
  from~ : InputSyntax,
) -> ModeCandidate raise ConversionError {
  let path = operand.to_path_input().spelling()
  validate_component_lengths(path)
  let parsed = self.resolve(
    parse_validated_path(path, from),
    from,
    Windows,
    true,
  )
  match parsed.root {
    NetworkRoot => return NetworkDirectory(None)
    NetworkServer(name) => return NetworkDirectory(Some(name))
    _ => ()
  }
  if self.is_drive_directory(parsed) {
    return Virtual(directory=true)
  }
  if parsed.root == PosixRoot && virtual_node(parsed.components) is Some(node) {
    if node is NullDevice {
      return NullDevice(native_input=parsed.components is ["dev", "null"])
    }
    return Virtual(directory=node is Directory)
  }
  let (native, mount) = self.map_posix_mount(parsed)
  let text_mode = match mount {
    Some(index) => self.mounts[index].text_mode
    None => (from == Posix || native.root is Unc(_, _)) && self.drive_text_mode
  }
  Filesystem(
    native.render(Windows, dos_names=self.dos_names(parsed, mount)),
    text_mode~,
  )
}

///|
/// Resolve an absolute POSIX fstab bind source in this snapshot, without
/// following links. The optional index identifies the selected declaration
/// in the supplied mounts array. UNC and drive-prefix paths use drive flags.
pub fn Context::resolve_bind_source(
  self : Context,
  path : String,
) -> (String, Int32?) raise ConversionError {
  let input = parse_path(path, Posix)
  guard input.is_absolute() else {
    raise InvalidOptions("bind source must be an absolute POSIX path")
  }
  // fstab calls the mount mapper directly. Ordinary proc entries keep their
  // POSIX spelling there, which cannot be registered as a native mount source.
  if input.root == PosixRoot &&
    input.components is ["proc", ..] &&
    !(input.components is ["proc", "sys", ..]) {
    raise InvalidOptions("bind source has no native mount spelling")
  }
  // Bind calls the mapper directly, without the operand's search for a
  // device in a parent directory. The runtime matches the raw source name.
  let dev_bind = path.has_prefix("/dev/")
  if dev_bind {
    let name = path[5:].to_owned()
    if runtime_device_name(name) {
      if name.has_prefix("sd") {
        raise UnsupportedNamespace("disk partition presence for bind source")
      }
      raise InvalidOptions("device has no native mount source")
    }
    if name.has_prefix("disk/") {
      raise InvalidOptions("device has no native mount source")
    }
  }
  let (mapped, mount) = self.map_posix_mount(input, dev_bind~)
  let native = mapped.native_mount_name()
  let spelling = if mapped.trailing ||
    (mapped.root is DriveAbsolute(_) && mapped.components.is_empty()) {
    native + "\\"
  } else {
    native
  }
  if mount_utf8_length(spelling) >= 260 {
    raise PathTooLong(path)
  }
  let normal = mapped.normalize().0
  let result = normal.native_mount_name()
  (
    if normal.root is DriveAbsolute(_) && normal.components.is_empty() {
      result + "\\"
    } else {
      result
    },
    mount,
  )
}

///|
fn Context::to_posix(
  self : Context,
  path : ParsedPath,
  prefix : UnixPrefix,
  terminal_dot~ : Bool = false,
) -> ParsedPath {
  for index in self.windows_mounts {
    let mount = self.mounts[index]
    if components_match(
        mount.windows.components,
        path.components,
        mount.case,
        roots=(mount.windows.root, path.root),
      ) {
      let mapped = remount(path, mount.windows, mount.posix)
      // A terminal . or .. leaves a separator in the normalized native tail.
      // An exact mount takes a slash only from the original operand.
      return {
        ..mapped,
        trailing: path.trailing ||
        (
          terminal_dot &&
          path.components.length() > mount.windows.components.length()
        ),
      }
    }
  }
  match path.root {
    DriveAbsolute(drive) => {
      let components = match prefix {
        Configured => self.drive_prefix.copy()
        ProcCygdrive => ["proc", "cygdrive"]
      }
      components.push(drive.to_lower())
      components.append(path.components)
      {
        root: PosixRoot,
        components,
        trailing: path.trailing || (terminal_dot && !path.components.is_empty()),
      }
    }
    _ => path
  }
}
