# Domain Documentation Layout

## Layout: Single-Context

This repository uses a single bounded context for domain documentation.

## Files

| Path | Purpose |
|------|---------|
| `sentinel/CONTEXT.md` | Ubiquitous language glossary (term → definition → aliases-to-avoid + relationships + example dialogue) |

## Consumer Rules

Engineering skills (`grill-with-docs`, `to-prd`, `to-tickets`, `triage`, `diagnose`, `improve-codebase-architecture`) read from these locations:

1. **Glossary terms** → `sentinel/CONTEXT.md`
2. **Cross-cutting principles** → `skill-observations/log.md` (maintained by `task-observer`)

## Maintenance

- `grill-with-docs` creates/updates `CONTEXT.md` when new terms are resolved during grilling
- Do not bulk-migrate old `UBIQUITOUS_LANGUAGE.md` — migrate lazily on next touch
