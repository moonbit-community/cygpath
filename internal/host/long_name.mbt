///|
/// None means DOS eligibility depends on the OEM character set or space
/// handling. An exact spelling on disk is usable in either case.
fn dos_component(name : String) -> Bool? {
  if name.length() > 12 || name.has_prefix(".") || name.has_suffix(".") {
    return Some(false)
  }
  let fields = name.split(".").to_array()
  if fields.length() > 2 ||
    fields[0].length() > 8 ||
    (fields.length() == 2 && fields[1].length() > 3) {
    return Some(false)
  }
  let mut uncertain = false
  for unit in name.code_units() {
    if unit
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
      | ':') {
      return Some(false)
    }
    if unit <= 32 || unit >= 127 {
      uncertain = true
    }
  }
  if uncertain {
    None
  } else {
    Some(true)
  }
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
/// GetLongPathNameW consults the directory entry for short-shaped names,
/// including spaces and characters that require an alternate name for -s.
fn may_expand_long_component(name : String) -> Bool {
  if name.length() > 12 {
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
  if !may_expand_long_component(name) {
    return name
  }
  if @fs.kind(host_io_path(path), follow_symlink=false) is SymLink {
    // A normalized handle name would follow this link. Use its own directory entry.
    if primary_entry_name(entry_parent(path, name), name) is Some(entry) {
      return entry
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
      if name is ("." | "..") {
        name
      } else {
        entry(path[:end].to_owned(), name)
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
  guard @async.platform is Windows else {
    raise NameLookupUnavailable("long-name lookup requires a Windows host")
  }
  long_name_on_disk(path)
}

///|
/// GetShortPathNameW copies components already in DOS form, including the
/// caller's case, even when NTFS has a separately assigned alternate name.
fn already_short_path(path : String) -> Bool {
  let plain = plain_native(path)
  let drive = plain.length() >= 3 &&
    plain[0] is ('a'..<='z' | 'A'..<='Z') &&
    plain[1:3] == ":/"
  if plain.has_prefix("//./") ||
    plain.has_prefix("/??/") ||
    (plain.length() != path.length() && !drive && !plain.has_prefix("//")) {
    return false
  }
  plain[windows_name_root(plain):]
  .split("/")
  .all(part => {
    part is ("" | "." | "..") || dos_component(part.to_owned()) == Some(true)
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
