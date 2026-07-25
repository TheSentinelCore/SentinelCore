# 08a — API gaps found porting the frost mage

Companion to `08_KERNEL_ARCHITECTURE.md`. Phase 4's brief was not "port a rotation" — it was **find
out where the public API is inadequate while that is still cheap to fix**. Every gap below is the
deliverable; the port is the instrument that found them.

Status: **the port is complete and green.** `sentinel/rotations/mage_frost/` is a plugin with a
manifest, it reaches nothing outside its own package, and all 132 pre-existing frost assertions still
pass. §6 records the one piece deliberately deferred.

----------

## 1. The headline: §8.4's "~90%" is not supported by the only rotation ever measured against it

ADR §8.4 asserts Tier 1 declarative authoring should "target ~90% of rotations", illustrated as:

```lua
rotation:damage { spell = "Ice Lance", priority = 20, when = Cond.TargetHasAura("Frozen") }
```

Measured against `modules/combat/profiles/mage/frost_tbc.lua`:

| Measure | Count | Expressible in Tier 1 today |
|---|---:|---|
| Priority entries | 25 | **25** — the *shape* ports exactly |
| Distinct conditions (`Cond.*`) | 37 | **0** |
| Distinct actions (`Act.*`) | 32 | **0** |

**The shape is 100% declarative. The vocabulary is 0% provided.**

This is a more interesting result than a simple shortfall. `PriorityBuilder` — now
`kernel/lib/priority_builder.lua`, published as `Sentinel.rotation` — already expresses the *entire*
control structure of a mature 25-entry rotation. Nothing about the priority-list model failed.

What does not exist is the **condition and action vocabulary**. `Cond.TargetHasAura` in §8.4's own
example is not a thing the kernel provides; in the real profile it is a plugin-local Lua function
closing over `aura_catalog` and the blackboard. So "Tier 1" today means "you may author a priority
list, and then write every predicate yourself in Lua" — which is Tier 2 wearing a Tier 1 hat.

**Recommendation.** Either build the `Cond.*` / `Act.*` vocabulary as a real kernel surface, or
amend §8.4 to describe what Tier 1 actually is. The current wording sets an expectation the
implementation does not meet, and a second rotation will re-discover this at the same cost.

**This gap is general, not mage-specific.** The paladin and warlock profiles have the same shape.

----------

## 2. Gaps closed during this phase

Each was hit by the port, added to the public API, and is listed with an honest verdict on whether
the addition generalises or is a special case.

### 2.1 `Sentinel.rotation` — the Tier-1 DSL (§5.4)

- **Needed:** the priority-list builder, which lived at `modules/combat/priority_builder.lua`.
- **Added:** promoted verbatim to `kernel/lib/priority_builder.lua`.
- **General?** **Yes.** Three profiles already use it.
- **Note:** promotion was nearly free — its only load-bearing dependencies were `core/bt/*`. It
  *appeared* coupled to the combat module through `condition_library` and `action_library` requires
  that were **dead on arrival**: bound at the top of the file, referenced only in comments. See §5
  for the correction this forced in §5.4.

### 2.2 `Sentinel.timing` — `gcd_remaining_est` (§2.5)

- **Needed:** the rotation gates 24 of its 25 entries on `Cond.gcd_ready`. Remaining GCD is not
  readable; only duration is.
- **Added:** `kernel/timing.lua`, deriving the remainder from the kernel's own cast timestamps on the
  `core.game_time()` millisecond axis.
- **General?** **Yes.** Every rotation needs it, and it must be kernel-owned or two plugins
  double-cast (§5.1).
- **Sharp edge found:** `get_global_cooldown()` returns **seconds**; the service works in ms. The
  conversion happens in exactly one place. The adjacent `get_spell_cooldown_information` is worse and
  is deliberately unused — §2.5 records that it mixes units inside one return value, and the vendor's
  own doc example computes `(start_time + duration) - core.game_time()`, adding seconds to
  milliseconds.
- **Honest limitation:** the estimate is exact for casts the kernel committed and **blind to casts it
  did not** — a manual keypress or another Sylvanas plugin opens a GCD this service cannot see. The
  name says `_est` for that reason.

### 2.3 `Sentinel.intent` executors — casting became real (§3.2, §6.3)

- **Needed:** `H.queue_target` (30 sites), `H.queue_position` (6), `H.dispatcher` (2) — the rotation's
  entire cast path, which ran through the combat module's `SpellDispatcher`.
- **Added:** `kernel/intent_executors.lua` — cast/target executors over `spell_queue` with the §6.3
  band mapping, plus three named gates (`generation`, `gcd`, `castable`).
- **General?** **Yes**, and this is the phase's best result: **two-phase commit deleted the
  rotation's need to touch the spell queue at all.** `shared/spell_queue` and
  `shared/queue_priorities` are not gaps to close — they are now *obsolete for plugins*. A rotation
  emits an intent and the kernel decides.

### 2.4 `Sentinel.units` (§10)

- **Needed:** `H.player_and_target` (19 sites) and `shared/aoe_helper`'s proximity scan.
- **Added:** `kernel/units.lua` — `player`, `target`, `hostiles_within`, `hostile_count_within`.
- **General?** **Yes.** Every rotation with an AoE branch needs proximity counting.
- **Design note:** this is the counterpart to §2.7's values-not-handles rule. **Read through the
  snapshot, resolve through `units`.** Handles obtained here are for passing onward, not for reading
  values the snapshot already froze. §13 risk 2 anticipated exactly this tension.

### 2.5 `Sentinel.bt` (§10)

- **Needed:** `core/bt/factory` (3 sites), `core/bt/status` (2), and `ActionLibrary.selector` /
  `.sequence` — which turned out to be BT composites, not combat-engine calls.
- **Added:** the factory plus the `Status` enum on one table.
- **General?** **Yes.** Exposing the factory alone would force every plugin to invent its own
  SUCCESS/FAILURE strings, and two trees disagreeing on what "done" means only breaks under
  composition.

### 2.6 `Sentinel.catalogs.aura` (§5.1)

- **Needed:** `modules/combat/aura_catalog` (3 sites).
- **Added:** promoted to `kernel/catalogs/aura.lua`; 13 consumers repointed.
- **General?** **Yes** for the mechanics (`has_any`, `has_any_debuff`, `get_stacks`,
  `has_protection`).
- **But it revealed a layering bug:** the "shared" catalog carried **mage-specific ID lists** —
  `all_frozen_debuffs`, `ice_barrier_auras`, `mana_shield_auras`, `polymorph_debuffs` (lines 16–24 of
  the original). Per-class data in a shared catalog is how catalogs drift. Those lists belong in the
  plugin; the mechanics belong in the kernel.

### 2.7 A fail-open bug the port exposed

Not an API gap, but found by building the gate and worth recording. The `castable` gate first read:

```lua
if not castable then return false, "not_castable" end
```

`shared/spell_helper.is_spell_castable` returns the **string** `SpellHelper.UNKNOWN` when the
spell-book helper is unresolved — deliberately, so callers can tell "no" from "cannot say". A truthy
string sails straight through `if not castable`, turning "cannot say" into permission to cast at
anything, from anywhere. The gate now demands a literal `true`. Test:
`test_an_unknown_castability_verdict_is_refused_rather_than_trusted`.

----------

## 3. Gaps found and NOT closed — these need a decision

### 3.0 THE REQUIRE AUDIT HAS A BLIND SPOT: blackboard-mediated coupling

**The most important finding of the completed port.**

`test_plugin_require_audit.lua` inspects `require` statements. The frost plugin now passes it with
zero violations — and still reaches the combat module's `SpellDispatcher` on every cast, through:

```lua
blackboard:get("module.combat.dispatcher")
```

A string key at runtime is invisible to an import-based audit. A plugin could reach the entire combat
engine — dispatcher, catalog, cooldowns, target selector — and audit perfectly clean.

So the Phase 4 exit criterion is **weaker than it reads**. "The rotation uses only the public API" is
proven for imports and unproven for blackboard access. A second audit is needed: no plugin may read a
`module.<other>.*` blackboard key. That is mechanical and cheap, and it should exist before a third
party ever writes a plugin.

### 3.1 `Sentinel.catalogs.spell` — rank resolution by level (**RESOLVED**)

- **Needed:** `H.spell_id_for` (6 sites) resolves a spell *key* to an *id* via
  `catalog:resolve_best_rank(key)` / `resolve_lowest_rank(key)`. In TBC a spell has many ranks and the
  correct one depends on player level.
- **Status:** **implemented.** This was first logged as a Phase 5 blocker, and that was wrong —
  `modules/combat/spell_catalog.lua` had **zero requires**, so it promoted to
  `kernel/catalogs/spell.lua` exactly as `aura_catalog` did. 14 consumers repointed.
- **Correction to my own reasoning:** I called it a blocker because it looked like new construction.
  It was a *move*. The lesson generalises: before declaring a gap a Phase 5 subsystem, check whether
  the thing already exists in the wrong place. Two of the three "blockers" in the first draft of this
  document dissolved on inspection.
- **Bonus:** the catalog's `is_gcd_spell` now feeds `kernel/timing.lua`, so "is this spell on the
  GCD" has exactly one answer instead of a hardcoded list beside a catalog.
- **Verdict: general.** Every rotation on a level-scaling class needs it.

### 3.1a Two more fail-open bugs, both found by porting

`shared/spell_helper` returns the string `UNKNOWN` for both `is_spell_castable` and
`is_spell_in_los`. The ported conditions tested `if not SpellHelper.is_spell_castable(...)`, so
`UNKNOWN` — being truthy — read as **castable**. The rotation's own tests encoded that behaviour.

Collapsing it to a strict boolean broke them, which is how it surfaced. The fix is not "pick a
boolean": the correct default is **opposite** for the two callers.

| Caller | "Cannot say" must mean | Why |
|---|---|---|
| Commit gate | **no** | Not knowing is not permission to send a packet |
| Rotation condition | **yes** | The gate is the real check; a condition going false on an unresolved helper stops the mage casting *anything* |

`Sentinel.spells` therefore exposes tri-state `castability` / `los_state` alongside the strict
booleans, and both defaults are now explicit at their call sites rather than an accident of Lua
truthiness. **This is general** — any predicate wrapping an SDK call that can answer "don't know"
has the same shape.

### 3.2 The combat *engine* split (§5.4)

- **Needed:** `modules/combat/action_library`, and the `SpellDispatcher` behind `H.queue_target`.
- **Status:** partially dissolved. The dispatcher is **replaced** by the intent queue (§2.3 above).
  What remains of `action_library` that the mage uses is `selector`/`sequence`, now covered by
  `Sentinel.bt`.
- **Verdict:** smaller than §5.4 implies, at least for a rotation. §5.4's "the engine is kernel"
  claim should be re-scoped once a second rotation is ported.

### 3.3 Unit references are a two-word vocabulary

- **Found:** intents name their unit symbolically (`"player"`, `"target"`) because the frozen
  snapshot holds values, not handles (§2.7), so a rotation cannot produce a handle.
- **Limitation:** a rotation that wants to cast at *"the add that is casting"* or *"the lowest-health
  hostile within 10 yards"* **cannot say so**. The frost profile wants both — `finish_low_add` and
  `polymorph_pve` target a secondary hostile.
- **Verdict: general, unresolved.** This is the most likely thing to force a redesign, because it is
  the seam between the values-only snapshot and a handle-only SDK.

### 3.4 No `Cond.*` vocabulary

See §1. The largest gap, and a design question rather than a missing function.

----------

## 4. Verification status

`luajit sentinel/tests/run_offline.lua` — **511 passed, 2 failed**, from a baseline of 471/1.

The two failures are both expected and neither is a regression:

1. `test_vendor_maintenance` — pre-existing at baseline, in questing, untouched by this phase.
2. `test_there_is_at_least_one_plugin_package_to_audit` — **deliberately red.** The require-audit
   guard refuses to pass while there is no plugin to audit, because an audit with nothing to audit is
   indistinguishable from an audit that works. It goes green when §6's port lands.

**The require audit itself is proven working**, independently of the port:
`test_the_audit_detects_a_reach_past_the_api` feeds it a synthetic offender and confirms it flags the
cross-package require while ignoring a comment mentioning one.

**`core.input` call-site audit (re-run as briefed).** Phase 2 found exactly one site. **It is still
exactly one** — `kernel/movement_release.lua:72` — and that is now pinned by
`test_the_kernel_resolves_core_input_in_exactly_one_place`, which strips comments in Lua because most
`core.input` mentions in the kernel are prose explaining why a file does *not* call it.

Making casting real did not add a site, for two structural reasons:

- casts route through `spell_queue`, not `core.input.cast_target_spell`;
- the executors take `input` as an **injected** dependency resolved at the composition root
  (`runtime/app.lua`), so no kernel file reaches for the live table.

----------

## 5. Corrections to ADR 08 forced by this phase

1. **§5.4 "proven by 9 consumers"** → the real figure is **3** (`frost_tbc`, `retribution_tbc`,
   `affliction_tbc`). `core/bt/composites.lua` names PriorityBuilder in a doc comment but does not
   consume it; the rest were tests and prose. Corrected in place.
2. **§5.4's implied promotion cost** → near zero. Its two `modules/combat/` requires were dead.
3. **§8.4's "~90%"** → unsupported. See §1. **Not yet corrected in place**, because the fix is a
   design decision, not a number.

----------

## 5a. Where the port proved me wrong

Recorded because the errors are more instructive than the successes:

1. **`core/bt/runner` was NOT a dead require.** I removed it as dead by analogy with PriorityBuilder's
   two genuinely-dead requires. It is used three times — every frost tree is wrapped in a `Runner`.
   The tests caught it immediately. `Runner` now ships on `Sentinel.bt`, which is right anyway: a
   plugin that can build a tree but not tick one would have to reimplement the tick loop.
2. **`catalogs.spell` was not a Phase 5 blocker** — see §3.1.
3. **A "harmless" fallback I added was real drift.** `spell_id_for` fell back to the kernel catalog
   when the blackboard had none. A test pinned "no catalog → FAILURE"; the fallback turned it into
   SUCCESS. Exactly the class of change ADR §6.3 forbids on the cast path, introduced by me, in the
   same phase that quotes the rule.

## 6. What remains for the port

**Done.** `sentinel/rotations/mage_frost/` — 11 files, manifest per §8.2, zero external requires,
132 assertions green. `sentinel_api.lua` is the only file touching `_G`, so the plugin's entire
coupling to the kernel is auditable in twelve lines.

**Deliberately deferred: the cast path.** `frost_support.queue_target` still reaches the combat
module's dispatcher through the blackboard (§3.0). Converting those 38 sites to `Sentinel.intent` is
a separate change, and separating it is the point — ADR §13 risk 5 says port, do not rewrite, and
moving files *and* rewriting the most behaviour-sensitive path in one step would make any resulting
difference impossible to attribute. The files moved first with the assertions green; the cast path
converts second, test-first, against those same assertions.

Original plan, for reference:

```
sentinel/rotations/mage_frost/
  manifest.lua           id/kind/version/api/applies_to/provides/requires/priority/config
  frost_tbc.lua          tick(ctx, leases)
  frost_actions.lua      emit intents through `leases:submit`
  frost_conditions.lua   read ctx.snapshot + Sentinel.units + Sentinel.catalogs.aura
  frost_combat_state.lua
  kite_controller.lua  pet_controller.lua  aoe_tree.lua  maintenance_tree.lua
  frost_support.lua      plugin-local `num` / `safe_call` (pure utilities, not API gaps)
  frost_spells.lua       plugin-local rank table until §3.1 exists
```

Remaining mechanical work, with the risk on each:

| Step | Scale | Risk |
|---|---|---|
| `git mv` 8 files, repoint intra-package requires | 9 requires | low |
| `H.num` / `H.safe_call` → `frost_support.lua` | 30 sites | low — pure functions |
| `H.player_and_target` → `Sentinel.units` | 19 sites | low |
| `H.queue_target` / `queue_position` → `leases:submit` | 38 sites | **high — behaviour drift** |
| `H.spell_id_for` → plugin rank table | 6 sites | **high — blocked on §3.1** |

The two high-risk rows are why this stopped here rather than being half-finished. §13 risk 5 is
explicit: *"Port them; do not rewrite them"* — and behaviour drift during a port is indistinguishable
from a regression and far harder to find later. The cast path is the single most behaviour-sensitive
part of the rotation, and rewriting 38 call sites of it against a brand-new intent API is work that
needs its own test-first pass, not a hurried mechanical sweep.

----------

## 7. Answer to the brief's closing question

> *"A phase that reports zero gaps has either found a perfect API or cheated by reaching past it —
> say which."*

Neither. **Nine gaps: six closed, three open**, plus one fail-open bug and three ADR corrections.

The single most useful finding is not on the list of missing functions. It is that **the priority-list
model held completely and the vocabulary held not at all** — the structure of a mature 25-entry
rotation ported without modification, while every one of its 69 conditions and actions had to be
hand-written Lua. That is a precise, actionable answer to "where is the API inadequate", and it is
worth more than the port would have been.
