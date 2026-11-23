///|
/// Names that GetShortPathNameW can copy without reading an alternate name.
fn is_ascii_short_component(name : String) -> Bool {
  may_expand_long_component(name) &&
  !name.has_suffix(".") &&
  name
  .code_units()
  .all(unit => {
    unit > 32 &&
    unit < 127 &&
    !(unit
    is ('+'
    | ','
    | ';'
    | '='
    | '['
    | ']'
    | '*'
    | '?'
    | '<'
    | '>'
    | '"'
    | '|'
    | ':'))
  })
}

///|
fn windows_name_root(path : String) -> Int32 {
  let plain = plain_native(path)
  let prefix = path.length() - plain.length()
  let root = if plain.has_prefix("//") {
    native_root_end(plain)
  } else if plain.length() >= 2 && plain[1] == ':' {
    if plain.length() >= 3 && plain[2] == '/' {
      3
    } else {
      2
    }
  } else if plain.has_prefix("/") {
    1
  } else {
    0
  }
  prefix + root
}

///|
fn entry_parent(path : String, name : String) -> String {
  let prefix = path[:path.length() - name.length()]
  if prefix.is_empty() || prefix.has_suffix(":") {
    prefix.to_owned() + "."
  } else {
    let end = prefix
      .trim_end(chars="/\\")
      .length()
      .max(windows_name_root(prefix.to_owned()))
    prefix[:end].to_owned()
  }
}

///|
/// Prefer an exact directory entry. Accept an ASCII case match only when it
/// is unique. The name may instead be a separately stored DOS alias.
async fn primary_entry_name(parent : String, name : String) -> String? {
  let dir = @fs.opendir(host_io_path(parent))
  defer dir.close()
  let mut match_count = 0
  let mut candidate = None
  while dir.next() is Some(entry) {
    if entry.name == name {
      return Some(name)
    }
    if entry.name.equal_ignore_ascii_case(name) {
      match_count += 1
      candidate = Some(entry.name)
    }
  }
  if match_count == 1 {
    candidate
  } else {
    None
  }
}

///|
/// Recover a reparse point's own entry when the operand only names its alias.
/// Windows volumes other than NTFS can report colliding IDs. Require a unique
/// link to the resolved target as well as the identity of the unfollowed link.
async fn link_alias_entry(path : String, name : String) -> String? {
  let operand = host_io_path(path)
  guard @metadata.identity(operand, follow_symlink=false) is Some(id) else {
    return None
  }
  let target = @fs.realpath(operand)
  let prefix = path[:path.length() - name.length()].to_owned()
  let dir = @fs.opendir(host_io_path(entry_parent(path, name)))
  defer dir.close()
  let mut candidate = None
  while dir.next(include_hidden=true) is Some(entry) {
    let child = host_io_path(prefix + entry.name)
    if @fs.kind(child, follow_symlink=false) is SymLink &&
      @fs.realpath(child) == target {
      if candidate is Some(_) ||
        @metadata.identity(child, follow_symlink=false) != Some(id) {
        return None
      }
      candidate = Some(entry.name)
    }
  }
  candidate
}

///|
/// GetLongPathNameW consults the directory entry for short-shaped names,
/// including spaces and characters that require an alternate name for -s.
fn may_expand_long_component(name : String) -> Bool {
  if name.is_empty() || name.has_prefix(".") || name.length() > 12 {
    return false
  }
  match name.split(".").to_array() {
    [stem] => stem.length() <= 8
    [stem, ext] => stem.length() <= 8 && ext.length() <= 3
    _ => false
  }
}

///|
async fn long_component(path : String, name : String) -> String {
  if @fs.kind(host_io_path(path), follow_symlink=false) is SymLink {
    // A normalized handle name would follow this link. Use its own directory entry.
    if primary_entry_name(entry_parent(path, name), name) is Some(entry) {
      return entry
    }
    let entry = link_alias_entry(path, name) catch {
      @metadata.IOError(_) | @os_error.OsError(_, ..) => None
      err => raise err
    }
    if entry is Some(primary) {
      return primary
    }
    raise NameLookupUnavailable(
      "long name of a reparse-point alias: " + @debug.to_string(path),
    )
  }
  // moonrun requests FILE_NAME_NORMALIZED. Only take the leaf so that an
  // expanded parent junction never replaces the user's chosen directory.
  let normalized = plain_native(
    @fs.realpath(host_io_path(path)) catch {
      @os_error.OsError(_, ..) => {
        if primary_entry_name(entry_parent(path, name), name) is Some(entry) {
          return entry
        }
        raise NameLookupUnavailable(
          "cannot obtain normalized name: " + @debug.to_string(path),
        )
      }
      err => raise err
    },
  )
  guard normalized.rev_split_once("/") is Some((_, leaf)) && !leaf.is_empty() else {
    raise NameLookupUnavailable(
      "cannot obtain entry name: " + @debug.to_string(path),
    )
  }
  leaf.to_owned()
}

///|
async fn expand_long_components(
  path : String,
  entry : async (String, String) -> String,
) -> String {
  let root = windows_name_root(path)
  let result = StringBuilder()
  result.write_stringview(path[:root])
  for start = root; start < path.length(); {
    if path[start] is ('/' | '\\') {
      result.write_stringview(path[start:start + 1])
      continue start + 1
    }
    let mut end = start + 1
    while end < path.length() && !(path[end] is ('/' | '\\')) {
      end += 1
    }
    let name = path[start:end].to_owned()
    result.write_string(
      if may_expand_long_component(name) {
        entry(path[:end].to_owned(), name)
      } else {
        name
      },
    )
    continue end
  }
  result.to_string()
}

///|
async fn long_name_on_disk(path : String) -> String {
  try {
    ignore(@fs.kind(host_io_path(path), follow_symlink=false))
    expand_long_components(path, long_component)
  } catch {
    @os_error.OsError(_, ..) => path
    err => raise err
  }
}

///|
pub async fn long_name(path : String) -> String {
  if @async.platform is Windows {
    long_name_on_disk(path)
  } else {
    guard is_dos_namespace(path, plain_native(path)) else {
      raise NameLookupUnavailable("long-name lookup requires a Windows host")
    }
    expand_long_components(path, (_, _) => {
      raise NameLookupUnavailable("long-name lookup requires a Windows host")
    })
  }
}

///|
fn is_dos_namespace(path : String, plain : String) -> Bool {
  let drive = plain.length() >= 3 &&
    plain[0] is ('a'..<='z' | 'A'..<='Z') &&
    plain[1:3] == ":/"
  !plain.has_prefix("//./") &&
  !plain.has_prefix("/??/") &&
  (plain.length() == path.length() || drive || plain.has_prefix("//"))
}

///|
/// GetShortPathNameW copies components already in DOS form, including the
/// caller's case, even when NTFS has a separately assigned alternate name.
fn already_short_path(path : String) -> Bool {
  let plain = plain_native(path)
  guard is_dos_namespace(path, plain) else { return false }
  plain[windows_name_root(plain):]
  .split("/")
  .all(part => {
    part is ("" | "." | "..") || is_ascii_short_component(part.to_owned())
  })
}

///|
async fn short_name_on_disk(path : String) -> String? {
  let plain = plain_native(path)
  let drive_root = plain.length() == 3 &&
    plain[0] is ('A'..<='Z' | 'a'..<='z') &&
    plain[1:] == ":/"
  let kind = @fs.kind(host_io_path(path), follow_symlink=false) catch {
    @os_error.OsError(NotFound | NotDirectory, ..) if !drive_root => return None
    @os_error.OsError(_, ..) =>
      raise NameLookupUnavailable(
        "cannot inspect Windows name: " + @debug.to_string(path),
      )
    err => raise err
  }
  if drive_root ||
    (kind is (Regular | Directory | SymLink) && already_short_path(path)) {
    return Some(path)
  }
  // A component needing conversion requires its actual alternate name.
  raise NameLookupUnavailable(
    "Windows 8.3 name record required for " + @debug.to_string(path),
  )
}

///|
pub async fn short_name(path : String) -> String? {
  match path {
    "" => return None
    "." | ".." => return Some(path)
    _ => ()
  }
  guard @async.platform is Windows else {
    raise NameLookupUnavailable("short-name lookup requires a Windows host")
  }
  short_name_on_disk(path)
}
