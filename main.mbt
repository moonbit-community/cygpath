///|
async fn write_record(action : @cli.RecordAction, codepage : Int) -> Bool {
  match action {
    Output(text) => {
      @host.write_stdout_bytes(@encoding.encode(text, codepage) + b"\n")
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
      let converter = request.prepare()
      match request.input() {
        Names(paths) => {
          if paths.is_empty() && !request.ignore_missing() {
            raise @cli.MissingInput
          }
          for path in paths {
            let action = converter.convert_operand(path)
            if !write_record(action, converter.codepage()) {
              break
            }
          }
        }
        File(path) => {
          let _ = @host.stream_file_until(path, record => {
            let action = converter.convert_file_record(record)
            write_record(action, converter.codepage())
          })
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
        @cli.CliError::_ as error => (error.exit_code(), error.diagnostic())
        @host.HostError::_ as error => (1, error.diagnostic())
        _ => (1, "cygpath: internal-error: unexpected runtime failure")
      }
      // A failed diagnostic write cannot make a failed command successful.
      @host.write_stderr(diagnostic + "\n") catch {
        _ => ()
      }
      @host.exit(code)
    }
  }
}
