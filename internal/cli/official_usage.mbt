///|
// Diagnostic text frozen from Cygwin and MSYS2 official
// process output (525c383 oracle, invalid-type). This compatibility message
// is distinct from this project's capability-aware --help text.
fn official_usage_error() -> String {
  "Usage: cygpath (-d|-m|-u|-w|-t TYPE) [-f FILE] [OPTION]... NAME...\n" +
  "       cygpath [-c HANDLE] \n" +
  "       cygpath [-ADHOPSW] \n" +
  "       cygpath [-F ID] \n" +
  "\n" +
  "Convert Unix and Windows format paths, or output system path information\n" +
  "\n" +
  "Output type options:\n" +
  "\n" +
  "  -d, --dos             print DOS (short) form of NAMEs (C:\\PROGRA~1\\)\n" +
  "  -m, --mixed           like --windows, but with regular slashes (C:/WINNT)\n" +
  "  -M, --mode            report on mode of file (binmode or textmode)\n" +
  "  -u, --unix            (default) print Unix form of NAMEs (/cygdrive/c/winnt)\n" +
  "  -w, --windows         print Windows form of NAMEs (C:\\WINNT)\n" +
  "  -t, --type TYPE       print TYPE form: 'dos', 'mixed', 'unix', or 'windows'\n" +
  "\n" +
  "Path conversion options:\n" +
  "\n" +
  "  -a, --absolute        output absolute path\n" +
  "  -l, --long-name       print Windows long form of NAMEs (with -w, -m only,\n" +
  "                        don't mix with -r and -s)\n" +
  "  -r, --root-local      print Windows path with root-local path prefix (\\\\?\\,\n" +
  "                        with -w only, don't mix with -l and -s)\n" +
  "  -p, --path            NAME is a PATH list (i.e., '/bin:/usr/bin')\n" +
  "  -U, --proc-cygdrive   Emit /proc/cygdrive path instead of cygdrive prefix\n" +
  "                        when converting Windows path to UNIX path.\n" +
  "  -s, --short-name      print DOS (short) form of NAMEs (with -w, -m only,\n" +
  "                        don't mix with -l and -r)\n" +
  "  -C, --codepage CP     print DOS, Windows, or mixed pathname in Windows\n" +
  "                        codepage CP.  CP can be a numeric codepage identifier,\n" +
  "                        or one of the reserved words ANSI, OEM, or UTF8.\n" +
  "                        If this option is missing, cygpath defaults to the\n" +
  "                        character set defined by the current locale.\n" +
  "\n" +
  "System information:\n" +
  "\n" +
  "  -A, --allusers        use `All Users' instead of current user for -D, -O, -P\n" +
  "  -D, --desktop         output `Desktop' directory and exit\n" +
  "  -H, --homeroot        output `Profiles' directory (home root) and exit\n" +
  "  -O, --mydocs          output `My Documents' directory and exit\n" +
  "  -P, --smprograms      output Start Menu `Programs' directory and exit\n" +
  "  -S, --sysdir          output system directory and exit\n" +
  "  -W, --windir          output `Windows' directory and exit\n" +
  "  -F, --folder ID       output special folder with numeric ID and exit\n" +
  "Try `cygpath --help' for more information."
}
