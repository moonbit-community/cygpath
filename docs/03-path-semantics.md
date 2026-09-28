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
| `C:a`, `C:` | Drive-relative syntax; preserved for non-absolute Windows/Mixed library output, anchored at C's root for POSIX or absolute conversion |
| `\a` | Windows path rooted on the current drive; resolution needs a drive-absolute `windows_cwd` |
| `\\server\share\a`, `//server/share/a` | Complete UNC path; server/share are part of the root |
| `\\?\C:\a`, `\??\C:\a` | Supported ordinary extended drive spelling |
| `\\?\UNC\server\share\a`, `\??\UNC\server\share\a` | Supported ordinary extended UNC spelling |
| `\\.\COM1`, extended `GLOBALROOT` or other device forms | `UnsupportedNamespace` |
| `/usr/bin` with POSIX source | POSIX absolute path; Windows output needs a drive mapping or mount |
| `a/b`, `../a` | Ordinary relative path; source grammar determines whether backslashes are separators |

The supported extended prefixes are removed for ordinary drive/UNC conversion;
rendering later decides whether an extended output prefix is required.
Incomplete UNC forms such as `//` and `//server` remain unsupported. Complete
double-forward-slash UNC input is recognized in either source syntax and does
not use the POSIX root mount.

For Windows source and POSIX output, a single leading forward slash is an
already-POSIX spelling: `/a/../b` remains `/a/../b`, including with `absolute=true`.
Backslashes in that spelling become forward slashes. This branch requires no
cwd or mount and also preserves `/dev/...` and `/proc/...` text. Explicit POSIX
source instead uses POSIX normalization and virtual-namespace validation.

## 3. Context validity and immutability

`Context::new` accepts a profile, drive prefix, mounts in declaration order,
optional POSIX/Windows cwd, and per-drive cwd metadata. It validates inputs and
copies mutable collections. Context and Mount fields are private; conversions
do not mutate them or consult cwd, environment, registry, fstab, or the real
mount table.

- A drive prefix must be an absolute, dot-free POSIX path. Trailing separators
  are normalized. `/dev`, `/proc`, and their subtrees are not valid prefixes.
- Mount sources must be absolute, dot-free POSIX paths; targets must be
  drive-absolute or complete UNC paths without `.` or `..`. Supported ordinary
  extended target spellings are parsed into those ordinary roots.
- Duplicate POSIX mount points and mounts below `/dev` or `/proc` are rejected.
  Mounts overlapping the configured drive-prefix subtree are also rejected.
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
The library does not interpret fstab permissions, text/binary mode, or
user/system mount provenance. An external caller must supply resolved ordinary
mappings, including the intended declaration priority.

## 4. Mapping, profile ordering, and case

POSIX-to-Windows conversion first recognizes `/proc/cygdrive/<drive>`, then
branches under the configured drive prefix, then explicit mounts. A malformed
drive component under a nonempty configured prefix raises `InvalidDrivePrefix`;
it does not fall through to the root mount. `/p3-drives/cat/file` is therefore
different from `/p3-drives-extra/cat/file`. Missing ordinary root/mount context
raises `MissingContext(field="root or mount")`.

Windows-to-POSIX conversion tries explicit mounts first. An unmatched absolute
drive uses the configured prefix, or `/proc/cygdrive` when requested through
`UnixPrefix::ProcCygdrive`. `ProcCygdrive` never bypasses an explicit mount.
Unmatched UNC paths retain UNC spelling with forward separators.

All mapping matches end at component boundaries: `/usr` does not match `/usr2`,
and `C:\work` does not match `C:\workspace`. Ordering is profile-specific:

| Profile | POSIX-to-Windows order | Windows-to-POSIX order |
| --- | --- | --- |
| Cygwin | Longest matching POSIX component prefix, declaration order for equal priority | Longest matching Windows component prefix, declaration order for equal priority |
| MSYS2 | Native target UTF-8 byte length ascending, native byte spelling as tie breaker, followed by the pinned runtime's POSIX-prefix ordering pass | Descending POSIX-length minus native-length in UTF-8 bytes, then POSIX byte spelling |

The MSYS2 POSIX-prefix pass has equal comparisons for unrelated mounts. Its
observable ordering is reproduced with the pinned newlib sorting behavior;
substituting a stable generic sort would change some nested-mount results.
Equal native aliases start with the supplied declaration priority before that
second ordering pass; matching still checks full component boundaries.
Consequently, the MSYS2 profile does not promise universal longest-prefix
selection. The real default/custom mount and alias cases are part of P3's
frozen evidence. See [the sorting provenance](../third_party/newlib/README.md).

Drive letters compare without ASCII case sensitivity and render uppercase in
Windows/Mixed output, lowercase in POSIX drive fallback. Other components retain
their spelling. Each mount chooses `Sensitive` or `AsciiInsensitive`; the latter
folds ASCII only. Non-ASCII Windows case folding is outside this contract.

The root is an explicit mount. Supplying `/ → C:\cygwin64` does not create
`/usr/bin`, `/usr/lib`, or any other alias. Callers must supply those mappings.

## 5. Relative resolution and normalization

Ordinary relative paths preserve `.` and `..` without an absolute request.
Absolute resolution joins the applicable explicit cwd, normalizes in that path
space, then maps and renders. This is lexical conversion: no file existence,
symlink, junction, or realpath query occurs.

| Library request | Base or result |
| --- | --- |
| Ordinary relative input, `absolute=false` | No cwd, except the long Windows-output fallback below |
| POSIX relative input, `absolute=true` | `posix_cwd`; Windows output also needs its mapping |
| Windows ordinary relative input, `absolute=true` | `windows_cwd` |
| `C:a` to Windows/Mixed, `absolute=false` | Preserve `C:a` |
| `C:a` or `C:` to POSIX, or with `absolute=true` | Resolve from `C:\`, without using per-drive cwd metadata |
| `\a` to Windows/Mixed, `absolute=false` | Preserve its current-drive-rooted form |
| `\a` to POSIX, or with `absolute=true` | Take the drive from drive-absolute `windows_cwd` |

The CLI's natural recognition additionally treats bare `C:` and absolute
Windows-output requests for `C:child` as literal POSIX-relative names, matching
the official command behavior. This differs deliberately from an explicitly
Windows library request; [04](04-api-and-cli.md) gives examples.

Absolute POSIX/drive paths collapse repeated separators, remove `.`, and resolve
`..` without crossing their root. UNC parents beyond the share boundary remain
`..`. Unmatched Windows-to-POSIX UNC input preserves its original tail spelling,
including internal dots, repeated separators, and terminal separators. A mapped
UNC path uses the normalized mapping result. Relative Windows-to-POSIX input
without an absolute request similarly preserves its slashified original spelling.

Trailing-separator intent is determined before normalization. In the Cygwin
profile, the slash in bare POSIX `/` expresses the root and is not an optional
suffix: mapping it to `C:\root` yields `C:\root`. Mapping to a drive or share
root retains its required separator. A non-root input `/folder/../` retains its
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
Windows-to-POSIX reverses those mappings and U+F020/U+F02E for space/dot; other
private-use characters are preserved. These are filename rules, independent
of the CLI's output byte encoding.

Ordinary component spellings such as `CON`, trailing dots, and trailing spaces
are preserved. A literal backslash in an explicitly POSIX component cannot be
rendered as an ordinary Windows filename and raises `UnrepresentablePath`.
UNC server/share validation also rejects invalid authority components. CR/LF
are path content where allowed; the CLI does not impose a second blanket
line-break rejection on argv or converted output.

There is no tilde, variable, glob, or URI expansion. Path content is never
executed. The product does not query 8.3 names, actual filename case, system
directories, file modes, process HANDLEs, symlinks, junctions, or arbitrary device
namespaces. POSIX-to-Windows `/dev` and `/proc` mappings are unsupported except
the explicit `/proc/cygdrive/<drive>` rule. Already-POSIX Windows-to-POSIX
passthrough is the separate spelling rule from section 2.

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
| Windows → POSIX | `C:a`, with or without `drive_cwds` | `/cygdrive/c/a` |
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
