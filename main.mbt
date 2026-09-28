///|
async fn execute() -> Unit {
  match @cli.parse_args(@host.args()) {
    Help => @host.write_stdout(@cli.help_text())
    Version => @host.write_stdout(@cli.version_text())
    Convert(request) => {
      let converter = request.prepare()
      let count = match request.input() {
        Names(paths) => {
          for path in paths {
            @host.write_stdout(converter.convert(path) + "\n")
          }
          paths.length()
        }
        File(path) =>
          @host.stream_file(path, record => {
            @host.write_stdout(converter.convert(record) + "\n")
          })
      }
      if count == 0 && !request.ignore_missing() {
        raise @cli.MissingInput
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
