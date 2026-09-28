///|
/// Recoverable conversion failures. List indices and UTF-16 offsets are zero
/// based. Error payloads contain data, not preformatted CLI diagnostics.
pub(all) suberror ConversionError {
  EmptyPath
  InvalidPath(reason~ : String, offset~ : Int)
  InvalidContext(field~ : String, reason~ : String)
  MissingContext(field~ : String)
  UnsupportedNamespace(String)
  UnrepresentablePath(component~ : String, reason~ : String)
  InvalidOptions(String)
  ListEntryError(index~ : Int, ConversionError)
} derive(Eq, Debug)

///|
pub extend ConversionError with Eq::{equal, not_equal}

///|
pub extend ConversionError with @debug.Debug::{to_repr}
