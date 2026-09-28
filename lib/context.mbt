///|
fn context_path(
  value : String,
  syntax : InputSyntax,
  field : String,
) -> ParsedPath raise ConversionError {
  parse_path(value, syntax) catch {
    error => raise InvalidContext(field~, reason="\{Repr(error)}")
  }
}

///|
fn has_dot_components(path : ParsedPath) -> Bool {
  path.components.any(part => part == "." || part == "..")
}

///|
fn is_virtual_root(parts : Array[String]) -> Bool {
  parts.get(0) is Some("dev" | "proc")
}

///|
/// Defines a mount using absolute, dot-free paths. Duplicate and drive-prefix
/// conflicts are checked when a Context is constructed.
pub fn Mount::new(
  posix : String,
  windows : String,
  case? : MountCase = Sensitive,
) -> Mount raise ConversionError {
  let posix = context_path(posix, Posix, "mount.posix")
  guard posix.root == PosixRoot &&
    !has_dot_components(posix) &&
    !is_virtual_root(posix.components) else {
    raise InvalidContext(
      field="mount.posix",
      reason="expected a non-virtual, dot-free absolute POSIX path",
    )
  }
  let windows = context_path(windows, Windows, "mount.windows")
  guard windows.is_absolute() && !has_dot_components(windows) else {
    raise InvalidContext(
      field="mount.windows",
      reason="expected a dot-free drive-absolute or UNC path",
    )
  }
  { posix, windows, case, }
}

///|
fn parse_cwd(
  value : String?,
  syntax : InputSyntax,
  field : String,
) -> ParsedPath? raise ConversionError {
  match value {
    None => None
    Some(value) => {
      let path = context_path(value, syntax, field)
      guard path.is_absolute() else {
        raise InvalidContext(
          field~,
          reason="working directory must be absolute",
        )
      }
      let path = path.normalize()
      if syntax == Posix {
        validate_posix_namespace(path) catch {
          error => raise InvalidContext(field~, reason="\{Repr(error)}")
        }
      }
      Some(path)
    }
  }
}

///|
fn ordered_mounts(mounts : Array[Mount], windows~ : Bool) -> Array[Mount] {
  // Include the declaration index explicitly: sorting stability is not an API
  // dependency, and equal-length aliases must keep their declared priority.
  let indexed = mounts.mapi((i, mount) => (i, mount))
  indexed.sort_by((a, b) => {
    let a_path = if windows { a.1.windows } else { a.1.posix }
    let b_path = if windows { b.1.windows } else { b.1.posix }
    let order = b_path.components.length().compare(a_path.components.length())
    if order == 0 {
      a.0.compare(b.0)
    } else {
      order
    }
  })
  indexed.map(pair => pair.1)
}

///|
/// Builds an immutable context. Collections are copied; the host cwd, mounts,
/// environment variables and file system are never consulted.
///
/// Cygwin defaults to `/cygdrive`, MSYS2 to `/`. Per-drive cwd keys are single
/// ASCII letters, and each value must be absolute on that same drive.
pub fn Context::new(
  profile? : Profile = Cygwin,
  drive_prefix? : String,
  mounts? : Array[Mount] = [],
  posix_cwd? : String,
  windows_cwd? : String,
  drive_cwds? : Map[String, String] = Map([]),
) -> Context raise ConversionError {
  let prefix = match drive_prefix {
    Some(value) => value
    None => if profile == Cygwin { "/cygdrive" } else { "/" }
  }
  let prefix = context_path(prefix, Posix, "drive_prefix")
  guard prefix.root == PosixRoot &&
    !has_dot_components(prefix) &&
    !is_virtual_root(prefix.components) else {
    raise InvalidContext(
      field="drive_prefix",
      reason="expected a non-virtual, dot-free absolute POSIX prefix",
    )
  }
  let seen : Map[String, Unit] = Map([])
  for index, mount in mounts {
    let name = "/" + mount.posix.components.join("/")
    if seen.contains(name) {
      raise InvalidContext(
        field="mounts[\{index}]",
        reason="duplicate POSIX mount point",
      )
    }
    seen[name] = ()
    let conflicts = if prefix.components.is_empty() {
      mount.posix.components.get(0) is Some(drive) && is_drive(drive)
    } else {
      components_match(prefix.components, mount.posix.components, mount.case)
    }
    if conflicts {
      raise InvalidContext(
        field="mounts[\{index}]",
        reason="mount overlaps reserved drive prefix",
      )
    }
  }
  let drive_paths : Map[String, ParsedPath] = Map([])
  for drive, value in drive_cwds {
    guard is_drive(drive) else {
      raise InvalidContext(
        field="drive_cwds",
        reason="key must be a single ASCII drive letter",
      )
    }
    let drive = upper_drive(drive)
    if drive_paths.contains(drive) {
      raise InvalidContext(
        field="drive_cwds[\{drive}]",
        reason="duplicate drive after case folding",
      )
    }
    let path = context_path(value, Windows, "drive_cwds[\{drive}]")
    guard path.root == DriveAbsolute(drive) else {
      raise InvalidContext(
        field="drive_cwds[\{drive}]",
        reason="cwd must be absolute on the keyed drive",
      )
    }
    drive_paths[drive] = path.normalize()
  }
  {
    drive_prefix: prefix.components,
    posix_mounts: ordered_mounts(mounts, windows=false),
    windows_mounts: ordered_mounts(mounts, windows=true),
    posix_cwd: parse_cwd(posix_cwd, Posix, "posix_cwd"),
    windows_cwd: parse_cwd(windows_cwd, Windows, "windows_cwd"),
    drive_cwds: drive_paths,
  }
}
