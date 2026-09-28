///|
/// The input grammar, independent of the machine running the conversion.
pub(all) enum InputSyntax {
  Windows
  Posix
} derive(Eq, Debug)

///|
pub extend InputSyntax with Eq::{equal, not_equal}

///|
pub extend InputSyntax with @debug.Debug::{to_repr}

///|
/// Mixed paths use Windows semantics with forward slashes.
pub(all) enum OutputFormat {
  Windows
  Mixed
  Posix
} derive(Eq, Debug)

///|
pub extend OutputFormat with Eq::{equal, not_equal}

///|
pub extend OutputFormat with @debug.Debug::{to_repr}

///|
/// Selects mount ordering and default drive prefix without detecting the host.
pub(all) enum Profile {
  Cygwin
  Msys2
} derive(Eq, Debug)

///|
pub extend Profile with Eq::{equal, not_equal}

///|
pub extend Profile with @debug.Debug::{to_repr}

///|
/// Controls unmatched drive paths; explicit mounts always take precedence.
pub(all) enum UnixPrefix {
  Configured
  ProcCygdrive
} derive(Eq, Debug)

///|
pub extend UnixPrefix with Eq::{equal, not_equal}

///|
pub extend UnixPrefix with @debug.Debug::{to_repr}

///|
/// Mount comparison policy. ASCII folding does not implement Windows Unicode
/// case equivalence. Drive letters are always compared without case.
pub(all) enum MountCase {
  Sensitive
  AsciiInsensitive
} derive(Eq, Debug)

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
}

///|
/// An immutable snapshot of the path environment. No conversion reads the host.
pub struct Context {
  priv profile : Profile
  priv drive_prefix : Array[String]
  priv posix_mounts : Array[Mount]
  priv windows_mounts : Array[Mount]
  priv posix_cwd : ParsedPath?
  priv windows_cwd : ParsedPath?
}

///|
priv enum PathRoot {
  Relative
  PosixRoot
  DriveAbsolute(String)
  DriveRelative(String)
  WindowsRooted
  Unc(String, String)
} derive(Eq)

///|
priv struct ParsedPath {
  root : PathRoot
  components : Array[String]
  trailing : Bool
}
