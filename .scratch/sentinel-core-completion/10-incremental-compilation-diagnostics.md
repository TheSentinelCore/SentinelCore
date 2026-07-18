---
id: 10
title: "Incremental Compilation + Compiler Diagnostics"
state: open
labels: ["enhancement", "ready-for-agent", "size:medium"]
created: "2026-07-18T00:00:00Z"
updated: "2026-07-18T00:00:00Z"
---

# 10 — Incremental Compilation + Compiler Diagnostics

**What to build:** Add incremental compilation support via a DirtyTracker so editing one Operation only re-runs affected stages, and polish the diagnostic system for clear, actionable compiler output.

**Blocked by:** #9 (all 7 stages must exist before incremental compilation can skip them)

**Acceptance criteria:**

**Incremental Compilation:**
- [ ] `DirtyTracker` type: tracks dirty state per Operation (new, modified, deleted, unchanged)
- [ ] On recompile: only Operations marked dirty re-run Stages 1–3 (structural validation, reference resolution, blueprint expansion)
- [ ] Stage 4 (dependency resolution) re-runs only if the dirty edit touched `dependencies`, `priority`, `excludes_with`, or `entry_conditions`
- [ ] Stage 5 (goal coverage) re-runs only for the dirty Operation's goals
- [ ] Stage 6 (optimization) re-runs only for the dirty Operation + its immediate neighbors in the dependency graph
- [ ] Stage 7 (lowering) re-lowers only affected `RuntimeOperation` entries
- [ ] Test: compile full profile → mark one Operation dirty → recompile → verify only affected stages ran (track via diagnostic output or mock call counts)

**Diagnostics Polish:**
- [ ] Every diagnostic has: severity (Error/Warning/Info/Success), error code (C-xxxx), stage number, human-readable message, entity reference (Operation/Action ID), optional suggested fix text
- [ ] Compiler returns `Result<RuntimeProfile, Vec<Diagnostic>>` — never a partial RuntimeProfile on error
- [ ] Warnings do not prevent compilation (only Errors do)
- [ ] Test: compile a profile with 2 errors + 3 warnings → assert exactly 2 errors + 3 warnings in result, compilation fails
- [ ] Test: compile a profile with 0 errors + 5 warnings → assert compilation succeeds with warnings
