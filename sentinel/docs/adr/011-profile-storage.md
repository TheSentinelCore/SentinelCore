# Quest Authoring IDE
## Volume 11 — Profile Storage & File Format

Version: 1.0
Status: Draft

---

# 0. Why This Volume Exists

The very first analysis in this project's history — before Volume 1 even
existed — praised a specific idea:

```
"routes, objective groups, conditions, events are all separate
files/modules instead of one 15,000-line XML blob. Honorbuddy mixed
everything into each profile."
```

Every volume since has assumed that idea survived intact. None of them
actually specified it:

```
Volume 1  §8    Defines "Operation," "Chapter," "Campaign" as
                organizational vocabulary, never as a file layout.

Volume 2  §4    ProfileManager.load(path) / .save(path) — signatures
                only, no format.

Volume 2  §25   Lifetime Ownership diagram shows Workspace → Profile →
                Operations → Actions, with no indication which of these
                are files vs in-memory nodes.

Volume 5        Defines the canonical Rust schema in full, but never
                says how a Profile becomes bytes on disk.

Volume 6  §12   "Authors can save custom Blueprints... across
                profiles" — implies Blueprints live somewhere shared,
                never says where.

Volume 8  §14   Schema migration logic assumes an on-disk
                schema_version to check against, never defines where
                that value actually lives.
```

This volume defines the file layout, serialization format, and
load/save pipeline that makes every one of those assumptions concrete.

---

# 1. Design Goals

- **Readable as documentation** — Volume 1 §4's example ("Northshire
  Cleanup • Accept Wolves Across the Border • Kill Wolves...") should be
  roughly what an author sees opening the file directly, not JSON they'd
  need the editor to decode.
- **Diffable and mergeable** — a single-line change to one Action should
  produce a single-line diff. Two authors editing different Operations
  should never conflict.
- **One Operation, one file** — Volume 5's "Why Operations? Operations
  compile independently" extends naturally to storage: independent
  compilation deserves independent files.
- **No duplicated data on disk** — the same "database first" principle
  Volume 1 §3 applied to the Mangos DB applies here to the Profile's own
  libraries: an NPC referenced by twelve Actions should exist once on
  disk, not twelve times.
- **Derived data is never a source of truth on disk** — anything
  computed by another system (Volume 10's AnalyticsServer, most
  notably) is loaded live, never serialized into a file an author would
  edit or a git diff would show as "changed" for no authored reason.

---

# 2. Format Choice: YAML

```
JSON     — no comments, poor diffs on nested structures, not what an
           author would willingly hand-edit
TOML     — good for flat config, awkward for deeply nested Action lists
YAML     — human-readable, supports comments, diffs cleanly line-by-line,
           already the de facto format the original bot-design research
           sketched profiles in
```

YAML is the on-disk authoring format for every file in this volume.
`serde_yaml` (or an equivalent maintained crate at implementation time)
handles (de)serialization against the exact same Rust structs Volume 5
and Volume 7 already defined — no separate on-disk schema to maintain
in parallel with the canonical one.

The compiled `RuntimeProfile` (Volume 8 §10) is the one exception: it's
build output, not authored content, and is cached as JSON (§9) — nobody
is meant to hand-edit it, and JSON's faster parse time matters more than
readability for something regenerated on every compile.

---

# 3. Workspace and Profile Relationship

Volume 5's `Workspace` (from its Overall Hierarchy) contains multiple
`Profile`s and a shared `Blueprint Library` (Volume 6 §12). On disk,
that's two distinct scopes:

```
sentinel-workspace/            ← one Workspace

├── workspace.yaml              ← Workspace-level metadata

├── blueprints/                 ← shared across every Profile
│   ├── quest-hub.yaml
│   ├── vendor-stop.yaml
│   └── ...

└── profiles/
    ├── alliance-human-1-60/    ← one Profile
    └── horde-orc-1-60/         ← another Profile
```

Blueprints live at the Workspace level because Volume 6 §12 explicitly
requires cross-profile reuse. A Profile's directory never contains a
Blueprint definition — only references to one by `BlueprintReference`
(Volume 5), resolved against the shared `blueprints/` directory at load
time.

---

# 4. Profile Directory Layout

```
profiles/alliance-human-1-60/

├── profile.yaml            ← manifest: metadata, settings, operation
│                              order, library file pointers

├── npc_library.yaml
├── quest_library.yaml
├── vendor_library.yaml
├── variables.yaml

└── operations/
    ├── northshire.yaml
    ├── goldshire.yaml
    ├── westbrook-garrison.yaml
    └── eastvale.yaml
```

Every top-level file here corresponds directly to a field on Volume 5's
`Profile` struct except `operations`, which becomes a directory instead
of an inline list — this is the concrete form of Volume 5 §"Why
Operations?" applied to storage.

---

# 5. The Manifest — profile.yaml

```yaml
schema_version: "1.0.0"
profile_id: "b3f1c9a2-..."
name: "Alliance Human 1-60"
author: "Alex"
description: "Full Human leveling route, Northshire through Redridge."

game: TbcClassic
faction: Alliance
race: Human
class: null

level_range:
  min: 1
  max: 60

tags: ["alliance", "human", "leveling"]

settings:
  auto_vendor: true
  auto_repair: true
  auto_train: true
  auto_loot: true
  auto_accept: true
  auto_turnin: true
  use_flight_paths: true
  allow_hearthstone: true
  use_mailbox: true
  death_skip: true
  dry_run_enabled: true

operations:
  - operations/northshire.yaml
  - operations/goldshire.yaml
  - operations/westbrook-garrison.yaml
  - operations/eastvale.yaml
```

The `operations` list here is **declarative bookkeeping, not authority**
— it tells Profile Manager which files belong to this Profile and gives
an editor-friendly default ordering for the Explorer tree (Volume 3
§5). It is explicitly not the execution order; that's computed fresh by
Compiler Stage 4 (Volume 8 §7) from each Operation's own
`dependencies`, every time. Two Operations can be listed in any order
here and still compile identically.

---

# 6. Operation Files

One file per Operation, matching Volume 7 §3's revised struct field for
field, with one change described in §8 below:

```yaml
# operations/northshire.yaml

id: "7e2a...-northshire"
name: "Northshire"
description: "Starting zone questline through Marshal McBride."
enabled: true

level_range: { min: 1, max: 5 }
priority: 100
tags: ["starting-zone"]

goals:
  required:
    - type: CompleteQuestChain
      quests: [33, 34, 35, 36]
  optional:
    - type: ReachLevel
      level: 5
      weight: 0.4

entry_conditions:
  - RaceIs: Human
  - LevelBelow: 6

exit_conditions:
  success:
    - QuestRewarded: 33
    - QuestRewarded: 34
    - QuestRewarded: 35
    - QuestRewarded: 36
  failure:
    - QuestFailed: 33
  abort:
    - DeathsExceed: 3

dependencies: []

optimization_policy:
  travel_weight: 0.6
  xp_weight: 0.3
  risk_weight: 0.1
  cluster_objectives: true
  allow_reordering: true
  grind_fallback: false

completion_metrics:
  target_duration: "00:04:30"
  target_xp: 1800
  min_success_rate: 0.95

variables: []

actions:
  - id: "a1..."
    payload:
      type: Blueprint
      blueprint: quest-hub
      params:
        npc: { entry: 197 }          # resolves against npc_library.yaml
        quests: [33, 34]
        vendor: { entry: 201 }
        repair: true

  - id: "a2..."
    payload:
      type: GrindArea
      polygon: { ref: "polygons/kobold-camp" }
      targets: [{ entry: 305 }, { entry: 306 }]
```

Notice `npc: { entry: 197 }` rather than a fully embedded `NpcReference`
with name/zone/position/roles — that distinction is the subject of §8.

---

# 7. Shared Library Files

```yaml
# npc_library.yaml

- entry: 197
  guid: "0xF13000197..."
  name: "Marshal McBride"
  zone: "Northshire Abbey"
  position: { map: 0, x: 48.2, y: 42.7, z: 0.0 }
  roles: [QuestGiver]

- entry: 201
  name: "Brother Danil"
  zone: "Northshire Abbey"
  position: { map: 0, x: 49.1, y: 43.0, z: 0.0 }
  roles: [Vendor, Repair]
```

`quest_library.yaml` and `vendor_library.yaml` follow the same pattern —
one entry per referenced entity, populated by the Capture workflow
(Volume 3 §8, Volume 9 §8) the first time an author captures that NPC,
and updated in place if a later capture finds it's moved or gained a
role. This is Volume 5's "Why Libraries?" design decision, made literal:
Marshal McBride's data exists in exactly one file, referenced by ID from
every Action and every Operation that needs him.

---

# 8. On-Disk Reference Shape vs. Resolved Shape

Volume 5 defines Action payloads holding a full `NpcReference` struct
directly (e.g. `PickupQuestAction.npc: NpcReference`). Stored literally,
that would duplicate Marshal McBride's full record into every Action
that references him — exactly what §1 and §7 rule out.

This volume resolves that by introducing a third tier, sitting between
"file on disk" and "Volume 8's fully compiler-resolved RuntimeProfile":

```
Tier 1 — On-disk reference (this volume)
  { entry: 197 }
  Lightweight. Just enough to look up the record.

Tier 2 — Profile Manager load-time resolution (this volume, §10)
  Full NpcReference struct, exactly as Volume 5 defines it — hydrated
  from npc_library.yaml. This is the in-memory Profile the editor
  actually manipulates.

Tier 3 — Compiler Stage 2 resolution (Volume 8 §5)
  Re-resolved against live QueryServer data at compile time — current
  spawn state, not last-captured state. This produces the
  ResolvedActionPayload inside RuntimeProfile.
```

Tier 2 is what Volume 5 was describing all along; this volume just makes
explicit that the *authored, on-disk* shape is lighter than the
*in-memory, editor-facing* shape, and that Profile Manager's load
pipeline is what bridges them. Nothing in Volume 5 needs to change —
this is an additive clarification, not a correction.

---

# 9. Compiled Output — Not Source Controlled

```
sentinel-workspace/

├── .sentinel-cache/            ← gitignored
│   ├── compiled/
│   │   └── alliance-human-1-60.runtime.json
│   ├── resolution-cache/       ← Volume 8 §15's Resolution Cache
│   └── expansion-cache/        ← Volume 8 §15's Expansion Cache
│
├── .gitignore                  ← contains .sentinel-cache/
├── workspace.yaml
├── blueprints/
└── profiles/
```

The compiled `RuntimeProfile` is exactly as reproducible as Volume 8
§15 already establishes (`source_profile_hash` keyed caching) — treating
it as disposable build output, the same way a `target/` directory is
disposable in any normal Cargo workspace, is a direct consequence of
that guarantee rather than a new decision this volume has to justify.

---

# 10. Load Pipeline

```
ProfileManager::load(path)

    │
    ▼
Read profile.yaml manifest
    │
    ▼
Read npc_library.yaml, quest_library.yaml, vendor_library.yaml,
variables.yaml
    │
    ▼
For each path listed in manifest.operations:
    Read operations/*.yaml
    Resolve each on-disk reference (§8, Tier 1) against the loaded
    libraries → Tier 2 fully-hydrated structs
    │
    ▼
Resolve BlueprintReferences against workspace-level blueprints/
    │
    ▼
Check schema_version (manifest, and per-file if present — see §12)
    → run migrations if needed, in-memory only, before returning
    │
    ▼
Return fully-hydrated Profile (Volume 5 struct, in memory)
```

A reference that fails to resolve at this stage — an Action pointing at
an NPC entry not present in `npc_library.yaml` — is a Stage 1 Structural
Validation error (Volume 8 §4) the moment the Compiler runs, but Profile
Manager itself surfaces it earlier, at load time, since there's no
reason to wait for a compile to catch a file that's simply broken.

---

# 11. Save Pipeline

```
ProfileManager::save(profile)

    │
    ▼
For each Operation currently marked Dirty (Volume 2 §13):
    Lower Tier 2 struct back to Tier 1 on-disk shape
    Write operations/<slug>.yaml
    │
    ▼
If npc_library / quest_library / vendor_library / variables changed:
    Write only the changed library file(s)
    │
    ▼
If manifest-level fields changed (settings, operation list, metadata):
    Write profile.yaml
    │
    ▼
Clean Operations, unchanged libraries, and an unchanged manifest are
never rewritten — their file mtimes and git blobs stay untouched
```

This is what makes "one Operation, one file" pay off in practice:
editing a single Action inside Northshire produces a one-file diff
(`operations/northshire.yaml`), not a rewrite of the entire Profile.

Writes are atomic — write to a temp file in the same directory, then
rename over the target — so a crash or power loss mid-save can never
leave a half-written YAML file behind.

---

# 12. Schema Versioning on Disk

```yaml
# profile.yaml
schema_version: "1.1.0"
```

```yaml
# operations/eastvale.yaml  (untouched since an older schema version)
schema_version: "1.0.0"     # optional override; absent = inherit manifest's
...
```

Per-file overrides exist because Volume 5's "Why Operations? — Operations
compile independently" implies they should also *migrate*
independently. An author who hasn't touched Eastvale in months
shouldn't be forced through a bulk rewrite of every file in the Profile
just because Northshire picked up a new field — Profile Manager's
migration step (§10) runs per-file, against whichever `schema_version`
each file actually declares, and only rewrites files that actually
needed migrating.

---

# 13. Concurrent Access and File Watching

```
Reads          — lock-free, any number of concurrent readers
                 (editor, AnalyticsServer queries, background compiler)

Writes          — single advisory lock file per Profile directory
                 (.profile.lock), held only for the duration of the
                 atomic write in §11

Hot Reload      — a filesystem watcher on operations/*.yaml, debounced
                 (per Volume 2 §12) so a save doesn't trigger a reload
                 of its own write, and so rapid successive saves don't
                 each trigger a full validate+compile independently
```

A lock held by a crashed process is broken automatically after a short
timeout — this is a local single-author tool, not a multi-user database,
and the failure mode to optimize for is "never permanently block the
author from saving again," not strict lock correctness.

---

# 14. Git Workflow

```
git diff on a single-Action edit inside Northshire:

  operations/northshire.yaml | 3 +-
  1 file changed, 2 insertions(+), 1 deletion(-)
```

```
Merge conflicts are structurally rare because:

  - Two authors editing different Operations never touch the same file
  - UUIDs (Volume 5's "Why UUIDs?") mean reordering Actions inside one
    Operation never breaks a reference from another file
```

The one place conflicts do concentrate is the shared library files —
`npc_library.yaml` growing to hundreds of entries as a Profile matures
means two authors capturing different NPCs in the same session can both
touch the same file, even though their actual changes don't overlap
semantically. For large Profiles, this volume allows an equivalent
escape hatch to Operations' own file-per-item pattern:

```
npc_library/
├── 00197-marshal-mcbride.yaml
├── 00201-brother-danil.yaml
└── ...
```

a directory of one file per entry, functionally identical to the
single-file form and freely convertible between the two — Profile
Manager reads either shape transparently, and this is purely a
scale-driven authoring convenience, not a schema change.

---

# 15. Derived Fields Are Never Persisted

Volume 7 §3's `Operation` struct includes an `analytics: OperationAnalytics`
field. That field is never present in `operations/*.yaml` on disk.

```rust
#[serde(skip)]
pub analytics: OperationAnalytics,
```

Profile Manager's load pipeline (§10) populates it after loading, via a
live query to AnalyticsServer (Volume 10 §6) — the same pattern already
established for Tier 1→2 reference resolution, just sourced from a
different system. Persisting a metrics snapshot into a git-tracked YAML
file would mean every play session produces a spurious diff on data
nobody authored, which directly contradicts §1's diffability goal. Any
future struct field populated by an external system follows this same
`#[serde(skip)]` + load-time-hydration pattern by default, not the
exception.

---

# 16. Module Layout

```
sentinel-profile-io

├── manifest
├── operations
│   ├── reader
│   └── writer
├── libraries
│   ├── npc
│   ├── quest
│   └── vendor
├── reference_resolution     (Tier 1 → Tier 2, §8/§10)
├── migration
├── locking
├── watcher
└── models
```

This crate sits between Profile Manager (Volume 2 §4) and the
filesystem — Profile Manager calls into it for `load`/`save`, and it has
no knowledge of compilation, execution, or anything past producing a
fully-hydrated, Volume 5-shaped `Profile` in memory.

---

# 17. Design Decisions

## Why YAML instead of a custom DSL?

A custom format would need its own parser, its own editor tooling
(syntax highlighting, schema validation), and its own diff/merge
behavior built from scratch. YAML gets all of that for free from the
existing ecosystem while still meeting every readability goal in §1 —
introducing a bespoke format here would be solving a problem that
doesn't need solving.

## Why is the manifest's operation list non-authoritative for execution order?

Because Volume 8 §7 already computes execution order from each
Operation's own declared `dependencies` — having a second, potentially
contradictory ordering mechanism in the manifest would mean two sources
of truth that can disagree. The manifest list exists purely so Profile
Manager knows which files exist without needing to scan a directory,
and so the Explorer tree (Volume 3 §5) has a sensible default display
order.

## Why per-Operation-file schema versioning instead of one version for the whole Profile?

Consistent with Volume 5's own justification for Operations existing at
all — independent compilation implies independent everything else,
including migration. A single Profile-wide version would force a
big-bang migration the moment any one field anywhere changes, which is
exactly the kind of all-or-nothing maintenance burden Operations were
introduced to avoid in the first place.

## Why does the compiled RuntimeProfile not live in the Profile directory at all?

Putting build output next to source invites someone eventually
git-tracking it by accident, and invites confusion about which one is
authoritative after a schema change. Volume 8's hashing already
guarantees the compiled artifact is trivially reproducible from source
— there's no information in `.sentinel-cache/` that isn't recoverable by
recompiling, so it doesn't belong in the same tree as the files an
author actually owns.

---

# 18. Architecture Volumes Complete

With Volumes 1 through 11, every system this project's own internal
cross-references have pointed at now has a home:

```
1   Vision, Philosophy & Architecture
2   Runtime Architecture
3   In-Game UI Architecture
4   QueryServer Architecture
5   Canonical Profile Schema
6   Blueprint System
7   Operation System
8   The Compiler
9   Sylvanas Addon API Integration Layer
10  Analytics & Telemetry System
11  Profile Storage & File Format
```

Nothing currently open in any of these eleven volumes hands off to a
volume that doesn't exist. What's left isn't architecture — it's the
implementation tickets breakdown (phased, hour-estimated, matching the
pattern already used on the other Sentinel-family projects) and,
eventually, per-module `CLAUDE.md` files once an agent starts building
against this set. Both of those are downstream of "the architecture is
settled," which, as of this volume, it now is.

---

End of Volume 11
