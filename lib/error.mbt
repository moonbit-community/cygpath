///|
/// Recoverable conversion failures. List indices and UTF-16 offsets are zero
/// based. Error payloads contain data, not preformatted CLI diagnostics.
#derive(Eq, Debug)
pub(all) suberror ConversionError {
  EmptyPath
  PathTooLong(String)
  InvalidDrivePrefix
  InvalidWindowsPrefix
  NotDirectory
  PathNotFound
  NoSuchDeviceOrAddress
  TooManyLinks
  InvalidPath(reason~ : String, offset~ : Int32)
  InvalidContext(field~ : String, reason~ : String)
  MissingContext(field~ : String)
  NetworkServerLookup(String)
  UnsupportedNamespace(String)
  UnrepresentablePath(component~ : String, reason~ : String)
  InvalidOptions(String)
  ListEntryError(index~ : Int32, ConversionError)
}

///|
pub extend ConversionError with Eq::{equal, not_equal}

///|
pub extend ConversionError with @debug.Debug::{to_repr}
