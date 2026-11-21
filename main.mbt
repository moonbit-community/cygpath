///|
async fn write_record(
  action : @cli.RecordAction,
  converter : @cli.Converter,
  installation : @lib.Context?,
) -> Bool {
  match action {
    QueryFolder(folder) => {
      match converter.folder_output(folder, @host.system_folder) {
        Some(path) => @host.write_stdout_bytes(path + b"\n")
        None =>
          @host.write_stderr(
            "cygpath: failed to retrieve special folder path\n",
          )
      }
      true
    }
    QueryMode(path) => {
      @host.report_mode(
        path,
        converter.context,
        installed=installation is Some(_),
        server_lookup?=converter.server_lookup,
      )
      true
    }
    Output(text) => {
      @host.write_stdout_bytes(
        converter.encode_output(
          text,
          expand=@host.long_name,
          shorten=@host.short_name,
        ) +
        b"\n",
      )
      true
    }
    OutputBytes(bytes) => {
      @host.write_stdout_bytes(bytes + b"\n")
      true
    }
    Skip => true
    Stop(text) => {
      @host.write_stdout(text)
      false
    }
  }
}

///|
async fn execute() -> Unit {
  match @cli.parse_args(@host.args()) {
    Help => @host.write_stdout(@cli.help_text())
    Version => @host.write_stdout(@cli.version_text())
    ExitSuccess => ()
    Convert(request) => {
      let profile = request.installation_profile()
      let installation = match profile {
        Some(profile) => @host.installation_context(profile)
        None => None
      }
      let nt_null = if installation is None &&
        profile is Some(_) &&
        request.needs_device_probe() {
        @host.nt_null_presence()
      } else {
        None
      }
      let converter = request.prepare(
        installation?,
        nt_null?,
        server_lookup=@host.network_server_exists,
        lookup=@host.convert_installed,
      )
      match request.input() {
        Folder(folder) =>
          ignore(write_record(QueryFolder(folder), converter, installation))
        Names(paths) => {
          if paths.is_empty() && !request.ignore_missing() {
            raise @cli.MissingInput
          }
          for path in paths {
            let action = converter.convert_operand(path)
            if !write_record(action, converter, installation) {
              break
            }
          }
        }
        File(path) => {
          let source = if path == "-" { "stdin" } else { path }
          let virtual_context = if profile is Some(_) {
            Some(converter.context)
          } else {
            None
          }
          let _ = @host.stream_file_bytes_until(
            path,
            installation?,
            virtual_context?,
            (record, line) => {
              let action = converter.convert_file_bytes(record, source~, line~)
              write_record(action, converter, installation)
            },
          )
        }
      }
    }
  }
}

///|
async fn main {
  execute() catch {
    error => {
      let (code, diagnostic) = match error {
        @cli.CliError::_ as error =>
          (error.exit_code(), error.diagnostic_bytes())
        @host.HostError::_ as error => (1, @utf8.encode(error.diagnostic()))
        _ => (1, b"cygpath: internal-error: unexpected runtime failure")
      }
      // A failed diagnostic write cannot make a failed command successful.
      @host.write_stderr_bytes(diagnostic + b"\n") catch {
        _ => ()
      }
      @host.exit(code)
    }
  }
}
