# Portable policy identifiers

These identifiers connect cases to intentional portable contracts in [chapter 04](../../docs/04-api-and-cli.md). They are **not recorded findings about an official installation**. Real collection must establish whether bytes/status actually differ and attach run evidence to any confirmed difference. An identifier never changes a comparison's result from `fail` to `pass`.

| Identifier | Project policy under comparison |
| --- | --- |
| `portable-empty-input-policy` | An empty file is missing input unless `-i` is present |
| `portable-empty-record-policy` | An empty single-path record fails and stops subsequent records |
| `portable-initial-bom-policy` | Remove a UTF-8 BOM only at byte zero of the input stream |
| `portable-strict-utf8-policy` | Reject malformed UTF-8 without replacement and preserve earlier output |
| `portable-failure-reporting-policy` | Stable project diagnostics, explicit exit categories, and first-failure stopping |
| `portable-line-protocol-policy` | Reject remaining CR/LF within a single CLI operand or record |

The shared matrix references these IDs in `known_difference_id` to make deliberate policy differences traceable. An omitted field indicates no policy difference has been identified in advance. Neither form supplies expected bytes: both still require a real oracle and exact comparison.
