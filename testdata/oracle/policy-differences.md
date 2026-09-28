# Portable policy identifiers

These identifiers connect observed differences to intentional portable contracts in [path semantics](../../docs/03-path-semantics.md) and [the CLI contract](../../docs/04-api-and-cli.md). [Windows oracle run 36371978419](https://github.com/moonbit-community/cygpath/actions/runs/36371978419) verified their exact scopes at commit `7dfe6ba58520a6f5249c41bd9aad39cfeb215440`. The measured distributions are Cygwin `3.6.10-1` and MSYS2 `3.6.10-5`; their binary/runtime hashes are fixed in the approvals. These observations are not universal claims about other upstream versions or environments.

[`reviewed-differences.json`](reviewed-differences.json) records 23 profile/case differences: 11 Cygwin and 12 MSYS2. Across Wasm/Native and collect/replay, they account for 92 preserved raw failures. An approval never changes `run.json` status from `fail` to `pass`; the CI wrapper uses the separate `reviewed-difference` category after checking exact fixture/upstream hashes, output hashes, and integer exits. [Remote Validation](../../docs/09-remote-validation.md) links the full evidence.

| Identifier | Portable contract and measured difference |
| --- | --- |
| `portable-empty-list-policy` | An empty Windows list converts to an empty output record; both official CLIs reject the empty operand before list conversion |
| `portable-drive-relative-policy` | `C:child` and bare `C:` use explicit per-drive cwd; both measured official conversions resolve these cases from the drive root |
| `portable-unc-normalization-policy` | Absolute UNC traversal is normalized and clamped at the share root; both measured official conversions retain the parent component |
| `portable-trailing-separator-policy` | A mapped installation directory needs no Windows drive-root separator; the measured MSYS2 `/` conversion adds a trailing separator |
| `portable-empty-input-policy` | An empty stream is missing input unless `-i` is present; both measured official file loops succeed without output |
| `portable-empty-record-policy` | Empty records stop processing with stable project diagnostics and exit 2; the measured official diagnostics and exit 1 differ |
| `portable-initial-bom-policy` | Remove a UTF-8 BOM only at byte zero; both measured official conversions preserve that initial BOM as path content |
| `portable-strict-utf8-policy` | Reject malformed UTF-8, preserve earlier output, and exit 1; the measured official runtimes continue and return success |
| `portable-failure-reporting-policy` | Stop at an empty operand after preserving earlier output, using project diagnostics and exit 2; the measured official diagnostics and exit 1 differ |
| `portable-line-protocol-policy` | Reject embedded CR/LF with exit 2; both measured official CLIs emit the embedded LF successfully |

Some fixtures declare `known_difference_id`; others gained a reviewed policy ID only after observing the official result. A fixture annotation alone never grants an approval. Exact entries bind profile, case, complete fixture-file SHA-256, upstream executable/runtime SHA-256, nonempty policy/reason, both streams, and both exits. A fixture or upstream update invalidates that scope, as does changed output. Review new evidence before changing an entry; do not regenerate approvals automatically to make a job green.

The corrected rendering of a mapped POSIX root and the measured Windows per-drive cwd are implementation/collection fixes, not policy exceptions. The remaining drive-relative entries above reflect actual results after those fixes. Full P3 coverage and real Windows collector fault drills remain open; this list describes only the verified subset.
