# 03 Path Semantics and Algorithm Contracts

Status: implemented portable conversion contract. P3 passed for the frozen pure
MoonBit, explicit-context matrix at `b32dd7448658bc251b216ba93a5c120ef54fdbc9`.
The [remote validation report](09-remote-validation.md) identifies the official
binaries, environments, raw observations, and remaining release gates. This is
a bounded compatibility result, not complete Cygwin or MSYS2 emulation.
See [01](01-upstream-and-scope.md) for behavioral sources and provenance.

## 1. Input, output, and profile

Library callers choose `InputSyntax::Windows` or `InputSyntax::Posix` explicitly.
There is no `Auto` library syntax. Output is `Windows`, `Mixed`, or `Posix`;
Mixed uses Windows path semantics and forward directory separators.

`Profile::Cygwin` and `Profile::Msys2` select the default drive prefix, mount
ordering, and mapped-root trailing-separator behavior. They never inspect the
host OS. Cygwin defaults to `/cygdrive`; MSYS2 defaults to `/`. A custom prefix
overrides that prefix without changing the profile's other rules. `/mnt/c`
does not enable WSL rules, and `/c` is not a drive branch in the default Cygwin
context.

The CLI supplies deterministic recognition around the explicit library API:
`-u` accepts ordinary Windows paths and preserves already-POSIX absolute
spellings; `-w/-m` use POSIX input with recognition of ordinary Windows forms.
`--from` overrides that recognition. Lists choose their delimiter before
converting members. The complete CLI rules are in [04](04-api-and-cli.md).

## 2. Path classification

Recognize namespace prefixes before ordinary path separators. The examples
below contain literal path characters, without shell escaping.

| Input | Classification and behavior |
| --- | --- |
| `C:\a`, `C:/a` | Drive-absolute Windows path; the drive must be ASCII A–Z |
| `C:a`, `C:` | Drive-relative syntax. POSIX output preserves `C:a` by default and maps bare `C:` to the drive root. Absolute conversion anchors both at the drive root. |
| `\a` | Windows path rooted on the current drive; resolution needs a drive-absolute `windows_cwd` |
| `\\server\share\a`, `//server/share/a` | Complete UNC path with a server and share under the network root |
| `\\?\C:\a`, `\??\C:\a` | Supported ordinary extended drive spelling |
| `\\?\UNC\server\share\a`, `\??\UNC\server\share\a` | Supported ordinary extended UNC spelling |
| `\\.\COM1` | Windows-to-POSIX returns `//./COM1` |
| `\\?\GLOBALROOT\Device\Null` | In `-u` the wide API rewrites this to the drive-rooted spelling `\BALROOT\Device\Null`; conversion to a native device remains unsupported |
| `/usr/bin` with POSIX source | POSIX absolute path; Windows output needs a drive mapping or mount |
| `a/b`, `../a` | Ordinary relative path; source grammar determines whether backslashes are separators |

Windows-to-POSIX accepts a server alone, including its optional trailing slash.
For POSIX input, exactly two slashes select the virtual network root. Its
Windows spelling contains two backslashes, its mode is binary, and reading
it as a directory with `-f //` yields no records. Three or more leading
forward slashes start at the local POSIX root. For example, `///usr/bin`
uses the same mount and parent-directory checks as `/usr/bin`. In a complete
UNC operand, repeated slashes between the server and share collapse to one.
[Cygwin normalization](https://github.com/cygwin/cygwin/blob/b11613e477c006b2ce0332463ed07f1118260e79/winsup/cygwin/path.cc#L267-L321)
· [MSYS2 normalization](https://github.com/msys2/msys2-runtime/blob/c770e1b9fa537fff9287c1fd40ebc84ac498fcb6/winsup/cygwin/path.cc#L267-L321)
· [Network directory lookup](https://github.com/cygwin/cygwin/blob/b11613e477c006b2ce0332463ed07f1118260e79/winsup/cygwin/fhandler/netdrive.cc#L554-L598).

For a server without a share, `-w //files` produces `\\files` and
`-w //files/` produces `\\files\`. Both results are independent of server
presence. `-M` reports binary mode. On Windows, opening the network directory
with `-f` uses the NT null object and yields no records, including for an
unresolved server. These Windows open cases await differential execution.
[Mount classification](https://github.com/cygwin/cygwin/blob/b11613e477c006b2ce0332463ed07f1118260e79/winsup/cygwin/mount.cc#L683-L703)
· [Network directory open](https://github.com/cygwin/cygwin/blob/b11613e477c006b2ce0332463ed07f1118260e79/winsup/cygwin/fhandler/netdrive.cc#L699-L713).

With `-am //files/`, a recognized server produces `//files` and a missing
one produces `//files/`. Library callers can supply this observation through
`Context::with_network_server("files", present=true)` or `present=false`.
The Windows CLI can confirm a hostname through the standard MoonBit socket
resolver. For WebDAV it queries the part preceding the first `@`. Canonical
numeric addresses are accepted directly. Other numeric spellings recognized
by MoonBit need a Windows observation. A failed hostname
lookup remains inconclusive because moonrun filters address families through
`AI_ADDRCONFIG`. The names `tsclient` and `wsl$` require a Windows network
provider query. When no observation is available the CLI reports the missing
capability. [Cygwin server presence](https://github.com/cygwin/cygwin/blob/b11613e477c006b2ce0332463ed07f1118260e79/winsup/cygwin/fhandler/netdrive.cc#L554-L598)
· [Directory suffix handling](https://github.com/cygwin/cygwin/blob/b11613e477c006b2ce0332463ed07f1118260e79/winsup/cygwin/path.cc#L1197-L1231)
· [moonrun resolver flags](https://github.com/moonbitlang/moon/blob/738607b3e4005a0343f09b744dbde641b38de64c/crates/moonrun/src/async_sys/socket.rs#L249-L263).

A UNC mount target requires both server and share. For a single
`\\?\UNC\server\share` operand the wide API strips the prefix before looking
for a mount. In a path list an unmatched member retains that prefix as
`//?/UNC/server/share`. The NT spelling `\??\UNC\server\share` similarly
retains `/??/UNC/` on an unmatched lookup. [Single-name lookup](https://github.com/cygwin/cygwin/blob/b11613e477c006b2ce0332463ed07f1118260e79/winsup/cygwin/mount.cc#L930-L948)
and [path-list API](https://github.com/cygwin/cygwin/blob/b11613e477c006b2ce0332463ed07f1118260e79/winsup/cygwin/path.cc#L4271-L4290).

For Windows or mixed output, Windows input resolves parents down to the
two-separator network root. For example, `-m '\\old\share\..\..\host'`
prints `//host`. A UNC share written without a trailing separator keeps
that spelling. Windows output also applies filename character mapping to
the server and share. [Windows normalization](https://github.com/cygwin/cygwin/blob/b11613e477c006b2ce0332463ed07f1118260e79/winsup/cygwin/path.cc#L1467-L1608)
· [UNC path rendering](https://github.com/cygwin/cygwin/blob/b11613e477c006b2ce0332463ed07f1118260e79/winsup/cygwin/path.cc#L489-L496).

POSIX input checks each named directory before cancelling it. For
`//host/share/../../other`, establishing that the share is a directory also
allows the consecutive ascent past `host`. An ordinary file gives `ENOTDIR`,
a missing entry gives `ENOENT`, and a native directory link changes where
ascent continues. On Windows the automatic CLI can check network parents
through the host filesystem without a selected installation. Offline library
conversion resolves share components lexically. Cancelling a server directly
requires its presence in the context. [POSIX parent checks](https://github.com/cygwin/cygwin/blob/b11613e477c006b2ce0332463ed07f1118260e79/winsup/cygwin/path.cc#L321-L381)
· [MSYS2 parent checks](https://github.com/msys2/msys2-runtime/blob/c770e1b9fa537fff9287c1fd40ebc84ac498fcb6/winsup/cygwin/path.cc#L322-L382).

For Windows source and POSIX output, a single leading forward slash is an
already-POSIX spelling: `/a/../b` remains `/a/../b`, including with `absolute=true`.
Backslashes in that spelling become forward slashes. This branch requires no
cwd or mount and also preserves `/dev/...` and `/proc/...` text. Explicit POSIX
source instead uses POSIX normalization and virtual-namespace validation.

The Cygwin terminal devices `/dev/tty` and `/dev/ptmx` keep their POSIX
spelling in Windows and mixed output, including in a path list. Both have
binary mode. Using either as a directory gives `ENOTDIR`. The CLI can convert
these names without opening the terminal. Session-specific consoles and
numbered PTYs still require runtime state.
[Device definitions](https://github.com/cygwin/cygwin/blob/b11613e477c006b2ce0332463ed07f1118260e79/winsup/cygwin/devices.in#L164-L177)
· [Special path conversion](https://github.com/cygwin/cygwin/blob/b11613e477c006b2ce0332463ed07f1118260e79/winsup/cygwin/path.cc#L465-L473).

Nine Cygwin devices share the Windows NT null object. These are `/dev/null`,
`zero`, `full`, `random`, `urandom`, `windows`, `mixer`, `dsp` and
`clipboard` under `/dev`. The host records presence using `core/async/fs.kind`.
An explicit library context can supply the observation through `nt_null`.
A missing object gives `ENXIO` on direct lookup. An inconclusive observation
leaves availability unknown. All nine have binary mode when present. Only
`/dev/null` uses the NT null object's native read behavior for `-f`.
[Device mappings](https://github.com/cygwin/cygwin/blob/b11613e477c006b2ce0332463ed07f1118260e79/winsup/cygwin/devices.in#L165-L182)
· [Existence check](https://github.com/cygwin/cygwin/blob/b11613e477c006b2ce0332463ed07f1118260e79/winsup/cygwin/path.cc#L788-L800).

The library returns the runtime spelling `\\.\GLOBALROOT\Device\Null` for
Windows output. The CLI then checks the encoded bytes for an NT device prefix.
UTF-8 output needs DOS alias lookup in the current Windows session. With IBM037
the encoded prefix bypasses that lookup in the official CLI, so the port can emit
the encoded runtime spelling. The Windows differential covers the IBM037 bytes,
mode and null input for both profiles and awaits execution.
[Runtime prefix](https://github.com/cygwin/cygwin/blob/b11613e477c006b2ce0332463ed07f1118260e79/winsup/cygwin/globals.cc#L143-L146)
· [CLI lookup](https://github.com/cygwin/cygwin/blob/b11613e477c006b2ce0332463ed07f1118260e79/winsup/utils/cygpath.cc#L169-L270).

The 13 fixed files directly under `/proc`, including `version`, `uptime`
and `meminfo`, retain their names for Windows output. The directories `/proc`,
`/proc/net`, `/proc/sysvipc` and the three registry views also retain their
names. Registry hive names preserve the supplied case. A directory suffix
in `-w /proc/.` produces `/proc\`; `-aw /proc/.` produces `/proc`.
The file operand `/proc/version/` returns `ENOTDIR`, while
`/proc/version/child` returns `ENOENT`. PID entries, `self`, `mounts`,
registry subkeys, IPv6 interface availability and IPC service state need
runtime information. [Proc entries](https://github.com/cygwin/cygwin/blob/b11613e477c006b2ce0332463ed07f1118260e79/winsup/cygwin/fhandler/proc.cc#L57-L83)
· [Registry lookup](https://github.com/cygwin/cygwin/blob/b11613e477c006b2ce0332463ed07f1118260e79/winsup/cygwin/fhandler/registry.cc#L310-L352).

## 3. Context validity and immutability

`Context::new` accepts a profile, drive prefix, mounts in declaration order,
optional POSIX/Windows cwd, and per-drive cwd metadata. It validates inputs and
copies mutable collections. Context and Mount fields are private; conversions
do not mutate them or consult cwd, environment, registry, fstab, or the real
mount table.

- A drive prefix must be an absolute, dot-free POSIX path. Trailing separators
  are normalized. A physical directory such as `/dev/drives` can serve as
  the prefix. Virtual devices and the proc namespace are reserved.
- Mount sources must be absolute, dot-free POSIX paths; targets must be
  drive-absolute or complete UNC paths without `.` or `..`. Supported ordinary
  extended target spellings are parsed into those ordinary roots.
- Ordinary names under `/dev` use the installation's filesystem and mounts.
  For example, mounting `D:/files` at `/dev/local` makes `/dev/local/names`
  available to both path conversion and `-f`. Device names are case-sensitive
  and have bounded decimal ranges. `ttyS127` names a serial device, while
  `ttyS128` and `ttyS01` use ordinary filesystem lookup. The disk namespace
  covers whole drives `sda` through `sddx` and partitions 1 through 63.
  Resolving these names requires knowing which Windows disks exist.
  [Cygwin device names](https://github.com/cygwin/cygwin/blob/b11613e477c006b2ce0332463ed07f1118260e79/winsup/cygwin/devices.in#L160-L192)
  · [Disk lookup](https://github.com/cygwin/cygwin/blob/b11613e477c006b2ce0332463ed07f1118260e79/winsup/cygwin/devices.in#L263-L327).
- Unscoped explicit mounts require unique POSIX names and cannot overlap the
  configured drive-prefix subtree. An installation table can retain one user
  and one system entry at the same name. A native target can map back to a
  mount underneath the drive prefix, while forward conversion follows the
  drive. A scoped installation mount at `/dev/tty` likewise retains its
  Windows-to-POSIX mapping. Forward lookup of the exact name selects the
  terminal. A bind source is matched as a whole, so `/dev/tty/sub` uses the
  declared mount to construct the native source of the bind.
  With prefix `/`, only single-letter drive branches and their descendants are
  reserved; `/`, `/usr`, and other ordinary mount points remain available.
- Cwds must be absolute in their source syntax and are normalized lexically.
  A UNC Windows cwd supports ordinary relative resolution but cannot supply a
  current drive for `\name`.
- `drive_cwds` keys are single ASCII drive letters, unique after case folding.
  Each value must be absolute on that same drive. These entries are **validated
  metadata only**: they do not select conversion bases. Cygpath drive-relative
  conversion uses the drive-root rule described below.

Omitting cwd or mounts is valid until a requested conversion needs them.
The host parses fstab. The library takes the mount declarations, their mode
and their optional user/system ownership as explicit inputs.

## 4. Mapping, profile ordering, and case

POSIX-to-Windows conversion follows `/proc/cygdrive` to the configured drive
prefix before resolving later components. With prefix `/media/drives`,
`/proc/cygdrive/../other` resolves to `/media/other`. The prefix directory
itself takes its Windows spelling from its enclosing mount. With prefix `/`,
multi-letter children such as `/proc/cygdrive/etc` use the ordinary mounts.
[Cygwin link target](https://github.com/cygwin/cygwin/blob/b11613e477c006b2ce0332463ed07f1118260e79/winsup/cygwin/fhandler/proc.cc#L1974-L1980)
· [Mount lookup](https://github.com/cygwin/cygwin/blob/b11613e477c006b2ce0332463ed07f1118260e79/winsup/cygwin/mount.cc#L730-L785).

A malformed drive component under a nonempty prefix raises `InvalidDrivePrefix`.
For example, `/p3-drives/cat/file` fails with prefix `/p3-drives`, while
`/p3-drives-extra/cat/file` uses its enclosing mount. Missing ordinary
root/mount context raises `MissingContext(field="root or mount")`.

Windows-to-POSIX conversion tries explicit mounts first. An unmatched absolute
drive uses the configured prefix, or `/proc/cygdrive` when requested through
`UnixPrefix::ProcCygdrive`. `ProcCygdrive` never bypasses an explicit mount.
Unmatched UNC paths retain UNC spelling with forward separators.

All mapping matches end at component boundaries: `/usr` does not match `/usr2`,
and `C:\work` does not match `C:\workspace`. Ordering is profile-specific:

| Profile | POSIX-to-Windows order | Windows-to-POSIX order |
| --- | --- | --- |
| Cygwin | Installed POSIX name in descending UTF-8 byte length, then byte spelling | Installed native name in descending UTF-8 byte length, then byte spelling |
| MSYS2 | Native target UTF-8 byte length ascending, native byte spelling as tie breaker, followed by the pinned runtime's POSIX-prefix ordering pass | Descending POSIX-length minus native-length in UTF-8 bytes, then POSIX byte spelling |

On a spelling tie in the installed table, the runtime comparator reads the
right-hand entry's user/system flag. The pinned newlib sort preserves the
result even for several aliases of the same ownership. A Cygwin table with
no ownership supplied uses component-prefix and declaration priority.

The MSYS2 POSIX-prefix pass has equal comparisons for unrelated mounts. Its
observable ordering is reproduced with the pinned newlib sorting behavior;
substituting a stable generic sort would change some nested-mount results.
Equal native aliases with no ownership supplied start with their declaration
priority before the second ordering pass. Matching checks full component boundaries.
Consequently, the MSYS2 profile does not promise universal longest-prefix
selection. The real default/custom mount and alias cases are part of P3's
frozen evidence. See [the sorting provenance](../third_party/newlib/README.md).

Drive letters compare without ASCII case sensitivity and render uppercase in
Windows/Mixed output, lowercase in POSIX drive fallback. Other components retain
their spelling. Mounts default to `Sensitive`. `AsciiInsensitive` compares ASCII
letters without regard to case. `WindowsInsensitive` applies the Windows
uppercase table to individual UTF-16 units. The entire matched prefix must
also have the original mount prefix's UTF-8 byte length. For example, `ÄΣ`
matches `äσ`, while Greek final sigma `ς` stays distinct. The comparison
preserves the spelling of the unmatched suffix. Installation fstab entries
with `posix=0` select this policy. See [Cygwin's prefix boundary](https://github.com/cygwin/cygwin/blob/b11613e477c006b2ce0332463ed07f1118260e79/winsup/cygwin/path.cc#L189-L204)
and [bounded comparison](https://github.com/cygwin/cygwin/blob/b11613e477c006b2ce0332463ed07f1118260e79/winsup/cygwin/strfuncs.cc#L1375-L1394).

The root is an explicit mount. Supplying `/ → C:\cygwin64` does not create
`/usr/bin`, `/usr/lib`, or any other alias. Callers must supply those mappings.

When the CLI reads an installation's ordinary fstab rows, it normalizes drive
and UNC sources without looking up their directories. For example,
`D:/missing/../tools` mounts `D:/tools`. A POSIX mount point such as
`/etc/../tools` requires `/etc` to resolve to a directory in the table built
so far. A missing or non-directory parent or a drive-relative source such as
`D:tools` skips the row. Reading continues even when the table is full until
a valid insertion needs a new slot. See [mount admission](https://github.com/cygwin/cygwin/blob/b11613e477c006b2ce0332463ed07f1118260e79/winsup/cygwin/mount.cc#L1466-L1535)
and [fstab error handling](https://github.com/cygwin/cygwin/blob/b11613e477c006b2ce0332463ed07f1118260e79/winsup/cygwin/mount.cc#L1269-L1282).

## 5. Relative resolution and normalization

In the portable library, ordinary relative paths preserve `.` and `..` without an absolute request.
Absolute resolution joins the applicable explicit cwd, normalizes in that path
space, then maps and renders. This is lexical conversion: no file existence,
symlink, junction, or realpath query occurs.

With an installed Cygwin context, the CLI checks ordinary POSIX directory
components before crossing `..` in Windows/mixed output and in the argument
to `-f`. For example, if `/bin/link` points to `/work/deep`, the name
`/bin/link/../files` resolves through `/work/files`. A missing directory
before `..` produces ENOENT. A regular file there produces ENOTDIR. The
Windows-to-POSIX branch uses mount conversion directly. See the upstream
[parent lookup](https://github.com/cygwin/cygwin/blob/b11613e477c006b2ce0332463ed07f1118260e79/winsup/cygwin/path.cc#L333-L378)
and [direction-specific conversion](https://github.com/cygwin/cygwin/blob/b11613e477c006b2ce0332463ed07f1118260e79/winsup/cygwin/path.cc#L3986-L4066).

When an installed relative operand maps back into the native working directory,
the CLI compares that directory using the selected mount's case policy. A
`posix=0` alias targeting `D:\WORK` can therefore return `Leaf.exe` from
`D:\Work`. A sibling such as `D:\Workshop` keeps its absolute name. Bind mounts
inherit the source policy, and drive-prefix paths use the cygdrive entry's
policy. The snapshot does not query the additional system-wide or filesystem
case settings used by Cygwin. See [working directory comparison](https://github.com/cygwin/cygwin/blob/b11613e477c006b2ce0332463ed07f1118260e79/winsup/cygwin/path.cc#L419-L443)
and [runtime case policy](https://github.com/cygwin/cygwin/blob/b11613e477c006b2ce0332463ed07f1118260e79/winsup/cygwin/path.cc#L1260-L1301).

For installed Windows/mixed output the CLI tries the exact final name first.
An absent `tool` or `tool.conf` can match `tool.exe` or `tool.conf.exe`,
respectively. A directory with an appended suffix is skipped. The same rules
apply to each path-list member and file record. An existing native symlink at
the leaf keeps its spelling. A trailing separator requests a directory and
requires resolving that link. A missing name below a native directory link
can also require resolving the link target. An ordinary Explorer shortcut
keeps its `.lnk` name. Looking up `report` skips an ordinary `report.lnk`.
The Cygwin shortcut check uses the Shell Link CLSID, flags, normal show
mode, and a nonempty description. On Windows a successful write-access
check rules out the read-only attribute for a matching regular file.
An unsuccessful check leaves that attribute unknown. Following a matching
Cygwin shortcut or a system-file symlink still needs Windows attributes.
[Shell Link header](https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-shllink/c3376b21-0931-45e4-b2fc-a48ac0e60d15) and
[Cygwin shortcut recognition](https://github.com/cygwin/cygwin/blob/b11613e477c006b2ce0332463ed07f1118260e79/winsup/cygwin/path.cc#L2364-L2423).
[Cygwin suffix scan](https://github.com/cygwin/cygwin/blob/b11613e477c006b2ce0332463ed07f1118260e79/winsup/cygwin/path.cc#L2902-L3007)
and [native link handling](https://github.com/cygwin/cygwin/blob/b11613e477c006b2ce0332463ed07f1118260e79/winsup/cygwin/path.cc#L1040-L1106).

If the resulting relative Windows name reaches 260 UTF-16 code units, the
installed converter looks up the original operand again in absolute mode.
This lookup follows the final native link and probes the exact basename
without adding `.exe`. An explicit `-a` performs the ordinary lookup from
the start and can therefore return a different name.
[Cygwin wide conversion](https://github.com/cygwin/cygwin/blob/b11613e477c006b2ce0332463ed07f1118260e79/winsup/cygwin/path.cc#L3986-L4008).

| Library request | Base or result |
| --- | --- |
| Ordinary relative input, `absolute=false` | No cwd, except the long Windows-output fallback below |
| POSIX relative input, `absolute=true` | `posix_cwd`; Windows output also needs its mapping |
| Windows ordinary relative input, `absolute=true` | `windows_cwd` |
| `C:a`, `absolute=false` | Preserve `C:a` for all three output formats |
| `C:`, `absolute=false` | POSIX output maps the drive root. Windows/Mixed output preserves `C:`. |
| `C:a` or `C:`, `absolute=true` | Resolve from `C:\` |
| `\a` to Windows/Mixed, `absolute=false` | Preserve its current-drive-rooted form |
| `\a` to POSIX, or with `absolute=true` | Take the drive from drive-absolute `windows_cwd` |

The CLI's natural recognition additionally treats bare `C:` and absolute
Windows-output requests for `C:child` as literal POSIX-relative names, matching
the official command behavior. This differs deliberately from an explicitly
Windows library request; [04](04-api-and-cli.md) gives examples.

Windows-to-POSIX normalizes the whole UNC name for mount lookup. Given a mount
from `//server/share` to `/net`, `//server/old/../share/file` yields `/net/file`.
An unmatched name retains its original traversal, repeated separators and
trailing slash. Relative Windows input without an absolute request retains
its slashified spelling too. For a matched mount, `//server/share/.` yields
`/net` and `//server/share/sub/.` yields `/net/sub/`. A terminal dot or parent
leaves a separator in the normalized suffix below the mount. An exact mount
takes a trailing slash only when the operand ends in a separator. At the
POSIX root this yields `//` in Cygwin and `/` in MSYS2.
[Windows normalization](https://github.com/cygwin/cygwin/blob/b11613e477c006b2ce0332463ed07f1118260e79/winsup/cygwin/path.cc#L1467-L1608)
and [mount lookup and fallback](https://github.com/cygwin/cygwin/blob/b11613e477c006b2ce0332463ed07f1118260e79/winsup/cygwin/mount.cc#L995-L1073).
The [MSYS2 mount lookup](https://github.com/msys2/msys2-runtime/blob/c770e1b9fa537fff9287c1fd40ebc84ac498fcb6/winsup/cygwin/mount.cc#L1019-L1033)
checks whether the mount point already ends in a slash.

Trailing-separator intent is determined before normalization. In the Cygwin
profile, the slash in bare POSIX `/` expresses the root and is not an optional
suffix: mapping it to `C:\root` yields `C:\root`. Mapping to a drive root
retains its required separator. A bare UNC share mapped to `/` keeps its
spelling in Cygwin. A non-root input `/folder/../` retains its
explicit trailing separator and can therefore yield `C:\root\`. MSYS2 adds a
trailing separator when an empty POSIX-root component sequence maps through a
mount, including the observed `-w /` case. Neither profile trims path spaces.

## 6. Long paths

Windows/Mixed conversion checks input components for the 255 UTF-16-unit limit
and raises `PathTooLong(original_path)` when exceeded. POSIX output does not
apply that Windows component check. Thus both an argument and a file-input chunk
can convert a longer Windows component to POSIX text.

Ordinary rendered drive/UNC paths of at least 260 UTF-16 units gain `\\?\`
or `\\?\UNC\` prefixes; Mixed uses forward slashes in that prefix as well.
Long relative Windows/Mixed output is retried as an absolute request using the
explicit source cwd. `-r` is a CLI modifier for requesting a root-local prefix
on a single Windows result even when short.

For `-u` on a single Windows input, cygpath counts the terminating NUL when
preparing the wide argument. At 259 UTF-16 units it adds the extended prefix.
A drive path or backslash UNC name keeps its meaning. For other spellings,
the wide API treats the three units after the prefix as the UNC marker and
replaces them with a backslash. With a cwd on drive D, a 259-unit name
starting with `abc` therefore yields `/cygdrive/d/` followed by the text
after `abc`. The same name at 258 units stays relative. List mode (`-pu`)
keeps the relative member at both lengths. A supplementary character
contributes two UTF-16 units. If the wide API's three-unit rewrite splits
a surrogate pair, the CLI writes the three bytes for the remaining low
surrogate. The text API reports `UnrepresentablePath` when these bytes reach
the output. [Newlib wide encoding](https://github.com/cygwin/cygwin/blob/b11613e477c006b2ce0332463ed07f1118260e79/newlib/libc/stdlib/wctomb_r.c#L102-L125).
The library takes its caller's path directly;
the CLI applies the threshold to arguments and file records. [CLI wide argument](https://github.com/cygwin/cygwin/blob/b11613e477c006b2ce0332463ed07f1118260e79/winsup/utils/wide_path.h#L19-L38)
and [runtime prefix handling](https://github.com/cygwin/cygwin/blob/b11613e477c006b2ce0332463ed07f1118260e79/winsup/cygwin/mount.cc#L930-L948).

The narrow path parser accepts an extended drive root or absolute drive name
and an uppercase `UNC` marker followed by a separator. A drive-relative
member such as `\\?\C:name` fails in a list, even though the single-name
wide API strips its prefix and returns `C:name` under `-u`. With `-au`,
it maps to `/cygdrive/c/name`. [Windows normalization](https://github.com/cygwin/cygwin/blob/b11613e477c006b2ce0332463ed07f1118260e79/winsup/cygwin/path.cc#L1474-L1486).

This is not a universal guarantee for every Windows path length or filesystem.
The frozen threshold corpus distinguishes valid multi-component 259/260/261
paths from overlong individual components, and covers relative resolution and
the file reader's 8192-byte boundary. Inputs outside that validated matrix need
additional evidence before broader compatibility claims.

## 7. PATH lists

`convert_list` selects the input delimiter from explicit source syntax:
Windows uses `;`, POSIX uses `:`. Output uses `:` for POSIX and `;` otherwise.
Choose the delimiter before processing members; a drive colon inside a declared
POSIX list is still a separator. No CSV or shell quote decoding occurs.

`recognize_windows=false` is the library default. With `recognize_windows=true`,
POSIX-list members containing backslashes use Windows grammar after splitting;
single-backslash-rooted members also resolve against the supplied current drive.
The CLI enables this for natural recognition. It never changes the whole list's
delimiter based on one member.

- POSIX-to-Windows/Mixed converts every empty member as `.`.
- Windows-to-POSIX skips empty members.
- Same-syntax library conversions preserve empty-member positions.
- The library accepts an empty list string according to those rules. The CLI
  rejects an empty NAME/record before list conversion, unless `-i` skips it.

Member order is retained and results are not deduplicated. Joining does not
escape a target delimiter already present in path content and does not promise
lossless serialization; callers needing structured results should keep arrays
and call `convert` themselves. One invalid member raises
`ListEntryError(index, cause)`, with an original zero-based index counting empty
members, and returns no partial list.

The CLI preserves the structured cause but uses the official whole-operand
diagnostic for known runtime-style list failures. In the pinned runtime, a
nested conversion return of `-1` becomes the list wrapper's errno, producing
`Unknown error -1` for the tested length and invalid-drive-prefix list failures.
This does not turn unsupported project namespaces into official runtime errors.

## 8. Characters and namespace limits

The core accepts Unicode strings, rejects NUL and unpaired UTF-16 surrogates,
and does not normalize Unicode to NFC/NFD. Windows filename output maps ASCII
controls U+0001–U+001F and `" * : < > ? |` to U+F000 plus the ASCII value.
Windows-to-POSIX reverses those mappings and U+F020/U+F02E for space/dot.
Under C.UTF-8, each U+F080–U+F0FF contributes its low byte. Adjacent escapes
can form a Unicode name that matches a configured Windows mount. POSIX mount
targets keep their own UTF-8 spelling. The CLI and the library method
`Context::windows_to_posix_bytes` preserve the resulting bytes for single
paths and lists. Text methods raise `UnrepresentablePath` if the result
contains invalid UTF-8. [Cygwin filename encoding](https://github.com/cygwin/cygwin/blob/b11613e477c006b2ce0332463ed07f1118260e79/winsup/cygwin/strfuncs.cc#L972-L997).

Ordinary component spellings such as `CON`, trailing dots, and trailing spaces
are preserved. A literal backslash in an explicitly POSIX component cannot be
rendered as an ordinary Windows filename and raises `UnrepresentablePath`.
Configured UNC mount targets require valid server and share components. CR/LF
are path content where allowed; the CLI does not impose a second blanket
line-break rejection on argv or converted output.

The `dos` fstab option changes the Windows spelling at component boundaries.
For a mount `/dos` pointing to `D:/work`, `-m /dos/name.` ends in
`name` followed by U+F02E. A leading space after the mount directory
becomes U+F020. Regular ntfs mounts preserve these literal characters.
The same selection applies to file lookup and to bind mounts that inherit
the source flags. [Cygwin native path conversion](https://github.com/cygwin/cygwin/blob/b11613e477c006b2ce0332463ed07f1118260e79/winsup/cygwin/path.cc#L467-L523)

There is no tilde, variable, glob, or URI expansion. Path content is never
executed. The portable library performs no host queries. The installed CLI
consults filesystem entries for Windows output and mount modes as described
above. 8.3 names, actual filename case, system directories, process HANDLEs
and arbitrary device namespaces remain outside its coverage.
Section 2 describes the supported physical and virtual entries under `/dev`
and `/proc`. Section 4 describes the configurable cygdrive link.

## 9. Public API examples and invariants

The default Context is Cygwin with prefix `/cygdrive`, no mounts, and no cwd.

| Source → target | Input / additional context | Result |
| --- | --- | --- |
| Windows → POSIX | `C:\work\a.txt` | `/cygdrive/c/work/a.txt` |
| Windows → Mixed | `c:\work\a.txt` | `C:/work/a.txt` |
| POSIX → Windows | `/cygdrive/d/a` | `D:\a` |
| POSIX → Mixed | `/proc/cygdrive/d/a` | `D:/a` |
| POSIX → Windows | `/usr/bin`, no mounts | `MissingContext` |
| POSIX → Windows | `/usr/bin`, `/ → C:\cygwin64` | `C:\cygwin64\usr\bin` |
| Windows → POSIX | `C:a`, default options | `C:a` |
| Windows → POSIX | `C:a`, `absolute=true` | `/cygdrive/c/a` |
| Windows → POSIX | `\\?\C:\a` | `/cygdrive/c/a` |
| Windows → POSIX | `\\server\share\..\file` | `//server/share/../file` |
| POSIX → Windows | `a/../b`, `absolute=false` | `a\..\b` |
| POSIX → Windows | `/c/a`, profile Msys2 | `C:\a` |
| Windows → POSIX list | `C:\a;;D:\b;` | `/cygdrive/c/a:/cygdrive/d/b` |
| POSIX → Windows list | `/cygdrive/c/a::/cygdrive/d/b` | `C:\a;.;D:\b` |

Identical input, Context, and options give identical results across backends.
Core calls preserve Context and caller-owned collections; list failure is
atomic; mount matching respects component boundaries. Round trips apply only
to canonical paths in a fixed, unambiguous mapping and character domain.
Aliases, encoded filename characters, case normalization, delimiters, and
empty members rule out a universal string round-trip identity.
