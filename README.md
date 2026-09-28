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

Input can come from arguments, UTF-8 files (`-f FILE`), or stdin (`-f -`), with
per-record options (`-o`) and skipping empty operands (`-i`). Windows/mixed output
supports UTF-8 and 110 legacy numeric code pages (`-C`). The CLI runs on Wasm and
Native. Import `ZSeanYves/cygpath/lib` to use the conversion library.

Unsupported: automatic installation-root or working-directory discovery; DOS/8.3 and
filesystem long-name lookup; symlink/junction resolution; Windows system-folder
queries; mount-mode queries and handle closing; device and virtual-filesystem
paths; non-ASCII mount case folding; automatic ANSI/OEM selection; GB18030,
stateful encodings, and CP29001. Malformed UTF-8 is rejected.

[Apache-2.0](LICENSE), with [Unicode](third_party/unicode/README.md),
[Microsoft](third_party/microsoft/README.md), and
[newlib](third_party/newlib/README.md) notices.
