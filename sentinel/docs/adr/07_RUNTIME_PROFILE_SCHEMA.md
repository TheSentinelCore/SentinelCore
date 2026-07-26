
# 07_RUNTIME_PROFILE_SCHEMA.md

## Sentinel Questing

### Runtime Profile Schema — RestedXP ingest to kernel-executable artifact

**Version:** 1.0 Draft
**Status:** Proposal
**Target:** Project Sylvanas, TBC Classic 2.4.3, levels 1–70, both factions
**Consumer:** Quest Activity plugin, per `ADR-000 — Sentinel Kernel: API-First Plugin Architecture`
**Producer:** `sentinel-compiler` (Rust, offline) — the `Compiler::compile_kernel` library entry
point. **No binary emits one of these artifacts yet**; see §1.2 for delivery state.

**Numbering.** The repository's ADR sequence runs `00_PRD` … `06_QUESTING_SCHEMA_V2`. `07` is the next
free number. The kernel document is referred to throughout as ADR-000; see §1.1 for its status, which
is not what the sequence implies.

----------

# 1. D1 — Executive summary

The recommendation is a **task graph of containers**, not a list of actions.

A compiled profile is an array of `Task` records. A `Task` is the direct descendant of a RestedXP
`step`: an ordered bundle of operations that execute as one unit at one place, plus a completion
predicate, plus a declaration of which control channels it needs. Every runtime condition in the
corpus lowers into a single extended `Predicate` tree evaluated only by `Sentinel.objectives`. Every
static gate — class, race, faction, expansion, realm mode — is resolved away by the compiler, which
emits one artifact per character archetype. Concurrency is expressed as channel leases, not as a
background flag. Behaviours the kernel already owns (vendor, flight, hearth, bank, trainer, corpse)
are delegated with a payload rather than reimplemented.

**Read §1.2 before reading §5.** This document is written in the present indicative throughout, and
§1.2 is the only place that says which of those sentences describe working code.

Four findings drove the design and each contradicts an obvious default:

1. **`#sticky` and `#completewith` are not the same mechanism.** Only 37 steps carry both, against
   274 sticky-only and 5,423 completewith-only. They are separate axes — *lifetime* and *completion
   authority* — and the schema models them as two independent fields. Collapsing them into one
   "background" flag, which is the intuitive move, is wrong on the evidence (§2.4, §5.3).
2. **A step is a container, decisively.** 90.5% of steps carry two or more commands; the mode is four.
   One action per step is not a simplification, it is a misreading (§2.3).
3. **Player faction and reputation are not readable from the Sylvanas API at all.** This is not a
   preference for compile-time gating; it is a hard requirement, because the runtime physically cannot
   evaluate `<< Alliance` (§5.2, §5.8).
4. **The serialization question is not a codec question.** Measured, the entire profile decodes in
   ~306 ms of which only ~250 ms is parsing; the remaining ~53 ms is an irreducible LuaJIT table
   allocation floor. No format on the evaluation list gets under one frame. Reading one record out of
   an offset-indexed container costs 7.3 µs. The fix is the container, not the encoding (§6.2).

## 1.1 ADR-000's verified status — read this before relying on anything below

**ADR-000 is not committed to this repository.** I searched exhaustively before designing: no file
matches it under any name, `rg` finds no occurrence of `ControlBroker`, `objectives:satisfied`,
`schema_hash`, `tags_used`, or `Sentinel.control` anywhere outside `SentinelNavClient` and a test mock,
and the CodeGraph/graphify indexes return nothing. It exists as a conversation artifact whose own
header reads `Status: Proposal`.

So its status is **Proposal, uncommitted** — weaker than the task framing assumed. I have designed
against it as binding anyway, because a schema needs a fixed consumer. But the following decisions are
downstream of ADR-000 and change if it is rejected:

| If ADR-000 is rejected | What changes here |
|---|---|
| No ControlBroker / channels | §5.3 concurrency collapses to a scheduler-priority model; `channels` and `band` become dead fields. This is the largest single dependency. |
| No `Sentinel.objectives` single authority | §5.1 still holds — one predicate evaluator is right regardless — but `Predicate` becomes owned by the Quest Activity rather than the kernel. |
| No built-in behaviour plugins (§3.2) | All 11 `DELEGATE` verdicts in §4 become `KEEP`, and the Quest Activity must implement vendor/flight/hearth/bank itself. 4,210 command instances move. |
| Two-phase intent commit dropped | No schema change. The artifact never names intents. |

The parts that are **not** contingent: step-as-container, compile-time static gating, the tri-state
predicate result, the offset-indexed container, and the content-integrity fields. Those follow from the
corpus and the Sylvanas API, not from the kernel.

## 1.2 Delivery state — what is designed here versus what exists

Everything below §2 is written in the present indicative: "the compiler resolves", "the kernel
refuses", "the runtime probes". That is the register a schema document is written in, and on its own
it is indistinguishable from a report on working software. **Most of it is not working software yet.**
This section says which is which, so a reader can tell a contract from a description without reading
the source to find out.

Measured on the tree this revision was written against. The method is stated so each figure can be
re-run.

| Surface | Designed | Delivered | How this was measured |
|---|---|---|---|
| `Op` variants | 13 (§7.1, §7.2) | **4** — `Travel`, `Accept`, `TurnIn`, `UseItem` | Construction sites in `compiler/src/`, i.e. `k::Op::X { … }` in expression position. The other nine appear only as `match` patterns or in doc comments. |
| `Predicate` variants | 24 (§7.1, §7.2) | **11** — `And`, `Or`, `Not`, `QuestInLog`, `QuestComplete`, `QuestTurnedIn`, `QuestObjective`, `LevelAtLeast`, `XpAtLeast`, `InArea`, `ItemCount` | Same method. The eight leaf arms live in `compiler/src/kernel/predicate.rs::leaf`; `And` / `Or` / `Not` come from the same file plus `task_graph.rs::fold_and`. |
| `Op::Delegate` and §5.5's delegation table | 11 commands, **4,210 instances** | **nothing** | `Op::Delegate` is never constructed anywhere outside tests — only pattern-matched, in `task_graph.rs`'s irreversibility check. `DelegatePayload`, `BehaviorId`, `VendorMode`, `FlightMode`, `HearthMode`, `BankMode`, `StableMode` and `CorpseIntent` are declared, round-tripped and unreachable. |
| A binary that emits an ADR 07 artifact | §6.2.5's container, §7.1's root | **none** | The workspace has two binaries. `compiler/src/main.rs` (`sentinel-compile`) calls `Compiler::compile` — the **ADR-05** path, which emits `sentinel_models::runtime::RuntimeProfile`, a different and unrelated struct. `Compiler::compile_kernel` is called only from `compiler/tests/`. `editor`'s `import-guides` produces authoring JSON. |
| A Lua loader for the artifact | §5.4's fail-closed load, §6.2.5's chunked warmup | **none** | `magic`, `schema_hash`, `tags_used` and `waypoint_pool` appear nowhere under `sentinel/` outside this ADR and ADR 08. Nothing in the runtime can read one of these files. |
| The two BLAKE3 digests and world provenance | §5.4.1 | **placeholders** | `compile_kernel` emits zeroes; §7.3.3 prints synthetic hex. Pinned as *not yet computed* by `compiler/tests/kernel_lowering.rs::compile_kernel_emits_zero_placeholder_digests_not_computed_ones`. |
| The first-touch `expect_name` probe | §5.4.1 | **none** | It is a proposal that needs kernel support (§9 item 15). `expect_name` is carried in the artifact; nothing compares it against an observed unit. |
| Route-level coordinate dedup | §2.6, §5.7, §8 — 4,190 triples | **none** | Explicitly a later deliverable; §7.3.3's task 2 is printed in its un-collapsed 8-point form (§9 item 26). |

**What *is* delivered, end to end.** One real guide excerpt (`A-11-23.lua:211–280`) lowers through
`parse_guide` → `ProjectBuilder::build` → `Compiler::compile_kernel` into the exact artifact §7.3.3
prints, compared field for field, with the ids resolved against `tbcmangos.sqlite`
(`compiler/tests/kernel_worked_example.rs`). The model in §7.1 exists in full as
`sentinel_models::kernel`, including the variants nothing constructs; every dispatched enum's wire
shape is pinned (`shared/tests/kernel_wire_shape.rs`); archetype gate resolution, band assignment,
route aggregation, the unknown-policy rule and the tag census all have their own suites.

So **9 of 13 `Op` variants and 13 of 24 `Predicate` variants are declared, wire-pinned and
unreachable** — which is a defensible state for a schema ADR, but not one a reader should have to
infer from the absence of a sentence saying so.

**Why the unreachable variants are still in §7.1 rather than deleted.** They are not speculation:
each is justified in §4's disposition table by a measured corpus command with an instance count, and
§5.1.1 argues the model is unsatisfiable without them. Deleting them would make the schema look
finished and force a breaking change to every artifact when the missing lowerings land (§6.5's
`schema_version`). Declaring them costs a variant and an unreachable `$defs` entry; omitting them
costs a format migration. What it does not license is prose that reads as though they were reachable
— which is what this section exists to correct.


----------

# 2. D2 — Corpus analysis

## 2.1 Method

Seven `.lua` files under `sentinel/docs/adr/restedxp guides/`, 182,851 lines, 6,909,964 bytes.
`The Burning Crusade.lua` alone is 154,328 lines / 5,704,898 bytes, matching the stated scale.

Tokenisation, applied line-by-line over raw bytes:

- **Step** — a line matching `^step\b`. Every step line in the corpus begins at column 0; there are no
  indented step headers.
- **Command** — `^\s*\.([A-Za-z_][A-Za-z0-9_]*)`. Commented-out commands (`--  .goto …`) do not match
  and are excluded.
- **Directive** — `^\s*#([A-Za-z_][A-Za-z0-9_]*)`.
- Trailing ` >> display text` and `-- comment` are stripped before argument analysis.

## 2.2 Independently derived counts, against the stated baseline

| Metric | Baseline | Derived | Δ |
|---|---|---|---|
| Distinct `.` commands | 74 | **74** | **0 — exact** |
| Distinct `#` directives | 48 | **49** | +1 |
| `step` blocks | 22,282 | **23,894** | +1,612 (+7.2%) |
| Command instances | 107,620 | **115,021** | +7,401 (+6.9%) |
| Directive instances | 16,339 | **17,598** | +1,259 (+7.7%) |

**The distinct-command count matches exactly at 74**, which is strong evidence the tokeniser is
correct. Two discrepancies remain, and I resolved one of them.

**Directives, 49 vs 48 — resolved.** The corpus contains `#completewithTBTurnins`
(`The Burning Crusade.lua:211`), a **missing-space typo** of `#completewith TBTurnins`. A tokeniser
that prefix-matches against a known directive table folds it into `#completewith` and reports 48
distinct; a tokeniser that reads the identifier greedily, as mine does, reports 49. Both are defensible.
I report 49 and treat the extra as a malformed instance of `#completewith` (§4, §5.10 — whose closed
alias table is where the six real typos are normalised; an earlier revision of this sentence cited a
non-existent §7.6).

**Instance counts, ~7% high — unresolved.** I tested and eliminated four hypotheses:

- *Whole-file exclusion* — no subset of the seven files sums to the 1,612-step delta.
- *Expansion filtering* — dead. All 277 `RegisterGuide` blocks carry `#tbc`; there is no
  `#wotlk`-only or `#classic`-only guide to exclude.
- *Duplicate guide bodies* — 277 guides, 272 distinct bodies; deduplicating removes 1 step and 47
  directives, nowhere near the delta.
- *Indentation sensitivity* — dead, and instructive: 97,956 of 115,021 commands sit at column 0, not
  indented, so an indentation-anchored regex would undercount by 85%, not 7%.

The per-token deltas are also **not uniform** (`.goto` +7.5%, `.dungeon` +10.0%,
`.isQuestTurnedIn` +1.4%), which rules out a clean proportional subset. The most likely remaining
explanation is that the baseline was computed against a different snapshot of the guides. **I have not
adopted the baseline figures.** Every count in this document is derived, and the arithmetic in §4 uses
my numbers so it is internally consistent.

## 2.3 Step-as-container — settled by the histogram

| Commands in step | Steps | Cumulative |
|---|---|---|
| 0 | 360 | 1.5% |
| 1 | 1,899 | 9.5% |
| 2 | 1,873 | 17.3% |
| 3 | 4,813 | 37.4% |
| 4 | **6,286** | 63.7% |
| 5 | 3,520 | 78.5% |
| 6–10 | 3,469 | 93.0% |
| 11+ | 1,674 | 100% |

**21,635 of 23,894 steps (90.5%) carry two or more commands.** The distribution peaks at four. A
schema that emits one action per step is not lossy at the margin; it misrepresents the primary unit.

Ordering within a step is real but positional, not arbitrary. Mean relative position (0 = first,
1 = last) across the corpus:

`.goto` 0.26 · `.vendor` 0.37 · `.train` 0.42 · `.turnin` 0.43 · `.accept` 0.56 · `.complete` 0.56 ·
`.target` 0.77 · `.mob` 0.78 · `.xp` 0.82

The canonical shape is **navigate → interact → declare**. `.target`, `.mob` and the `.is*` predicates
cluster at the end because they are *annotations on the step*, not sequential actions — they say who to
talk to, what is legal to kill, and when the step is done. The schema reflects this by separating
`ops` (ordered, executed) from step-level `combat`, `interact_target` and `complete_when` (unordered,
declarative).

## 2.4 Concurrency — `#sticky` and `#completewith` are distinct

| | Steps |
|---|---|
| `#sticky` **and** `#completewith` | **37** |
| `#sticky` only | 274 |
| `#completewith` only | 5,423 |
| `#loop` **and** `#sticky` | 56 |
| `#loop` total | 1,661 |

The two directives are effectively disjoint as authored. Their command payloads differ accordingly:

- **Inside `#sticky` steps**: `.waypoint` 416, `.goto` 296, `.complete` 136, `.mob` 89. Sticky work is
  overwhelmingly *movement plus a kill/collect objective* — it wants `MOVEMENT`.
- **Inside `#loop` steps**: `.goto` 14,117, `.mob` 2,846, `.complete` 1,958. Loops are patrol circuits
  with a kill objective.

`#completewith` takes `next` in 2,681 of 5,469 uses; the remaining 2,788 name one of **1,246 distinct
labels**.

**The nuance that reconciles this with the kernel's framing.** Reading the actual RXPGuides
implementation (`GuideWindow.lua:1917`):

```lua
if step.completewith and not step.tip then step.sticky = true end
```

`#completewith` *implies* sticky **at runtime**. So the two are authored disjointly but converge in
execution — which is why the combined figure of ~5,700 is meaningful even though the intersection is
37. The schema keeps them as two fields precisely because the authored intent differs: one is a
lifetime, the other is a completion authority (§5.3).

## 2.5 Gating grammar

196 distinct step-level gate expressions. Confirmed operators, each with a corpus witness:

| Operator | Meaning | Witness |
|---|---|---|
| space | AND | `step << NightElf !Druid` (20 uses) |
| `/` | OR | `step << Warrior/Paladin/Rogue` (37 uses) |
| `!` | NOT | `step << !Mage` (312 uses) |

`/` binds **looser** than space: `step << Gnome !Warlock/Dwarf !Paladin` (14 uses) reads
`(Gnome ∧ ¬Warlock) ∨ (Dwarf ∧ ¬Paladin)`. `step << Alliance/Horde Hunter` (10 uses) is ambiguous under
that precedence and is flagged in §9.

Token vocabulary: 9 classes, races, `Alliance`/`Horde`, expansions (`tbc` 223, `wotlk` 84, `era` 14),
`DK` 81, and `skip` 147. Junk tokens (`if`, `checking`, `mount`, `nothing`) all originate from
commented-out lines and are not real gates.

**Gating is not step-only.** There are **3,052 command-level `<<` gates across 134 distinct
expressions** — a single command inside a shared step can be class-gated. This is the decisive
evidence for P2 (§5.9).

*(Measured under the importer's own definition of a command — `lexer.rs::lex_body_line`, a body line
beginning with `.`. An earlier revision claimed 3,412 across 172; neither figure is reproducible
under any single slicing of the corpus, and the two nearest matches come from **different** slices,
so they cannot both be right. Counting display-text lines and in-step `#` directives as well gives
4,499 across 173. The conclusion is unaffected and in fact strengthened: against 6,069 step-level
gates, that is roughly one gate below the step for every 1.35 on it.)*

## 2.6 Spatial representation

`.goto` uses **two mutually exclusive coordinate systems**:

- **Zone-percentage** — `<zone name|zone id>,<x>,<y>` with x,y always in 0..100. 35,449 name-form,
  1,765 numeric-id form (4.6%).
- **World coordinates** — `<uiMapId>/<continentMapId>,<x>,<y>` with raw world coords, never in
  0..100. 873 instances **on `.goto`**, e.g. `The Burning Crusade.lua:7210` →
  `.goto 1419/0,-3196.90015,-11815.10059 << !tbc !wotlk`. Corpus-wide the raw-world form appears
  **929** times (`.goto` 873, `.waypoint` 48, `.groundgoto` 8).

**The number after the slash is a continent map id, not a floor.** *(An earlier revision of this
section spelled the form `<mapId>/<floor>`. It is not a floor, and the mistake matters: it is the
value that becomes `Point::map_id` in the artifact, so reading it as a floor and taking the ui map
id instead puts every raw-world waypoint on the wrong map.)* Measured, two independent ways:

- Across all 929 raw-world lines the value after the slash takes exactly **three** values —
  `0` (207), `1` (268), `530` (454). Those are Eastern Kingdoms, Kalimdor and Outland, the three
  continents the corpus visits. No floor index is 530, and a real floor axis would not partition a
  seven-file corpus into precisely the continent set.
- For every ui map id that appears in *both* forms, the value after the slash equals that zone's
  measured continent: `1429/0` Elwynn Forest → 0, `1437/0` Wetlands → 0, `1453/0` Stormwind City →
  0, `1439/1` Darkshore → 1. Four for four against `ZONE_TABLE` (`SentinelQuesting/shared/src/zone.rs`).

**Corollary for the zone-percentage form.** A converted percentage carries the zone's **continent**
as its `map_id`, never the ui map id it was authored against. `.goto 1439,36.051,44.757` and
`.goto Darkshore,36.051,44.757` are the same point on continent `1`; `1439` is a lookup key that
must not survive the lookup. A compiled `Point` whose `map_id` is `1439` is therefore a **named bug
signature** — a percentage that survived compilation wearing a ui map id — and is exactly the ADR 06
invariant 3 failure, visible without needing to know the right answer.

**Axis order: the first authored value is world Y and the second is world X.** This holds in *both*
coordinate systems and is not the obvious reading, so it is recorded rather than assumed. Evidence:
`A-11-23.lua:764` and `:769` are consecutive steps of one guide that click two objects on the same
Darkshore beach — a Beached Sea Turtle and a Beached Sea Creature — authored one in each system:

```
.goto 1439,37.105,62.167       (zone percentage)  then  .accept 4722
.goto 1439/1,579.500,5240.300  (raw world)        then  .accept 4728
```

Under the ordering above they lower **385 yd** apart, which is one beach. Under the reversed reading
they lower **6,911 yd** apart, which is most of the zone. Only one of the two is survivable, and it
is this one. `ZoneMap` (`SentinelQuesting/shared/src/zone.rs`) documents the matching convention for
the percentage transform: world X interpolates along the map's *y* axis, world Y along its *x* axis.

The three `.goto` figures partition it exactly: 35,449 + 1,765 + 873 = 38,087. *(An earlier revision
printed 36,322 name-form beside 873 raw-world as if the two were disjoint. They are not: 36,322 was
computed as "first field is not a bare integer", which silently includes every raw-world entry,
because `1419/0` is not a bare integer. 35,449 + 873 = 36,322.)*

**Discriminate on the `/` in field 0, not on the 0..100 range.** Both tests happen to agree on this
corpus — no zone-form coordinate falls outside 0..100 and no raw-world coordinate falls inside it —
but reversing the order is exactly how the 36,322 double-count arose.

**`.goto` is not the only coordinate-bearing command.** Five carry coordinates: `.goto` (38,087),
`.waypoint` (593), `.line` (485), `.groundgoto` (114), `.flygoto` (1) — 39,280 live instances.
`.line` is variadic from arity 5 to 259 (a 129-point polyline at `The Burning Crusade.lua:14816`)
and carries 6 malformed lines of its own, including one with an empty x field that shifts an entire
polyline by one position (`The Burning Crusade.lua:114541`).

Both zone forms appear **in the same file for the same zone**: `A-1-11-Dwarf-Gnome.lua:1955` uses
`1426` while `:1975` uses `Dun Morogh`. Normalisation is unavoidable.

Arity: 3 args (16,231), 4 (5,436), 5 (16,353), 6 (67 — all malformed).

**The 67 six-arg lines are three distinct defects, not one.** An earlier revision described them all
as "a decimal typed with a comma: `Un'Goro Crater,20.6,60,4,70,0` should be `60.4`". Only **4** have
that shape. The other 63 are:

| Shape | Count | Example |
| --- | --- | --- |
| Stray **trailing** zero — radius and flag intact | 60 | `.goto Silithus,<x>,<y>,70,0,0` |
| Decimal typed with a comma | 4 | `.goto Un'Goro Crater,20.6,60,4,70,0` |
| Stray **leading** zero | 3 | `.goto Burning Steppes,<x>,<y>,0,60,0` |

An importer written to the old description — fuse fields 2 and 3 into a decimal — would **corrupt 63
of the 67** into wrong coordinates and drive the character somewhere else entirely. This is the
concrete reason malformed arity must be a hard error and never a repair: `20.6,60,4` is equally
readable as `60.4` or as `60` with a stray field, and the corpus contains both.

The 4th positional is an arrival radius; observed values 0 (3,983), −1 (586), then 5–200, across 41
distinct values of which the most common is 50 (4,767). The 5th is **invariantly 0 across all 16,353
five-arg instances** — its meaning is UNDETERMINED (§9).

Decisive disambiguation: `A-11-23.lua:247` and `:249` give the *same coordinates* as
`.goto 1439,38.226,52.780,0` and `.goto 1439,38.226,52.780,50,0`. The lone trailing `0` in the 4-arg
form is therefore not a radius.

**Importer gotcha — every figure here is measured over the 7-file corpus.** 1,723 steps (1,304 of them
`#loop`) contain at least one repeated `zone,x,y`, giving **4,190** distinct repeated coordinate
triples across **4,600** redundant emissions. An importer treating each `.goto` as a distinct route
node doubles the path. The compiler deduplicates — a **route-level** collapse, one that shortens the
route. It is *not* the `waypoint_pool` interning of §7.1 and §7.3.3, which shrinks the pool and
provably never changes a route's length (§9 item 26).

**No section of this document demonstrates the route-level collapse yet.** An earlier revision cited
§7.3 as its own proof; that forward reference was wrong and is withdrawn. §7.3.3 prints task 2 in the
doubled form it is supposed to fix — 8 route points where 6 suffice, because `A-11-23.lua:247`/`:248`
state the loop's anchors in 4-arg form and `:249`/`:254` re-emit the same two coordinates in 5-arg
form. When the collapse lands, that route becomes the worked example for it.

**Do not key that collapse on "once 4-arg, once 5-arg".** That shape is the plurality, not the rule: it
covers 2,897 of the 4,190 triples (**69%**). 779 are (5,5), 154 are (3,5), and 285 triples repeat three
or more times, so a predicate matching only a 4-arg/5-arg pair misses 31% of the duplicates.

*(An earlier revision of this section stated 553 steps and 1,252 triples. Both are refuted: roughly
3.3× too low, and not reproducible under any of 21 tried definitions of* step *and* duplicate*.)*

----------

# 3. D3 — Prior art

## 3.1 RXPGuides — the source format's own parser

Read directly from `github.com/RestedXP/RXPGuides` at commit `d69e178`, not from documentation.

**Line grammar** (`GuideLoader.lua::parseLine`, 804–914), strip order: `<<` gate → `#tag[=]value` →
`>> display` → `^%.(%S+)%s*(.*)` command. Bare `+text` is an objective line; bare `*text` is a
tooltip-only line. Args comma-split by default, **but `addon.separators` overrides it** —
`.target`/`.mob`/`.unitscan` split on semicolon, `.link`/`.clicknext` take the rest of the line
verbatim. This is why `.target Korfax, Champion of the Light` is one argument, not two.

**Unknown `.tag` is a hard error** (`addon.error("Invalid function call (." .. tag .. ")")`). Fail-loud
is the shipped behaviour, and Sentinel should match it at ingest (§5.10).

**Elements are dual-mode**, discriminated by `type(self) == "string"`: the same function is the parser
and the runtime handler, and the parsed table *is* the live object. There is no compiled artifact.

**`#completewith` resolution** (`GuideWindow.lua:682–704`) resolves `next` to `step.index + 1` and
otherwise looks up `guide.labels[…]`; **`#requires` mutates an earlier step at load time**
(`:1918–1928`), synthesising a `completewith` back-edge onto the step it depends on. Control flow
therefore cannot be read top-to-bottom.

**Known defects worth not repeating.** `applies()` caches gate results in `local aCache = {}`
(`GuideLoader.lua:29`) which is **never invalidated anywhere in the addon**, and `playerLevel` is read
*inside* the cached computation — so a level-threshold gate freezes at whatever level the player was
when the string was first evaluated. The cache key is also the gate string alone while the result also
depends on `customClass`. There is **no validation pass**: an unresolved `#completewith foo` silently
never fires.

**Adopt:** the `.command args >> display << gate` line shape; `<<` as parse-time elimination; the
`events[tag]` declarative reactivity table; fail-loud on unknown tokens.
**Avoid:** the unkeyed cache; the dual-mode function; load-time mutation of earlier steps; the absence
of a validator.

## 3.2 Honorbuddy (WoW) — the cautionary XML case

Honorbuddy, Bossland GmbH, discontinued after the 2017 Blizzard litigation. Quest profiles are XML:
`<QuestOrder>` containing `<PickUp>`, `<TurnIn>`, `<If>`, `<While>`, and `<CustomBehavior>` elements,
with a companion `QuestBehaviors` repository of C# behaviour classes (`InteractWith`, `RunMacro`,
`WaitTimer`, `ForcedDismount`).

Its defining decision — and its defining problem — is that **conditions are embedded C# expression
strings** evaluated at runtime, e.g. `Condition="Me.Level &gt;= 20 &amp;&amp; !HasQuest(1234)"`. That
buys unlimited expressiveness and costs everything else: profiles cannot be statically validated, a
condition typo surfaces as a runtime exception mid-run, the expressions bind to an API surface that
changed every patch, and profile packs broke wholesale on client updates. This is the strongest
available argument for Sentinel's compiled `Predicate` AST over any embedded scripting.

**RebornBuddy is the Final Fantasy XIV product of the same lineage and is not evidence about
Honorbuddy.** Its profile format and behaviour set differ and I have not cited it.

I could not reach primary Honorbuddy documentation (the vendor site and forums are gone); the structure
above is corroborated across archived community profile repositories and behaviour source, and I flag
element-name precision as medium confidence in §9.

## 3.3 Guidelime — the closest open analogue

Open-source WoW Classic guide addon with a bracket-code markup (`GuideParser.lua`). Its transferable
strength is that **the entire vocabulary is one 30-line declarative table** (`GP.codes`) with the
reverse map derived, including first-class `--deprecated` aliases (`COMPLETE_WITH_NEXT = "C"` "same as
OC"). Conditions lower into **typed struct fields** on the step (`step.spellMin`, `step.repMax`,
`step.itemMax`) rather than a string re-parsed at runtime — independent validation of Sentinel's
compile-to-typed-condition approach.

Its weaknesses are equally instructive: **no labels, no join edges** (`[OC]` can only ever mean "the
next step"), so non-adjacent dependencies are inexpressible; **no sticky equivalent**, so "kill 10 boars
while you run this route" has no clean encoding. Sentinel needs Guidelime's *table discipline* with
RXP's *label expressiveness*.

## 3.4 LazyBot / Lazy Evolution — the tiering ADR-000 is built on

C# out-of-process bot (`descention/LazyBot`, GPLv3). Three tiers: `ILazyEngine` (activity, supplies
`List<MainState>`), `MainState` (`Priority` / `NeedToRun` / `DoWork` — a four-member contract), and
`ILazyPlugin` (ambient `Pulse`). The scheduler sorts states by descending priority and runs the first
whose guard passes, then `break`s — one state per tick, with a guaranteed lowest-priority `StateIdle`
making the selector total.

Grind routes are XML with `Waypoint` / `GhostWaypoint` / `ToTown` lists, entered **at the nearest point
rather than at index 0** — a genuinely good recovery model that Sentinel should copy for corpse runs.

**The single worst anti-pattern in the codebase** is profile loading: `GrindingProfile.LoadFile` is a
sequence of ~8 independent `try { … } catch { }` blocks with *empty* catch bodies, each silently
falling back to a hardcoded default. A profile can be 90% broken and still "load". Sentinel's
fail-closed artifact (§5.4) is the deliberate inversion of this. Also: coordinate parsing is
culture-dependent, conditions cannot nest (one `MatchAll` bool per rule), and **there is no completion
model at all** — `MainState` has a precondition but never an "am I done", so LazyBot can grind
indefinitely but can never finish a quest chain.

## 3.5 RuneMate TreeBot (non-WoW) — the profiles-as-code extreme

RuneScape/OSRS. Profiles are **not data**: a bot is a compiled Java class hierarchy of `BranchTask`
(conditions only), `LeafTask` (effects only), and `TreeTask`, rooted at `createRootTask()`. Both
`successTask()` and `failureTask()` are mandatory and non-null, so branching is total — no silent
fallthrough, which is a stronger guarantee than either RXP or Guidelime provides.

The tree is **stateless per tick**: it re-derives the whole situation from live world state, so
interruption recovery is free — there is no cursor to resume. The cost is disqualifying for Sentinel:
nothing can be imported, validated, diffed, or shipped without compilation, and with no cursor there is
no progress, no ETA, and no blocked-reason for the runner cockpit.

**Adopt:** the branch-holds-only-conditions / leaf-holds-only-effects discipline, and mandatory
explicit failure branches — that discipline is exactly what prevents the fail-open condition bug.
**Avoid:** profiles as code; full statelessness.

----------

# 4. D4 — Command disposition table

*Core deliverable.* All 74 commands and all 49 directives. Use counts are my derived figures (§2.2).
Verdicts: `KEEP` (becomes a first-class op), `MERGE` (folded into another construct), `TRANSFORM`
(becomes a different kind of construct, usually a `Predicate`), `DELEGATE` (handed to an ADR-000
behaviour plugin per §3.2 of that document), `DROP`.

## 4.1 Commands (74)

| Source token | Uses | Verdict | Maps to | Justification |
|---|---|---|---|---|
| `.goto` | 38,087 | KEEP | `Op::Travel { waypoints }` | Primary movement. Zone/world coords normalised to `(map_id, x, y, z?)` by the compiler. |
| `.target` | 13,352 | MERGE | `Task.interact_target` / `Op::Interact.target` | Not a verb — it names the NPC that `.accept`/`.turnin`/`.train` act on. `+`-prefix (1,292) binds to the preceding quest line, becoming per-op rather than per-task. |
| `.turnin` | 7,712 | KEEP | `Op::TurnIn { quest, reward_choice, optional }` **plus the derived predicate pair** | 2nd arg is reward index (proven: `A-1-11-Human.lua:155/156` turn in quest 33 with reward 2 vs 1, split by armour class). Negative id ⇒ `optional: true` (38 instances). A step whose only completion authority is its own hand-in also gets `applies_when: QuestComplete{q}` / `complete_when: QuestTurnedIn{q}` — §7.3.3's turn-in task carries both and authors neither, and without them the task has no completion authority at all. Emitted only for a **single** hand-in with no `any_of`; 540 corpus steps hand in more than one quest and get a `HAND_IN_PREDICATES_NOT_DERIVED` diagnostic instead of an invented disjunction (`compiler/src/kernel/task_graph.rs::hand_in_predicates`). |
| `.accept` | 7,490 | KEEP | `Op::Accept { quest }` | Core verb. |
| `.mob` | 7,456 | TRANSFORM | `Task.combat.targets: Vec<CreatureEntry>` | Not an action — a target whitelist feeding the combat policy (C6). Names resolve to entries via MaNGOS `creature_template`. |
| `.complete` | 7,218 | TRANSFORM | `Predicate::QuestObjective { id, index, need }` | The step's completion authority. `need` is baked from `quest_template.ReqItemCount*`/`ReqCreatureOrGOCount*`, removing the need to parse a localized progress string for the denominator. |
| `.isOnQuest` | 3,139 | TRANSFORM | `Predicate::QuestInLog` (OR-list ⇒ `Or`) | Multi-arg lists are any-of, up to 11 ids. |
| `.collect` | 3,044 | TRANSFORM | `Predicate::ItemCount` + `Task.loot_filter` | Acquire-N-of-item; optional 3rd arg is the owning quest. |
| `.xp` | 2,133 | TRANSFORM | `Predicate::XpAtLeast { level, offset }` | Two forms: `4-420` (level minus xp) and `>5,1` (comparison). Grind-to-level objective. |
| `.zoneskip` | 2,032 | TRANSFORM | `Predicate::InArea { kind: Zone }` | Skip-if-already-arrived guard on travel steps. |
| `.use` | 1,678 | KEEP | `Op::UseItem { item }` | Quest-item use, including quest-starting items. |
| `.itemcount` | 1,666 | TRANSFORM | `Predicate::ItemCount { id, cmp, count }` | Carries explicit `<`/`>` operators — the direct justification for adding `cmp` (C1). |
| `.train` | 1,653 | DELEGATE | `behavior.trainer` — payload `{ spell_id, npc_entry, pos }` | 1-arg = action (train spell); 2-arg (`,1`/`,3`) = condition ⇒ `Predicate::SpellKnown`. Split by arity. |
| `.isQuestTurnedIn` | 1,488 | TRANSFORM | `Predicate::QuestTurnedIn` | Maps to `core.quests.is_quest_flagged_completed`. Distinct from complete-but-unhanded. |
| `.isQuestComplete` | 1,389 | TRANSFORM | `Predicate::QuestComplete` | Objectives met, not yet handed in. |
| `.dungeon` | 1,351 | TRANSFORM | Archetype gate ⇒ compile-time variant selector | A GATE, not an action: marks a step as belonging to a dungeon variant of the guide. `!` negates. Case is inconsistent (`Mara` 105 / `MARA` 91) and is normalised. |
| `.zone` | 1,063 | TRANSFORM | `Predicate::InArea { kind: Zone }` | Travel-completion condition. |
| `.subzone` | 991 | TRANSFORM | `Predicate::InArea { kind: SubArea }` | Numeric AreaTable id. |
| `.isQuestAvailable` | 930 | TRANSFORM | `Predicate::QuestAvailable` | Obtainable — prerequisites/level/rep satisfied and not already done. |
| `.subzoneskip` | 820 | TRANSFORM | `Predicate::InArea { kind: SubArea, negate }` | `,1` negates; `,2` is a distinct mode. |
| `.fly` | 741 | DELEGATE | `behavior.flightpath` — payload `{ dest_node, npc_entry, pos }` | Taxi travel. Behaviour does not exist in ADR-000 §3.2 — see §5.5. |
| `.unitscan` | 735 | TRANSFORM | `Task.combat.watch_units` | Registers a roamer/rare/low-spawn name to watch for; feeds targeting, not a standalone action. |
| `.waypoint` | 593 | KEEP | `Op::Travel { waypoints, route_kind }` | Route node rather than destination; see C7. |
| `.cast` | 589 | KEEP | `Op::Cast { spell }` | Also covers "click this object which casts spell N". |
| `.bindlocation` | 557 | TRANSFORM | `Predicate::HearthBoundTo { area }` | Silent skip on current hearth bind; `,1` negates. |
| `.cooldown` | 549 | TRANSFORM | `Predicate::CooldownCmp { kind, id, cmp, secs }` | `item,6948,>2,1` — hearthstone gating with an explicit operator. |
| `.skill` | 507 | TRANSFORM | `Predicate::SkillCmp { line, cmp, value }` | Explicit `<` operator present (`A-23-30.lua:1008` `.skill cooking,<50,1`). Readable via `core.spell_book.get_profession_info`. |
| `.line` | 485 | DROP | — | Draws a polyline on the addon's map to show an NPC patrol route. Pure cartography for a human reader; the bot navigates by waypoints, not by a drawn line. |
| `.trainer` | 469 | DELEGATE | `behavior.trainer` — payload `{ npc_entry, pos }` | "Train your class spells" — a whole-visit delegation. |
| `.requires` (command) | 445 | TRANSFORM | `Task.serves_quests: Vec<QuestId>` | Distinct from `#requires`. `quest,<id>` declares which quest the step exists to serve — used for whole-chain pruning when the quest is unobtainable. |
| `.vendor` | 385 | DELEGATE | `behavior.vendor` — payload `{ npc_entry?, pos, mode: Sell\|Buy, items? }` | Bare = sell junk; with entry id = buy from this vendor. |
| `.hs` | 382 | DELEGATE | `behavior.hearth` — payload `{}` | Always bare; the `.cooldown item,6948` sibling supplies the gate. |
| `.itemStat` | 327 | TRANSFORM | `Predicate::ItemStatCmp { slot, stat, cmp, value }` | Upgrade check on equipped gear; note this one is *stay-active-while-true*, inverted vs `.money`. |
| `.reputation` | 298 | TRANSFORM | `Predicate::ReputationCmp` — **fails closed** | No Sylvanas API exposes reputation (§5.8). Compiler resolves what it can from `quest_template.RequiredMinRepFaction`; the residual predicate evaluates `Unknown` and blocks. |
| `.skipgossip` | 282 | MERGE | `Op::Interact.gossip: GossipPolicy::AutoAdvance` | A modifier on the interaction, not an action. |
| `.money` | 259 | TRANSFORM | `Predicate::MoneyCmp { cmp, copper }` | `<0.0480` = gold.silver-copper. Readable via `core.inventory.get_gold`. |
| `.collectmultiple` | 210 | MERGE | `Predicate::ItemCount` (aggregated) | Attaches to sibling `.collect` lines for the same item across several quests. |
| `.usespell` | 204 | MERGE | `Op::Cast` | 181/204 duplicate a sibling `.cast` with the same spell id; the pair is one action. |
| `.timer` | 200 | TRANSFORM | `Op::Wait { secs, label }` | Scripted RP/cutscene/spawn delay after an interaction. Real bot behaviour, not display. |
| `.fp` | 199 | DELEGATE | `behavior.flightpath` — payload `{ node_name, npc_entry, pos, mode: Discover }` | Acquire a flight path. |
| `.disablecheckbox` | 194 | DROP | — | Suppresses the manual-completion checkbox the addon renders for a human. No bot meaning. |
| `.group` | 190 | TRANSFORM | `Predicate::InGroup { cmp, size }` + `Task.combat.expect_group` | Optional party size; drives combat policy and blocking. |
| `.home` | 186 | DELEGATE | `behavior.hearth` — payload `{ mode: Bind, npc_entry, pos }` | Set hearth at innkeeper. |
| `.aura` | 174 | TRANSFORM | `Predicate::AuraPresent { spell, on }` | Leading `-` on an id negates. |
| `.maxlevel` | 171 | TRANSFORM | `Predicate::LevelAtMost` + optional `Task.jump_to` | 2-arg form is a forward jump to a label. |
| `.link` | 165 | DROP | — | Renders a clickable URL (YouTube reference video) or a raw slash-command macro for a human. |
| `.abandon` | 142 | KEEP | `Op::Abandon { quests }` | Real inventory-of-quests mutation; needed for failed/obsolete quests. |
| `.groundgoto` | 114 | KEEP | `Op::Travel { waypoints, mode: Ground }` | Forces ground travel where a flying line would fail. |
| `.deathskip` | 77 | DELEGATE | `behavior.corpse` — payload `{ intent: DeliberateDeath, resurrect_at }` | Deliberate death as traversal. Interacts with the band 90–99 safety net; see §8. |
| `.destroy` | 72 | KEEP | `Op::DestroyItem { item }` | Frees bag space; real action. |
| `.bankwithdraw` | 53 | DELEGATE | `behavior.bank` — payload `{ mode: Withdraw, items, npc_entry, pos }` | Lists up to 89 item ids. Behaviour does not exist in ADR-000 — see §5.5. |
| `.clicknext` | 53 | DROP | — | Renders a UI button switching the human reader to another guide. Profile chaining is `#next` (§4.2). |
| `.stable` | 42 | DELEGATE | `behavior.stable` — payload `{ mode, npc_entry, pos }` | Hunter pet stabling, both directions. Behaviour does not exist — see §5.5. |
| `.dailyturnin` | 40 | MERGE | `Op::TurnIn { repeatable: true }` | Repeatable counterpart of `.turnin`. |
| `.daily` | 35 | MERGE | `Op::Accept { repeatable: true }` | Repeatable counterpart of `.accept`. |
| `.addquestitem` | 32 | TRANSFORM | `Task.loot_filter += { item, for_quest }` | Declares an item that counts toward a quest the current step is not working on, so it is kept while doing something else. |
| `.isNotOnQuest` | 28 | TRANSFORM | `Predicate::Not(QuestInLog)` | Negation of `.isOnQuest`. |
| `.equip` | 27 | KEEP | `Op::Equip { slot, item }` | Slot-then-item; slot numbering corroborated by sibling `.itemStat`. |
| `.gossip` | 23 | KEEP | `Op::Interact { npc, gossip: Index(n) }` | NPC entry + option index; transport/escort/RP triggers. |
| `.bankdeposit` | 23 | DELEGATE | `behavior.bank` — payload `{ mode: Deposit, items, npc_entry, pos }` | As `.bankwithdraw`. |
| `.bronzetube` | 22 | TRANSFORM | `Predicate::ItemCount { id: 4371, cmp: Ge, count: 1 }` | Determined, not guessed: `A-23-30.lua:1229` carries the author comment `--skips the step if you have a bronze tube`, and every instance sits on a vendor step buying one. |
| `.solo` | 13 | TRANSFORM | `Predicate::Not(InGroup)` | Exact complement of `.group`; the two tag paired alternative step variants. |
| `.tbcWBF` | 11 | DROP | — | Guide-local filter confined to one `RestedXP TBC Preparation` guide, selecting Wrath-of-the-Blue-Flight turn-in staging steps. Semantics UNDETERMINED (§9); the whole preparation guide group is out of scope for a 1–70 leveling profile. |
| `.gossipoption` | 7 | MERGE | `Op::Interact { gossip: OptionId(n) }` | Same action as `.gossip`, addressed by option id instead of index. |
| `.blastedLands` | 7 | DROP | — | Guide-local filter on the optional Blasted Lands stat-buff farming apparatus. Semantics UNDETERMINED (§9); the gated content is an optional detour, not the leveling path. |
| `.vehicle` | 2 | KEEP | `Op::EnterVehicle` | Rare but a genuine distinct action (Fel Reaver console, quest 10612). Kept because it cannot be expressed by `.use` or `.interact`. |
| `.setturninhs` | 2 | DROP | — | Addon planner state marker inside the TBC pre-launch preparation guides. No world action. |
| `.showtotalxp` | 2 | DROP | — | Injects a computed XP number into the addon's guide window text. |
| `.isQuestNotComplete` | 1 | TRANSFORM | `Predicate::Not(QuestComplete)` | Negation; one instance, half of an explicit complementary pair. |
| `.turninmultiple` | 1 | MERGE | `Op::TurnIn { any_of: [..] }` | The Aldor/Scryer allegiance choice — turn in whichever one was taken. |
| `.flygoto` | 1 | KEEP | `Op::Travel { mode: Air }` | Airborne counterpart of `.groundgoto`. Kept for symmetry; one instance. |
| `.setquestdb` | 1 | DROP | — | A 2,546-field inline Lua table literal backing the addon's TBC turn-in planner. Not comma-tokenisable, not a bot instruction. |
| `.show25quests` | 1 | DROP | — | Renders a clickable "see the 25 best quests" UI element. |
| `.setturninroute` | 1 | DROP | — | Marks its guide as the dynamically generated turn-in route. Addon planner internal. |

**Commands: 74/74 present.**

## 4.2 Directives (49)

| Source token | Uses | Verdict | Maps to | Justification |
|---|---|---|---|---|
| `#completewith` | 5,469 | TRANSFORM | `Task.completion = CompletionSource::LinkedTo(TaskId)` | Completion authority delegated to another task. `next` (2,681) resolves to the successor; 2,788 name one of 1,246 labels. Compiler resolves all to `TaskId`. |
| `#optional` | 3,067 | TRANSFORM | `Task.blocking = false` | Non-mandatory: failure or skip does not stall the profile. |
| `#label` | 2,581 | TRANSFORM | Compiler-side symbol table ⇒ `TaskId` | Link target for `#completewith`/`#requires`. Names do not survive into the artifact. |
| `#loop` | 1,661 | TRANSFORM | `Route.kind = RouteKind::Circuit` | Patrol circuit: cycle the waypoints while working the objective, rather than walking once. |
| `#xprate` | 735 | DROP | — | Filters guides by server XP-rate multiplier so RestedXP can publish one pack for 1× and boosted realms. Realm economics, not bot behaviour; the archetype selects the right guide set at compile time. |
| `#requires` | 349 | TRANSFORM | `Task.deps: Vec<TaskId>` | Dependency edge. Plural in the schema — see P1 and §5.9. |
| `#sticky` | 311 | TRANSFORM | `Task.lifetime = Lifetime::Background { channels, band }` | Concurrent task holding a channel subset. Payload analysis (§2.4) shows it wants `MOVEMENT`. |
| `#name` | 278 | KEEP | `GuideMeta.name` | Unique link target within a `#group`, resolved by `#next`/`#include`. |
| `#tbc` | 277 | TRANSFORM | Archetype filter `expansion` | Client-version whitelist; resolved at compile time. |
| `#group` | 277 | KEEP | `GuideMeta.group` | Catalogue bucket and the namespace in which `#name` is unique. |
| `#subgroup` | 272 | KEEP | `GuideMeta.subgroup` | Level band / themed section. |
| `#version` | 265 | KEEP | `GuideMeta.source_version` | Guide-pack revision; feeds `content_hash` provenance (§5.4). |
| `#aldor` | 239 | TRANSFORM | Archetype filter `allegiance: Aldor` | Shattrath allegiance branch; irreversible in-game, so compile-time. |
| `#questguide` | 228 | TRANSFORM | Archetype filter `mode: QuestGuide` | Selects do-the-quests mode over the pure speed route. |
| `#scryer` | 209 | TRANSFORM | Archetype filter `allegiance: Scryer` | Mirror of `#aldor`. |
| `#ah` | 178 | TRANSFORM | Archetype filter `self_found: false` | Auction-house-permitted variant. |
| `#phase` | 174 | TRANSFORM | Archetype filter `content_phase` | Server content-release phase, e.g. `4-6`. |
| `#next` | 156 | TRANSFORM | `GuideMeta.next: Vec<GuideRef>` | Guide chaining; `;`-separated alternatives. Becomes the profile-chain edge. |
| `#wotlk` | 129 | TRANSFORM | Archetype filter `expansion` | As `#tbc`. |
| `#classic` | 125 | TRANSFORM | Archetype filter `expansion` | As `#tbc`. |
| `#include` | 107 | TRANSFORM | Compile-time splice | Inlines another guide by `#name`, optionally `@start-end` label range. Fully resolved; no runtime construct. |
| `#softcore` | 91 | TRANSFORM | Archetype filter `hardcore: false` | Death-is-cheap variant of an objective. |
| `#displayname` | 71 | DROP | — | Human-facing label overriding `#name` in the addon's guide list. Pure UI chrome. |
| `#hardcore` | 59 | TRANSFORM | Archetype filter `hardcore: true` | Permadeath variant, with extra safety/grouping requirements. |
| `#ssf` | 58 | TRANSFORM | Archetype filter `self_found: true` | No-auction-house twin of `#ah`. |
| `#title` | 56 | DROP | — | Human-facing chapter title, distinct from `#name`. UI only. |
| `#chapter` | 50 | DROP | — | Marks a guide as a leaf in a parent's `#chapters` navigator. UI tree structure. |
| `#level` | 22 | TRANSFORM | `Predicate::LevelAtLeast` | Every instance is `#level 70` on a `step << skip` step. Kept as a predicate because level changes during play. |
| `#defaultfor` | 17 | DROP | — | Declares which character the guide is auto-selected for in the addon's picker. Sentinel selects by archetype at compile time. |
| `#chapters` | 17 | DROP | — | Ordered list of sibling chapter guides for the UI navigator. |
| `#noflyable` | 14 | TRANSFORM | Archetype filter `can_fly: false` | Selects the ground-route variant. |
| `#internal` | 10 | DROP | — | Marks a guide as a non-selectable template that exists only to be `#include`d. Resolved and consumed at compile time. |
| `#tip` | 9 | DROP | — | Marks a step as purely informational; every instance contains only `#tip` plus a `#completewith`. |
| `#icon` | 6 | DROP | — | Overrides the step's displayed icon with an inline WoW texture escape. |
| `#hidewindow` | 6 | DROP | — | Suppresses the addon's step-tracking frame for informational guides. |
| `#hardcoreserver` | 4 | TRANSFORM | Archetype filter `realm: Hardcore` | Realm-type variant (dying is unacceptable ⇒ different route). |
| `#flyable` | 3 | TRANSFORM | Archetype filter `can_fly: true` | Positive half of the `#noflyable` pair. |
| `#OnClick` | 3 | DROP | — | Binds a named addon handler (`turninconfig`, `noop`) to the guide-list entry. Addon UI behaviour. |
| `#season` | 2 | TRANSFORM | Archetype filter `season` | Seasonal realm/ruleset gate. Both instances `#season 0`; low confidence (§9). |
| `#softcoreserver` | 2 | TRANSFORM | Archetype filter `realm: Softcore` | Counterpart of `#hardcoreserver`. |
| `#qremove` | 2 | TRANSFORM | `Op::UntrackQuest { quest }` | Drops a quest from guide tracking where the route never turns it in. Distinct from `.abandon` (no in-game effect). |
| `#compltewith` | 2 | MERGE | `#completewith` | Author typo (transposed letters). Normalised at ingest with a diagnostic (§5.10). |
| `#completewithTBTurnins` | 1 | MERGE | `#completewith TBTurnins` | Author typo — a **missing space**, not a misspelling. Also the source of the 49-vs-48 count discrepancy (§2.2). |
| `#lable` | 1 | MERGE | `#label` | Author typo (transposed `le`/`el`). |
| `#ignorecorpse` | 1 | TRANSFORM | `Task.suppress_behaviors: [corpse]` | Suppresses corpse-recovery on a step that deliberately dies inside an instance to corpse-run elsewhere. Low confidence (§9), but it is the only lever that makes deliberate death work against the safety net (§8). |
| `#noflyasble` | 1 | MERGE | `#noflyable` | Author typo (stray `s`). |
| `#completewity` | 1 | MERGE | `#completewith` | Author typo (transposed final letters). |
| `#subweight` | 1 | DROP | — | Signed integer controlling guide-list ordering. UI sort key. |
| `#requries` | 1 | MERGE | `#requires` | Author typo (transposed `ri`/`ir`). |

**Directives: 49/49 present.**

## 4.3 Coverage arithmetic

Computed programmatically over the derived counts, not estimated.

**Commands — 74 tokens, 115,021 instances**

| Verdict | Tokens | Instances | Share |
|---|---|---|---|
| KEEP | 13 | 56,530 | 49.15% |
| MERGE | 8 | 14,131 | 12.29% |
| TRANSFORM | 31 | 39,228 | 34.11% |
| DELEGATE | 11 | 4,210 | 3.66% |
| DROP | 11 | 922 | 0.80% |

Retained = 115,021 − 922 = **114,099 / 115,021 = 99.20%**

**Directives — 49 tokens, 17,598 instances**

| Verdict | Tokens | Instances | Share |
|---|---|---|---|
| KEEP | 4 | 1,092 | 6.21% |
| MERGE | 6 | 7 | 0.04% |
| TRANSFORM | 27 | 15,518 | 88.18% |
| DROP | 12 | 981 | 5.57% |

Retained = 17,598 − 981 = **16,617 / 17,598 = 94.43%**

**Combined = 130,716 / 132,619 = 98.57% of all token instances retained.**

The dropped 0.80% of commands is dominated by `.line` (485, map cartography) and `.disablecheckbox`
(194, a UI checkbox). The dropped 5.57% of directives is dominated by `#xprate` (735, realm XP-rate
publishing) and a long tail of guide-list UI chrome. **No dropped token carries world state or a bot
action.**

----------

# 5. D5 — Architecture alignment

*Core deliverable.* One subsection per interface contract.

## 5.1 C1 — Conditions compile to `Predicate`

**Contract.** `Sentinel.objectives:satisfied(predicate, snapshot)` is the only completion authority.
No second condition system.

**How the schema satisfies it.** Every one of the 31 `TRANSFORM`-to-predicate commands lowers into one
`Predicate` tree. There is exactly one condition type in the artifact. `Task` has three predicate
slots — `applies_when`, `complete_when`, `abort_when` — and all three hold the same type evaluated by
the same function. Grep the Rust structs in §7: there is no other boolean-valued construct.

### 5.1.1 Proposed `Predicate` additions

ADR-000 §7.2 ships `And`, `Or`, `Not`, `QuestComplete`, `QuestObjective`, `HasItem`, `AtLocation`,
`LevelAtLeast`, `AuraPresent`, `Flag`. That set cannot express this corpus. Minimal additions:

| New variant | Corpus command | Uses | Justification |
|---|---|---|---|
| `QuestInLog { id }` | `.isOnQuest` | 3,139 | "On quest" is neither complete nor turned in. Maps to `core.quests.is_on_quest`. Third distinct quest state. |
| `QuestTurnedIn { id }` | `.isQuestTurnedIn` | 1,488 | Distinct API (`is_quest_flagged_completed`) and distinct meaning from `QuestComplete`. Without it, a resumed run cannot tell "handed in" from "never taken". |
| `QuestAvailable { id }` | `.isQuestAvailable` | 930 | Obtainable: prerequisites, level and rep satisfied, not already done. Requires compile-time prerequisite resolution from `quest_template`. |
| `ItemCount { id, cmp, count }` | `.itemcount`, `.collect`, `.bronzetube` | 4,732 | **Supersedes `HasItem`**, which has no operator. The corpus needs `<1` and `>0` (`A-1-11-Dwarf-Gnome.lua:631` `.itemcount 16321,<1`). |
| `MoneyCmp { cmp, copper }` | `.money` | 259 | No money variant exists. `.money <0.0480` gates purchase steps. Readable via `core.inventory.get_gold`. |
| `SkillCmp { line, cmp, value }` | `.skill` | 507 | No skill variant. Explicit operator: `.skill cooking,<50,1`. |
| `ReputationCmp { faction, standing, cmp, value }` | `.reputation` | 298 | No reputation variant — and **not evaluable client-side** (§5.8). Present so the compiler can emit it and the runtime can fail closed rather than fail open. |
| `XpAtLeast { level, xp_offset }` | `.xp` | 2,133 | No XP variant. Both corpus forms (`4-420`, `>5,1`) fold into level + signed offset. `get_xp`/`get_max_xp`. |
| `CooldownCmp { kind, id, cmp, secs }` | `.cooldown` | 549 | No cooldown variant. Hearthstone gating depends on it. |
| `InArea { area_id, kind, }` | `.zone`, `.subzone`, `.zoneskip`, `.subzoneskip` | 4,906 | `AtLocation` is a point plus radius; zone/sub-area membership is a set test, not a distance test. Largest single addition by use count. |
| `HearthBoundTo { area_id }` | `.bindlocation` | 557 | Not expressible otherwise. |
| `ItemStatCmp { slot, stat, cmp, value }` | `.itemStat` | 327 | Gear-upgrade gate on the currently equipped item. |
| `InGroup { cmp, size }` | `.group`, `.solo` | 203 | Party-size test; drives both gating and combat policy. |
| `SpellKnown { spell }` | `.train` (2-arg form) | 403 | The condition half of `.train`; distinct from `AuraPresent`. |
| `LevelAtMost { level }` | `.maxlevel` | 171 | `LevelAtLeast` cannot express a ceiling without `Not`, and `Not(LevelAtLeast(n))` is off by one. |

Plus one shared enum, not a variant: `Cmp { Lt, Le, Eq, Ge, Gt }`. Adding a comparison *operator* once
is what keeps this at 15 additions instead of 40 — the RXPGuides parser re-invents `<`/threshold
parsing in every one of ~120 handlers (§3.1), which is exactly the cost of not doing this.

**Bend:** I am replacing `HasItem { id, count }` with `ItemCount { id, cmp, count }` rather than adding
alongside it. `HasItem` is the `cmp: Ge` case. Keeping both would be a second way to say one thing.

### 5.1.2 Tri-state — the correctness requirement

`satisfied()` returns `Truth { True, False, Unknown }`, not `bool`.

This is not defensive design; the API forces it. Three documented facts:

1. **The quest log has no readiness contract.** `docs/SylvannasAPI/dev/api/events.md:47–95` registers no
   `QUEST_LOG_UPDATE`, no `QUEST_ACCEPTED`, no `PLAYER_ENTERING_WORLD`. All quest state must be
   **polled**, and there is no documented signal for "the log is populated". An empty read after a
   loading screen is indistinguishable from "no quests".
2. **`is_complete` is genuinely tri-state and the two APIs disagree.**
   `core.game_ui.get_quest_log_info` documents it as an integer `1 / -1 / 0` where `-1` is *failed*;
   `core.quests.get_quest_log_title` names the same field and its own example treats it as a boolean
   (`quests.md:171`). In Lua both `0` and `-1` are truthy, **so the documented example reports a failed
   quest as COMPLETE**. Standardise on `get_quest_log_info` and compare `== 1`.
3. **The profession API returns safe defaults indistinguishable from real zeroes.**
   `professions.md:18`: on clients where the underlying global is absent the call returns
   "`0`, `false`, `nil`, or an empty table instead of erroring". A `skill >= 125` gate silently
   evaluates false on a client that cannot answer.

**Policy, declared per task.** `Task.unknown_policy: UnknownPolicy`:

| Policy | Behaviour on `Unknown` | Compiler default |
|---|---|---|
| `Block` | Task does not start; the runner reports `blocked_reason`. Nothing advances. | `complete_when` on any task with a `DELEGATE` or irreversible op (turn-in, abandon, destroy, deathskip) |
| `Defer` | Task yields this tick, retries next; after `budget_ticks` ticks escalates to `Block`. | Default for `complete_when` |
| `Treat(False)` | Proceed as if not satisfied — re-do the work. Safe only when the work is idempotent. | `applies_when` on pure-travel tasks |
| `Treat(True)` | Proceed as if satisfied — skip the work. **Never a default.** Requires an explicit compiler opt-in and emits a diagnostic. | never |

The failure mode ADR-000 §7.1 exists to kill is `Unknown → false → "not complete" → redo the step`.
Making `Treat(False)` opt-in per task, and never the default for `complete_when`, is what prevents the
ledger reintroducing it.

**The rule the compiler applies**, in this order, over what a task *does* and what its completion
*measures* — never over where the task sits in the list
(`compiler/src/kernel/task_graph.rs::unknown_policy`):

1. **An irreversible op ⇒ `Block`.** The table's own first row. `Op::TurnIn`, `Op::Abandon`,
   `Op::DestroyItem` and `Op::Delegate`; "deathskip" is §5.5's kernel behaviour and therefore
   arrives as a `Delegate`. `Op::UseItem` is deliberately **not** in the set — §7.3.3 task 2
   consumes a quest item the guide itself calls unrecoverable and the worked example still gives it
   `Defer`, so the set is the four named kinds rather than a judgement about consequences.
2. **A monotone player statistic ⇒ `Treat(False)`.** `XpAtLeast` and `LevelAtLeast`, which are one
   statistic at two precisions and cannot decrease in TBC. This is the table's "safe only when the
   work is idempotent" made concrete: an `Unknown` read costs one more grind tick and leaves the
   threshold closer, never further. A `QuestObjective` counter rises too and is **excluded**,
   because it *disappears* with its quest — treating a gone objective as false is exactly the
   failure the paragraph above names.
3. **Otherwise `Defer`**, the table's stated default, with the magnitudes §9 item 25 records as
   unstated.

Row 3's own "Compiler default" column reads "`applies_when` on pure-travel tasks", which describes a
slot rather than a task and has no §7.3.3 witness — the worked example's only `Treat(False)` task
carries a *`complete_when`* of `XpAtLeast` and no `applies_when` at all. Rule 2 is what the artifact
shows; the column is left as written because narrowing it is a separate decision.

## 5.2 C2 — Static gating resolves at compile time

**Contract.** Static gates must not reach `Sentinel.objectives`.

**Decision: one artifact per character archetype, gates fully resolved away.**

An `Archetype` is `(class, race, faction, expansion, allegiance, hardcore, self_found, can_fly,
content_phase, mode, xp_rate_milli, hardcore_server, season)`. The last three were added when C2
landed: §4.2's verdict column already classified `#xprate`, `#hardcoreserver`/`#softcoreserver` and
`#season` as archetype filters, and the seven-axis tuple had nowhere to answer them.
`#hardcoreserver` describes the **realm** and is independent of the player's own `#hardcore` —
aliasing them, since one name is a prefix of the other, admits 4 realm-specific steps to every
hardcore character on a normal realm. `xp_rate_milli` is **thousandths, not a float**: `Archetype`
derives `Eq`, and `>1.49` and `>1.499` are different thresholds that disagree at 1.495.
The compiler evaluates every `<<` expression, every `#aldor`/`#scryer`,
`#hardcore`/`#softcore`, `#ah`/`#ssf`, `#flyable`/`#noflyable`, `#phase`, `#tbc`/`#wotlk`/`#classic`,
`#questguide` (228), `#xprate` (735), `#hardcoreserver`/`#softcoreserver` (4/2), `#season` (2)
and `.dungeon` against a concrete archetype and emits only the surviving tasks and ops. The last four
are archetype filters in §4.2's own verdict column and were missing from this list; a resolver that
does not know them leaves a gate in the artifact, which C2 forbids.

**`<<` is not a class/race/faction language.** The era tokens `tbc`, `wotlk`, `classic`, `era` and
`sod` appear **inside** `<<` expressions 958 times, not only as `#` directives, so the same vocabulary
must be accepted in both positions.

**`skip` is not an archetype token.** It appears 139 times in gate position and is a *disable
sentinel*: `step << skip`, `step << Warrior skip`. Resolving it as vocabulary would silently **enable
steps the author disabled** — the failure is invisible, because the step simply runs. It is
recognised before archetype resolution and marks the step dead (140 corpus steps).

**The argument that settles it is not cache economics — it is capability.** Player faction is **not
readable from the Sylvanas API**. `game_object:get_faction_id()` returns a *unit faction template*
(who is hostile to whom), not Alliance/Horde player side; the only faction-side call,
`core.game_ui.get_battlefield_arena_faction()`, works in arena/battleground context only. There is also
**no race enum and no `race_id_to_name` table** anywhere in `enums.md` — `get_race_id()` returns a bare
number with no documented value space. A residual-gate design would require the runtime to answer
"am I Alliance?" and it cannot. Compile-time resolution is therefore forced.

Weighed against the alternative:

| | Per-archetype artifacts (chosen) | One artifact with residual gates |
|---|---|---|
| Runtime cost | Zero — gates do not exist | Per-tick gate evaluation over 23,894 tasks |
| Faction/race readability | Not needed | **Impossible** — blocks the design |
| Second condition system | None | Required, violating C1 |
| Artifact count | One per archetype actually played | One |
| Reroll cost | Offline recompile (seconds) | None |
| Cache-ability | Keyed by `(archetype, content_hash)`; immutable, shareable | Single blob |

Artifact count is the real cost, and it is smaller than it looks: profiles are generated on demand for
the archetype being played, not exhaustively for all valid TBC `(class, race, faction)` combinations. A
reroll is a recompile of an offline Rust binary.

**Bend:** `#level` (22 uses) is *not* resolved at compile time despite looking static, because player
level changes during play. It becomes `Predicate::LevelAtLeast`. Same for `.maxlevel`. This is the RXP
`applies()` cache bug (§3.1) avoided by construction.

## 5.3 C3 — Concurrency maps to channels and leases

**Contract.** Sticky steps are concurrent tasks holding a channel subset. No generic background flag.

**The schema separates two axes that the intuitive design conflates.** §2.4 showed `#sticky` and
`#completewith` are disjoint as authored; §3.1 showed `#completewith` implies sticky at runtime. Both
facts are captured by making them independent fields:

```rust
pub struct Task {
    pub lifetime:   Lifetime,          // from #sticky  — how long do I live, what do I hold
    pub completion: CompletionSource,  // from #completewith — who decides I am done
    // ...
}
```

- `Lifetime::Exclusive` — the foreground task. Acquires its ops' channels as needed.
- `Lifetime::Background { channels, band, terminate_on }` — a concurrent task holding
  `channels` at `band` until `terminate_on`.
- `CompletionSource::OwnPredicate` — `complete_when` decides.
- `CompletionSource::LinkedTo(TaskId)` — the named task's completion completes this one.

A `#completewith`-only task therefore becomes `Background` with an **empty or minimal channel set** and
`LinkedTo` completion — it rides along without contending. A `#sticky`-only task becomes `Background`
with `channels: [MOVEMENT]` and `OwnPredicate`. A step carrying both (the 37) gets both.

**Channels, from the payload evidence.** Sticky steps are 416 `.waypoint` + 296 `.goto` + 136
`.complete` + 89 `.mob`: movement plus a kill objective. So the compiler assigns:

| Task shape | Channels claimed |
|---|---|
| Sticky patrol / grind loop | `MOVEMENT` (combat delegates `CASTING`+`TARGETING` separately per C6) |
| Foreground turn-in / accept | `INTERACTION`, `FACING`, transiently `MOVEMENT` to approach |
| Vendor / bank / trainer delegation | `INTERACTION` + `ITEMS` |
| Travel-only fused (`#completewith next`) | none — display/marker only |

This is exactly the case ADR-000 §4.1 calls out: the sticky patrol holds `MOVEMENT` while a foreground
turn-in holds `INTERACTION`, and they coexist.

**Lifecycle, fully specified:**

- **Start.** A `Background` task starts when its `applies_when` first evaluates `True` *and* the
  foreground cursor reaches or passes its source position. It acquires its channels at **band 30–49
  (Goal)**, per ADR-000 §4.2, offset by task order so two sticky tasks cannot deadlock.
- **Suspend vs terminate.** `terminate_on` is a `Predicate` — normally the linked task's completion or
  its own `complete_when`. *Suspension* is involuntary: losing a lease to a higher band. *Termination*
  is voluntary and permanent: `terminate_on` becomes `True`, or the profile cursor passes
  `terminate_at_task`.
  "Normally" underdetermines §7.3.3's own three background tasks, so the compiler applies this chain
  (`compiler/src/kernel/task_graph.rs::assemble_tasks`): the hand-in of the quest the task's
  objective belongs to, **iff this artifact performs that hand-in** (task 0's does, downstream);
  otherwise the task's own `complete_when`; otherwise the completion at the end of its
  `CompletionSource::LinkedTo` chain, which is followed transitively because the relation is — if the
  linked task defers in turn, its authority is whatever *it* defers to, and a walk that stopped at
  one hop left 43 corpus tasks with no termination while a real completion sat two links away.
  A cycle of links contains no completion by construction and falls out of the walk.
  **When the chain finds nothing, the artifact says so rather than guessing.** 800 corpus tasks —
  `#sticky` patrols carrying no `.complete`, and `#completewith` riders whose whole content is
  movement and whose chain ends without a completion — get `Or([])`, the empty disjunction, which is
  never satisfiable, plus a `BACKGROUND_WITHOUT_TERMINATION` diagnostic. That is the honest reading
  of "the guide states no termination condition", and the second route above — the cursor passing the
  task — still ends it. The empty *conjunction* is the spelling that must never appear here: `And([])`
  is vacuously `True` and would terminate a patrol on the tick it started.
- **Orphaned `#completewith` target.** If the target task is skipped or never reached, the linking task
  would hang forever — this is the exact defect RXPGuides ships (`guide.labels[…]` returns nil and the
  edge silently never fires, §3.1). **The compiler resolves every link to a concrete `TaskId` and
  emits a hard diagnostic for any unresolved label**, so an unresolvable link cannot reach the artifact.
  At runtime, a link whose target is skipped inherits the target's terminal state: skipped target ⇒
  linking task also completes (it was riding along on work that is no longer needed).
- **Lease revocation mid-loop.** Combat preempts at band 50–69. The task receives `on_revoke`, writes
  its `ResumeCursor`, and parks. When it re-acquires, it resumes from the cursor.

**Resume granularity — the gap ADR-000 leaves open.** ADR-000 asserts resume-after-preemption but never
defines the unit. Resolved here, explicitly, in the struct:

```rust
pub struct ResumeCursor {
    pub task:     TaskId,
    pub op_index: u16,   // which op within the task's ordered `ops`
    pub waypoint: u16,   // which waypoint within that op's route, if it is a Travel op
    pub loop_iter: u32,  // circuit iteration, for #loop tasks
}
```

Three levels because the corpus needs three. A 15-waypoint patrol circuit
(`A-11-23.lua:218–231`) preempted by combat must not restart the circuit — that is a
minutes-long regression per interruption. `op_index` alone is insufficient because one `Travel` op
carries the whole route.

## 5.4 C4 — The artifact is fail-closed

**Contract.** `schema_hash`, `tags_used`, adjacently-tagged **dispatched** enums, refuse-don't-degrade.

Present on the profile root (§7.1): `schema_hash: [u8; 32]`, `tags_used: Vec<String>`.

**The tagging rule is by role, not by arity.** Sum types the kernel **dispatches on** carry
`#[serde(tag = "type", content = "payload")]` — `Lifetime`, `CompletionSource`, `UnknownPolicy`,
`Op`, `RouteKind`, `GossipPolicy`, `DelegatePayload`, `CombatStance`, `GroupExpectation`, `Cmp`,
`Predicate` — **even where every variant happens to be a unit variant.** `Cmp` (five unit variants),
`CombatStance` and `GroupExpectation` are all fully unit-variant and all adjacently tagged, which is
why §7.3.3 prints `{"type": "Aggressive"}` and `{"type": "Solo"}` rather than bare strings: Lua
switches on `.type`, and a value that is sometimes a string and sometimes an object cannot be
dispatched on uniformly.

**Leaf vocabulary enums serialise as bare strings.** They only name a value and are never dispatched
on: `Class`, `Race`, `Faction`, `Expansion`, `Allegiance`, `ProfileMode`, `Channel`, `TravelMode`,
`BehaviorId`, `VendorMode`, `FlightMode`, `HearthMode`, `BankMode`, `StableMode`, `CorpseIntent`,
`UnitRef`, `SkillLine`, `Standing`, `CooldownKind`, `AreaKind`, `ItemStat`, `DungeonId` (all 22
declared in §7.1). Each emits the Rust variant name verbatim; `Channel` alone is SCREAMING_SNAKE,
per §7.2. §7.3.3 requires this: `"class": "Hunter"`, `"mode": "Any"`, `"kind": "SubArea"`,
`"channels": ["MOVEMENT"]`.

**One of the 22 is not uniformly a string, and this document said otherwise for two revisions.**
`ProfileMode::Dungeon { instance: DungeonId }` carries a payload, so `archetype.mode` is a bare
string for `SpeedRoute` / `QuestGuide` and an **externally tagged object**,
`{"Dungeon": {"instance": "Mara"}}`, for the third. Earlier revisions of this section, of §7.1 and of
§10 item 7 all claimed the 21 leaf enums "carry no payload", which stopped being true the moment
`.dungeon`'s argument had to be preserved (§5.6, §8) — a mode that only says "this is a dungeon run"
admits every dungeon's steps into every dungeon's profile. The claim is corrected in all three
places (§9 item 28), and the count of enums that genuinely carry no payload is **21 of 22**.

That external form is not the failure C4 names, for the same reason the rule is stated by role:
nothing dispatches on `archetype.mode`. §5.2 makes the archetype **provenance** — the compiler reads
it to resolve gates, an auditor reads it to know what an artifact is for, and the runtime never
looks at it. Adjacently tagging it would buy nothing and would rewrite the two spellings §7.3.3
prints. §7.2's `$defs/ProfileMode` and
`shared/tests/kernel_wire_shape.rs::profile_mode_dungeon_is_externally_tagged_and_carries_a_dungeon_id`
pin both spellings so the exception cannot become an accident.

**`tags_used` is emitted sorted and deduplicated, byte-ascending.** It is a set, and sorted is the
only spelling that does not move when an unrelated task is added, reordered or elided — which is
what R3's digest over the emitted bytes depends on. §7.3.3's nine tags are printed in that order;
`compiler/src/kernel/mod.rs::tag_census` collects into a `BTreeSet` and is where the ordering is
enforced.

**The failure C4 guards against is _external_ tagging on a dispatched sum type — not the absence of
a wrapper on a leaf.** This repository has already been bitten by exactly that: `RuntimeCondition`
was externally tagged (`{"QuestInLog": {"id": 983}}`) and every non-unit condition fell through to
fail-open `true`, so gating silently stopped gating.

One consequence of serde's canonical adjacent tagging is worth stating once, because §7.3.3 used to
print it the other way: **the content key is omitted for a unit variant.** The emitted form is
`{"type": "Exclusive"}`, never `{"type": "Exclusive", "payload": null}`. §7.2's `$defs` require only
`["type"]` on those objects, deserialisation accepts both spellings, and in Lua an absent key and a
`null` key are both `nil`, so older artifacts still load (§9 item 23).

### 5.4.1 The content-integrity gap

`schema_hash` guards the *tag set*. Nothing guards the *resolved IDs*, and this project resolves a lot
of them: `tbcmangos.sqlite` (298 MB, 197 tables) supplies `creature_template` (18,799 rows),
`item_template` (30,396), `gameobject_template` (14,216), `quest_template` (6,599). If that snapshot
drifts from what the server actually runs, the compiler emits a syntactically perfect profile that
walks to the wrong NPC forever.

**Proposal — three fields, not one:**

```rust
pub struct ContentIntegrity {
    pub content_hash: [u8; 32],   // BLAKE3 over every resolved (kind, entry_id, expect_name) triple, sorted
    pub world_source: String,     // "tbcmangos.sqlite"
    pub world_build:  String,     // snapshot identity: file digest + row counts of the tables consulted
}
```

**What the kernel does on mismatch — and the honest limit.** The kernel **cannot** independently
compute the server's content hash; there is no documented API exposing world-database identity. So
`content_hash` is *not* a server-truth check. It is two things it can actually be:

1. **A coherence check across artifacts.** Profile, its sidecar index, and its `.save.json` must all
   carry the same `content_hash`. Mismatch ⇒ **refuse**, because a save file resumed against a
   differently-resolved profile will step to the wrong task index. This is a real, checkable failure.
2. **A provenance record** for the operator and for bug reports.

To get actual server-truth verification, the schema carries `expect_name` alongside every resolved
entry id, and the runtime does a **first-touch probe**: the first time a task interacts with NPC
entry *N*, it compares the observed unit name against `expect_name`. Mismatch ⇒ fail that task with a
named reason and quarantine the profile. Rationale for failing rather than warning: a wrong entry id is
not recoverable by retrying, and the bot would otherwise loop indefinitely at the wrong coordinates.

This costs a few bytes per resolved reference and is the only mechanism that can actually catch drift.

## 5.5 C5 — Delegate to existing behaviours

**Contract.** Prefer delegation over reimplementation.

Eleven commands (4,210 instances) become `Op::Delegate { behavior, payload }`:

| Command | Uses | Behaviour | Payload |
|---|---|---|---|
| `.vendor` | 385 | `behavior.vendor` | `{ npc_entry?, pos, mode: Sell\|Buy, item_filter?, gold_floor? }` |
| `.train` (1-arg) | 1,250 | `behavior.trainer` † | `{ npc_entry, pos, spell_id }` |
| `.trainer` | 469 | `behavior.trainer` † | `{ npc_entry, pos, mode: TrainAll }` |
| `.fly` | 741 | `behavior.flightpath` † | `{ npc_entry, pos, dest_node }` |
| `.fp` | 199 | `behavior.flightpath` † | `{ npc_entry, pos, mode: Discover }` |
| `.hs` | 382 | `behavior.hearth` † | `{ mode: Use }` |
| `.home` | 186 | `behavior.hearth` † | `{ mode: Bind, npc_entry, pos }` |
| `.bankwithdraw` | 53 | `behavior.bank` † | `{ npc_entry, pos, mode: Withdraw, items }` |
| `.bankdeposit` | 23 | `behavior.bank` † | `{ npc_entry, pos, mode: Deposit, items }` |
| `.stable` | 42 | `behavior.stable` † | `{ npc_entry, pos, mode }` |
| `.deathskip` | 77 | `behavior.corpse` | `{ intent: DeliberateDeath, resurrect_at }` |

**Behaviours marked † do not exist in ADR-000 §3.2.** That section lists corpse recovery, loot,
vendor/repair/mail, rest/eat/drink, anti-stuck, mount handling, and blacklists. It does **not** list
trainer, flight path, hearth, bank, or stable. Those are five new built-in behaviour plugins — listed
as required kernel changes in §5.9.

`.deathskip` delegates to the *existing* corpse behaviour but needs a capability it does not currently
expose: an `intent` distinguishing deliberate death from accidental death (§8).

`behavior.vendor` also needs a `mode: Buy` with an item list; ADR-000 describes vendor/repair/mail as a
selling/maintenance behaviour, and 43 of the 385 `.vendor` instances name a vendor entry id to **buy**
from.

## 5.6 C6 — Combat is a service invoked with a policy

**Contract.** The Quest Activity delegates `CASTING`+`TARGETING` with a policy.

**Scope decision: a profile-level default with per-task override.** Justification from the corpus —
`.mob` (7,456 instances) is per-step and names a *step-specific* whitelist, so policy cannot be
profile-only; but **18,404 of 23,894 steps (77.0%) carry no combat token at all**, so per-task-only
would mean emitting a redundant policy on more than three quarters of tasks. Default plus override is
the smaller artifact and matches the authoring reality.

*(An earlier revision of this sentence read "16,438 of 23,894", which was `23,894 − 7,456`: an
**instance** count subtracted from a **step** count. `.mob` occurs 7,456 times but only on 3,526
distinct steps — a step naming three mobs is one step and three instances — so the subtraction
double-counts every multi-`.mob` step and the residual is too low by 1,966. The error propagated into
`shared/src/kernel/profile.rs` and `shared/src/kernel/task.rs` doc comments and is corrected in all
three places (§9 item 28). The direction of the argument is unaffected and gets stronger: the
majority is larger than claimed.)*

Measured three ways over the same 23,894 steps, because "no combat token" has three defensible
readings and they differ by 1,964 steps:

| Reading | Steps with none of them | Share |
|---|---|---|
| `.mob` only | 20,368 | 85.2% |
| `.mob` / `.unitscan` | 19,718 | 82.5% |
| `.mob` / `.unitscan` / `.solo` / `.group` / `.dungeon` | **18,404** | **77.0%** |

The third row is the one that governs, because it is the set of steps for which *every* field of
`CombatPolicy` would have to be defaulted: `.mob` fills `targets`, `.unitscan` fills `watch_units`,
and `.solo` / `.group` / `.dungeon` fill `expect_group`. A step carrying only `.solo` still needs a
policy emitted, so counting it as "no combat token" would overstate what the default covers.

```rust
pub struct CombatPolicy {
    pub stance:       CombatStance,        // Avoid | Defensive | Objective | Aggressive
    pub targets:      Vec<CreatureEntry>,  // from .mob — the whitelist
    pub watch_units:  Vec<CreatureEntry>,  // from .unitscan — roamers/rares to notice
    pub leash_yards:  u16,
    pub allow_adds:   bool,
    pub expect_group: GroupExpectation,    // Solo | Party(u8) | Dungeon
}
```

Mapping from the corpus:

| Corpus signal | Uses | Policy |
|---|---|---|
| No combat token | — | profile default, `stance: Defensive`, empty whitelist |
| `.mob` present | 7,456 | `stance: Objective`, `targets` = whitelist, `allow_adds: false` |
| `#loop` + `.mob` + `.complete` | 1,661 | `stance: Aggressive` (a grind circuit *wants* pulls), leash from route radius |
| `.solo` | 13 | `expect_group: Solo` |
| `.group [n]` | 190 | `expect_group: Party(n)` |
| `.dungeon` | 1,351 | `expect_group: Dungeon` — resolved at compile time into a separate archetype variant |

This is the C6 distinction made concrete: `Objective` kills only what blocks the objective and refuses
adds; `Aggressive` on a `#loop` grind circuit pulls proactively. Same schema field, opposite behaviour,
selected from evidence in the source.

## 5.7 C7 — Navigation is async; engine owns pathfinding

**Contract.** `request_path` returns a handle; decide whether the artifact carries destinations or
baked routes.

**Decision: carry both, discriminated by `RouteKind`, because the corpus contains both and they are
not interchangeable.**

*The case for destinations only.* 16,231 `.goto` lines are 3-arg — a bare `zone,x,y` with no radius and
no successor. For those, RXP's coordinate is just "the place the NPC stands", and the engine's navmesh
will path there better than a 2004-era hand-placed waypoint chain. Carrying redundant intermediate
points would fight the navmesh, and 1,723 steps already contain duplicated coordinates (§2.6, measured)
that would double a naively-imported path.

*The case for baked routes.* Some chains encode intent no navmesh can infer. The decisive witness is
`A-11-23.lua:215–231`:

```
.goto 1439,36.051,44.757,0          <- entry point
.waypoint 1439,36.091,51.501,60,0
   … 14 waypoints …
.waypoint 1439,36.051,44.757,60,0   <- returns to the entry point
```

**The last waypoint is byte-identical to the first `.goto`.** This is a *closed circuit*, and the step
carries `#loop`. A navmesh asked to path from A to A returns a zero-length path; it cannot know the
intent is to walk a 15-node loop repeatedly to farm respawns. The route *is* the objective.

Similarly `.groundgoto` (114) exists precisely to override the engine's preferred line — it threads
mountain paths, caves and stairs where a direct or flying line fails.

**Resolution:**

```rust
pub enum RouteKind {
    Destination,                  // single point; engine paths freely  (16,231 3-arg .goto)
    Corridor,                     // ordered points, engine may smooth between them
    Circuit { close: bool },      // ordered points, cycled; DO NOT smooth away  (#loop)
}
```

The compiler emits `Destination` for isolated `.goto`, `Corridor` for a run of `.goto`/`.waypoint` in a
non-loop task, and `Circuit` for `#loop` tasks — and deduplicates the 4,190 measured duplicated
coordinate triples (§2.6) on the way in. That is the route-level collapse, distinct from the pool
interning of §7.1; §7.3.3 demonstrates the interning only (§9 item 26).

**Coordinate normalisation.** Both corpus coordinate systems (§2.6) normalise to
`{ map_id: u32, x: f32, y: f32, z: Option<f32> }` **in world coordinates**, resolved offline. The
runtime never converts zone-percentage to world space — it has no reliable table for it, and the
repository already records that Sylvanas zone coordinates are percentage-based with no Z.

`z` is `Option` because the corpus never supplies it; the compiler fills it from the navmesh where it
can and leaves `None` otherwise, letting the engine ground-snap.

## 5.8 C8 — Raw game types stop at the sensor boundary

**Contract.** No raw Sylvanas representations in the artifact.

The artifact carries Sentinel types only:

| Concept | Artifact form | Why |
|---|---|---|
| Class | `Class` enum (`Warrior`, `Paladin`, …) | `get_class()` returns a numeric id; `enums.class_id_to_name` yields **UPPERCASE** (`"WARRIOR"`) while RestedXP class tails are Title-Case. The mismatch is a live trap already recorded in this repo. Resolved at compile time — the artifact never contains a class at all after archetype resolution. |
| Race | `Race` enum | **There is no race enum and no `race_id_to_name` in `enums.md`.** `get_race_id()` is a bare number with an undocumented value space. The compiler owns the numeric map; the artifact carries none. |
| Faction | `Faction` enum | Not readable at runtime (§5.2). Compile-time only. |
| Creature | `CreatureEntry(u32)` + `expect_name: String` | Resolved from `creature_template`; `expect_name` powers the first-touch probe (§5.4.1). |
| Area | `AreaId(u32)` | Numeric AreaTable id; zone *names* never reach the artifact. |
| Reaction / power / creature type | not carried | No corpus token requires them. |

Since C2 resolves the archetype away entirely, class/race/faction appear in the artifact **only in the
header**, as provenance describing which archetype it was compiled for — never as a runtime test.

## 5.9 Kernel changes this design requires

Not "none". Listed explicitly:

| # | Change | ADR-000 § | Why forced |
|---|---|---|---|
| K1 | Extend `Predicate` with 15 variants + `Cmp` | §7.2 | The shipped enum cannot express money, reputation, skill, XP, cooldown, area membership, hearth bind, item stats, group size, or any comparison operator. §5.1.1. |
| K2 | `satisfied()` returns `Truth`, not `bool` | §7.2 | Cold-tier data is genuinely unavailable; `is_complete` is a documented tri-state including *failed*. §5.1.2. |
| K3 | Five new built-in behaviour plugins: `trainer`, `flightpath`, `hearth`, `bank`, `stable` | §3.2 | 3,322 command instances delegate to behaviours the kernel does not list. §5.5. |
| K4 | `behavior.vendor` gains `mode: Buy` with an item list | §3.2 | 43 `.vendor` instances name a vendor to buy from, not sell to. |
| K5 | `behavior.corpse` gains an `intent` distinguishing deliberate from accidental death | §3.2 | `.deathskip` (77) must not fight the band 90–99 safety net. §8. |
| K6 | Profile root gains `ContentIntegrity` + per-reference `expect_name`; loader gains the first-touch probe | §7.1 | `schema_hash` guards tags, not content. §5.4.1. |
| K7 | Loader reads via `core.read_data_file_partial` against an offset index rather than one whole-file read | §2 | A single decode is a measured ~306 ms render-thread hitch. §6.2. |
| K8 | Specify resume granularity as `(task, op_index, waypoint, loop_iter)` | §4.3 | ADR-000 asserts resume-after-preemption without defining the unit. §5.3. |

K1, K2 and K8 are corrections to under-specification. K3–K5 are additive. K6 and K7 are new mechanism.

## 5.10 P2 and P3

**P2 — class-gating granularity.** The boundary is now empirical, not a judgement call. **3,052
command-level `<<` gates across 134 distinct expressions** prove that gating happens *below* the step
(§2.5, where the counting rule is stated — it matters, since defensible readings of "command level"
differ by 47%).
So:

- *"Class quest chain to exclude"* = a run of tasks whose **step-level** gate is a single class token,
  and whose `.requires quest,<id>` set is disjoint from the surrounding tasks. The compiler drops the
  whole run.
- *"Inline class-conditional micro-action"* = an **op-level** gate inside a task whose step-level gate
  is absent or broader. The compiler drops the op and keeps the task.

Does compile-time resolution make the problem disappear? **No — it moves it into the compiler, which is
the right place.** The compiler must evaluate gates at *two* levels and, having dropped ops, must then
decide whether the remaining task is still meaningful. A task reduced to zero executable ops is elided
(this is what the 360 zero-command steps already look like). A task reduced to only a `.goto` becomes a
pure travel task and is a candidate for fusion with its successor.

**P3 — malformed input.** Six real typos: `#compltewith` (2), `#completewity` (1),
`#completewithTBTurnins` (1), `#lable` (1), `#noflyasble` (1), `#requries` (1). Plus 67 malformed
`.goto` lines (a decimal typed with a comma) and one duplicated-argument `.turnin 2948,2948,1`.

**Decision: normalise at ingest with a diagnostic; reject unknown tokens; keep the artifact fail-closed.**

The tension C4 names is real, and it is resolved by putting the two policies at *different stages*:

- **Ingest is permissive-but-loud.** A closed alias table maps each known typo to its intended token
  and emits a `Diagnostic::Normalised { line, from, to }`. An **unknown** token is a hard error — RXP
  itself does this (`addon.error("Invalid function call")`, §3.1) and silently skipping is how you get
  the 60%-coverage failure. Malformed `.goto` arity is a hard error, not a guess: `20.6,60,4` could be
  `60.4` or `60` with a stray field, and guessing wrong sends the bot to the wrong coordinates.
- **The artifact is strict.** By the time a profile is emitted, every token is canonical, every label
  is resolved to a `TaskId`, and `tags_used` lists **exactly** the registered op and predicate tags
  the artifact references — no more, no fewer. Nothing malformed survives compilation, so the
  fail-closed loader has nothing to forgive.

  `tags_used` is a **census**, not a subset of the registry, and it has to be exact in *both*
  directions because C4 makes each error a different failure. A **spurious** tag makes a fail-closed
  kernel refuse an artifact it could actually have run — the loader declines a tag it does not
  implement, for work no task ever asks it to do. A **missing** tag is worse and quieter: the
  loader's check passes on an artifact the kernel cannot fully evaluate, and the unimplemented tag
  is discovered mid-run, which is precisely the check the field exists to prevent. A census that is
  merely a superset therefore defeats the mechanism entirely.

The alias table is closed and versioned: a *new* typo is a compile error and a one-line patch, not a
silent normalisation. That is the difference between tolerating known damage and tolerating unknown
damage.

----------

# 6. D6 — Design rationale

## 6.1 Execution / control-flow model

**Chosen: an explicit task graph with a cursor — ordered tasks, plus dependency edges, plus a
concurrent background set.**

| Alternative | Why not |
|---|---|
| **Linear step list with skips** (RXP, Guidelime) | Cannot express non-adjacent dependencies. Guidelime's `[OC]` can only mean "the next step" and it is a documented capability gap (§3.3). The corpus has 1,246 distinct `#completewith` labels and 349 `#requires` edges — non-adjacency is the norm, not an edge case. |
| **Stateless behaviour tree** (RuneMate, §3.5) | Recovery becomes free, but progress, ETA and blocked-reason become impossible, and the runner cockpit in this repo already ships all three. Also forces re-deriving 23,894 tasks of context every tick. |
| **Task graph with cursor** (chosen) | Keeps the cursor for progress/ETA/resume; gets non-adjacency from explicit edges; gets concurrency from the background set. Cost: the compiler must topologically validate the graph. |

The borrowed discipline from RuneMate is narrower and worth stating: *preconditions are re-checked
against live state every tick even though the cursor is persisted*. The cursor says where we are; it
never asserts what is true. This repository's own recent fix — skipping kill ops gated on a quest the
player never took — is exactly the bug that arises from trusting a persisted cursor for truth.

## 6.2 Serialization format

**Chosen: JSON as the codec; an offset-indexed record container as the format; lazy reads via
`core.read_data_file_partial`.**

ADR-000 §2 says "Runtime Profile JSON". **I am keeping JSON** — but the container changes, and that
distinction is the whole answer.

### 6.2.1 Measurements

No citable public benchmark exists for pure-Lua decoding at this shape and scale, so these are
**first-party measurements**, method and environment disclosed, not quoted from anywhere.

*Method:* a generated artifact schema-faithful to the real Rust runtime model — 22,000 operations, each
with a UUID, 2 entry conditions, 1 exit condition and 4–6 guarded actions (≈110,000 actions), including
nested adjacently-tagged condition ASTs, plus 4,000 NPCs and 6,000 quests. Result: 20,695,404 bytes of
compact JSON. *Environment:* Intel Core Ultra 7 265K, LuaJIT 2.1, WSL2, JIT on, no render-thread
contention — **every number below is a floor; in-client will be worse.**

| Configuration | Wire bytes | Decode | Resident Lua heap |
|---|---|---|---|
| JSON — the decoder the runtime ships | 19.74 MB | **306 / 323 ms** | 63.9 MB |
| JSON — `lunajson` (fastest pure-Lua) | 19.74 MB | **303 / 327 ms** | 64.7 MB |
| MessagePack — `lua-MessagePack` 0.5.4 | 15.34 MB | **332 / 407 ms** | 67.0 MB |
| Table construction only, **zero parsing** | — | **53.1 ms** | 64.5 MB |
| Offset-indexed container — decode **one** record | 19.56 MB | **7.3 µs** | 3.2 KB |
| Parse a 22,000-entry `u32` index | 176 KB | **0.26 ms** | ~0.35 MB |

### 6.2.2 What the measurements force

**A better codec buys nothing.** MessagePack shrank the wire 22% and decoded *slower*. `lunajson`, a
heavily optimised decoder, matched a hand-written one within noise. Two independent swaps, zero
improvement — both are bottlenecked on something neither controls.

**That something is LuaJIT table allocation, floor ~53 ms.** Building the identical object graph from
compile-time constants with the parser removed entirely still costs 53.1 ms and 64.5 MB. So a
hypothetical perfect zero-parse decoder that still materialises Lua tables costs **3+ dropped frames at
60 Hz**. No format on the evaluation list gets under one frame.

**Not materialising costs 7.3 µs.** That is 0.04% of a 16.7 ms frame, at 3.2 KB resident per live
record. A 64-record sliding window is ~205 KB instead of 64 MB.

The gap between 306,000 µs and 7.3 µs is an architecture problem. Choosing a different codec does not
touch it.

### 6.2.3 The capability that makes it possible

`docs/SylvannasAPI/dev/api/file-io.md` documents `core.get_data_file_size(filename)` and
`core.read_data_file_partial(filename, offset, size)` — the latter explicitly binary-safe and
offset-addressed. This is **random access to the artifact** with no C module, no FFI, and no host
decoder. The premise that file reads must return one whole string is incomplete, and the incompleteness
is load-bearing.

### 6.2.4 Format-by-format

| Format | Pure-Lua decoder | Lazy access | Verdict |
|---|---|---|---|
| **JSON** | Yes, already shipped | Not native, but trivially containerised | **Chosen.** Greppable, diffable in git, readable in a bug report, mature serde, adjacent tagging is native. |
| MessagePack | Yes (`lua-MessagePack`) | No length-prefixed skip in the pure-Lua decoder | Rejected — measured *slower*, and loses diffability for a 22% size win that does not matter. |
| Protobuf | Only via codegen or a heavy pure-Lua runtime | Requires full parse | Rejected — schema-evolution story is good, but adjacently-tagged enums map to `oneof` awkwardly and the Lua runtime cost is unjustified. |
| FlatBuffers | Pure-Lua reader exists but is verbose | **Yes, genuinely zero-copy** | Rejected reluctantly. Real zero-copy, but every field access crosses a vtable indirection in interpreted Lua, the artifact stops being human-readable, and it needs an IDL alongside the Rust types — two sources of truth. The offset-indexed JSON container gets the same laziness at 7.3 µs/record without that cost. |
| RON | No usable pure-Lua parser | No | Rejected — Rust-side only, no consumer. |
| bincode | No pure-Lua decoder; not self-describing | No | Rejected — a schema change silently misparses. Exactly the fail-open class this design exists to eliminate. |
| rkyv | No pure-Lua access; relies on Rust archived types and alignment | Yes, in Rust | Rejected — the consumer is Lua. rkyv's zero-copy is unreachable without FFI into a Rust reader, which the sandbox does not offer. |

### 6.2.5 Container layout and chunked warmup

```
[ magic "SNTL" | u16 version | u32 task_count ]
[ header: compact-JSON profile header               ]
[ index:  task_count × (u32 offset, u32 length)     ]   ~176 KB at 22k tasks, 0.26 ms to parse
[ body:   task_count × compact-JSON task record     ]   read on demand
```

The kernel reads magic+header+index at load (measured ~0.26 ms plus a small header decode) and then
reads individual task records through `read_data_file_partial` as the cursor approaches them. Measured
prefetch, if warming ahead of the cursor is wanted:

| Slice | Worst slice | Mean slice | Wall time to prefetch all @1 slice/frame, 60 Hz |
|---|---|---|---|
| 32 tasks | 2.19 ms | 0.31 ms | 11.5 s |
| 64 tasks | 4.97 ms | 0.63 ms | 5.7 s |

A 32-task slice stays inside a frame budget on this hardware with room to spare. **Judgement call:**
prefetch is optional — a 7.3 µs on-demand read is cheap enough that lazy-only is the safer default, and
prefetch should be added only if measurement in-client shows read latency mattering.

## 6.3 Condition lowering

**Chosen: lower to a typed `Predicate` AST at compile time.**

| Alternative | Why not |
|---|---|
| Embedded expression strings (Honorbuddy, §3.2) | Unlimited expressiveness, zero static validation. A typo is a runtime exception mid-run; profiles broke wholesale on client patches. The single clearest cautionary case in the prior art. |
| Per-command imperative handlers (RXPGuides, §3.1) | ~120 handlers each re-inventing `<`/threshold parsing. Adding one operator means touching all of them, and completion truth ends up scattered — a problem this repository has already logged against itself. |
| Typed struct fields per condition kind (Guidelime, §3.3) | Genuinely good and independently validates the approach, but flat fields cannot nest, and the corpus needs `Or` over 11-element quest lists and `Not` over quest states. |
| **Typed AST** (chosen) | Nests, validates offline, evaluates in one function, serialises adjacently. Cost: 15 new variants. |

## 6.4 Spatial representation

Covered in §5.7. The alternative — destinations only, letting the navmesh do everything — is rejected
on the single decisive counter-example of a closed patrol circuit whose first and last points are
identical. The cost of carrying routes is artifact size, mitigated by the waypoint pool (§7.1) that
deduplicates shared points across tasks.

## 6.5 Versioning

Three independent version axes, because they change for different reasons and at different rates:

| Field | Covers | Mismatch |
|---|---|---|
| `schema_version` + `schema_hash` | The tag set and struct shape | **Refuse** — the kernel cannot interpret the bytes |
| `content_hash` + `world_build` | Resolved entry ids | **Refuse** across artifacts (§5.4.1); first-touch probe for server drift |
| `source_version` (from `#version`) | The upstream guide pack revision | **Warn** — informational; a newer guide pack is not an error, it is a reason to recompile |

Collapsing these into one number is the mistake: a guide-pack update should not invalidate a
structurally identical artifact, and a struct change must not be maskable by a content refresh.

## 6.6 Should authoring and runtime formats be the same artifact?

**No.** They are the same information at different stages and they want opposite properties.

| | Authoring (Project JSON) | Runtime Profile |
|---|---|---|
| Optimised for | Human diff, review, editor round-trip | Frame budget, random access |
| Gates | Present, unresolved | Resolved away |
| References | Names (`"Wizbang Cranktoggle"`) | Entry ids (`3666`) |
| Labels | Strings (`"BuzzBox1"`) | `TaskId` indices |
| Layout | Whole file | Offset-indexed records |
| Failure mode | Permissive with diagnostics | Fail-closed |

RXPGuides is the counter-example: its parsed table *is* its runtime object, so a guide cannot be
serialised, validated, or diffed independently of the running UI (§3.1). This repository's existing
Project → Runtime Profile split is correct and this design keeps it.

The one thing worth carrying across the boundary is **provenance**: every `Task` keeps
`source: { file, line_start, line_end }` so a runtime failure points at a corpus line. That is how every
citation in this document was produced, and it costs ~20 bytes per task.

----------

# 7. D7 — The schema

## 7.1 Rust structs (serde-annotated, authoritative)

```rust
// ─── Profile root ────────────────────────────────────────────────────────────

#[derive(Serialize, Deserialize)]
pub struct RuntimeProfile {
    pub magic:          [u8; 4],          // b"SNTL"
    pub schema_version: u16,
    pub schema_hash:    [u8; 32],         // C4: over the full tag set
    pub tags_used:      Vec<String>,      // C4: every op/predicate tag referenced
    pub integrity:      ContentIntegrity, // C4 gap-closer
    pub archetype:      Archetype,        // C2: what this artifact was resolved for
    pub meta:           GuideMeta,
    pub defaults:       ProfileDefaults,
    pub waypoint_pool:  Vec<Point>,       // deduplicated; routes index into this
    pub tasks:          Vec<Task>,        // ordered; TaskId is the index
}

#[derive(Serialize, Deserialize)]
pub struct ContentIntegrity {
    pub content_hash: [u8; 32],  // BLAKE3 over sorted (kind, entry_id, expect_name)
    pub world_source: String,    // "tbcmangos.sqlite"
    pub world_build:  String,    // file digest + consulted row counts
}

#[derive(Serialize, Deserialize)]
pub struct Archetype {
    pub class:         Class,
    pub race:          Race,
    pub faction:       Faction,
    pub expansion:     Expansion,
    pub allegiance:    Option<Allegiance>,   // #aldor / #scryer
    pub hardcore:      bool,                 // #hardcore / #softcore
    pub self_found:    bool,                 // #ssf / #ah
    pub can_fly:       bool,                 // #flyable / #noflyable
    pub content_phase: Option<u8>,           // #phase
    pub mode:          ProfileMode,          // #questguide, .dungeon variant
    pub xp_rate_milli: u32,                  // #xprate, in THOUSANDTHS (1_000 = blizzlike)
    pub hardcore_server: bool,               // #hardcoreserver / #softcoreserver — the REALM
    pub season:        Option<u8>,           // #season
}

#[derive(Serialize, Deserialize)]
pub struct GuideMeta {
    pub name:           String,       // #name
    pub group:          String,       // #group
    pub subgroup:       Option<String>,
    pub source_version: u32,          // #version
    pub next:           Vec<String>,  // #next — profile chaining
}

#[derive(Serialize, Deserialize)]
pub struct ProfileDefaults {
    pub combat:         CombatPolicy,    // C6: profile-level default
    pub unknown_policy: UnknownPolicy,   // C1: fallback when a task does not override
}

// ─── Task: the step-as-container ─────────────────────────────────────────────

pub type TaskId = u32;

#[derive(Serialize, Deserialize)]
pub struct Task {
    pub id:              TaskId,
    pub deps:            Vec<TaskId>,          // P1: MULTI-dependency. Plural.
    pub blocking:        bool,                 // #optional ⇒ false
    pub lifetime:        Lifetime,             // C3: from #sticky
    pub completion:      CompletionSource,     // C3: from #completewith
    pub applies_when:    Option<Predicate>,    // C1: gate
    pub complete_when:   Option<Predicate>,    // C1: the ONLY completion authority
    pub abort_when:      Option<Predicate>,    // C1: failure/abandon
    pub unknown_policy:  UnknownPolicy,        // C1: tri-state policy
    pub ops:             Vec<Op>,              // ORDERED — step-as-container
    pub interact_target: Option<NpcRef>,       // from .target (step-wide form)
    pub combat:          Option<CombatPolicy>, // C6: per-task override
    pub loot_filter:     Vec<LootRule>,        // .collect / .addquestitem
    pub serves_quests:   Vec<QuestId>,         // .requires quest,<id>
    pub suppress:        Vec<BehaviorId>,      // #ignorecorpse
    pub jump_to:         Option<TaskId>,       // .maxlevel 2-arg forward jump
    pub source:          SourceSpan,           // provenance
}

#[derive(Serialize, Deserialize)]
pub struct SourceSpan { pub file: String, pub line_start: u32, pub line_end: u32 }

#[derive(Serialize, Deserialize)]
#[serde(tag = "type", content = "payload")]
pub enum Lifetime {
    Exclusive,
    Background {
        channels:     Vec<Channel>,   // C3: MOVEMENT | FACING | CASTING | ...
        band:         u8,             // C3: 30..=49, Goal band
        terminate_on: Predicate,
    },
}

#[derive(Serialize, Deserialize)]
#[serde(tag = "type", content = "payload")]
pub enum CompletionSource {
    OwnPredicate,
    LinkedTo(TaskId),   // #completewith — compiler-resolved, never a dangling label
}

#[derive(Serialize, Deserialize)]
#[serde(tag = "type", content = "payload")]
pub enum UnknownPolicy {
    Block,
    Defer { budget_ticks: u16 },
    TreatFalse,
    TreatTrue,          // requires explicit compiler opt-in; emits a diagnostic
}

// ─── Operations ──────────────────────────────────────────────────────────────

#[derive(Serialize, Deserialize)]
#[serde(tag = "type", content = "payload")]
pub enum Op {
    Travel        { route: Route },
    Accept        { quest: QuestId, repeatable: bool },
    TurnIn        { quest: QuestId, any_of: Vec<QuestId>, reward_choice: Option<u8>,
                    optional: bool, repeatable: bool },
    Abandon       { quests: Vec<QuestId> },
    UntrackQuest  { quest: QuestId },
    Interact      { npc: NpcRef, gossip: GossipPolicy },
    UseItem       { item: ItemId },
    Cast          { spell: SpellId },
    DestroyItem   { item: ItemId },
    Equip         { slot: u8, item: ItemId },
    EnterVehicle,
    Wait          { secs: u16, label: String },       // .timer
    Delegate      { behavior: BehaviorId, payload: DelegatePayload },  // C5
}

#[derive(Serialize, Deserialize)]
pub struct Route {
    pub kind:      RouteKind,
    pub mode:      TravelMode,   // Any | Ground | Air
    pub points:    Vec<u32>,     // indices into RuntimeProfile.waypoint_pool
    pub radii:     Vec<u16>,     // arrival radius per point, yards
}

#[derive(Serialize, Deserialize)]
#[serde(tag = "type", content = "payload")]
pub enum RouteKind {
    Destination,             // C7: single point, engine paths freely
    Corridor,                // C7: ordered, engine may smooth
    Circuit { close: bool }, // C7: cycled patrol; DO NOT smooth away
}

#[derive(Serialize, Deserialize)]
pub struct Point { pub map_id: u32, pub x: f32, pub y: f32, pub z: Option<f32> }

#[derive(Serialize, Deserialize)]
pub struct NpcRef { pub entry: u32, pub expect_name: String, pub pos: Option<u32> }

#[derive(Serialize, Deserialize)]
#[serde(tag = "type", content = "payload")]
pub enum GossipPolicy { None, AutoAdvance, Index(u8), OptionId(u32) }

#[derive(Serialize, Deserialize)]
#[serde(tag = "type", content = "payload")]
pub enum DelegatePayload {
    Vendor      { npc: NpcRef, mode: VendorMode, items: Vec<ItemId>, gold_floor: Option<u32> },
    Trainer     { npc: NpcRef, spell: Option<SpellId> },
    FlightPath  { npc: NpcRef, mode: FlightMode, dest_node: Option<String> },
    Hearth      { mode: HearthMode, npc: Option<NpcRef> },
    Bank        { npc: NpcRef, mode: BankMode, items: Vec<ItemId> },
    Stable      { npc: NpcRef, mode: StableMode },
    Corpse      { intent: CorpseIntent, resurrect_at: Option<u32> },  // K5
}

// ─── Combat policy (C6) ──────────────────────────────────────────────────────

#[derive(Serialize, Deserialize)]
pub struct CombatPolicy {
    pub stance:       CombatStance,
    pub targets:      Vec<NpcRef>,     // .mob whitelist
    pub watch_units:  Vec<NpcRef>,     // .unitscan
    pub leash_yards:  u16,
    pub allow_adds:   bool,
    pub expect_group: GroupExpectation,
}

#[derive(Serialize, Deserialize)]
#[serde(tag = "type", content = "payload")]
pub enum CombatStance { Avoid, Defensive, Objective, Aggressive }

#[derive(Serialize, Deserialize)]
#[serde(tag = "type", content = "payload")]
pub enum GroupExpectation { Solo, Party { size: u8 }, Dungeon }

// ─── Predicate: THE single condition language (C1) ────────────────────────────

#[derive(Serialize, Deserialize)]
#[serde(tag = "type", content = "payload")]
pub enum Cmp { Lt, Le, Eq, Ge, Gt }

#[derive(Serialize, Deserialize)]
#[serde(tag = "type", content = "payload")]
pub enum Predicate {
    // — ADR-000 §7.2 baseline —
    And(Vec<Predicate>),
    Or(Vec<Predicate>),
    Not(Box<Predicate>),
    QuestComplete  { id: QuestId },
    QuestObjective { id: QuestId, index: u8, need: u32 },
    AtLocation     { point: u32, radius: f32 },
    LevelAtLeast   { level: u8 },
    AuraPresent    { spell: SpellId, on: UnitRef },
    Flag           { key: String },

    // — additions, each justified in §5.1.1 —
    QuestInLog     { id: QuestId },
    QuestTurnedIn  { id: QuestId },
    QuestAvailable { id: QuestId },
    ItemCount      { id: ItemId, cmp: Cmp, count: u32 },   // supersedes HasItem
    MoneyCmp       { cmp: Cmp, copper: u64 },
    SkillCmp       { line: SkillLine, cmp: Cmp, value: u16 },
    ReputationCmp  { faction: u32, standing: Standing, cmp: Cmp, value: i32 },
    XpAtLeast      { level: u8, xp_offset: i32 },
    CooldownCmp    { kind: CooldownKind, id: u32, cmp: Cmp, secs: f32 },
    InArea         { area: u32, kind: AreaKind },
    HearthBoundTo  { area: u32 },
    ItemStatCmp    { slot: u8, stat: ItemStat, cmp: Cmp, value: f32 },
    InGroup        { cmp: Cmp, size: u8 },
    SpellKnown     { spell: SpellId },
    LevelAtMost    { level: u8 },
}

// ─── Leaf vocabulary: bare strings on the wire, never dispatched on ──────────
//
// These 22 enums only NAME a value. The kernel never switches on any of them, so none
// carries a tagging attribute: each serializes as the Rust variant name verbatim.
// §7.3.3 forces exactly this — `"class": "Hunter"`, `"expansion": "Tbc"`,
// `"mode": "Any"`, `"kind": "SubArea"`. `Channel` alone is SCREAMING_SNAKE, per §7.2's
// channel enum. Class / Race / Faction are reused from the ADR-02 authoring vocabulary
// rather than redefined (§5.2); their variant names are already the wire spellings.
//
// TWENTY-ONE of the 22 carry no payload. `ProfileMode` is the exception and always has
// been mis-described here: `Dungeon { instance: DungeonId }` carries one, so it is a
// bare string for its two unit variants and an object for the third. It stays in this
// group because the rule that puts an enum here is ROLE — the kernel does not dispatch
// on it (§5.2 makes the archetype provenance, read by the compiler and by whoever
// audits an artifact, never by the runtime) — not arity.

#[derive(Serialize, Deserialize)]
pub enum Class { Warrior, Paladin, Hunter, Rogue, Priest, Shaman, Mage, Warlock, Druid }

#[derive(Serialize, Deserialize)]
pub enum Race { Human, Orc, Dwarf, NightElf, Undead, Tauren, Gnome, Troll, BloodElf, Draenei }

#[derive(Serialize, Deserialize)]
pub enum Faction { Alliance, Horde, Neutral }

#[derive(Serialize, Deserialize)]
pub enum Expansion { Classic, Tbc, Wotlk }              // #classic / #tbc / #wotlk

#[derive(Serialize, Deserialize)]
pub enum Allegiance { Aldor, Scryer }                   // #aldor / #scryer

#[derive(Serialize, Deserialize)]
pub enum ProfileMode { SpeedRoute, QuestGuide, Dungeon { instance: DungeonId } }
// absence of #questguide / #questguide / .dungeon <instance>. The dungeon variant carries WHICH
// dungeon: `.dungeon Mara` (105) and `.dungeon ZF` (150) are different archetype variants, and a
// unit variant admits every dungeon's steps into every dungeon's profile.
// Wire: the two unit variants stay bare strings ("mode": "SpeedRoute", as §7.3.3 prints); the
// payload-carrying one takes serde's DEFAULT EXTERNAL form, {"Dungeon": {"instance": "Mara"}}.
// Adjacent tagging is deliberately NOT applied: it would rewrite the two spellings §7.3.3 pins,
// and C4's tagging rule (§5.4) is by role — nothing dispatches on this field.

#[derive(Serialize, Deserialize)]                       // .dungeon <instance> — the closed argument set
pub enum DungeonId {
    Bf, Bfd, Crypts, Dm, Gnomer, Mara, Mt, Ramparts, Rfd, Rfk,
    Sfk, Sm, Sp, St, Stockades, Ub, Ulda, Wc, Zf,
}
// Instance counts, in that order: BF 27, BFD 66, Crypts 11, DM 157, Gnomer 41, Mara 105 (+MARA 91),
// MT 24, Ramparts 11 (+RAMPARTS 11), RFD 69, RFK 37, SFK 25, SM 55, SP 16, ST 182, Stockades 36,
// UB 26, Ulda 41 (+ULDA 25), WC 85, ZF 150. BF, MT, SP and UB are staged from an outdoor zone
// (Hellfire Peninsula, Terokkar Forest, Zangarmarsh, Zangarmarsh).
// NINETEEN variants, measured over the 1,351 `.dungeon` instances after folding the three
// case-split spellings (MARA/Mara, ULDA/Ulda, RAMPARTS/Ramparts). Closed on purpose: an open
// String would let a typo'd instance name compile into an archetype nothing matches. This
// declaration was missing for two revisions — the type was referenced by `ProfileMode` above and
// its 19 variants existed only inside a `//` comment, so the ADR named a type it never defined
// (§9 item 28).

#[derive(Serialize, Deserialize)]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]           // the ONE exception (§7.2)
pub enum Channel { Movement, Facing, Casting, Targeting, Interaction, Items, Camera }

#[derive(Serialize, Deserialize)]
pub enum TravelMode { Any, Ground, Air }                // .goto/.waypoint / .groundgoto / .flygoto

#[derive(Serialize, Deserialize)]
pub enum BehaviorId { Vendor, Trainer, FlightPath, Hearth, Bank, Stable, Corpse }  // C5; five are K3

#[derive(Serialize, Deserialize)]
pub enum VendorMode { Sell, Buy }                       // bare .vendor / .vendor <entry> (K4)

#[derive(Serialize, Deserialize)]
pub enum FlightMode { Fly, Discover }                   // .fly / .fp

#[derive(Serialize, Deserialize)]
pub enum HearthMode { Use, Bind }                       // .hs / .home

#[derive(Serialize, Deserialize)]
pub enum BankMode { Withdraw, Deposit }                 // .bankwithdraw / .bankdeposit

#[derive(Serialize, Deserialize)]
pub enum StableMode { Visit, Store, Retrieve }          // .stable is always bare ⇒ Visit

#[derive(Serialize, Deserialize)]
pub enum CorpseIntent { Accidental, DeliberateDeath }   // .deathskip ⇒ DeliberateDeath (K5)

#[derive(Serialize, Deserialize)]
pub enum UnitRef { Player, Target }                     // .aura only ever names the player

#[derive(Serialize, Deserialize)]                       // .skill — the 10 distinct corpus lines
pub enum SkillLine { Cooking, Enchanting, Engineering, FirstAid, Herbalism,
                     Lockpicking, Mining, Riding, Skinning, Tailoring }

#[derive(Serialize, Deserialize)]                       // .reputation — the 6 bands the corpus names
pub enum Standing { Unfriendly, Neutral, Friendly, Honored, Revered, Exalted }

#[derive(Serialize, Deserialize)]
pub enum CooldownKind { Item, Spell }                   // .cooldown item,… / .cooldown spell,…

#[derive(Serialize, Deserialize)]
pub enum AreaKind { Zone, SubArea }                     // .zone/.zoneskip / .subzone/.subzoneskip

#[derive(Serialize, Deserialize)]
pub enum ItemStat { Quality, DamagePerSecond }          // QUALITY / ITEM_MOD_DAMAGE_PER_SECOND_SHORT

// ─── Resume (C3, closing the ADR-000 gap) ────────────────────────────────────

#[derive(Serialize, Deserialize)]
pub struct ResumeCursor {
    pub task:      TaskId,
    pub op_index:  u16,
    pub waypoint:  u16,
    pub loop_iter: u32,
}
```

## 7.2 JSON Schema (excerpt — the load-bearing shapes)

Full schema is mechanical from the structs; these are the parts where agreement matters.

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "title": "Sentinel Runtime Profile",
  "type": "object",
  "required": ["magic","schema_version","schema_hash","tags_used","integrity",
               "archetype","meta","defaults","waypoint_pool","tasks"],
  "properties": {
    "magic":          { "const": "SNTL" },
    "schema_version": { "type": "integer", "minimum": 1 },
    "schema_hash":    { "type": "string", "pattern": "^[0-9a-f]{64}$" },
    "tags_used":      { "type": "array", "items": { "type": "string" } },
    "integrity": {
      "type": "object",
      "required": ["content_hash","world_source","world_build"],
      "properties": {
        "content_hash": { "type": "string", "pattern": "^[0-9a-f]{64}$" },
        "world_source": { "type": "string" },
        "world_build":  { "type": "string" }
      }
    },
    "archetype":      { "$ref": "#/$defs/Archetype" },
    "waypoint_pool": {
      "type": "array",
      "items": {
        "type": "object",
        "required": ["map_id","x","y"],
        "properties": {
          "map_id": { "type": "integer" },
          "x": { "type": "number" }, "y": { "type": "number" },
          "z": { "type": ["number","null"] }
        }
      }
    },
    "tasks": { "type": "array", "items": { "$ref": "#/$defs/Task" } }
  },
  "$defs": {
    "Archetype": {
      "type": "object",
      "required": ["class","race","faction","expansion","allegiance","hardcore","self_found",
                   "can_fly","content_phase","mode","xp_rate_milli","hardcore_server","season"],
      "properties": {
        "class":     { "enum": ["Warrior","Paladin","Hunter","Rogue","Priest","Shaman","Mage",
                                "Warlock","Druid"] },
        "race":      { "enum": ["Human","Orc","Dwarf","NightElf","Undead","Tauren","Gnome","Troll",
                                "BloodElf","Draenei"] },
        "faction":   { "enum": ["Alliance","Horde","Neutral"] },
        "expansion": { "enum": ["Classic","Tbc","Wotlk"] },
        "allegiance":      { "oneOf": [{ "enum": ["Aldor","Scryer"] }, { "type": "null" }] },
        "hardcore":        { "type": "boolean" },
        "self_found":      { "type": "boolean" },
        "can_fly":         { "type": "boolean" },
        "content_phase":   { "type": ["integer","null"] },
        "mode":            { "$ref": "#/$defs/ProfileMode" },
        "xp_rate_milli":   { "type": "integer" },
        "hardcore_server": { "type": "boolean" },
        "season":          { "type": ["integer","null"] }
      },
      "$comment": "C2 provenance (§5.2). Not dispatched on, so nothing here is adjacently tagged."
    },
    "ProfileMode": {
      "oneOf": [
        { "enum": ["SpeedRoute","QuestGuide"] },
        { "type": "object",
          "required": ["Dungeon"],
          "properties": {
            "Dungeon": { "type": "object",
                         "required": ["instance"],
                         "properties": { "instance": { "$ref": "#/$defs/DungeonId" } } }
          } }
      ],
      "$comment": "The ONE externally-tagged shape in this schema, and deliberately so: `mode` is a leaf vocabulary field the kernel never dispatches on (§5.4), the two unit variants are the bare strings §7.3.3 prints, and adjacent tagging would rewrite both. A `{type,payload}` spelling here would be a change to every artifact compiled so far, bought with nothing."
    },
    "DungeonId": {
      "enum": ["Bf","Bfd","Crypts","Dm","Gnomer","Mara","Mt","Ramparts","Rfd","Rfk",
               "Sfk","Sm","Sp","St","Stockades","Ub","Ulda","Wc","Zf"],
      "$comment": "Closed: 19 variants over the 1,351 `.dungeon` instances, after folding the MARA/ULDA/RAMPARTS case splits. See §7.1."
    },
    "Task": {
      "type": "object",
      "required": ["id","deps","blocking","lifetime","completion","unknown_policy","ops","source"],
      "properties": {
        "id":       { "type": "integer" },
        "deps":     { "type": "array", "items": { "type": "integer" } },
        "blocking": { "type": "boolean" },
        "lifetime":       { "$ref": "#/$defs/Lifetime" },
        "completion":     { "$ref": "#/$defs/CompletionSource" },
        "applies_when":   { "oneOf": [{ "$ref": "#/$defs/Predicate" }, { "type": "null" }] },
        "complete_when":  { "oneOf": [{ "$ref": "#/$defs/Predicate" }, { "type": "null" }] },
        "abort_when":     { "oneOf": [{ "$ref": "#/$defs/Predicate" }, { "type": "null" }] },
        "unknown_policy": { "$ref": "#/$defs/UnknownPolicy" },
        "ops":    { "type": "array", "items": { "$ref": "#/$defs/Op" } },
        "source": {
          "type": "object",
          "required": ["file","line_start","line_end"],
          "properties": { "file": {"type":"string"},
                          "line_start": {"type":"integer"},
                          "line_end": {"type":"integer"} }
        }
      }
    },
    "Lifetime": {
      "type": "object",
      "required": ["type"],
      "properties": {
        "type": { "enum": ["Exclusive","Background"] },
        "payload": {
          "type": "object",
          "properties": {
            "channels": { "type": "array",
                          "items": { "enum": ["MOVEMENT","FACING","CASTING","TARGETING",
                                              "INTERACTION","ITEMS","CAMERA"] } },
            "band": { "type": "integer", "minimum": 30, "maximum": 49 },
            "terminate_on": { "$ref": "#/$defs/Predicate" }
          }
        }
      }
    },
    "CompletionSource": {
      "type": "object",
      "required": ["type"],
      "properties": {
        "type":    { "enum": ["OwnPredicate","LinkedTo"] },
        "payload": { "type": "integer" }
      }
    },
    "UnknownPolicy": {
      "type": "object", "required": ["type"],
      "properties": { "type": { "enum": ["Block","Defer","TreatFalse","TreatTrue"] },
                      "payload": { "type": "object" } }
    },
    "Predicate": {
      "type": "object",
      "required": ["type"],
      "properties": {
        "type": { "enum": ["And","Or","Not","QuestComplete","QuestObjective","AtLocation",
                           "LevelAtLeast","AuraPresent","Flag","QuestInLog","QuestTurnedIn",
                           "QuestAvailable","ItemCount","MoneyCmp","SkillCmp","ReputationCmp",
                           "XpAtLeast","CooldownCmp","InArea","HearthBoundTo","ItemStatCmp",
                           "InGroup","SpellKnown","LevelAtMost"] },
        "payload": {}
      },
      "$comment": "Adjacently tagged per C4. An externally-tagged variant fails closed at load."
    },
    "Op": {
      "type": "object",
      "required": ["type"],
      "properties": {
        "type": { "enum": ["Travel","Accept","TurnIn","Abandon","UntrackQuest","Interact",
                           "UseItem","Cast","DestroyItem","Equip","EnterVehicle","Wait","Delegate"] },
        "payload": {}
      }
    }
  }
}
```

## 7.3 Worked example

**Source:** `sentinel/docs/adr/restedxp guides/A-11-23.lua:211–280`, transcribed contiguously.
**Every game ID below is copied from a corpus line and independently verified against
`tbcmangos.sqlite`.** Nothing is invented.

### 7.3.1 The corpus excerpt

```
211  step
212      #sticky
213      #label BuzzBox1
214      #loop
215      .goto 1439,36.051,44.757,0
216      .goto 1439,36.280,50.071,0
217      .goto 1439,35.275,53.464,0
218      .waypoint 1439,36.091,51.501,60,0
             … 13 further .waypoint lines …
231      .waypoint 1439,36.051,44.757,60,0
232      >>Kill |cRXP_ENEMY_Pygmy Tide Crawlers|r and |cRXP_ENEMY_Young Reef Crawlers|r …
234      .complete 983,1 --Crawler Leg (6)
235      .mob Pygmy Tide Crawler
236      .mob Young Reef Crawler
237      .isOnQuest 983
238  step
239      .isOnQuest 3524
240      .goto 1439,36.371,50.920
241      >>Open the |cRXP_PICK_Beached Sea Creature|r. Loot it for the |cRXP_LOOT_Sea Creature Bones|r
242      .complete 3524,1 --Sea Creature Bones (1)
243  step
244      #sticky
245      #label RabidThistle
246      #loop
247      .goto 1439,38.226,52.780,0
             … 7 further .goto lines …
255      >>|cRXP_WARN_Use|r |T134335:0|t[Tharnariun's Hope] on a |cRXP_ENEMY_Rabid Thistle Bear|r …
258      .complete 2118,1 --Rabid Thistle Bear Captured (1)
259      .unitscan Rabid Thistle Bear
260      .use 7586
261  step
262      .goto Darkshore,38.90,53.59
263      >>Run toward the edge of the Furbolg Camp
264      .complete 984,1 -- Find a corrupt furbolg camp
265  step
266      #optional
267      #requires RabidThistle
268  --XXREQ Placeholder invis step until multiple requires per step
269  step
270  #optional
271      .xp 10+6760 >> Grind to 6760+/7600xp
272  step
273      #label Auber1
274      #completewith next
275      .subzone 442 >> Travel to Auberdine
276  step
277      #requires BuzzBox1
278      .goto 1439,36.634,46.250
279      >>Click the |cRXP_PICK_Buzzbox 827|r on the ground
280      .turnin 983 >> Turn in Buzzbox 827
```

### 7.3.2 ID verification against `tbcmangos.sqlite`

| ID | Kind | MaNGOS name | Corroborating corpus text |
|---|---|---|---|
| 983 | quest | `Buzzbox 827` | `A-11-23.lua:280` "Turn in Buzzbox 827" |
| 5385 | item | `Crawler Leg` | `A-11-23.lua:234` comment `--Crawler Leg (6)` |
| 2231 | creature | `Pygmy Tide Crawler` | `A-11-23.lua:235` `.mob Pygmy Tide Crawler` |
| 2234 | creature | `Young Reef Crawler` | `A-11-23.lua:236` `.mob Young Reef Crawler` |
| 3524 | quest | `Washed Ashore` | `A-11-23.lua:239` `.isOnQuest 3524` |
| 12242 | item | `Sea Creature Bones` | `A-11-23.lua:241` "Sea Creature Bones" |
| 2118 | quest | `Plagued Lands` | `A-11-23.lua:258` `.complete 2118,1` |
| 11836 | creature | `Captured Rabid Thistle Bear` | `A-11-23.lua:258` comment "Rabid Thistle Bear Captured (1)" |
| 2164 | creature | `Rabid Thistle Bear` | `A-11-23.lua:259` `.unitscan Rabid Thistle Bear` |
| 7586 | item | `Tharnariun's Hope` | `A-11-23.lua:255` `[Tharnariun's Hope]` |
| 984 | quest | `How Big a Threat?` | `A-11-23.lua:264` `.complete 984,1` |
| 17182 | gameobject | `Buzzbox 827` | `A-11-23.lua:279` "Click the Buzzbox 827 on the ground" |
| 1439 | ui map | Darkshore | `A-11-23.lua:262` uses the **name** `Darkshore` for the same area |

`1439` is the last row for a reason: it is the only id in the table that **does not appear in the
compiled artifact**. It is a *lookup key* — the ui map the author wrote coordinates against — and
§2.6 requires it to be consumed by the transform rather than emitted. §7.3.3's pool carries
`map_id: 1` (Kalimdor, Darkshore's continent) with world `x`/`y`, via
`ZoneMap::to_world` (`SentinelQuesting/shared/src/zone.rs`); a compiled `Point` still wearing `1439`
is §2.6's named bug signature, and this listing printed exactly that for two revisions (§9 item 27).

Three cross-checks that validate the whole pipeline, not just the ids:

- `quest_template` row 983 has `ReqItemId1 = 5385, ReqItemCount1 = 6` — **matching the corpus author's
  comment `(6)` exactly.** This is why `Predicate::QuestObjective.need` can be baked offline instead of
  parsed from a localized progress string at runtime.
- Quest 983's ender is **`gameobject_involvedrelation` entry 17182**, not a creature — which is exactly
  why §7.3.3's task 6 has a `.turnin` with **no `.target`**. The schema's `interact_target: None` is
  not an omission, it is correct.
- Quest 984 has **no `Req*` columns populated at all** — it is an exploration objective, matching
  `.complete 984,1 -- Find a corrupt furbolg camp`. So `QuestObjective.need` must permit `0`
  (satisfied by area discovery, not a count).

### 7.3.3 Compiled output

Archetype resolved for a Night Elf Hunter, Alliance, TBC, softcore, AH-permitted. Every route's
`points` are indices into `waypoint_pool`, which is printed in full below.

**This listing is generated from the fixture, not typed.** The artifact below is
`SentinelQuesting/shared/tests/fixtures/adr07_worked_example.json` verbatim, and
`shared/tests/kernel_adr_listing.rs` fails if the two stop matching: it extracts this fence by its
heading anchor, loads it into `sentinel_models::kernel::RuntimeProfile`, and compares it to the
fixture leaf by leaf. The fixture is the specification — its ids are verified against
`tbcmangos.sqlite` (§7.3.2) and `compiler/tests/kernel_worked_example.rs` drives the real
`parse_guide` → `ProjectBuilder` → `Compiler::compile_kernel` pipeline into it. When that guard
fails, this section is what moves. It was written by hand once, and when the drift was finally
measured the two sides disagreed on **136 leaf paths** (§9 item 28).

Two consequences of being generated, both deliberate:

- **The listing carries no `_comment` keys.** `RuntimeProfile` is `deny_unknown_fields` (C4, §5.4),
  so a listing carrying prose keys is a worked example of something that cannot load. The per-task
  prose that used to live in them is the table below instead.
- **Both digests are valid 64-character hex, not prose.** `"<blake3-of-tagset>"` is 20 characters
  against §7.2's `^[0-9a-f]{64}$`. `deadbeef × 8` and `cafebabe × 8` are obviously synthetic and
  actually loadable; R3 replaces them with real BLAKE3 output (§5.4.1, §9 item 25).

**The pool holds world coordinates on the continent map, not authored percentages.** All 28 source
route lines are authored zone-percentage form against ui map `1439` (Darkshore), and every one is
converted through `ZoneMap::to_world` (`SentinelQuesting/shared/src/zone.rs`) before it reaches the
artifact, so each entry carries `map_id: 1` — Kalimdor, Darkshore's continent — and raw world
`x`/`y`. §2.6 states why this is the only admissible shape: `1439` is a *lookup key*, and a
compiled `Point` still wearing it is that section's **named bug signature**. An earlier revision of
this listing printed exactly that signature on all 22 entries — the document demonstrated the
failure it names (§9 item 28). `z` is `null` throughout: RestedXP supplies no Z, and the trailing
`,0` on each source line is a flag argument.

The pool is **interned**: one entry per *distinct* `(map_id, x, y, z)`, not one per source route
line. The 28 route lines of `A-11-23.lua:211–280` visit only **22** distinct coordinates, so the
pool is 22 entries. An entry may therefore be referenced **more than once**, and the two routes
that do so do it for two different reasons that must not be conflated:

- **Task 0 repeats indices 0, 1, 2 and 3 because the bot physically walks those coordinates
  twice.** `:224` re-walks `:217`, `:225` re-crosses the circuit's own first waypoint `:218`,
  `:226` re-walks `:216`, and `:231` returns to `:215` to close the circuit. All four repeats are
  geometrically real and survive route-level dedup. *Do not justify them by the arrival radius* —
  three of the four change it (0 on the approach, 60 on the circuit). The sound justification is
  that the route visits the coordinate twice.
- **Task 2 repeats indices 14 and 15 because of the §2.6 double emission, not because it re-crosses
  anything.** `:247` and `:248` are 4-arg `.goto`s naming the loop's two anchors; `:249`–`:254`
  then walk the real circuit and re-emit those same two coordinates in 5-arg form. The radii
  corroborate it — task 2's are `[0,0,50,50,50,50,50,50]`, the two 4-arg emissions carrying 0 and
  their 5-arg twins 50. That two-line preamble is redundant, and route-level dedup will take task 2
  from **8 points to 6**.

A route that re-crosses a point says so by **repeating the index**, never by carrying a second copy
of the point.

**Eight authored steps lower to seven tasks.** `A-11-23.lua:265–268` is an empty `#optional` step
whose only content is `#requires RabidThistle` plus the author's own marker
`--XXREQ Placeholder invis step until multiple requires per step`: RestedXP permits one `#requires`
per step, so a second predecessor is encoded as a throwaway step. The compiler folds that
placeholder into its successor, the grind step, and the `#requires` edge goes with it — which is why
task 4 spans `265–271` and carries `deps: [2]`. An earlier revision printed the placeholder as a
task of its own, giving eight tasks and shifting every index from 4 upward (§9 item 28).

**`meta.name` is `12-14 Darkshore`, from `#name`.** `A-11-23.lua` also carries three `#displayname`
lines, one of them `10-14 Darkshore << Dwarf Hunter`. A Night Elf Hunter is not a Dwarf Hunter, and
`GuideMeta.name` reads `#name` regardless; `10-14` was a display string in the wrong field.

**What this listing does and does not demonstrate.** It demonstrates the **pool interning** of
§7.1 (`waypoint_pool` "deduplicated; routes index into this") and §6.4 ("deduplicates shared points
across tasks"): only the pool shrinks, no `points` array changes length, and no `radii` array
changes at all. It does **not** demonstrate the **route-level dedup** of §2.6 ("An importer treating
each `.goto` as a distinct route node doubles the path"), §8 ("an importer that does not doubles
every affected route") and §5.7 ("deduplicates the 4,190 measured duplicated coordinate triples on
the way in"). Those three state a route-*length* consequence, which interning provably cannot
deliver — as the previous sentence says. Route-level dedup is a later deliverable, and task 2's
route is printed below in its **un-deduplicated** 8-point form.

**It also does not demonstrate `Task.deps` plurality.** No task below has two predecessors: task 4
carries `[2]` and task 6 carries `[0]`, and after the XXREQ fold nothing in this excerpt carries
more. The pre-fold listing showed `deps: [2, 0]` on the placeholder task, which spent the excerpt's
single `#requires BuzzBox1` twice — once there and once on the turn-in that actually names it. §8
and §10 item 2 cited this excerpt as the multi-predecessor witness; it is not one, and both now say
so. `Vec<TaskId>` is justified by §2.5's authoring measurement and by the fold itself, not by an
artifact in this document.

**Per-task prose.** What each task demonstrates, kept *outside* the artifact so the artifact loads.
This replaces the seven `_comment` keys the listing used to carry — one of which annotated the folded
placeholder and has no task left to describe, and one of which put `map_id 1439` in the reader's head
as though it survived compilation:

| Task | Source | What it demonstrates |
|---|---|---|
| 0 | `211–237` | `#sticky` + `#loop` → a `Background` task holding `MOVEMENT`, running a **closed** `Circuit`, band 34. `.mob` × 2 gives an `Aggressive` whitelist because a grind circuit wants pulls (§5.6). |
| 1 | `238–242` | An `Exclusive` objective task. `.isOnQuest 3524` → `applies_when`, and the loot filter comes from the objective's `ReqItemId`. |
| 2 | `243–260` | The second sticky circuit, band 35. `.use 7586` is an **op**, not a completion condition; `.unitscan` feeds `watch_units` rather than `targets`, and `stance: Objective` with `allow_adds: false` is what §5.6 maps a bare `.mob`-free objective circuit to. |
| 3 | `261–264` | The zone **name** form (`.goto Darkshore,…`) normalises through the same `ZoneMap` as tasks 0–2 and lands on the same `map_id: 1`. `need: 0` is correct: quest 984 has no `Req*` columns (§7.3.2). |
| 4 | `265–271` | The **XXREQ fold**. `#optional` + `.xp 10+6760` → a non-blocking fallback grind with `stance: Aggressive` and an empty whitelist; the folded placeholder's `#requires RabidThistle` is the `deps: [2]`. `unknown_policy: TreatFalse` — a grind that cannot read its own progress must not block the run. |
| 5 | `272–275` | `#completewith next` → `CompletionSource::LinkedTo(6)`. A ride-along: `Background` with **empty** channels, because a task whose completion is decided elsewhere contends for nothing. Its `budget_ticks: 30` is the smaller of the two budgets (§9 item 25). |
| 6 | `276–280` | `#requires BuzzBox1` → `deps: [0]`. A **gameobject** turn-in: quest 983's ender is `gameobject_involvedrelation` 17182, so `interact_target: null` is correct rather than missing (§7.3.2). Its `applies_when` / `complete_when` pair is authored nowhere and derived from the hand-in itself (`compiler/src/kernel/task_graph.rs::hand_in_predicates`). |

```json
{
  "magic": "SNTL",
  "schema_version": 1,
  "schema_hash": "deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef",
  "tags_used": [
    "InArea",
    "QuestComplete",
    "QuestInLog",
    "QuestObjective",
    "QuestTurnedIn",
    "Travel",
    "TurnIn",
    "UseItem",
    "XpAtLeast"
  ],
  "integrity": {
    "content_hash": "cafebabecafebabecafebabecafebabecafebabecafebabecafebabecafebabe",
    "world_source": "tbcmangos.sqlite",
    "world_build": "sha256:…; quest_template=6599 creature_template=18799 gameobject_template=14216"
  },
  "archetype": {
    "class": "Hunter",
    "race": "NightElf",
    "faction": "Alliance",
    "expansion": "Tbc",
    "allegiance": null,
    "hardcore": false,
    "self_found": false,
    "can_fly": false,
    "content_phase": null,
    "mode": "SpeedRoute",
    "xp_rate_milli": 1000,
    "hardcore_server": false,
    "season": null
  },
  "meta": {
    "name": "12-14 Darkshore",
    "group": "RestedXP TBC Guide (A)",
    "subgroup": "RestedXP Alliance 1-20",
    "source_version": 7,
    "next": ["14-20 Bloodmyst"]
  },
  "defaults": {
    "combat": {
      "stance": { "type": "Defensive" },
      "targets": [],
      "watch_units": [],
      "leash_yards": 40,
      "allow_adds": true,
      "expect_group": { "type": "Solo" }
    },
    "unknown_policy": { "type": "Defer", "payload": { "budget_ticks": 60 } }
  },
  "waypoint_pool": [
    { "map_id": 1, "x": 6378.9443, "y": 580.3262, "z": null },
    { "map_id": 1, "x": 6146.8994, "y": 565.3264, "z": null },
    { "map_id": 1, "x": 5998.7383, "y": 631.15405, "z": null },
    { "map_id": 1, "x": 6084.456, "y": 577.70605, "z": null },
    { "map_id": 1, "x": 6046.597, "y": 510.6338, "z": null },
    { "map_id": 1, "x": 5990.049, "y": 509.65137, "z": null },
    { "map_id": 1, "x": 5922.0156, "y": 535.1963, "z": null },
    { "map_id": 1, "x": 5893.589, "y": 606.26416, "z": null },
    { "map_id": 1, "x": 5927.955, "y": 643.40234, "z": null },
    { "map_id": 1, "x": 6213.1416, "y": 549.41016, "z": null },
    { "map_id": 1, "x": 6219.517, "y": 585.1731, "z": null },
    { "map_id": 1, "x": 6274.668, "y": 590.08545, "z": null },
    { "map_id": 1, "x": 6348.465, "y": 599.45215, "z": null },
    { "map_id": 1, "x": 6109.826, "y": 559.3662, "z": null },
    { "map_id": 1, "x": 6028.6064, "y": 437.86328, "z": null },
    { "map_id": 1, "x": 5749.3145, "y": 378.71704, "z": null },
    { "map_id": 1, "x": 5946.4697, "y": 418.14795, "z": null },
    { "map_id": 1, "x": 5852.4116, "y": 450.24316, "z": null },
    { "map_id": 1, "x": 5783.418, "y": 446.4441, "z": null },
    { "map_id": 1, "x": 5806.1685, "y": 407.0786, "z": null },
    { "map_id": 1, "x": 5993.2363, "y": 393.7163, "z": null },
    { "map_id": 1, "x": 6313.75, "y": 542.13965, "z": null }
  ],
  "tasks": [
    {
      "id": 0,
      "deps": [],
      "blocking": true,
      "lifetime": {
        "type": "Background",
        "payload": {
          "channels": ["MOVEMENT"],
          "band": 34,
          "terminate_on": { "type": "QuestTurnedIn", "payload": { "id": 983 } }
        }
      },
      "completion": { "type": "OwnPredicate" },
      "applies_when": { "type": "QuestInLog", "payload": { "id": 983 } },
      "complete_when": { "type": "QuestObjective", "payload": { "id": 983, "index": 1, "need": 6 } },
      "abort_when": null,
      "unknown_policy": { "type": "Defer", "payload": { "budget_ticks": 60 } },
      "ops": [
        {
          "type": "Travel",
          "payload": {
            "route": {
              "kind": { "type": "Circuit", "payload": { "close": true } },
              "mode": "Any",
              "points": [0, 1, 2, 3, 4, 5, 6, 7, 8, 2, 3, 1, 9, 10, 11, 12, 0],
              "radii": [0, 0, 0, 60, 60, 60, 60, 60, 60, 60, 60, 60, 60, 60, 60, 60, 60]
            }
          }
        }
      ],
      "interact_target": null,
      "combat": {
        "stance": { "type": "Aggressive" },
        "targets": [
          { "entry": 2231, "expect_name": "Pygmy Tide Crawler", "pos": null },
          { "entry": 2234, "expect_name": "Young Reef Crawler", "pos": null }
        ],
        "watch_units": [],
        "leash_yards": 60,
        "allow_adds": true,
        "expect_group": { "type": "Solo" }
      },
      "loot_filter": [{ "item": 5385, "for_quest": 983 }],
      "serves_quests": [983],
      "suppress": [],
      "jump_to": null,
      "source": { "file": "A-11-23.lua", "line_start": 211, "line_end": 237 }
    },

    {
      "id": 1,
      "deps": [],
      "blocking": true,
      "lifetime": { "type": "Exclusive" },
      "completion": { "type": "OwnPredicate" },
      "applies_when": { "type": "QuestInLog", "payload": { "id": 3524 } },
      "complete_when": { "type": "QuestObjective", "payload": { "id": 3524, "index": 1, "need": 1 } },
      "abort_when": null,
      "unknown_policy": { "type": "Defer", "payload": { "budget_ticks": 60 } },
      "ops": [
        {
          "type": "Travel",
          "payload": {
            "route": {
              "kind": { "type": "Destination" },
              "mode": "Any",
              "points": [13],
              "radii": [5]
            }
          }
        }
      ],
      "interact_target": null,
      "combat": null,
      "loot_filter": [{ "item": 12242, "for_quest": 3524 }],
      "serves_quests": [3524],
      "suppress": [],
      "jump_to": null,
      "source": { "file": "A-11-23.lua", "line_start": 238, "line_end": 242 }
    },

    {
      "id": 2,
      "deps": [],
      "blocking": true,
      "lifetime": {
        "type": "Background",
        "payload": {
          "channels": ["MOVEMENT"],
          "band": 35,
          "terminate_on": {
            "type": "QuestObjective",
            "payload": { "id": 2118, "index": 1, "need": 1 }
          }
        }
      },
      "completion": { "type": "OwnPredicate" },
      "applies_when": { "type": "QuestInLog", "payload": { "id": 2118 } },
      "complete_when": { "type": "QuestObjective", "payload": { "id": 2118, "index": 1, "need": 1 } },
      "abort_when": null,
      "unknown_policy": { "type": "Defer", "payload": { "budget_ticks": 60 } },
      "ops": [
        {
          "type": "Travel",
          "payload": {
            "route": {
              "kind": { "type": "Circuit", "payload": { "close": true } },
              "mode": "Any",
              "points": [14, 15, 14, 16, 17, 18, 19, 15],
              "radii": [0, 0, 50, 50, 50, 50, 50, 50]
            }
          }
        },
        { "type": "UseItem", "payload": { "item": 7586 } }
      ],
      "interact_target": null,
      "combat": {
        "stance": { "type": "Objective" },
        "targets": [{ "entry": 2164, "expect_name": "Rabid Thistle Bear", "pos": null }],
        "watch_units": [{ "entry": 2164, "expect_name": "Rabid Thistle Bear", "pos": null }],
        "leash_yards": 50,
        "allow_adds": false,
        "expect_group": { "type": "Solo" }
      },
      "loot_filter": [],
      "serves_quests": [2118],
      "suppress": [],
      "jump_to": null,
      "source": { "file": "A-11-23.lua", "line_start": 243, "line_end": 260 }
    },

    {
      "id": 3,
      "deps": [],
      "blocking": true,
      "lifetime": { "type": "Exclusive" },
      "completion": { "type": "OwnPredicate" },
      "applies_when": { "type": "QuestInLog", "payload": { "id": 984 } },
      "complete_when": { "type": "QuestObjective", "payload": { "id": 984, "index": 1, "need": 0 } },
      "abort_when": null,
      "unknown_policy": { "type": "Defer", "payload": { "budget_ticks": 60 } },
      "ops": [
        {
          "type": "Travel",
          "payload": {
            "route": {
              "kind": { "type": "Destination" },
              "mode": "Any",
              "points": [20],
              "radii": [5]
            }
          }
        }
      ],
      "interact_target": null,
      "combat": null,
      "loot_filter": [],
      "serves_quests": [984],
      "suppress": [],
      "jump_to": null,
      "source": { "file": "A-11-23.lua", "line_start": 261, "line_end": 264 }
    },

    {
      "id": 4,
      "deps": [2],
      "blocking": false,
      "lifetime": { "type": "Exclusive" },
      "completion": { "type": "OwnPredicate" },
      "applies_when": null,
      "complete_when": { "type": "XpAtLeast", "payload": { "level": 10, "xp_offset": 6760 } },
      "abort_when": null,
      "unknown_policy": { "type": "TreatFalse" },
      "ops": [],
      "interact_target": null,
      "combat": {
        "stance": { "type": "Aggressive" },
        "targets": [],
        "watch_units": [],
        "leash_yards": 40,
        "allow_adds": true,
        "expect_group": { "type": "Solo" }
      },
      "loot_filter": [],
      "serves_quests": [],
      "suppress": [],
      "jump_to": null,
      "source": { "file": "A-11-23.lua", "line_start": 265, "line_end": 271 }
    },

    {
      "id": 5,
      "deps": [],
      "blocking": true,
      "lifetime": {
        "type": "Background",
        "payload": {
          "channels": [],
          "band": 30,
          "terminate_on": { "type": "InArea", "payload": { "area": 442, "kind": "SubArea" } }
        }
      },
      "completion": { "type": "LinkedTo", "payload": 6 },
      "applies_when": null,
      "complete_when": { "type": "InArea", "payload": { "area": 442, "kind": "SubArea" } },
      "abort_when": null,
      "unknown_policy": { "type": "Defer", "payload": { "budget_ticks": 30 } },
      "ops": [],
      "interact_target": null,
      "combat": null,
      "loot_filter": [],
      "serves_quests": [],
      "suppress": [],
      "jump_to": null,
      "source": { "file": "A-11-23.lua", "line_start": 272, "line_end": 275 }
    },

    {
      "id": 6,
      "deps": [0],
      "blocking": true,
      "lifetime": { "type": "Exclusive" },
      "completion": { "type": "OwnPredicate" },
      "applies_when": { "type": "QuestComplete", "payload": { "id": 983 } },
      "complete_when": { "type": "QuestTurnedIn", "payload": { "id": 983 } },
      "abort_when": null,
      "unknown_policy": { "type": "Block" },
      "ops": [
        {
          "type": "Travel",
          "payload": {
            "route": {
              "kind": { "type": "Destination" },
              "mode": "Any",
              "points": [21],
              "radii": [5]
            }
          }
        },
        {
          "type": "TurnIn",
          "payload": {
            "quest": 983,
            "any_of": [],
            "reward_choice": null,
            "optional": false,
            "repeatable": false
          }
        }
      ],
      "interact_target": null,
      "combat": null,
      "loot_filter": [],
      "serves_quests": [983],
      "suppress": [],
      "jump_to": null,
      "source": { "file": "A-11-23.lua", "line_start": 276, "line_end": 280 }
    }
  ]
}
```

**Step types exercised:** `Background`+`Circuit` sticky loop with declared channels (tasks 0 and 2),
`Exclusive` objective task (1, 3), the XXREQ fold carrying a folded `#requires` (4), fallback grind
(4, the same task), `CompletionSource::LinkedTo` ride-along with empty channels (5), and a
dependency-gated turn-in against a gameobject (6). Four distinct `unknown_policy` values appear
across the seven tasks — `Defer{60}`, `TreatFalse`, `Defer{30}`, `Block` — which is the whole
evidence base in this document for §5.1.2's per-task rule.
`Op::Travel`, `Op::UseItem`, `Op::TurnIn` all appear; `Op::Delegate` is shown in §5.5 rather than here
because this excerpt contains no vendor/flight/hearth step — and, per §1.2, is emitted by nothing at
all yet.

----------

# 8. D8 — Edge case matrix

| Edge case | Schema mechanism | ADR-000 subsystem |
|---|---|---|
| **Multi-predecessor chains across non-adjacent steps** | `Task.deps: Vec<TaskId>` — plural in the struct (§7.1). Compiler folds the XXREQ placeholder into its successor and carries the edge with it. §7.3.3's excerpt is **not** a witness for the plural case: after the fold no task in it carries two deps (§9 item 28); the justification is §2.5's authoring measurement, not an artifact printed here. | Quest Activity cursor |
| **Grind/patrol loops on dynamic conditions** | `RouteKind::Circuit` + `complete_when` predicate. `#loop`+`.mob`+`.complete` → `Aggressive` stance with an objective predicate (§7.3, task 0). | ControlBroker (`MOVEMENT`), `service.combat` |
| **Group/party content and tag contention** | `CombatPolicy.expect_group` (`Solo`/`Party{n}`/`Dungeon`). `.group` 190, `.solo` 13. Tag contention is **not schema-solvable** — the schema exposes `targets` and `allow_adds` so the combat service can decide to abandon a tagged mob; the retry budget lives in the runtime. | `service.combat`, ControlBroker `TARGETING` |
| **Escort quests** | **Not expressible in the source DSL.** Escorts appear only as `>>` display prose (`A-23-30.lua:2017` "Escort Corporal Keeshan back to Lakeshire"). The schema exposes `Op::Interact` with `GossipPolicy` to *start* one (`.gossip 6669,0`, `A-11-23.lua:3661`) and `complete_when` to detect the outcome, but following/protecting the NPC is a behaviour the kernel must own. Flagged in §9 as a genuine gap. | Would need a new `behavior.escort` |
| **Timed quests** | `Op::Wait { secs, label }` from `.timer` (200). Failure detected via `abort_when` on the quest's failed state (`is_complete == -1`). | `Sentinel.objectives` |
| **Vehicle quests** | `Op::EnterVehicle` (`.vehicle`, 2). Kept precisely because it cannot be expressed as `.use`. | ControlBroker — vehicle control needs `MOVEMENT`+`CASTING`; ADR-000 does not model a vehicle channel (§9) |
| **Quests with failure states** | `Task.abort_when` predicate, plus the documented `is_complete == -1` *failed* tri-state (§5.1.2). This is why `satisfied()` must not return `bool` — the failed state is truthy in Lua. | `Sentinel.objectives` |
| **Faction/race starting-zone variance** | Resolved entirely at compile time into `Archetype`. Distinct starting guides (`A-1-11-Human`, `A-1-11-Draenei`, …) become distinct artifacts. | Compiler; no runtime subsystem |
| **Objectives already complete on arrival / resume mid-profile** | `applies_when` re-evaluated against live state every tick; `Predicate::QuestTurnedIn` distinguishes handed-in from never-taken. `ResumeCursor` restores position but is **never trusted for truth** (§6.1). | `Sentinel.objectives`, Persist |
| **Death and corpse recovery** | Delegated to `behavior.corpse` at band 90–99. Automatic. | §3.2 corpse recovery |
| **Deliberate death as traversal (`.deathskip`)** | `Op::Delegate { behavior: corpse, payload: { intent: DeliberateDeath } }` **plus** `Task.suppress: [corpse]` derived from `#ignorecorpse`. The `intent` field (kernel change K5) is what stops the band 90–99 safety net from "rescuing" a death the profile wanted: recovery sees `DeliberateDeath` and resurrects at the *intended* graveyard instead of running back to the corpse. Without K5 the safety net and the profile fight each other. | §3.2 corpse recovery — **needs a new capability** |
| **Vendor / restock / bank / hearth / flight** | `Op::Delegate` with typed `DelegatePayload` (§5.5). Five of the six behaviours do not yet exist (K3). | §3.2 built-in behaviours |
| **Dungeon steps** | `.dungeon` (1,351) is a **compile-time archetype gate**, not a runtime branch — a dungeon run is a different artifact, not a conditional inside the solo path. `expect_group: Dungeon` sets the combat policy. | Compiler; `service.combat` |
| **Daily quests in a solo leveling path** | `Op::Accept { repeatable: true }` / `Op::TurnIn { repeatable: true }` from `.daily`/`.dailyturnin`. `QuestTurnedIn` is unreliable for repeatables (a daily retaken after completion reads true on both `is_on_quest` and `is_quest_flagged_completed`), so the compiler emits `QuestInLog` as the gate for repeatables instead. | `Sentinel.objectives` |
| **Fallback grinding when quests run dry** | `.xp` (2,133) → `Predicate::XpAtLeast` on a non-blocking task with `Aggressive` stance and an empty whitelist (§7.3.3, task 4). | `service.combat` |
| **Faction-choice branches (`#aldor`/`#scryer`)** | `Archetype.allegiance`, resolved at compile time. The choice is irreversible in-game, so a runtime branch would be dead weight. The choice *point* itself is `Op::TurnIn { any_of: [10551, 10552] }` from `.turninmultiple`. | Compiler |
| **Content phasing (`#phase`)** | `Archetype.content_phase`. | Compiler |
| **Hardcore / softcore / SSF variants** | `Archetype.hardcore`, `Archetype.self_found`, plus `#hardcoreserver`/`#softcoreserver` for realm type. | Compiler |
| **Loading screens and zone transitions** | Two distinct effects, both handled. (1) **In-flight sticky tasks:** a zone transition is a band 90–99 interrupt, so every `Background` task loses its leases and receives `on_revoke`; it writes its `ResumeCursor` and parks. On the far side it re-acquires and resumes at `(op_index, waypoint, loop_iter)` — a 15-node circuit does not restart. (2) **Cold-tier predicate truth:** the quest log has **no readiness contract and no events** (§5.1.2), so every cold predicate must read `Unknown`, not `False`, across the transition. `UnknownPolicy::Defer` holds the cursor until the log repopulates; `Block` is used where an irreversible op would otherwise fire on stale data. Guard on `core.object_manager.get_local_player()` being non-nil, and treat a zero-length quest log as `Unknown`. | Scheduler §4.2 band 90–99; sensor tiering §5 |
| **Additional: contested turn-in objects** | Quest 983's ender is a **gameobject**, not an NPC (verified §7.3.2). `interact_target: None` with the object in the op is correct; a schema assuming every turn-in has an NPC target would emit a null target and stall. | Quest Activity |
| **Additional: exploration objectives with no count** | Quest 984 has no `Req*` columns; `QuestObjective.need` must permit `0`. A schema requiring a positive count would make the objective unsatisfiable. | `Sentinel.objectives` |
| **Additional: duplicated waypoints** | 1,723 steps emit the same coordinate twice (§2.6, measured). The compiler collapses the redundant **route** emissions; an importer that does not doubles every affected route. Distinct from the `waypoint_pool` interning of §7.1, which shrinks the pool but never a route (§9 item 26); §7.3.3 prints the interned pool and the still-un-deduplicated routes. | Compiler |
| **Additional: reputation-gated content** | Reputation is **unreadable** (§5.8). `Predicate::ReputationCmp` evaluates `Unknown` and `UnknownPolicy::Block` stops the profile with a named reason rather than looping. The compiler pre-resolves what it can from `quest_template.RequiredMinRepFaction`. | Sensor gap — see §9 |

----------

# 9. D9 — Open questions

**Corpus semantics I could not determine.**

1. **The fifth `.goto` positional.** Invariantly `0` across all 16,353 five-arg instances — no
   counter-example exists in the corpus, so its meaning cannot be inferred from variation. The
   compiler currently discards it. If it encodes something (facing? auto-complete suppression?), we
   are silently dropping it.
2. **`.goto` 4th positional value `-1`** (580 instances). Appears on multi-candidate marker waypoints
   (three adjacent Exodar auctioneer positions, `A-11-23.lua:959–961`) and on unstuck/instance-portal
   markers. Plausibly "no arrival radius / marker only", but no corpus line defines it.
3. **`.tbcWBF`** (11) — confined to one `RestedXP TBC Preparation` guide, associated with
   Wrath-of-the-Blue-Flight turn-in staging. Bare or with a literal `1`. Dropped; semantics unknown.
4. **`.blastedLands`** (7) — gates the optional Blasted Lands stat-buff farming apparatus. Dropped;
   semantics unknown.
5. **`#ignorecorpse`** (1) — single instance, on a step that deliberately dies inside an instance. I
   have mapped it to `Task.suppress: [corpse]` because that is the only reading that makes
   `.deathskip` work against the safety net, but with one witness this is inference, not proof.
6. **`#subweight -1`** (1) and **`#season 0`** (2) — single/low-witness directives; both mapped on
   weak evidence.
7. **Gate precedence ambiguity.** `step << Alliance/Horde Hunter` (10 uses). Under the derived
   precedence (`/` looser than space) this is `Alliance ∨ (Horde ∧ Hunter)`, which is semantically
   odd — an Alliance *anything* plus a Horde Hunter. The author may have meant
   `(Alliance ∨ Horde) ∧ Hunter`. RXPGuides' `applies()` flattens to a single disjunction, which
   supports my reading, but the authorial intent is genuinely unclear. **The compiler should emit a
   diagnostic on any gate mixing `/` and space rather than silently picking.**

**Baseline discrepancy.**

8. **The ~7% instance-count gap (§2.2) is unexplained.** Four hypotheses tested and eliminated. Most
   likely a different corpus snapshot. My counts are internally consistent and all arithmetic uses
   them, but if the baseline is authoritative, every absolute number in §4 shifts (proportions and
   verdicts do not).

**ADR-000 gaps and ambiguities hit while designing.**

9. **ADR-000 is not in the repository** (§1.1) and is marked `Status: Proposal`. Everything in §5 is
   designed against a document that has not been ratified or committed.
10. **Resume granularity is asserted but never specified** (§4.3 of ADR-000). Resolved here as
    `(task, op_index, waypoint, loop_iter)` — but that is my decision, not the kernel's.
11. **`Predicate` is under-specified for any real corpus** — no comparison operator at all. Fifteen
    additions proposed (§5.1.1). If the kernel rejects them, C1 becomes unsatisfiable and a second
    condition system becomes unavoidable, which the contract forbids.
12. **`satisfied()` returning `bool` is a latent fail-open bug** given the documented `1/-1/0`
    tri-state. This needs deciding before the ledger is implemented, not after.
13. **No vehicle channel.** ADR-000 §4.1 lists seven channels; a vehicle takes over movement and
    casting simultaneously in a way that does not decompose cleanly. Two instances in the corpus, so
    the priority is low, but the model does not cover it.
14. **Five behaviours are missing from §3.2** (trainer, flightpath, hearth, bank, stable) covering
    3,322 command instances, and no escort behaviour exists at all.
15. **The kernel cannot verify world-data content** (§5.4.1). There is no API exposing world-database
    identity, so `content_hash` can only be an inter-artifact coherence check plus provenance. The
    first-touch name probe is my proposal to get actual drift detection; it needs kernel support.

**Sensor gaps that constrain the schema.**

16. **Reputation is entirely absent from the Sylvanas API.** 298 `.reputation` uses cannot be
    evaluated. Highest-impact gap for TBC (Aldor/Scryer, Sporeggar, Cenarion Expedition).
17. **Player faction is not readable** outside arena/battleground context, and **there is no race
    name table**. Both forced compile-time archetype resolution (§5.2) — which I believe is right
    anyway, but the decision was made under constraint, not freely.
18. **The objective-progress numerator is integer-readable when RestedXP is loaded; the localized
    string is the fallback, not the only path.** *(An earlier revision of this item claimed objective
    progress "is only a localized string". That premise is now partially false: it correctly
    describes the base quest-log surface — `core.quests.get_quest_log_leader_board` (`quests.md`)
    returns only a localized description such as `"Wolves slain: 3/10"` — but it predates the addon
    integration surface.)* `core.addons.rested_xp.get_objectives(quest_id)` (`addons.md`) returns
    structured per-objective progress — `num_required`, `num_fulfilled`, `finished`, plus `text` and
    `type` — with the numerator as an integer, no parsing. Precondition: the RestedXP addon must be
    loaded (`core.addons.rested_xp.is_loaded()`), so **no artifact may hard-depend on it** — it is
    the preferred sensor, with the string parse as fallback, and a failed parse must still never
    fail open. Baking `need` from `quest_template` remains the denominator authority either way;
    when the integration is live, `num_required` doubles as a free runtime cross-check on the baked
    `need` (a mismatch is world-data drift, §5.4.1). The Zygor namespace is parallel in name only:
    `core.addons.zygor.get_objectives()` (`addons.md`) takes no quest id and returns an untyped
    `(number|string)[]` for the current guide step, so it is not a substitute sensor.
    Same-namespace corroboration for §2.6: `core.addons.rested_xp.get_current_waypoint()`
    (`addons.md`) returns `map_id` plus `x`/`y` **normalized to 0–1** — ui-map space, the
    zone-percentage form scaled by 100 — independently supporting §2.6's reading that authored
    zone-form numbers like `1439` are ui map ids paired with zone-normalized coordinates, lookup
    keys that must not survive compilation.
19. **No quest events exist**, so all quest state is polled. Re-verified against the event surface:
    the registered-events whitelist of `core.register_on_game_event_callback` (`events.md`,
    "Registered events") carries combat, player, group, chat/UI and auction-house events — no
    `QUEST_*` family at all — and the item-18 addon integrations are pull-only reads, so they change
    the preferred numerator sensor, not the polling model. Combined with the missing readiness
    contract, this makes resume-after-loading-screen a real correctness risk rather than a theoretical
    one.

**Prior-art confidence.**

20. **Honorbuddy element names are medium confidence.** The vendor site and forums are gone; structure
    is corroborated across archived community repositories, not primary documentation. The
    load-bearing claim — that conditions were embedded C# expression strings — is well corroborated;
    exact element spellings are not.

**Internal discrepancies found by the R1 model audit.**

Items 1–7 above are corpus semantics that could not be determined from the evidence. Items 21–24,
26, 27 and 28 below are different in kind: authoring errors in *this* document with a determinate
right answer, surfaced by building the §7.1 model, driving the real lowering against §7.3.3, and
finally pinning the two with a test. All are resolved in place, above, and are recorded here only so
the correction is traceable. Item 25 is a genuine open question that the same audit exposed but
cannot settle from this document.

The three waves are worth distinguishing, because each found what the previous one could not:
**items 21–24 and 26** came from building a model and reading it against the printed listing;
**item 27** came from compiling the corpus excerpt for real, which is the only thing that can catch a
coordinate transform or a `#displayname`/`#name` confusion; **item 28** came from asking why any of
this drifted, and the answer was that the specification existed twice.

21. **§7.3.3's task 0 route was one point too long — resolved.** `A-11-23.lua:215–231` is 3 `.goto`
    (radius 0) plus 14 `.waypoint` (radius 60) = **17** route points, not 18. That route-length
    finding stands: task 0 carries 17 points and 17 radii, and no 18th was reinstated. The pool
    arithmetic that originally accompanied it did not stand. This item first recorded a pool of
    **28** entries — one per source route line, "each referenced exactly once" — and both halves of
    that claim are now superseded by item 26: the pool is **interned** to the 22 *distinct*
    coordinates those 28 lines visit, and six of the 22 are referenced twice — **four by task 0,
    which genuinely re-crosses its own path, and two by task 2, which re-crosses nothing and is
    instead carrying the §2.6 double emission** (item 26). Task 0's four survive the route-level
    collapse untouched; task 2's two do not, and that collapse will take its route from 8 points to
    6. Nothing was invented in either correction (§7.3.2). §7.3.1's own elisions were already correct
    and are unchanged.
22. **§7.3.3 was not a loadable artifact as printed — resolved, but only at item 28.** §7.2's root
    `required` array names `waypoint_pool` and `defaults`; the listing printed neither, so the worked
    example could not satisfy its own schema. Both are now present, with **22 distinct real
    coordinates drawn from the 28 source route lines** of `A-11-23.lua:211–280` (item 26), every one
    of them taken from the corpus.

    **This item claimed "resolved" for two revisions while the listing still would not load**, in two
    independent ways it did not check: both digests were printed as prose (`"<blake3-of-tagset>"` is
    20 characters and `"<blake3-of-resolved-ids>"` 25, against §7.2's `^[0-9a-f]{64}$`), and seven
    `_comment` keys survived against a `deny_unknown_fields` root — guarded only by a sentence saying
    a real artifact carries none of them, which is not a mechanism. Adding the two missing *fields*
    was necessary and not sufficient. Loadability is now **checked rather than claimed**:
    `shared/tests/kernel_adr_listing.rs::the_adr_listing_loads_into_the_kernel_model` extracts the
    fence and deserializes it into `RuntimeProfile` (item 28).
    The `defaults` block takes its *shape* from §5.1.2 (`Defer` is the default for `complete_when`)
    and §5.6 (`stance: Defensive`), but two of its magnitudes — `leash_yards: 40` and
    `budget_ticks: 60` — are stated in **no** section of this ADR and originate in the worked example
    alone. They are therefore illustrative, not normative, and §7.3.2's "Nothing is invented" claim
    covers the coordinates, not these two numbers. Choosing them deliberately is open item 25.
23. **`"payload": null` on unit variants was the wrong spelling — resolved.** Serde's adjacent
    tagging **omits** the content key for a unit variant, and §7.2's `$defs` require only `["type"]`,
    so the emitted and canonical form is `{"type": "Exclusive"}`. The 17 printed `"payload": null`
    members are removed, so all 26 unit-variant envelopes in §7.3.3 — the 24 that were already there
    plus the two inside the newly printed `defaults` (item 22) — read `{"type": "X"}`. Deserialisation
    accepts both spellings, so artifacts written against the old printed form still load. The
    alternative — hand-written `Serialize` impls for eleven enums, to make the code match the prose —
    is strictly worse and is rejected.
24. **`tags_used` was wrong in both directions — resolved.** It listed `Wait`, `Delegate`, `Or` and
    `Not`, which no task in the example references, and omitted `QuestComplete`, which task 7's
    `applies_when` uses. `tags_used` is a **census**, not a subset of the registry; the definition in
    §5.10 has been tightened to say so and §7.3.3 now lists exactly the 10 tags the artifact
    references.
25. **Three magnitudes have no stated source — open.** `leash_yards: 40` and `budget_ticks: 60`
    appear only inside §7.3.3's listing (item 22), and so does a third: the ride-along task's
    `budget_ticks: 30`. §5.6 states the default *stance*, and §5.1.2 states that `Defer` is the
    default *policy*, but neither fixes a magnitude, and no other section does either. A leash
    distance and an escalation budget are behavioural constants that belong in §5.6 and §5.1.2 with a
    justification, not in a worked example. Until they are chosen deliberately, treat the printed
    values as illustrative.
    RestedXP has no notion of an escalation budget, so **no** corpus measurement can produce 30 or
    60 and calling either derived would be a fabrication. What §7.3.3 does witness is a *relation*:
    its one task whose completion authority is another task (`CompletionSource::LinkedTo`) carries
    the **smaller** budget, and every task that decides for itself carries the larger. The compiler
    encodes that relation with these two numbers as its endpoints
    (`compiler/src/kernel/task_graph.rs::unknown_policy`), and the two candidate causes are
    inseparable on the single witness — that task is also the only channel-less `Background` — so
    `LinkedTo` was chosen as the more primitive of the two, being what `lower_lifetime` reads to make
    the rider channel-less in the first place.
26. **§7.3.3's `waypoint_pool` was not interned — resolved.** The listing printed a **28**-slot
    pool, one slot per source route line, in which **six coordinates were stored twice**: old slots
    9≡2, 10≡3, 11≡1, 16≡0 (task 0's circuit) and 20≡18, 25≡19 (task 2's). Two sections of this
    document assert the opposite of that pool shape — §7.1 annotates the field "deduplicated; routes
    index into this", and §6.4 says the pool "deduplicates shared points across tasks". §7.3.3 is the
    artifact those two point at, so as printed it was the counter-example to its own schema rather
    than the demonstration of it.

    The pool is now **interned**: one entry per distinct `(map_id, x, y, z)`, first occurrence kept,
    giving **22** entries. The six duplicate slots are gone and the five `points` arrays are remapped
    onto the surviving indices. **A route referencing an entry more than once is correct and
    expected**, for either of two unrelated reasons:

    - **Task 0 names indices 0, 1, 2 and 3 twice each because it walks those coordinates twice.**
      It is a `Circuit` with `close: true`, and `A-11-23.lua:224`, `:225`, `:226` and `:231` really
      do re-visit `:217`, `:218`, `:216` and `:215`. Radius is *not* the justification — three of
      the four repeats change it — the geometry is.
    - **Task 2 names 14 and 15 twice because of the §2.6 double emission, not because it re-crosses
      anything.** `A-11-23.lua:247`–`:248` are 4-arg `.goto`s naming the anchors that `:249` and
      `:254` re-emit in 5-arg form; the radii `[0,0,50,50,50,50,50,50]` corroborate it. That is a
      route-level defect, still present in the printed route, and collapsing it will take task 2
      from 8 points to 6.

    Interning is a *pool* operation, never a route one: every route walks exactly the same sequence
    of world coordinates it walked before, task 0 still has 17 points and task 2 still has 8, no
    `points` array changed length, and no `radii` array changed at all. Every one of the 22 entries
    is reachable and every index is in bounds; "each referenced exactly once" (item 21) is retired,
    because for a closed circuit it was never achievable without duplicating points.

    **Interning is therefore not what §2.6 and §8 are asking for.** §2.6 says an importer treating
    each `.goto` as a distinct route node "doubles the path", §8 says an importer that does not
    deduplicate "doubles every affected route", and §5.7 says the compiler "deduplicates the 4,190
    measured duplicated coordinate triples on the way in" — all three name a route-*length*
    consequence, and interning changes no route's length. That route-level collapse is a **separate,
    later deliverable**; §7.3.3 demonstrates the pool interning of §7.1 and §6.4 alone.

27. **§7.3.3's worked example was wrong in four more ways, all corpus-determinate — resolved.** A
    second audit wave, run while the real lowering
    (`parse_guide` → `ProjectBuilder` → `Compiler::compile_kernel`) was built against the section:

    - **The pool stored authored percentages wearing ui map id `1439`** on all 22 entries. That is
      §2.6's own **named bug signature** (search: `a percentage that survived compilation wearing a
      ui map id`) — the section demonstrated the failure another section of the same document names.
      Every entry now carries `map_id: 1` (Kalimdor) and world `x`/`y` from
      `ZoneMap::to_world` (`SentinelQuesting/shared/src/zone.rs`).
    - **Eight tasks, not seven.** The `--XXREQ` placeholder at `A-11-23.lua:265–268` was printed as a
      task of its own. The compiler folds it into its successor, so the excerpt is **seven** tasks
      and every index from 4 upward shifted down by one. Two consequences the old numbering hid: the
      excerpt's single `#requires BuzzBox1` was spent **twice** (once on the placeholder, once on the
      turn-in that actually names it), and `deps: [2, 0]` — this document's only printed
      multi-predecessor task — does not exist. See item 28 for the citations that were withdrawn.
    - **Route `mode` was `Ground`.** §7.1's own `TravelMode` annotation sends `.goto` / `.waypoint`
      to `Any` and reserves `Ground` for `.groundgoto` (114 instances, none in this excerpt).
    - **`meta.name` was `10-14 Darkshore`.** That string is a `#displayname` gated
      `<< Dwarf Hunter`; `#name` is `12-14 Darkshore`, and `GuideMeta.name` reads `#name`. The
      archetype §7.3.3 resolves for is a *Night Elf* Hunter. `meta.next` was `[]` against a
      `#next 14-20 Bloodmyst` in the source.

    `tags_used` also lost `And` with the fold, leaving **nine** tags, and is emitted sorted (§5.4).

28. **§7.3.3 was hand-maintained beside a second copy of itself, and drifted 136 leaf paths —
    resolved structurally, not by patching.** `shared/tests/fixtures/adr07_worked_example.json` holds
    the same artifact as a loadable file, and it is the one that is right: it is derived from the
    corpus, its ids are verified against `tbcmangos.sqlite` (§7.3.2), and
    `compiler/tests/kernel_worked_example.rs` drives the real lowering into it field by field. The
    two copies were maintained by hand and diverged on **136 leaf paths** — items 26 and 27's
    findings plus every index they shifted.

    Patching 136 values by hand is how the 137th appears, so the fix is not a patch. **§7.3.3's
    listing is now the fixture, and three tests refuse to let them part again**
    (`shared/tests/kernel_adr_listing.rs`): the fence must parse, must load into
    `sentinel_models::kernel::RuntimeProfile`, and must compare equal to the fixture leaf by leaf.
    Editing either side alone fails. That guard, not the corrected values, is the deliverable — the
    values were only ever a symptom of there being two of them.

    Four further claims in this document were false and are corrected in place:

    - **§5.4, §7.1 and §10 item 7 each said the 21 leaf vocabulary enums "carry no payload".** False
      since `ProfileMode::Dungeon { instance: DungeonId }` landed: 21 of **22** carry none, and
      `archetype.mode` is a bare string for two variants and an externally tagged object for the
      third. §10 item 7's self-verification restated the claim and so passed on a false premise.
    - **`DungeonId` was referenced but never declared.** `ProfileMode` above named the type, and its
      19 variants existed only inside a `//` comment — no declaration in §7.1, no `$defs` entry, and
      §7.2 had **no `archetype` schema at all**, so `ProfileMode::Dungeon`'s wire shape was written
      down nowhere. All three now exist, and
      `shared/tests/kernel_wire_shape.rs::profile_mode_dungeon_is_externally_tagged_and_carries_a_dungeon_id`
      pins the shape the schema claims.
    - **§5.6's "16,438 of 23,894 tasks carry no combat token" subtracted an instance count from a
      step count.** `23,894 − 7,456` treats `.mob`'s 7,456 *instances* as 7,456 steps; it occurs on
      only 3,526 distinct steps. Measured, 18,404 steps (77.0%) carry none of
      `.mob` / `.unitscan` / `.solo` / `.group` / `.dungeon`, 19,718 carry neither `.mob` nor
      `.unitscan`, and 20,368 carry no `.mob`. The bad figure had been copied into
      `shared/src/kernel/profile.rs` and `shared/src/kernel/task.rs` doc comments and is corrected
      there too. The argument it supports is unaffected and gets stronger.
    - **Delivery state was stated nowhere**, so every "the compiler emits", "the kernel refuses" and
      "the runtime probes" in §5 read as description. §1.2 now measures what is designed against what
      is delivered.

----------

# 10. Self-verification

Run before finishing. Failures were fixed, not reported.

| # | Check | Result |
|---|---|---|
| 1 | Disposition table contains all 74 commands and all 48/49 directives | **PASS — 74/74 commands, 49/49 directives.** Verified programmatically: every corpus token has exactly one verdict, no token missing, no verdict for a non-existent token. The 49th is `#completewithTBTurnins`, reconciled against the stated 48 in §2.2. |
| 2 | Every mechanism promised in rationale exists in the formal schema *and* the Rust structs | **PASS on presence, with one witness withdrawn.** Spot-checked the ones most likely to be prose-only: multi-dependency → `Task.deps: Vec<TaskId>` (§7.1) — *declared* there, but **no longer exercised in §7.3.3**: the `--XXREQ` fold leaves every task in that excerpt with at most one dep, so the earlier "exercised in §7.3 task 4" is withdrawn (§9 item 28). The field's justification is §2.5's authoring measurement and the fold itself; `compiler/tests/kernel_task_graph.rs` is where plurality is exercised executably. tri-state → `UnknownPolicy` enum + `Task.unknown_policy`; resume granularity → `ResumeCursor` with all four fields; content integrity → `ContentIntegrity` struct + `expect_name` on `NpcRef`; channels → `Lifetime::Background.channels`. All appear in both §7.1 and §7.2. |
| 3 | Every game ID in the worked example traceable to a real corpus line, with citation | **PASS.** 13 IDs, each with a corpus `file:line` **and** an independent `tbcmangos.sqlite` name lookup (§7.3.2). Nothing invented. Three structural cross-checks also passed (objective count 6 matches the author's comment; quest 983's ender is a gameobject, explaining the absent `.target`; quest 984 has no count columns). |
| 4 | Worked example violates no exclusion rule stated in this document | **PASS.** The example is archetype-resolved for a Night Elf Hunter and contains no class-gated content — the source region `A-11-23.lua:211–280` carries no `<<` gate on any step or command, so nothing was excluded and nothing class-specific was smuggled in. No dropped token appears in the output. |
| 5 | `#sticky`/`#completewith` modeled via channels and leases, not desugared, not a background flag, not dropped | **PASS.** `Lifetime::Background { channels, band, terminate_on }` and `CompletionSource::LinkedTo` are **separate fields** on `Task`, justified by the disjointness measurement (§2.4). Tasks 0, 2 and 6 in §7.3 exercise all three combinations. Full lifecycle in §5.3. |
| 6 | Every runtime condition lowers to a `Predicate`; no second condition system | **PASS.** All three predicate slots on `Task` hold the same type. `Cmp` is a shared operator enum, not a parallel language. Static gates do not survive compilation (§5.2), so they are not a second system either. |
| 7 | Every **dispatched** sum type adjacently tagged; `schema_hash` / `tags_used` / content-integrity present | **PASS — restated twice, at §9 item 23 and again at §9 item 28.** The original claim, "all enums adjacently tagged", was false: §7.1 also declares **22** leaf vocabulary enums that are not, and that serialise as bare strings exactly as §7.3.3 prints them (`"class": "Hunter"`, `"mode": "Any"`, `"kind": "SubArea"`, `"channels": ["MOVEMENT"]`). Item 23's restatement then introduced a second false premise of its own — that all of those "carry no payload" — which this row repeated: `ProfileMode::Dungeon { instance: DungeonId }` carries one, so **21 of the 22** do and `archetype.mode` is externally tagged for the third. The rule is by **role**, not arity, in both directions: `Cmp` is tagged with no payload, `ProfileMode` is untagged with one. The eleven sum types the kernel dispatches on — `Lifetime`, `CompletionSource`, `UnknownPolicy`, `Op`, `RouteKind`, `GossipPolicy`, `DelegatePayload`, `CombatStance`, `GroupExpectation`, `Cmp`, `Predicate` — each carry `#[serde(tag = "type", content = "payload")]`, including `Cmp`, `CombatStance` and `GroupExpectation` where every variant happens to be a unit variant; the JSON Schema mirrors them with `{type, payload}` and an explicit `$comment`. Root has `schema_hash`, `tags_used`, and `integrity: ContentIntegrity`. |
| 8 | Unknown/unavailable predicate state handled explicitly, not collapsed to false | **PASS.** `Truth { True, False, Unknown }` (K2) plus a four-way per-task `UnknownPolicy`. `TreatFalse` is never the default for `complete_when`; `TreatTrue` requires explicit opt-in and emits a diagnostic. Grounded in three documented API facts (§5.1.2). |
| 9 | D5 lists every required kernel change, or states none required | **PASS.** Eight changes, K1–K8, in §5.9, each with an ADR-000 section reference and a forcing reason. Explicitly *not* "none". |
| 10 | No files created or modified other than this ADR | **PASS.** One file written: `sentinel/docs/adr/07_RUNTIME_PROFILE_SCHEMA.md`. All corpus analysis ran read-only or wrote to the session scratchpad outside the repository. No source file, test, or config touched. |
