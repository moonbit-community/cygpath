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
fn is_reserved_posix_path(parts : Array[String]) -> Bool {
  match parts {
    ["dev", name, ..] => runtime_device_name(name)
    ["proc", ..] => true
    _ => false
  }
}

///|
/// Defines a mount using absolute, dot-free paths. Duplicate and drive-prefix
/// conflicts are checked when a Context is constructed.
pub fn Mount::new(
  posix : String,
  windows : String,
  case~ : MountCase = Sensitive,
  text_mode~ : Bool = false,
  dos_names~ : Bool = false,
  system? : Bool,
) -> Mount raise ConversionError {
  let posix = context_path(posix, Posix, "mount.posix")
  // Installed declarations participate in reverse lookup even when the
  // runtime dispatches their POSIX spelling to a device before scanning mounts.
  guard posix.root == PosixRoot &&
    !has_dot_components(posix) &&
    (system is Some(_) || !is_reserved_posix_path(posix.components)) else {
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
  { posix, windows, case, text_mode, dos_names, system, }
}

///|
fn parse_cwd(
  value : String?,
  syntax : InputSyntax,
  field : String,
  drive_prefix? : Array[String],
  nt_null? : Bool,
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
      let (path, _) = path.normalize(drive_prefix?, nt_null?) catch {
        error => raise InvalidContext(field~, reason="\{Repr(error)}")
      }
      if syntax == Posix && !(virtual_node(path.components) is Some(Directory)) {
        validate_posix_namespace(path) catch {
          error => raise InvalidContext(field~, reason="\{Repr(error)}")
        }
      }
      Some(path)
    }
  }
}

///|
fn ordered_mounts(mounts : Array[Mount], windows~ : Bool) -> Array[Int32] {
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
  indexed.map(pair => pair.0)
}

///|
/// Builds an immutable context. Collections are copied; the host cwd, mounts,
/// environment variables and file system are never consulted.
/// Supply `nt_null` for an observed present or absent NT null device. Omit
/// it when the Windows host state is unknown.
///
/// Cygwin defaults to `/cygdrive`, MSYS2 to `/`. Per-drive cwd keys are single
/// ASCII letters, and each value must be absolute on that same drive.
/// These entries are validated metadata; drive-relative conversion follows
/// cygpath's drive-root rule instead of the Win32 per-drive working directory.
pub fn Context::new(
  profile~ : Profile = Cygwin,
  nt_null? : Bool,
  drive_prefix? : String,
  drive_text_mode~ : Bool = false,
  drive_dos_names~ : Bool = false,
  drive_case~ : MountCase = WindowsInsensitive,
  mounts~ : Array[Mount] = [],
  posix_cwd? : String,
  windows_cwd? : String,
  drive_cwds~ : Map[String, String] = Map([]),
) -> Context raise ConversionError {
  let prefix = match drive_prefix {
    Some(value) => value
    None => if profile == Cygwin { "/cygdrive" } else { "/" }
  }
  let prefix = context_path(prefix, Posix, "drive_prefix")
  guard prefix.root == PosixRoot &&
    !has_dot_components(prefix) &&
    !is_reserved_posix_path(prefix.components) else {
    raise InvalidContext(
      field="drive_prefix",
      reason="expected a non-virtual, dot-free absolute POSIX prefix",
    )
  }
  // An unscoped declaration occupies the name exclusively. A measured table
  // can contain one user and one system entry at the same destination.
  let seen : Map[String, Bool?] = Map([])
  for index, mount in mounts {
    let name = "/" + mount.posix.components.join("/")
    if seen.get(name) is Some(previous) {
      guard previous is Some(owner) && mount.system == Some(!owner) else {
        raise InvalidContext(
          field="mounts[\{index}]",
          reason="duplicate POSIX mount point",
        )
      }
      seen[name] = None
    } else {
      seen[name] = mount.system
    }
    let conflicts = if prefix.components.is_empty() {
      mount.posix.components.get(0) is Some(drive) && is_drive(drive)
    } else {
      components_match(prefix.components, mount.posix.components, mount.case)
    }
    // An installed entry below the drive prefix is shadowed for POSIX input.
    // Its native source still participates in Windows-to-POSIX lookup.
    if conflicts && mount.system is None {
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
    drive_paths[drive] = path.normalize().0
  }
  let use_runtime_order = profile == Msys2 ||
    mounts.any(m => m.system is Some(_))
  {
    profile,
    nt_null,
    network_servers: {},
    drive_prefix: prefix.components,
    drive_text_mode,
    drive_dos_names,
    drive_case,
    mounts: mounts.copy(),
    posix_mounts: if use_runtime_order {
      runtime_mount_order(mounts, profile, windows=false)
    } else {
      ordered_mounts(mounts, windows=false)
    },
    windows_mounts: if use_runtime_order {
      runtime_mount_order(mounts, profile, windows=true)
    } else {
      ordered_mounts(mounts, windows=true)
    },
    posix_cwd: parse_cwd(
      posix_cwd,
      Posix,
      "posix_cwd",
      drive_prefix=prefix.components,
      nt_null?,
    ),
    windows_cwd: parse_cwd(windows_cwd, Windows, "windows_cwd"),
  }
}

///|
/// Record whether the Windows network-directory handler recognizes this
/// server spelling, for POSIX parent traversal and absolute directory output.
pub fn Context::with_network_server(
  self : Context,
  server : String,
  present~ : Bool,
) -> Context {
  let network_servers = self.network_servers.copy()
  network_servers[server] = present
  { ..self, network_servers, }
}
