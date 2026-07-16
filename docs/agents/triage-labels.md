# Triage Label Vocabulary

## Canonical Labels (5 roles)

| Role | Label | Description |
|------|-------|-------------|
| **Category: Bug** | `bug` | Something is broken, throwing, or behaving incorrectly |
| **Category: Enhancement** | `enhancement` | New feature, improvement, or non-bug work |
| **State: Needs Triage** | `needs-triage` | Newly created, not yet categorized or prioritized |
| **State: Needs Info** | `needs-info` | Blocked on clarification from reporter/maintainer |
| **State: Ready for Agent** | `ready-for-agent` | Fully specified, actionable by autonomous agent |
| **State: Ready for Human** | `ready-for-human` | Requires human decision, design, or manual work |
| **State: Won't Fix** | `wontfix` | Explicitly deferred or rejected |

## Usage Rules

1. **Every issue must have exactly one category label** (`bug` or `enhancement`)
2. **Every issue must have exactly one state label** (from the 5 state labels)
3. Labels are applied by the `triage` skill during interactive sessions
4. `ready-for-agent` issues are picked up by `to-tickets` → dispatch workflow
5. `wontfix` issues are closed with a comment explaining rationale

## Additional Labels (Optional)

These may be added for filtering but are not part of the state machine:

| Label | Purpose |
|-------|---------|
| `area:quest` | Quest system work |
| `area:combat` | Combat rotation work |
| `area:grind` | Grind/bot behavior work |
| `area:nav` | Navigation/pathfinding work |
| `priority:high` / `priority:low` | Rough priority hint |
| `size:small` / `size:medium` / `size:large` | Effort estimate |

## Migration Note

If the repository previously used different labels (e.g., `type:bug`, `status:todo`), they should be renamed or mapped during the first triage session. The `triage` skill will prompt for this.