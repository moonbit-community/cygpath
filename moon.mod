name = "ZSeanYves/cygpath"

version = "0.1.0"

readme = "README.md"

repository = "https://github.com/moonbit-community/cygpath"

license = "Apache-2.0"

keywords = [ "cygpath", "cygwin", "windows", "path" ]

preferred_target = "wasm"

description = "A MoonBit implementation of Cygwin-style path conversion (in development)."

import {
  "moonbitlang/async@0.22.4",
  "moonbitlang/x@0.5.5",
}

options(
  exclude: [
    "docs/",
    "scripts/",
    "testdata/",
    "AGENTS.md",
    "**/*_test.mbt",
    "**/*_wbtest.mbt",
    "**/*_benchmark.mbt",
    ".github/",
    ".gitattributes",
    ".gitignore",
    ".moonagent/",
    ".mooncakes/",
    "_build/",
    "target/",
  ],
)
