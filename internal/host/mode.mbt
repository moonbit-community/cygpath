///|
fn absolute_drive_name(path : String) -> Bool {
  path.length() >= 3 &&
  path[0] is ('A'..<='Z' | 'a'..<='z') &&
  path[1] == ':' &&
  path[2] is ('/' | '\\')
}

///|
async fn installed_mode(
  context : @lib.Context,
  operand : String,
  inspect~ : async (String) -> NativeEntity = native_entity,
  parent_inspect? : async (String) -> NativeEntity,
  server_lookup~ : async (String) -> Bool = network_server_exists,
) -> Bool {
  let windows = operand.contains_char('\\') || absolute_drive_name(operand)
  let path = if windows {
    operand
  } else {
    checked_parents(
      context,
      operand,
      parent_inspect.unwrap_or(inspect),
      server_lookup~,
    )
  }
  let (is_directory, text_mode, _) = locate_entity(
    context,
    path,
    if windows {
      Windows
    } else {
      Posix
    },
    inspect,
  )
  if (
      operand.has_suffix("/") ||
      operand.has_suffix("/.") ||
      (windows && operand.has_suffix("\\"))
    ) &&
    is_directory is Some(false) {
    raise LookupErrno("Not a directory")
  }
  text_mode
}

///|
pub async fn report_mode(
  path : String,
  context : @lib.Context,
  installed~ : Bool,
  server_lookup? : async (String) -> Bool,
) -> Unit {
  let text_mode = try {
    if path.is_empty() {
      raise LookupErrno("No such file or directory")
    }
    if installed {
      installed_mode(context, path)
    } else if @async.platform is Windows &&
      server_lookup is Some(_) &&
      absolute_drive_name(path) {
      // A drive-qualified name bypasses POSIX mounts until a link target
      // has to be fed back through the runtime mount table.
      installed_mode(context, path, inspect=native => {
        match native_entity(native) {
          Found(_) as entry => entry
          Follow(_, _) =>
            raise InstallationError(
              "-M requires a selected Cygwin installation for a link target",
            )
        }
      })
    } else {
      let needs_installation = InstallationError(
        "-M requires a selected Cygwin installation",
      )
      let parent_inspect = if server_lookup is Some(_) &&
        path.has_prefix("//") &&
        !path.has_prefix("///") {
        Some(native_entity)
      } else {
        None
      }
      installed_mode(
        context,
        path,
        inspect=_ => raise needs_installation,
        parent_inspect?,
        server_lookup=server_lookup.unwrap_or(_ => raise needs_installation),
      ) catch {
        InstallationError(_) => raise needs_installation
        err => raise err
      }
    }
  } catch {
    LookupErrno(reason) => {
      write_stderr_bytes(
        @filename.encode("cygpath: file '" + path + "' - " + reason + "\n"),
      )
      return
    }
    err => raise err
  }
  write_stdout_bytes(
    @filename.encode(path) +
    (if text_mode { b": text\n" } else { b": binary\n" }),
  )
}
