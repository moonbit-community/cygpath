///|
async fn fixed_directory_name(root : String, child : String) -> String? {
  let path = if child.is_empty() {
    root
  } else if root.has_prefix("\\\\?\\") {
    root + "\\" + child
  } else {
    root + "/" + child
  }
  try {
    match @fs.kind(path, follow_symlink=false) {
      Directory => Some(plain_native(@fs.realpath(path)))
      SymLink => {
        // The NT query keeps the final reparse point. Looking up its target's
        // normalized path would substitute a different directory name.
        guard !child.is_empty() &&
          @fs.kind(root, follow_symlink=false) is Directory else {
          raise NameLookupUnavailable(
            "cannot determine the Windows root entry's own spelling",
          )
        }
        guard @fs.kind(path) is Directory else { return None }
        let parent = plain_native(@fs.realpath(root))
          .trim_end(chars="/")
          .to_owned()
        guard primary_entry_name(root, child) is Some(entry) else {
          raise NameLookupUnavailable(
            "cannot determine the system directory entry's own spelling",
          )
        }
        Some(parent + "/" + entry)
      }
      _ => None
    }
  } catch {
    @os_error.OsError(NotFound | NotDirectory, ..) => None
    @os_error.OsError(_, ..) =>
      raise NameLookupUnavailable("cannot resolve the Windows system directory")
    err => raise err
  }
}

///|
/// Resolve a fixed child of the running Windows installation independently
/// of the process environment. An empty child selects SystemRoot itself.
pub async fn system_folder(child : String) -> String? {
  guard @async.platform is Windows else {
    raise NameLookupUnavailable(
      "system-directory lookup requires a Windows host",
    )
  }
  guard fixed_directory_name("\\\\?\\GLOBALROOT\\SystemRoot", child)
    is Some(native) else {
    return None
  }
  guard native.length() >= 3 &&
    native[0] is ('A'..<='Z' | 'a'..<='z') &&
    native[1] == ':' &&
    native[2] == '/' else {
    raise NameLookupUnavailable("system directory has no local DOS drive path")
  }
  Some(native)
}
