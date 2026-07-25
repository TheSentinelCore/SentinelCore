# `adr07_worked_example.json` — provenance and deviations

Companion note for the R1 test fixture. It records exactly where the fixture departs from
ADR 07 §7.3.3 and why, so a future reader never has to re-derive it.

## 1. Provenance

| Item | Source |
|---|---|
| Profile structure and every field value | `sentinel/docs/adr/07_RUNTIME_PROFILE_SCHEMA.md` §7.3.3 (lines 1670–1975 post-audit) |
| Root required-key list | same ADR §7.2 (lines 1460–1577 post-audit) |
| Waypoint coordinates | `sentinel/docs/adr/restedxp guides/A-11-23.lua:215–231, 240, 247–254, 262, 278` |
| Game IDs (983, 5385, 2231, 2234, 3524, 12242, 2118, 2164, 7586, 984, 17182, map 1439) | ADR §7.3.2, verified there against `tbcmangos.sqlite` |

The archetype is the one §7.3.3 resolves for: Night Elf Hunter, Alliance, TBC, softcore,
AH-permitted, `mode: SpeedRoute`.

All 28 source route lines were re-verified line-by-line against the corpus: zone, `x`, `y` and the
source radius all agree. They visit 22 **distinct** coordinates, which is what the pool holds — see
D6 — so a source line maps to exactly one pool entry, but six entries are the target of two source
lines each. RestedXP coordinates are **zone percentages** and carry **no Z**, so `z` is `null`
everywhere; the trailing `,0` on each source line is a RestedXP flag argument, *not* a z coordinate.

## 2. The `_comment` keys, stripped and preserved verbatim

The model is `#[serde(deny_unknown_fields)]`, so `_comment` cannot survive in the JSON. The
prose is reproduced here verbatim against its task id. Task 1 carried no comment.

- **task 0** — "#sticky + #loop -> Background task holding MOVEMENT, running a CLOSED CIRCUIT"
- **task 2** — "second sticky circuit; .use 7586 is an op, .unitscan feeds watch_units"
- **task 3** — "zone NAME in source (Darkshore) normalises to the same map_id 1439 as tasks 0-2"
- **task 4** — "P1 — THE MULTI-DEPENDENCY TASK. Source lines 265-268 are the author's XXREQ hack:
  an empty #optional step carrying #requires, used because RXP allows only one requires per step.
  The compiler folds the placeholder away and emits BOTH predecessors directly in deps."
- **task 5** — "#optional + .xp 10+6760 -> fallback grind objective"
- **task 6** — "#completewith next -> CompletionSource::LinkedTo(7). Rides along with no channels
  of its own."
- **task 7** — "#requires BuzzBox1 -> deps [0]. Turn-in target is GAMEOBJECT 17182, so
  interact_target is null and the op carries the object. Verified: quest 983 ender is
  gameobject_involvedrelation 17182."

Two of those are load-bearing and must not be lost:

- **The XXREQ fold (task 4).** `A-11-23.lua:265–268` is an empty `#optional` step whose only
  content is `#requires RabidThistle` plus the author's own `--XXREQ Placeholder invis step until
  multiple requires per step` marker. RestedXP permits one `#requires` per step, so the guide
  author encodes a second predecessor as a throwaway step. The compiler folds that placeholder
  away and emits **both** predecessors directly, which is why `deps` is `[2, 0]` — plural, and in
  that printed order. The order is preserved as-is and deliberately **not** sorted.
- **The gameobject turn-in (task 7).** Quest 983's ender is `gameobject_involvedrelation` entry
  **17182**, not a creature. So `interact_target: null` on task 7 is *correct*, not an omission —
  there is no NPC to target.

## 3. Deviations from §7.3.3 — since folded back into the ADR

Every item below was a defect in the ADR, not a liberty taken by this fixture. The R1 model audit has
since **amended §7.3.3 itself** so the document and this file agree (ADR §9 items 21–24 and 26). The section
is kept as the derivation record: it is what shows the fixture was derived from the corpus rather than
typed freehand, and what a reader needs if they ever meet an artifact written against the pre-audit
text.

### D1 — `defaults` and `waypoint_pool` added (§7.2 requires them, §7.3.3 omitted them)

§7.2 lists both in the root `required` array and §7.1 declares both on `RuntimeProfile`, yet the
§7.3.3 listing printed neither — so the worked example could not satisfy its own schema. Both are
authored in here, and are now printed in the ADR too.

`waypoint_pool` — see D2 below for the indices.

`defaults` — derived from the ADR, not free-associated:

- `unknown_policy`: `{"type":"Defer","payload":{"budget_ticks":60}}`. §5.1.2's policy table states
  `Defer` is the **compiler default for `complete_when`**, and every `Defer` task in §7.3.3 uses a
  60-tick budget (task 6's 30 is a per-task override), so 60 is the consistent profile-level value.
- `combat`: the least surprising profile-level default consistent with §5.6 — stance `Defensive`,
  empty `targets`, empty `watch_units`, `leash_yards: 40`, `allow_adds: true`,
  `expect_group: Solo`. 40 is the value §7.3.3 task 5 uses for an unwhitelisted grind, i.e. the
  ADR's own "no whitelist" leash.

### D2 — waypoint indices renumbered: the ADR was off by one from task 1 onward

§7.3.3 gave task 0 an **18**-point route (`points: [0..17]`), but the corpus circuit at
`A-11-23.lua:215–231` has only **17** route lines: 3 × `.goto` (radius 0) then 14 × `.waypoint`
(radius 60). The ADR was off by one, so every waypoint index after task 0 shifts **down** by one.
Corrected, corpus-derived, authoritative — and now the ADR's numbering too:

| Task | §7.3.3 as printed | After the D2 renumbering | Fixture today (interned, D6) | Count |
|---|---|---|---|---|
| 0 | `[0..17]` | `[0..16]` | `[0,1,2,3,4,5,6,7,8,2,3,1,9,10,11,12,0]` | 17 |
| 1 | `[18]` | `[17]` | `[13]` | 1 |
| 2 | `[19..26]` | `[18..25]` | `[14,15,14,16,17,18,19,15]` | 8 |
| 3 | `[27]` | `[26]` | `[20]` | 1 |
| 7 | `[28]` | `[27]` | `[21]` | 1 |
| pool length | 29 implied | 28 | **22** | |

`radii` for task 0 is likewise trimmed from 18 entries to 17 (`[0,0,0]` then `60 × 14`), matching
the source radii exactly. All other `radii` arrays are unchanged from §7.3.3, and D6 changed no
`radii` array and no route *length* at all — only which pool slot each point names.

No 29th waypoint was invented to satisfy the ADR: §7.3.2 states "Nothing is invented". After
renumbering, pool indices 0–27 were each referenced exactly once with no gaps, which independently
corroborated the correction. That once-each property is **not** the invariant any more — D6 interns
the pool, and a circuit necessarily names some entries twice — but the count it rested on still
holds: 28 source route lines, 22 distinct coordinates, every pool entry reachable.

### D3 — `InArea` / `HearthBoundTo` field is `area`, not `area_id`

§5.1.1 writes `InArea { area_id, kind }` and `HearthBoundTo { area_id }`, but §7.1 and the §7.3.3
listing both use `area`. §7.1 is authoritative. The fixture uses `area` (task 6, both in
`lifetime.payload.terminate_on` and in `complete_when`).

### D4 — `tags_used` corrected: it is a census, and it was wrong in both directions

§7.3.3 originally declared thirteen tags. Four of them — `Wait`, `Delegate`, `Or`, `Not` — appear in
no task, and `QuestComplete`, which task 7's `applies_when` uses, was absent. §7.1 defines the field
as "every op/predicate tag referenced", i.e. a census, so the printed list contradicted its own
definition in both directions at once.

Measured by walking the artifact, it references exactly ten tags:

| Kind | Tags |
|---|---|
| ops | `Travel`, `TurnIn`, `UseItem` |
| predicates | `QuestComplete`, `QuestObjective`, `QuestInLog`, `QuestTurnedIn`, `InArea`, `XpAtLeast`, `And` |

Both directions are load-bearing, and ADR §5.10 now states it: a **spurious** tag makes a fail-closed
kernel refuse an artifact it could actually have run, while a **missing** tag lets the loader's check
pass on an artifact the kernel cannot fully evaluate — which defeats the check entirely. Pinned by
`tags_used_is_an_accurate_census_of_ops_and_predicates`.

### D5 — unit variants carry no `"payload": null`; the fixture is now byte-reproducible

§7.3.3 originally spelled unit variants of the adjacently-tagged enums two ways: mostly with an
explicit null payload (`{"type":"Exclusive","payload":null}`, `{"type":"Solo","payload":null}`,
`{"type":"Block","payload":null}`, …) but `completion` without one (`{"type":"OwnPredicate"}`). This
file used to preserve both forms verbatim. Verified empirically against serde 1, for
`#[serde(tag="type", content="payload")]`:

- **serialization omits** the content field for a unit variant — serde emits `{"type":"Exclusive"}`,
  never `{"type":"Exclusive","payload":null}`;
- **deserialization accepts both** — `{"type":"Exclusive"}` and `{"type":"Exclusive","payload":null}`
  load to the same value.

So **the ADR's printed spelling was the thing that was wrong, not the model.** §7.2's `$defs` require
only `["type"]` on those objects, and the only way to make the code emit a `null` would have been
eleven hand-written `Serialize` impls that buy nothing. The audit moved the ADR (§9 item 23) and all
19 envelopes in this file were normalised to `{"type": "X"}`.

**Consequence: this fixture is byte-reproducible.** `serialize(deserialize(fixture))` now compares
equal to `deserialize(fixture)` as *un-normalised* `serde_json::Value`s, which is what R3's digest
over the emitted bytes will depend on. An earlier revision of this note warned that the file was
**not** byte-stable under `serialize(deserialize(...))` and that round-trip tests had to compare
canonicalised values; that caveat is obsolete and has been removed. The comparison is still by parsed
`Value` rather than by raw string, but only for JSON number formatting: this file is hand-formatted
and writes `38.90` and `50.920`, which `serde_json` renders `38.9` and `50.92`.

Two-way acceptance is still covered, by `unit_variants_accept_the_adr_7_3_3_explicit_null_payload` in
`kernel_wire_shape.rs`, so artifacts written against the pre-audit text keep loading.

### D6 — the pool is interned: 22 distinct points, not 28 rows

§7.3.3 printed a **28**-slot `waypoint_pool`, one slot per source route line, in which six
coordinates appeared **twice**: old slots 9≡2, 10≡3, 11≡1 and 16≡0 (task 0's circuit) and 20≡18,
25≡19 (task 2's). Two clauses of the ADR say the opposite of that pool shape, neither hedged — §7.1
annotates the field "deduplicated; routes index into this", and §6.4 says the pool "deduplicates
shared points across tasks". §7.3.3 is the artifact those two clauses point at, so as printed it was
the counter-example to its own schema.

The pool is now interned on `(map_id, x, y, z)`, first occurrence kept, dropping old slots 9, 10, 11,
16, 20 and 25 — **22** entries. Old→new index map:

| old | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 | 12 | 13 | 14 | 15 | 16 | 17 | 18 | 19 | 20 | 21 | 22 | 23 | 24 | 25 | 26 | 27 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| new | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 2 | 3 | 1 | 9 | 10 | 11 | 12 | 0 | 13 | 14 | 15 | 14 | 16 | 17 | 18 | 19 | 15 | 20 | 21 |

**Repeated indices are now the only way a route can name a point twice, and the two routes that do
so do it for unrelated reasons.**

- **Task 0 names 0, 1, 2 and 3 twice each because the bot walks those coordinates twice.** It is a
  `Circuit` with `close: true`, and `A-11-23.lua:224`, `:225`, `:226` and `:231` really do re-visit
  `:217`, `:218`, `:216` and `:215`. Not a radius artefact — three of the four repeats change the
  radius (0 on the approach, 60 on the circuit); the geometry is the justification. These survive
  route-level dedup.
- **Task 2 names 14 and 15 twice because of the §2.6 double emission — it re-crosses nothing.**
  `A-11-23.lua:247` and `:248` are 4-arg `.goto`s naming the loop's anchors, re-emitted 5-arg by
  `:249` and `:254`; the radii `[0,0,50,50,50,50,50,50]` corroborate it. Route-level dedup will take
  task 2 from 8 points to 6.

Interning is a **pool** operation and never a route one — every route walks the identical sequence of
world coordinates it walked before, task 0 still has 17 points, task 2 still has 8, no `points` array
changed length, and no `radii` array changed at all.

Do not confuse this with the route-level deduplication §2.6 and §8 describe: collapsing a *single
source step* that emits the same coordinate twice shortens the route, which interning provably does
not do. That is a **later deliverable**, and task 2's route is still printed here in its
un-deduplicated 8-point form. The ADR now prints the same interned pool (§9 item 26), so this file
and §7.3.3 agree. Pinned by `no_two_waypoint_pool_entries_hold_the_same_coordinate`.

### Placeholder hashes

§7.3.3 prints both hashes as prose (`"<blake3-of-tagset>"`, `"<blake3-of-resolved-ids>"`), which
cannot satisfy §7.2's `^[0-9a-f]{64}$` pattern. Replaced with valid, obviously-synthetic 64-char
lowercase hex constants — a repeated hex word so no reader mistakes either for a real digest:

| Field | Value | Construction |
|---|---|---|
| `schema_hash` | `deadbeef` × 8 | `deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef` |
| `integrity.content_hash` | `cafebabe` × 8 | `cafebabecafebabecafebabecafebabecafebabecafebabecafebabecafebabe` |

R1 does not compute hashes at all — BLAKE3 and `ContentIntegrity` are R3. When R3 lands, these two
constants are the values it must replace. These two fields are the **only** remaining difference
between this file and §7.3.3's listing; everything else compares equal key-for-key.

## 4. Things kept verbatim that a reader may mistake for errors

These are **not** deviations. They are §7.3.3 as printed, preserved deliberately.

- **`integrity.world_build` contains a literal `…`** (`"sha256:…; quest_template=6599 …"`). The
  field is an unconstrained `String` with no pattern in §7.2, so the placeholder is loadable. Kept
  verbatim.
- **A pool index appearing twice in one route is not a typo.** The pool is interned (D6), so task 0's
  circuit revisits four coordinates by naming indices 0, 1, 2 and 3 twice, and task 2 names 14 and 15
  twice — the first four because the route really re-crosses itself, the last two because of the
  §2.6 double emission (D6). An earlier revision of this note claimed the opposite — that the fixture
  "pins the pre-dedup shape" and that dedup would need its own fixture. That is half obsolete: **this
  is the pool-interned fixture**, and the ADR now prints the same 22-entry pool — but it is *not*
  route-deduplicated, and task 2's 8-point route is the shape a later deliverable will collapse to 6.

- **`QuestObjective.need` is `0` on task 3.** Quest 984 has no `Req*` columns populated — it is an
  exploration objective (`.complete 984,1 -- Find a corrupt furbolg camp`), so `need: 0` is correct
  and the model must permit it (ADR §7.3.2, §8).

## 5. Self-consistency checks performed

Verified without compiling (the model is authored in parallel):

- `json.load` succeeds; 8 tasks, 22 pool points.
- All ten §7.2 root required keys present.
- Both hashes match `^[0-9a-f]{64}$`.
- Every route: `len(points) == len(radii)`, and every index `< 22`.
- No two pool entries share a `(map_id, x, y, z)` (D6).
- Pool indices 0–21 are each referenced at least once; no unused entries, no gaps. Six are referenced
  twice — four by task 0, which re-crosses its own path, and two by task 2, which carries the §2.6
  double emission. That is the interned pool working, not a pool defect.
- Each of the five routes walks the same coordinate sequence, point for point, that it walked under
  the pre-interning numbering.
- Every `deps` entry and the `LinkedTo(7)` payload resolve to an existing task id.
- Task 4 `deps == [2, 0]`, order preserved.
- Zero `_comment` keys remain.
- All 28 source route lines re-derived from `A-11-23.lua` and compared field by field against the 22
  pool entries they intern to.
- `tags_used` re-walked from the artifact (every op, plus `applies_when` / `complete_when` /
  `abort_when`, plus `Background.terminate_on`, recursing through `And` / `Or` / `Not`): the emitted
  set is exactly the ten declared tags, with nothing spurious and nothing missing (D4).
- Every `"payload": null` occurrence was confirmed to be a two-key `{type, payload}` unit-variant
  envelope before removal — 19 of them, and no ordinary nullable field was touched (D5).

Additionally verified by the test suite, against the compiled model:

- `serialize(deserialize(fixture))` equals `deserialize(fixture)` as **un-normalised**
  `serde_json::Value`s — `worked_example_reserialises_to_a_byte_equal_json_value`.
- `tags_used` is an exact census — `tags_used_is_an_accurate_census_of_ops_and_predicates`.
- The pool holds no coordinate twice — `no_two_waypoint_pool_entries_hold_the_same_coordinate` (D6).
