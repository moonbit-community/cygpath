///|
pub fn version_text() -> String {
  "cygpath (MoonBit) 0.1.0\nProfiles: cygwin, msys2\n"
}

///|
pub fn help_text() -> String {
  let text =
    #|Usage: cygpath [OPTION]... NAME...
    #|       cygpath [OPTION]... -f FILE
    #|Convert Windows and POSIX paths using explicit, portable context.
    #|
    #|Output and input:
    #|  -u, --unix                 POSIX output (default)
    #|  -w, --windows              Windows output with backslashes
    #|  -m, --mixed                Windows output with forward slashes
    #|  -t, --type TYPE            unix, windows, or mixed
    #|  -p, --path                 Convert each NAME as a path list
    #|  -a, --absolute             Resolve relative paths using supplied cwd
    #|  -U, --proc-cygdrive        Use /proc/cygdrive for drive fallback
    #|  -r                        Prefix single Windows paths with \\\\?\\
    #|  -f, --file FILE            Read UTF-8 lines; - reads standard input
    #|  -o, --option              Read options from leading - records in FILE
    #|  -i, --ignore               Skip empty path operands
    #|  -C, --codepage CP          UTF8, UTF-8, or a supported numeric code page
    #|  -h, --help                 Show this help
    #|  -V, --version              Show implementation version and profiles
    #|
    #|Explicit context (project extensions):
    #|      --from windows|posix   Select input syntax; recommended for lists
    #|      --profile cygwin|msys2 Select drive-prefix profile
    #|      --root WINDOWS        Mount / at an absolute Windows path
    #|      --mount POSIX WINDOWS Add an explicit mount (repeatable)
    #|      --mount-case POSIX POLICY sensitive or ascii-insensitive
    #|      --drive-prefix POSIX  Override the drive-prefix profile
    #|      --posix-cwd POSIX      Supply an absolute POSIX cwd
    #|      --windows-cwd WINDOWS Supply an absolute Windows cwd
    #|      --drive-cwd DRIVE WIN Validate per-drive cwd metadata (repeatable)
    #|
    #|Options may follow NAME arguments. -- ends parsing. Short options may
    #|be combined; option values may be attached. No cwd or root is guessed.
    #|Without --from, -u recognizes POSIX absolute and Windows paths;
    #|-w/-m read POSIX syntax and recognize ordinary Windows prefixes.
    #|Single paths with a drive prefix or backslashes are recognized as Windows.
    #|Absolute/POSIX conversion anchors C:name at C:/; drive-cwd does not alter it.
    #|Output uses LF records. -C affects Windows output; POSIX stays UTF-8.
    #|Numeric pages use the generated Microsoft mapping catalog (95 enabled
    #|Windows pages plus 15 Unicode pages and UTF-8/65001); unsupported or
    #|unavailable pages (including 29001) are errors.
    #|-f cannot be combined with NAME. No shell quoting is applied to records.
    #|
    #|Recognized but unsupported:
    #|  -d/--dos, -s/--short-name, -l/--long-name,
    #|  -M/--mode, -c/--close HANDLE, ANSI/OEM host code-page selection in
    #|  Windows output,
    #|  -D/--desktop, -H/--homeroot, -O/--mydocs, -P/--smprograms,
    #|  -S/--sysdir, -W/--windir, -F/--folder ID.
    #|-A/--allusers has no effect on ordinary path conversion.
    #|The upstream --root-local long spelling is rejected; use -r.
    #|
    #|Exit codes: 0 success, 1 options/context/I/O, 2 path conversion failure.
    #|
  text
}
