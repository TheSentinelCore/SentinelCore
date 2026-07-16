# Issue Tracker Configuration

## Tracker Type
**Local Markdown** — issues stored as Markdown files under `.scratch/<feature-slug>/`

## Structure
```
.scratch/
  dynamic-quest-graph-engine/
    001-dynamic-quest-graph-engine.md    # PRD
    002-quest-graph-dag.md               # Issue: build DAG from DB
    003-quest-scorer.md                  # Issue: scoring weights + heuristics
    ...
```

## Issue Format
Each issue file contains:
```markdown
---
id: 1
title: "Issue title"
state: open
labels: ["enhancement", "ready-for-agent", "area:quest"]
created: "2026-07-15T10:00:00Z"
updated: "2026-07-15T10:00:00Z"
---

## Description
Issue description here.

## Acceptance Criteria
- [ ] Criterion 1
- [ ] Criterion 2
```

## Workflow
- `to-tickets` creates issues as numbered Markdown files
- `triage` reads/writes issue state via file updates
- No CLI tools required (no `gh`/`glab`)
- Good for solo/local development