# Official oracle inputs

This directory contains **unexecuted inputs and a manifest template**, not official results. Cygwin and MSYS2 have separate ten-case starter corpora, plus a shared forty-case `fixtures.readonly-matrix.json`: fifty planned inputs per profile. The additional matrix covers root/nested mounts, prefix boundaries, cwd forms, normalization boundaries, trailing separators, lists, type/code-page selection, and stdin/partial-failure policies. Expected bytes must come from the pinned real program on Windows.

The cases are independently authored from the project's contracts and the linked upstream usage/source references. No upstream implementation or GPL source fixture has been copied. The design-reference commits in the files do not assert that any installed executable was built from those commits; the environment manifest records the actual distribution's source revision and binary hashes.

Read [Oracle Collection and Replay](../../docs/07-oracle-collection.md) before using `scripts/oracle.mbtx`. Fill every `REPLACE_` field in a copy of `environment.example.json`. For MSYS2, change the profile, executable/runtime paths, installation root, source metadata, mounts, and drive prefix together. For a Native project artifact, `project.launcher` must equal `project.artifact`.

Save real collection outputs outside this input directory, in a new evidence directory for every run and suite. Never populate these input files with guessed output. A `known_difference_id` is an annotation: mismatched bytes still produce `fail`. [Policy identifiers](policy-differences.md) describe intentional project policies awaiting observation, not verified upstream mismatches.
