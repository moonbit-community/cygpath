///|
/// Converts a PATH list atomically. Windows lists use `;`, POSIX lists use `:`.
/// Windows-to-POSIX skips empty entries; POSIX-to-Windows treats them as `.`.
/// Same-syntax conversions retain empty entries. Errors carry the original
/// zero-based entry index, including preceding empty entries.
pub fn Context::convert_list(
  self : Context,
  paths : String,
  from~ : InputSyntax,
  to~ : OutputFormat,
  absolute? : Bool = false,
  recognize_windows? : Bool = false,
  unix_prefix? : UnixPrefix = Configured,
) -> String raise ConversionError {
  validate_options(to, unix_prefix)
  let input_sep = if from == Windows { ";" } else { ":" }
  let output_sep = if to == Posix { ":" } else { ";" }
  let output : Array[String] = []
  for index, entry in paths.split(input_sep).iter2() {
    let value = entry.to_owned()
    if value.is_empty() {
      if from == Windows && to == Posix {
        continue
      }
      if (from == Windows && to != Posix) || (from == Posix && to == Posix) {
        output.push("")
        continue
      }
    }
    try {
      let value = if value.is_empty() { "." } else { value }
      let entry_syntax : InputSyntax = if recognize_windows &&
        from == Posix &&
        value.contains_char('\\') {
        Windows
      } else {
        from
      }
      let converted = self.convert(
        value,
        from=entry_syntax,
        to~,
        absolute=absolute ||
          (
            recognize_windows &&
            entry_syntax == Windows &&
            value.has_prefix("\\") &&
            !value.has_prefix("\\\\")
          ),
        unix_prefix~,
      )
      output.push(converted)
    } catch {
      error => raise ListEntryError(index~, error)
    }
  }
  output.join(output_sep)
}
