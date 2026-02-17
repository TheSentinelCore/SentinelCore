# GrindBuddy Versioning

GrindBuddy uses a 4-part version:

- `major.minor.patch-rrevision`
- Example: `0.1.0-r3`

Rules:

1. `revision` increments for every code change.
2. `patch` increments for bug fixes/releases; reset `revision` to `1`.
3. `minor` increments for new features; reset `patch=0`, `revision=1`.
4. `major` increments for breaking changes; reset `minor=0`, `patch=0`, `revision=1`.

## Files

- `GrindBuddy/version.lua`: current version and history.
- `GrindBuddy/tools/bump_version.ps1`: helper script to bump version and append history.

## Usage

From repo root:

```powershell
powershell -ExecutionPolicy Bypass -File .\GrindBuddy\tools\bump_version.ps1 -Level revision -Message "Your change summary"
```

Valid levels: `revision`, `patch`, `minor`, `major`.
