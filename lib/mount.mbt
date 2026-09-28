///|
fn component_equal(a : String, b : String, policy : MountCase) -> Bool {
  match policy {
    Sensitive => a == b
    AsciiInsensitive => a.equal_ignore_ascii_case(b)
  }
}

///|
fn components_match(
  prefix : Array[String],
  path : Array[String],
  policy : MountCase,
) -> Bool {
  if prefix.length() > path.length() {
    return false
  }
  for i in 0..<prefix.length() {
    if !component_equal(prefix[i], path[i], policy) {
      return false
    }
  }
  true
}

///|
fn roots_match(a : PathRoot, b : PathRoot, policy : MountCase) -> Bool {
  match (a, b) {
    (Unc(a_server, a_share), Unc(b_server, b_share)) =>
      component_equal(a_server, b_server, policy) &&
      component_equal(a_share, b_share, policy)
    _ => a == b
  }
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
  if path.root != PosixRoot || !is_virtual_root(path.components) {
    return
  }
  if path.components.length() >= 3 &&
    path.components[0] == "proc" &&
    path.components[1] == "cygdrive" &&
    is_drive(path.components[2]) {
    return
  }
  raise UnsupportedNamespace("POSIX virtual path")
}

///|
fn drive_path(
  path : ParsedPath,
  prefix_length : Int,
) -> ParsedPath raise ConversionError {
  guard path.components.get(prefix_length) is Some(drive) && is_drive(drive) else {
    raise InvalidPath(
      reason="drive prefix must be followed by a single ASCII drive letter",
      offset=0,
    )
  }
  {
    root: DriveAbsolute(upper_drive(drive)),
    components: path.components[prefix_length + 1:].to_owned(),
    trailing: path.trailing,
  }
}

///|
fn Context::to_windows(
  self : Context,
  path : ParsedPath,
) -> ParsedPath raise ConversionError {
  if path.root != PosixRoot {
    return path
  }
  validate_posix_namespace(path)
  if components_match(["proc", "cygdrive"], path.components, Sensitive) {
    return drive_path(path, 2)
  }
  if self.drive_prefix.is_empty() {
    if path.components.get(0) is Some(drive) && is_drive(drive) {
      return drive_path(path, 0)
    }
  } else if components_match(self.drive_prefix, path.components, Sensitive) {
    return drive_path(path, self.drive_prefix.length())
  }
  for mount in self.posix_mounts {
    if components_match(mount.posix.components, path.components, mount.case) {
      return remount(path, mount.posix, mount.windows)
    }
  }
  raise MissingContext(field="root or mount")
}

///|
fn Context::to_posix(
  self : Context,
  path : ParsedPath,
  prefix : UnixPrefix,
) -> ParsedPath {
  for mount in self.windows_mounts {
    if roots_match(mount.windows.root, path.root, mount.case) &&
      components_match(mount.windows.components, path.components, mount.case) {
      return remount(path, mount.windows, mount.posix)
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
      { root: PosixRoot, components, trailing: path.trailing, }
    }
    _ => path
  }
}
