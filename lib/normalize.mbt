///|
fn ParsedPath::is_absolute(self : ParsedPath) -> Bool {
  match self.root {
    PosixRoot | DriveAbsolute(_) | NetworkRoot | NetworkServer(_) | Unc(_, _) =>
      true
    _ => false
  }
}

///|
fn ParsedPath::normalize(
  self : ParsedPath,
  drive_prefix? : Array[String],
  nt_null? : Bool,
) -> (ParsedPath, Bool) raise ConversionError {
  if !self.is_absolute() && self.root != WindowsRooted {
    return (self, false)
  }
  let components = []
  let mut followed = false
  let mut links = 0
  for index, part in self.components {
    if self.root == PosixRoot {
      if components is ["proc"] &&
        part == "cygdrive" &&
        drive_prefix is Some(prefix) {
        links += 1
        if links > 10 {
          raise TooManyLinks
        }
        components.clear()
        components.append(prefix)
        followed = true
        continue
      }
      if part == ".." &&
        drive_prefix is Some(prefix) &&
        !prefix.is_empty() &&
        components.length() > prefix.length() &&
        components_match(prefix, components, Sensitive) &&
        !is_drive(components[prefix.length()]) {
        raise InvalidDrivePrefix
      }
      match virtual_node(components) {
        Some(NullDevice) => {
          check_nt_null(nt_null, parent=part == "..")
          raise NotDirectory
        }
        Some(Terminal) => raise NotDirectory
        Some(ProcFile) if part == ".." ||
          (part == "." && index + 1 == self.components.length()) =>
          raise NotDirectory
        Some(ProcFile) if part != "." => raise PathNotFound
        Some(Missing) => raise PathNotFound
        None if part == ".." && is_reserved_posix_path(components) =>
          raise UnsupportedNamespace("POSIX virtual path")
        _ => ()
      }
    }
    match part {
      "." => ()
      ".." => {
        // Cygwin resolves the cancelled parent in a separate path lookup.
        links = 0
        if components.last() is Some(part) && part != ".." {
          ignore(components.pop())
        } else if self.root is Unc(_, _) {
          components.push("..")
        }
      }
      _ => components.push(part)
    }
  }
  if self.root == PosixRoot {
    match virtual_node(components) {
      Some(NullDevice) => {
        check_nt_null(nt_null, parent=false)
        if self.trailing {
          raise NotDirectory
        }
      }
      Some(Terminal | ProcFile) if self.trailing => raise NotDirectory
      Some(Missing) => raise PathNotFound
      _ => ()
    }
  }
  ({ ..self, components, }, followed)
}

///|
fn check_nt_null(
  observed : Bool?,
  parent~ : Bool,
) -> Unit raise ConversionError {
  match observed {
    Some(true) => ()
    // The POSIX parent check reports ENOENT if its path lookup did not find
    // an entity, even when a direct device lookup would have returned ENXIO.
    Some(false) if parent => raise PathNotFound
    Some(false) => raise NoSuchDeviceOrAddress
    None => raise MissingContext(field="nt_null")
  }
}

///|
fn normalize_network(
  parts : Array[String],
  tail : Iter[String],
  trailing~ : Bool,
  servers? : Map[String, Bool],
) -> ParsedPath raise ConversionError {
  let mut check_parent = false
  for part in tail {
    match part {
      "" | "." => ()
      ".." => {
        if check_parent && parts is [server] && servers is Some(observations) {
          match observations.get(server) {
            Some(false) => raise PathNotFound
            None => raise NetworkServerLookup(server)
            Some(true) => ()
          }
        }
        ignore(parts.pop())
        check_parent = false
      }
      _ => {
        parts.push(part)
        check_parent = true
      }
    }
  }
  match parts {
    [] => { root: NetworkRoot, components: [], trailing: false, }
    [server] => { root: NetworkServer(server), components: [], trailing, }
    [server, share, .. rest] =>
      { root: Unc(server, share), components: rest.to_owned(), trailing, }
  }
}

///|
fn resolve_against(
  base : ParsedPath,
  path : ParsedPath,
  drive_prefix : Array[String],
  nt_null : Bool?,
) -> (ParsedPath, Bool) raise ConversionError {
  let components = base.components.copy()
  components.append(path.components)
  { root: base.root, components, trailing: path.trailing, }.normalize(
    drive_prefix~,
    nt_null?,
  )
}

///|
fn Context::resolve(
  self : Context,
  path : ParsedPath,
  from : InputSyntax,
  to : OutputFormat,
  absolute : Bool,
) -> ParsedPath raise ConversionError {
  match path.root {
    NetworkRoot =>
      normalize_network(
        [],
        path.components.iter(),
        trailing=path.trailing,
        servers?=if from == Posix { Some(self.network_servers) } else { None },
      )
    Relative if absolute => {
      let base = if from == Posix { self.posix_cwd } else { self.windows_cwd }
      guard base is Some(base) else {
        let field = if from == Posix { "posix_cwd" } else { "windows_cwd" }
        raise MissingContext(field~)
      }
      if base.root is Unc(server, share) {
        let names = [server, share]
        names.append(base.components)
        normalize_network(
          names,
          path.components.iter(),
          trailing=path.trailing || path.components.last() is Some("." | ".."),
          servers?=if from == Posix { Some(self.network_servers) } else { None },
        )
      } else {
        resolve_against(base, path, self.drive_prefix, self.nt_null).0
      }
    }
    Relative if from == Posix &&
      to != Posix &&
      self.posix_cwd is Some(base) &&
      (
        self.is_drive_directory(base) ||
        base.components.get(0) is Some("dev" | "proc") ||
        path.components.any(part => part is ("dev" | "proc"))
      ) => {
      let (full, followed) = resolve_against(
        base,
        path,
        self.drive_prefix,
        self.nt_null,
      )
      if full.root == PosixRoot &&
        (
          followed ||
          self.is_drive_directory(base) ||
          is_reserved_posix_path(full.components) ||
          virtual_node(base.components) is Some(Directory)
        ) {
        full
      } else {
        path
      }
    }
    DriveRelative(drive) if absolute || to == Posix =>
      // Cygwin's conversion API anchors DOS drive-relative input at that
      // drive's root rather than consulting the Win32 per-drive cwd.
      { ..path, root: DriveAbsolute(drive), }.normalize().0
    WindowsRooted if absolute || to == Posix => {
      guard self.windows_cwd is Some({ root: DriveAbsolute(drive), .. }) else {
        raise MissingContext(field="windows_cwd drive")
      }
      { ..path, root: DriveAbsolute(drive), }.normalize().0
    }
    _ => path.normalize(drive_prefix=self.drive_prefix, nt_null?=self.nt_null).0
  }
}
