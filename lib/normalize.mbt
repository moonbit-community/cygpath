///|
fn ParsedPath::is_absolute(self : ParsedPath) -> Bool {
  match self.root {
    PosixRoot | DriveAbsolute(_) | Unc(_, _) => true
    _ => false
  }
}

///|
fn ParsedPath::normalize(self : ParsedPath) -> ParsedPath {
  if !self.is_absolute() && self.root != WindowsRooted {
    return self
  }
  let components = []
  for part in self.components {
    match part {
      "." => ()
      ".." =>
        if components.last() is Some(part) && part != ".." {
          ignore(components.pop())
        } else if self.root is Unc(_, _) {
          components.push("..")
        }
      _ => components.push(part)
    }
  }
  { ..self, components, }
}

///|
fn resolve_against(base : ParsedPath, path : ParsedPath) -> ParsedPath {
  let components = base.components.copy()
  components.append(path.components)
  { root: base.root, components, trailing: path.trailing, }.normalize()
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
    Relative if absolute => {
      let base = if from == Posix { self.posix_cwd } else { self.windows_cwd }
      guard base is Some(base) else {
        let field = if from == Posix { "posix_cwd" } else { "windows_cwd" }
        raise MissingContext(field~)
      }
      resolve_against(base, path)
    }
    DriveRelative(drive) if absolute || to == Posix =>
      // Cygwin's conversion API anchors DOS drive-relative input at that
      // drive's root rather than consulting the Win32 per-drive cwd.
      { ..path, root: DriveAbsolute(drive), }.normalize()
    WindowsRooted if absolute || to == Posix => {
      guard self.windows_cwd is Some({ root: DriveAbsolute(drive), .. }) else {
        raise MissingContext(field="windows_cwd drive")
      }
      { ..path, root: DriveAbsolute(drive), }.normalize()
    }
    _ => path.normalize()
  }
}
