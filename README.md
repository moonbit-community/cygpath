# cygpath for moonx

A pure MoonBit library and command-line tool for converting between Windows and
Cygwin/MSYS2-style POSIX paths.

```sh
moonx ZSeanYves/cygpath -u 'C:\work\demo.txt'
moonx ZSeanYves/cygpath -w --root 'C:\cygwin64' /usr/bin
moonx ZSeanYves/cygpath -h
```

Supports POSIX (`-u`), Windows (`-w`), and mixed (`-m`) output; absolute conversion
(`-a`); path lists (`-p`); `/proc/cygdrive` output (`-U`); and root-local paths
(`-r`). Drive, UNC, relative, and ordinary extended paths are supported, with
lexical normalization, long-path handling, and Cygwin filename character mapping.
Cygwin and MSYS2 profiles accept explicit roots, mounts, drive prefixes, and
working directories.

For a server without a share, `-m //files/` prints `//files/` and `-M //files`
reports binary mode. With `-am //files/` the trailing slash depends on whether
Windows recognizes the server. [Network path rules](docs/03-path-semantics.md#2-path-classification)

Input can come from arguments, files (`-f FILE`), or stdin (`-f -`), with
per-record options (`-o`) and skipping empty operands (`-i`). Windows/mixed output
supports UTF-8, UTF-7 (65000), GB18030-2000 (54936), Windows Symbol (42),
the three Japanese ISO-2022 variants (50220–50222), ISO-2022-KR (50225), ISO-2022-CN (50227/50229),
HZ-GB-2312 (52936), ISCII (57002–57011), and 115 legacy code pages, including Windows JIS (20932), GB2312 (20936),
logical Hebrew (38598) and EUC Korean (51949). The CLI targets only
linear-memory Wasm for `moonx` and uses `moonbitlang/x@0.5.9` for file identity. Import
`ZSeanYves/cygpath/lib` to use the conversion library without host I/O.

The five Windows GSM pages (55000–55004) encode `@` as a zero byte.
For example, `-wC55000 A@B` prints `A` followed by LF. A converted name
without a zero byte produces an explicit error. [GSM output rules](docs/04-api-and-cli.md#8-output-encoding-and-failure-ordering)

On Windows, select an installed Cygwin once in PowerShell:

```powershell
$env:CYGPATH_ROOT = 'C:\cygwin64'
moonx ZSeanYves/cygpath -w /usr/bin/sh
moonx ZSeanYves/cygpath -am .
```

For MSYS2, set `CYGPATH_ROOT` to its installation directory and run
`moonx ZSeanYves/cygpath --profile=msys2 -w /bin/sh`. The CLI checks for
the selected runtime DLL, reads `etc/fstab`, and maps the process working
directory. Cygwin adds its automatic `/usr/bin` and `/usr/lib` mounts.
MSYS2 maps `/bin` to `usr/bin` unless the system fstab defines it. Its
distributed fstab sets the drive prefix to `/`, so `D:\work` becomes
`/d/work`. Set `CYGPATH_USER` to read `etc/fstab.d/<name>` for that account.
Explicit mounts, `--root`, prefix or cwd select the offline model.
In installation mode the filename after `-f` uses the same mappings.
`-f names` reads an exact match first, then tries `names.exe` when the name
is absent. A readable directory supplies zero records. `-f -` reads stdin.
A `usertemp` entry tries `TMP`, `TEMP`, then `USERPROFILE`, skipping empty
values and values longer than 260 UTF-16 units. If none qualifies, it uses
the running Windows installation directory. Relative values use the Windows
process working directory.
For example, `TMP=..\cache` under `C:\work\app` mounts `C:\work\cache`,
even if that directory is missing. A relative value that expands beyond 260
UTF-16 units raises an installation error. An ordinary `bind`
entry uses the source mapping in effect at that line, without following symlinks.
Mounts marked `posix=0` use Windows uppercase mappings for comparisons.
If a user mount and a later system mount share a POSIX name, both native
paths remain available for reverse conversion. Forward conversion and
`bind` use the entry selected by the current profile.
When a relative operand reaches the working directory through such a mount,
Windows and mixed output keep the relative name even if the mount spells the
directory differently, for example `C:\Work` and `C:\WORK`.
For Windows or mixed output, the CLI checks the final name on disk. If
`/usr/bin/sh` is absent and `sh.exe` is a regular file, it returns the path
to `sh.exe`. An exact match takes priority, including an exact directory.
An ordinary Windows shortcut keeps its `.lnk` extension. For example,
an Explorer shortcut named `report.lnk` does not supply a file named `report`.
For ordinary POSIX paths containing `..`, Windows/mixed output and `-f` check
the preceding directory on disk. If that directory is a resolvable native
link, traversal continues from the target's parent. This also applies to
POSIX path-list members and per-line options.
On Windows, `-am sub\tool` uses the process working directory and finds
`sub\tool.exe` when that executable supplies the missing name. `-M` can
query paths such as `sub\file` or `C:/work/file` without `CYGPATH_ROOT`. A native link can require the installation mount table
to determine its target’s mode.
On an `fstab` mount with the `dos` option, Windows output uses U+F020 and
U+F02E for affected filename-edge spaces and dots. File input uses the same
native spelling, so `-f /dos/records.` can open the encoded name on disk.
In installation mode, `-M NAME` reports the selected mount's text/binary
mode for ordinary files, directories, and missing names. It follows native
links that the host can resolve. Live session mounts, Cygwin shortcut/sysfile
links and dangling native links are not covered by this snapshot.

`-w /dev/tty` and `-w /dev/ptmx` preserve the device spelling, including
forward slashes. Both report binary mode with `-M`.
On Windows, the CLI checks the NT null device through the Wasm filesystem
API. When available, `-M /dev/null` reports binary mode and `-f /dev/null`
reads the device to EOF. The ordinary `-w /dev/null` spelling requires the
current session's DOS device aliases. Both official runtimes matched the Wasm
results for null-device mode and file input on Windows. [Windows comparison](docs/09-remote-validation.md#november-wasm-validation)
The fixed `/proc` files, including `/proc/version` and `/proc/uptime`, also
keep their names in Windows output. Process-specific paths and registry
values require Cygwin runtime state.

On Windows, `-wl` and `-ml` can expand a supplied alias and restore the
stored spelling of short-shaped ordinary names, including spaces, punctuation
and Unicode. For example, `-wl a+b.txt` prints `A+B.txt` when that is the
name on disk. A missing path keeps its entire converted spelling. For a live
native link supplied by an alias, the CLI can recover its own directory entry
when exactly one link in the parent resolves to that target and its identity
matches with link following disabled.

On Windows, `-d` and `-s` preserve the input spelling of an existing path
whose components already have unambiguous ASCII 8.3 names. This includes a
supplied DOS alias. For example, `-ws ReAdMe.TxT` prints `ReAdMe.TxT` even
when `README.TXT` has a different assigned alias. Dot operands and drive
roots are supported. A missing path exits with status 2. A component needing
conversion still requires its stored alternate name.
[Windows name lookup](https://github.com/moonbit-community/cygpath/issues/2)

On a Windows host, `-W` and `-S` query the running Windows installation and
print the Windows or system directory as a POSIX path. The same queries accept
`-F 0x24` and `-F 0x25`. On the standard fixed-folder layout, `-F 0x14`
selects Fonts, `-F 0x29` selects SysWOW64 on 64-bit Windows, and `-F 0x38`
selects Resources. Mounts and `-U` apply to each directory.
Cygwin and Wasm produced the same output for `-W`, `-US`, `-F044` and
`--folder=0x25` on the Windows runner. [Windows comparison](docs/09-remote-validation.md#november-wasm-validation)

Unsupported: automatic selection among installations; reading alternate 8.3
names; full Cygwin symlink resolution; raw Windows/mixed
system-directory output, redirected shell folders and closing real inherited handles; host-dependent device names
and general virtual-filesystem paths; automatic ANSI/OEM selection and CP29001. In C.UTF-8 file records, Windows and mixed
output map invalid filename bytes to their Windows private-use characters.
For example, a byte `ff` becomes U+F0FF. All three output formats accept
a supplementary character written as a CESU-8 surrogate pair in a file
record. An isolated surrogate unit produces an input error.

[Apache-2.0](LICENSE), with [Unicode](third_party/unicode/README.md),
[Microsoft](third_party/microsoft/README.md), [.NET](third_party/dotnet/README.md), and
[newlib](third_party/newlib/README.md) notices.
