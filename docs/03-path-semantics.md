# 03 Path Semantics and Algorithm Contracts

Status: portable behavior contract. See [the architecture index](README.md) for implementation and verification status. This chapter defines the project's deterministic rules; behavior marked as a differential gate requires evidence collected on real Cygwin/MSYS2 before the corresponding compatibility can be claimed. See [01](01-upstream-and-scope.md) for the primary behavioral sources and immutable source links.

The first real Windows runs now establish observations for the selected corpus;
see [the remote validation report](09-remote-validation.md). Its recorded
differences remain differences in raw output/status. They neither establish
complete compatibility nor extend the supported scope beyond this chapter.

## 1. Input, output, and profile are separate dimensions

The only input syntaxes are `Windows` and `Posix`, selected explicitly by the caller. Output formats are `Windows`, `Mixed`, and `Posix`. Mixed shares Windows path semantics and changes only the directory separator for ordinary paths. The profile is either `Cygwin` or `Msys2`; it determines the default drive prefix and the CLI's mode identification, not the host OS.

Both `C:\work` and `C:/work` are valid Windows inputs; `/cygdrive/c/work` is a POSIX input under the Cygwin profile. MSYS2's `/c/work` must not automatically become a drive path in the default Cygwin mode. Likewise, the similar-looking WSL path `/mnt/c/work` must not implicitly enable WSL rules.

The library provides no ambiguous `Auto` input syntax. The CLI defaults to Windows input for `-u` and Posix input for `-w/-m`. It can recognize unambiguous drive-letter and backslash prefixes to perform idempotent conversion when the output remains Windows. Users can override this default interpretation with `--from`; see [04](04-api-and-cli.md).

## 2. Path classification and recognition order

The scanner must recognize special prefixes before ordinary separators. It must not start by replacing every slash globally.

| Example input (literal path, without shell escaping) | Classification | Required handling |
| --- | --- | --- |
| `C:\a`, `C:/a` | DriveAbsolute | ASCII drive letter, colon, and separator |
| `C:a`, `C:` | DriveRelative | Relative to drive C's working directory; neither `C:\a` nor the drive root |
| `\a` | WindowsRooted | Rooted on the current drive; not a POSIX root |
| `\\server\share\a`, `//server/share/a` | UNC | Preserve the server and share root; never collapse to a single leading slash |
| `\\?\C:\a`, `\\?\UNC\server\share\a` | ExtendedNamespace | Explicitly unsupported initially; do not remove the prefix and apply ordinary rules |
| `\\.\COM1`, `\??\C:\a` | DeviceNamespace | Device namespace conversion is unsupported |
| `/usr/bin` | PosixAbsolute | Interpret using POSIX source syntax; Windows output requires mount information |
| `a/b`, `../a` | Relative | Preserve relative meaning; consume cwd only when making the path absolute |

In Windows source syntax, `/a` is rooted on the current drive. In Posix source syntax, `/a` is rooted at the POSIX root. The same text can therefore require different context. Only an explicit input syntax removes this ambiguity.

Initial UNC support requires a complete `server/share`. The network-browsing meanings of `//` and `//server`, like device namespaces, fall outside portable ordinary file paths and produce `UnsupportedNamespace`. A complete double-slash UNC in POSIX source syntax follows UNC rules rather than the root mount.

## 3. Context validity and immutability

The logical Context fields are profile, drive_prefix, Mount entries in declaration order, optional posix_cwd, optional windows_cwd, and drive_cwds keyed by drive letter. Every cwd must be an absolute ordinary path in its own syntax. A Windows cwd may be drive-absolute or a complete UNC, but a UNC cwd cannot establish the current drive. Each drive_cwds key must be a single ASCII drive letter, and its value must be an absolute path on that drive: an entry for C rejects `D:\work` and UNC paths. Keys must remain unique after normalization.

Context construction must:

- Validate that the prefix is a canonical POSIX absolute path. The Cygwin default is `/cygdrive`; the Msys2 default is `/`. Custom values such as `/drives` are allowed, with consistent trailing-separator normalization. Reject `/dev`, `/proc`, and their subtrees as custom prefixes. Access `/proc/cygdrive` through the dedicated UnixPrefix option.
- Validate that each mount source is POSIX-absolute and its target is drive-absolute or a complete UNC. Reject relative targets, empty server/share names, namespace targets, and definitions containing unresolved `.` or `..` components.
- Reject duplicate POSIX mount points. Different mount points may target the same Windows root, so the mapping need not be one-to-one.
- Reject explicit mounts at `/dev`, `/proc`, or their subtrees, including the reserved `/proc/cygdrive`, and explicit mounts that conflict with the configured drive_prefix subtree. When drive_prefix is `/`, regardless of profile, reserve only the `/[a-zA-Z]` drive branches and their subtrees; ordinary `/usr` or root `/` mounts remain allowed.
- Copy mutable collections and normalize drive-letter keys. An omitted cwd is valid until a conversion actually needs it.

The library does not interpret fstab permissions, text mode, or bind/usertemp entries, and does not read the registry. Callers that need this information must first resolve actual mappings into ordinary Mount entries. Any future fstab support requires its own explicit semantics and tests.

## 4. Mapping and matching rules

POSIX → Windows: first recognize `/proc/cygdrive/<drive>`, then drive paths under the configured prefix, and then select the longest matching explicit mount. Root `/` is also an explicit mount. If no mapping exists, return `MissingContext(RootOrMount)`. Never assume `C:\cygwin64` as an installation root.

Windows → POSIX: prefer explicit mounts. Only a drive-absolute path that matches no mount falls back to drive_prefix. Requesting `ProcCygdrive` changes only this fallback prefix to `/proc/cygdrive`; it must not bypass a matching mount. A UNC path without an explicit mount renders as `//server/share/...`.

Matches must end at component boundaries: `/usr` matches `/usr/bin` but not `/usr2`; `C:\work` does not match `C:\workspace`. Presorting context entries may improve lookup, but must not change the caller's declaration order.

When several aliases have equally long Windows targets, the portable rule chooses the first declared Mount as the canonical reverse mapping. A longer target still takes precedence. This deterministic rule does not promise every detail of Cygwin's ordering; real alias preferences remain a differential gate.

Drive letters are compared without ASCII case sensitivity. POSIX output uses lowercase drive letters; Windows/Mixed output uses uppercase drive letters. Other components preserve input case. Each mount has an explicit `Sensitive` or `AsciiInsensitive` comparison policy, defaulting to Sensitive. The latter folds ASCII only and does not claim to implement Windows' complete Unicode case rules. More complex case equivalence is outside the current compatibility commitment.

Root mapping includes only caller-provided entries. `--root` must not silently create `/usr/bin`, `/usr/lib`, or other aliases. These default Cygwin mappings must be supplied as explicit Mount entries to make behavior reproducible across machines and installation layouts.

## 5. Relative paths, absolute resolution, and normalization

Without an absolute request, ordinary relative paths receive only syntax and separator conversion. They preserve `.` and `..`, do not read cwd, and do not check whether files exist. Inputs that are already absolute receive limited lexical normalization: remove repeated separators and `.`, resolve `..` component by component, and never move above a drive root, POSIX root, or UNC share root.

When absolute resolution is requested, first join the path to the corresponding cwd in its source syntax, then resolve `.` and `..`, and finally map and render it. There is no symbolic-link inspection, so `link/../a` can only be resolved lexically; it must not be described as equivalent to real filesystem resolution. Behavior involving `..` across mount boundaries or symbolic links is an explicit differential gate. If official behavior differs, document the supported scope or revise the contract; do not hide the difference.

Special relative inputs require the following context:

| Input and target | Context requirement |
| --- | --- |
| Ordinary relative path, any format, absolute=false | No cwd required |
| POSIX relative path, absolute=true | posix_cwd; Windows output also requires the corresponding mapping |
| Windows ordinary relative path, absolute=true | windows_cwd |
| `C:a` to Windows/Mixed, absolute=false | Drive-relative semantics may be preserved |
| `C:a` to Posix, or absolute=true | C in drive_cwds; windows_cwd on C may serve as a fallback |
| `\a` to Windows/Mixed, absolute=false | Preserve the form rooted on the current drive |
| `\a` to Posix, or absolute=true | Obtain the drive from a drive-absolute windows_cwd; a UNC cwd is insufficient |

Do not interpret `C:` as `C:\`, or assume a drive root when its per-drive cwd is missing. `absolute` is not `realpath`, and the output does not establish that a file exists.

The pinned Windows runs observed that both official programs resolve the tested
`-au C:child` and `-au C:` inputs from the drive root, while this project's
explicit per-drive cwd produces the declared cwd plus `child`, or the cwd itself.
The existing explicit-context rule above remains the portable contract. For the
tested `-au \\server\share\..\file`, both official programs preserve the parent
component; this project's existing lexical rule clamps traversal at the share
and yields `//server/share/file`. These are bounded observations for those
fixtures and environments, recorded with their byte digests in
[the reviewed differences](../testdata/oracle/reviewed-differences.json).
They do not resolve every drive-state or UNC differential gate.

The portable trailing-separator rule is: roots retain the separator needed to
express the output root; if a non-root input has a trailing separator, render
exactly one target separator; preserve one trailing separator on ordinary
relative `.`/`..` paths as well. The slash in the bare POSIX root `/` is structural,
not an optional suffix. Mapping `/` to an ordinary Windows directory such as
`C:\root` therefore produces `C:\root`, without an extra backslash. Mapping it
to a drive root or UNC share still produces the required `C:\` or
`\\server\share\` form. Determine optional trailing-separator intent before
normalization: `/folder/` retains its suffix, and `/folder/../` mapped through `/ → C:\root`
produces `C:\root\` because a non-root input explicitly supplied that suffix.

Commit `476d6a8` corrected the parser's conflation of the bare POSIX root slash
with optional trailing separators. Both profiles use the same rule. In the
recorded `-w /` case, Cygwin agrees with the corrected ordinary-directory output;
MSYS2 appends a trailing backslash and is retained as a reviewed raw difference.
See [the remote validation report](09-remote-validation.md) for pinned programs
and evidence. Other root/trailing-separator combinations remain subject to their
differential gates. A different compatibility rule requires corresponding
contract and fixture updates.

## 6. Path lists are not simply batches of single paths

The input direction of `convert_list` must be explicit. Do not classify individual members first and then guess the list separator. Windows lists use `;`; POSIX lists use `:`. Mixed is an output style and still uses the Windows list separator `;`.

In Windows lists, `C:` contains a drive letter and is not split on the colon. In POSIX lists, a colon is always a list separator; do not accept a mixed-in `C:\a` and attempt to infer its meaning. The calling shell has already processed argv quoting. The library does not decode remaining quotes as CSV or shell quoting. If an ordinary path contains the target list separator, return `UnrepresentablePath` rather than silently splitting it into extra members.

Empty-member rules follow the pinned upstream `conv_path_list` and are asymmetric:

- POSIX → Windows: treat each empty member as `.`, then apply normal relative/absolute rules. Never discard a member representing the current directory.
- Windows → POSIX: discard empty members. Never inject the host cwd.
- Rerendering a list in the same direction preserves empty-member positions. A single empty path passed to `convert("")` still produces `EmptyPath`.

An empty POSIX list string represents one empty member. Converting a Windows list
containing only empty members to POSIX yields the empty string under the portable
contract. The CLI writes that result as LF and exits 0. In the recorded
`empty-windows-list` case, both official CLIs reject the empty operand before
list conversion, write no stdout, and report an error with exit 1. This confirms
a difference for that case; it does not change the library's established
empty-member contract. The [remote validation report](09-remote-validation.md)
retains the exact observations. Further endpoint and option combinations still
require real-system differential checks.

Preserve member order and do not deduplicate. If a valid member fails conversion, return an error containing its original member index, with no prefix result. The index counts original empty members so diagnostics can identify the user's input. One CLI `-p NAME` is an atomic conversion unit; separate NAME arguments follow the per-item output rules.

## 7. Characters and unrepresentable input

The core accepts String, recognizes path structure with ASCII characters, and preserves the contents and case of other valid Unicode scalars. Reject NUL and invalid surrogates. CLI UTF-8 decoding errors must not be replaced with U+FFFD to continue processing. Do not normalize combining characters to NFC/NFD. Chinese characters, emoji, and spaces need no special transliteration.

Ordinary Windows naming cannot represent some POSIX components, including names containing `:`, `*`, `?`, literal backslashes, or control characters; reserved device names; and trailing dots/spaces that require a special namespace to preserve. The first version returns `UnrepresentablePath` for such conversions, retaining the original component and reason. It does not implement Cygwin private-use-area encoding or silently delete characters. Build the exact reserved-name test table from [Microsoft's naming rules](https://learn.microsoft.com/en-us/windows/win32/fileio/naming-a-file).

The core does not expand `~`, `$HOME`, `%USERPROFILE%`, or globs, and does not decode URIs. `file://...` is not a supported path protocol; if it creates an invalid component, handle it as an ordinary path error. Do not trim spaces. A backslash is not a shell escape, and path content must never be executed as a command.

A single POSIX output path may retain `;` in a component, but its representability must be checked before placing it in a Windows PATH list. Likewise, a POSIX result containing `:` cannot be joined losslessly into a POSIX PATH list. Successful single-path conversion does not guarantee list serialization.

## 8. Unsupported runtime semantics

Generating or querying 8.3 names, restoring actual filename case, finding system special directories, binary/text mount modes, closing process HANDLEs, arbitrary Windows code pages, and extended/device namespaces cannot be implemented correctly through simple string operations. The current design reports explicit errors for these capabilities and prohibits approximate results.

`/proc/cygdrive` is a specific implementable mapping. Other `/proc` and `/dev` virtual paths must not be mapped to disk files below an ordinary root directory; they produce `UnsupportedNamespace`. Future capabilities must still satisfy the pure MoonBit requirement and consistent backend behavior, and may only be enabled after the scope matrix and tests are updated.

## 9. Expected cases

These are design acceptance vectors, not a record of executed results. Backslashes represent literal path characters. The default context uses Cygwin, drive_prefix=`/cygdrive`, no mounts, and no cwd.

| Source → target | Input / additional context | Expected result |
| --- | --- | --- |
| Windows → Posix | `C:\work\a.txt` | `/cygdrive/c/work/a.txt` |
| Windows → Mixed | `c:\work\a.txt` | `C:/work/a.txt` |
| Posix → Windows | `/cygdrive/d/a` | `D:\a` |
| Posix → Mixed | `/proc/cygdrive/d/a` | `D:/a` |
| Windows → Posix | `D:\a`, prefix=ProcCygdrive | `/proc/cygdrive/d/a` |
| Posix → Windows | `/usr/bin`, no mounts | `MissingContext` |
| Posix → Windows | `/usr/bin`, `/ → C:\cygwin64` | `C:\cygwin64\usr\bin` |
| Posix → Windows | Add `/usr/bin → C:\cygwin64\bin` to the previous context | `C:\cygwin64\bin` |
| Windows → Posix | `C:\cygwin64\bin`, previous mounts, prefix=ProcCygdrive | `/usr/bin` |
| Windows → Posix | `C:a`, no cwd for C | `MissingContext` |
| Windows → Posix | `C:a`, drive_cwds[C]=`C:\work` | `/cygdrive/c/work/a` |
| Windows → Posix | `\\server\share\a` | `//server/share/a` |
| Posix → Windows | `a/../b`, absolute=false | `a\..\b` |
| Posix → Windows | `/c/a`, profile=Msys2 | `C:\a` |
| Windows → Posix, list | `C:\a;;D:\b;` | `/cygdrive/c/a:/cygdrive/d/b` |
| Posix → Windows, list | `/cygdrive/c/a::/cygdrive/d/b`, absolute=false | `C:\a;.;D:\b` |
| Windows → Posix | `\\?\C:\a` | `UnsupportedNamespace` |

## 10. Verifiable invariants

Identical input, Context, and options produce identical results. Core calls do not mutate the Context or input collections. List ordering is stable. Rendering ordinary Windows versus Mixed paths differs only in directory separators. Mount matching respects component boundaries. Errors return no partial lists. Supported Unicode is never truncated.

Round-trip properties apply only to canonical absolute paths that are representable, unambiguous, and free of competing aliases. Compare canonical forms, not original strings. Case normalization, mount aliases, empty list members, and redundant separators prevent a global string round-trip identity.
