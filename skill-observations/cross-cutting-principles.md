# Cross-Cutting Principles

## 1. One Skill at a Time
Load a skill, complete its workflow, then transition to the next phase. Do not load multiple phase-workflow skills simultaneously.

## 2. Announce Phase Transitions
When moving between phases, tell the user what phase you are entering and why.

## 3. Respect the User's Scope
Not every feature needs all phases. Match the workflow to the size of the task.

## 4. The User Drives Decisions
Skills like `grill-me`, `grill-with-docs`, and `to-prd`'s deep-module quiz involve heavy user interaction. Never assume answers — always ask.

## 5. Keep Artifacts Connected
PRDs link to issues. Issues link to branches. Branches link to PRs. ADRs link to the decisions they record. `CONTEXT.md` is referenced wherever its terms appear.

## 6. Parallel Workers Require Worktree Isolation
Before dispatching two or more workers in the same message, create one `git worktree` per worker via the setup block in Phase 4.
