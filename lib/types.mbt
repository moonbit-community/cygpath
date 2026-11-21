///|
/// A mapped operand identifies a native filesystem entry or a virtual node.
/// For a null-backed device, `native_input` identifies the POSIX null stream.
#derive(Eq, Debug)
pub(all) enum PathTarget[T] {
  Filesystem(T, text_mode~ : Bool)
  Virtual(directory~ : Bool)
  NetworkDirectory(String?)
  NullDevice(native_input~ : Bool)
}

///|
pub extend PathTarget with Eq::{equal, not_equal}

///|
pub extend PathTarget with @debug.Debug::{to_repr}

///|
pub type ModeCandidate = PathTarget[String]

///|
/// The input grammar, independent of the machine running the conversion.
#derive(Eq, Debug)
pub(all) enum InputSyntax {
  Windows
  Posix
}

///|
pub extend InputSyntax with Eq::{equal, not_equal}

///|
pub extend InputSyntax with @debug.Debug::{to_repr}

///|
/// Mixed paths use Windows semantics with forward slashes.
#derive(Eq, Debug)
pub(all) enum OutputFormat {
  Windows
  Mixed
  Posix
}

///|
pub extend OutputFormat with Eq::{equal, not_equal}

///|
pub extend OutputFormat with @debug.Debug::{to_repr}

///|
/// Selects mount ordering and default drive prefix without detecting the host.
#derive(Eq, Debug)
pub(all) enum Profile {
  Cygwin
  Msys2
}

///|
pub extend Profile with Eq::{equal, not_equal}

///|
pub extend Profile with @debug.Debug::{to_repr}

///|
/// Controls unmatched drive paths; explicit mounts always take precedence.
#derive(Eq, Debug)
pub(all) enum UnixPrefix {
  Configured
  ProcCygdrive
}

///|
pub extend UnixPrefix with Eq::{equal, not_equal}

///|
pub extend UnixPrefix with @debug.Debug::{to_repr}

///|
/// Mount comparison policy. ASCII folding does not implement Windows Unicode
/// case equivalence. Drive letters are always compared without case.
#derive(Eq, Debug)
pub(all) enum MountCase {
  Sensitive
  AsciiInsensitive
  WindowsInsensitive
}

///|
pub extend MountCase with Eq::{equal, not_equal}

///|
pub extend MountCase with @debug.Debug::{to_repr}

///|
/// A validated mapping. Its representation cannot be mutated by consumers.
pub struct Mount {
  priv posix : ParsedPath
  priv windows : ParsedPath
  priv case : MountCase
  priv text_mode : Bool
  priv dos_names : Bool
  system : Bool?
}

///|
/// An immutable snapshot of the path environment. No conversion reads the host.
pub struct Context {
  priv profile : Profile
  priv nt_null : Bool?
  priv network_servers : Map[String, Bool]
  priv drive_prefix : Array[String]
  priv drive_text_mode : Bool
  priv drive_dos_names : Bool
  priv drive_case : MountCase
  priv mounts : Array[Mount]
  priv posix_mounts : Array[Int32]
  priv windows_mounts : Array[Int32]
  priv posix_cwd : ParsedPath?
  priv windows_cwd : ParsedPath?
}

///|
#derive(Eq)
priv enum PathRoot {
  Relative
  PosixRoot
  DriveAbsolute(String)
  DriveRelative(String)
  WindowsRooted
  NetworkRoot
  NetworkServer(String)
  Unc(String, String)
}

///|
priv struct ParsedPath {
  root : PathRoot
  components : Array[String]
  trailing : Bool
}
