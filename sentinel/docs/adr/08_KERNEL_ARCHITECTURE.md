
# 08_KERNEL_ARCHITECTURE.md

## Sentinel

### Kernel and Plugin Architecture — API-first bot on Project Sylvanas

**Version:** 1.1
**Status:** Accepted, and partially built. §12 phases 1–4 are in the tree; 5–7 have not started.
**Supersedes:** the uncommitted `ADR-000 — Sentinel Kernel: API-First Plugin Architecture` proposal
**Supersedes:** the current `module_registry` peer-module design (combat p10 / questing p50)
**Consumed by:** `07_RUNTIME_PROFILE_SCHEMA.md` (the Quest Activity's artifact)
**Companion:** `08a_API_GAPS.md` (what porting the frost mage found)

**Read these three sections before trusting anything else here.** They are the parts written from
measurement of the built tree rather than from design:

| Section | What it settles |
|---|---|
| **§14** | The rotation-plugin gap. Phase 4 built three plugins and **wired none of them.** |
| **§15** | Nobody loads or executes an ADR 07 `kernel::RuntimeProfile`. Largest gap in the stack. |
| **§16** | Every place this document and the built kernel disagree, and which one is ahead. |

Everything above §14 is the design as ratified, with corrections folded in where measurement forced
them. §13 and §13.1 now carry a **verdict per item** — open, closed, or superseded — rather than
standing as an undated risk list.

**Numbering.** ADR-000 was never committed to this repository — I searched exhaustively before
writing `07` and found no file, no `rg` hit for `ControlBroker` / `objectives:satisfied` /
`schema_hash`, and nothing in CodeGraph or graphify. `08` is the next free number in the repo's
`00`–`07` sequence. **This document is the ratified form of that proposal.** ADR-000's structure and
most of its decisions survive intact; §2 lists everything the research changed.

**Reference mapping for ADR 07.** `07_RUNTIME_PROFILE_SCHEMA.md` cites ADR-000 section numbers
throughout. They map here as: §1.1 → §3.1 · §3.2 → §5.2 · §4.1 → §6.1 · §4.2 → §6.2 · §4.3 → §6.4 ·
§5 → §7 · §7.1 → §9.1 · §7.2 → §9.2 · §7.3 → §9.3 · §8 → §10.

----------

# 1. D1 — Decision summary

Build a **kernel + plugin** architecture where the kernel owns state, arbitration and dispatch, and
everything that is *policy* is a plugin using the same public API as third-party code.

The three inversions from the ADR-000 proposal are correct and survive research intact:

1. **Combat is a service invoked with a policy**, not a peer module. Different goals want different
   combat behaviour, and a peer-module design cannot express that.
2. **Plugins emit intents; the kernel commits them.** No plugin calls `core.*` directly.
3. **The kernel ships zero behaviour that isn't expressible through the public API.** Built-in
   behaviours use the same manifest as external ones.

What research changed is the *shape*, not the *direction*. Six corrections matter (§2), and one is a
reversal: **rotations and activities ship in-repo behind the same API discipline, not as separate
Sylvanas plugins** — because the injector provides no load order, no dependency mechanism, a shared
`package.loaded` namespace, a per-plugin callback cap, and **only a global F6 reload**, which means
splitting buys you none of the hot-swap it was supposed to buy.

The good news from the inventory: this is mostly **promotion and boundary-drawing, not a rewrite**.
`core/` and `runtime/` are ~1,000 lines, cohesive, and covered by 1,153 lines of tests. The
ModuleRegistry already implements a 3-strike `DEGRADED` quarantine. The BT library is standalone. The
genuinely new code is the ControlBroker, the IntentQueue, the frozen snapshot, and the ObjectiveLedger.

**Delivered, measured on `62c98de`.** `sentinel/kernel/` holds **30 Lua files**. Three of those four
"genuinely new" pieces are built and driven from the tick — `kernel/control_broker.lua`,
`kernel/intent_queue.lua`, `kernel/snapshot.lua` + `kernel/snapshot_source.lua`. The fourth, the
ObjectiveLedger, does not exist: there is no `kernel/objectives.lua`, no `kernel/facts.lua`, and
`kernel/api.lua`'s own header says so ("`objectives`, `facts` … are Phase 5+ services. They are NOT
stubbed here"). That honesty is the right call and §15 is where its consequence lands.

----------

# 2. D2 — What research changed

Everything below is evidence, not preference. Each item cites what forced it.

## 2.1 The `CAMERA` channel does not exist — delete it

`rg -ni camera` over the entire `docs/SylvannasAPI/dev/` tree returns only an unrelated WMO collision
flag. **There is no camera control API.** ADR-000 §4.1 lists seven channels; one of them is
unimplementable.

## 2.2 `MODAL_UI` must be added as a channel

Vendor, bank, mail, trainer, gossip and profession frames are modal and block movement. Worse:
`core.trade_skill.get_trade_skill_line()` maps to `GetTradeSkillLine()`, so **reading a profession's
skill rank requires opening the profession window** — a *sensor read* that needs a control claim.

There is also **no vendor/merchant frame-open predicate**; only `core.quests.is_gossip_frame_shown()`,
`core.game_ui.is_map_open()` and `core.is_main_menu_open()` exist. So modal state is partly
unobservable, which makes owning it in the broker more important, not less.

**Net: seven channels, but not ADR-000's seven.**

```
MOVEMENT · FACING · CASTING · TARGETING · INTERACTION · ITEMS · MODAL_UI
```

### 2.2.1 `PET` is the eighth, added in Phase 4b

A pet command contends with other pet commands and with nothing else. Ordering it against
`CASTING` would be wrong — commanding the water elemental to freeze does not compete with the
mage's own global cooldown — and leaving it *inside* `CASTING` is worse: a rotation holding
`CASTING` would then implicitly own the pet, which is precisely the ambient authority the
channel split exists to remove.

It is a channel rather than a column on some permission table for the same reason every other
channel is: it is a genuinely separate arbitration surface.

**Net: eight channels.**

```
MOVEMENT · FACING · CASTING · TARGETING · INTERACTION · ITEMS · MODAL_UI · PET
```

## 2.3 Separate Sylvanas plugins buy less than the proposal assumed

| Verified constraint | Consequence |
|---|---|
| No documented plugin load order; **plugin A cannot require plugin B** | The `_G` handshake is the only mechanism |
| `_G` **is** shared; plugins are not sandboxed into separate Lua states | The `_G.Sentinel` surface works — proven in-repo (§2.4) |
| **`package.path` and `package.loaded` are also shared** — module names collide globally | Two plugins that both `require("core/blackboard")` collide. One plugin clearing `package.loaded` affects every plugin sharing that name. |
| Each plugin has an **undocumented maximum callback count**; exceeding it raises a Lua error | Splitting multiplies callback pressure |
| **Reload is F6 and is GLOBAL** — all Lua scripts reload together, no per-plugin hot-swap | **The main advertised benefit of splitting does not exist** |
| Menu-element IDs share **one namespace across all plugins** | UIHost must own ID allocation regardless |

ADR-000 §11 already hedged this ("if nobody but you writes rotations, put them in an in-repo
`rotations/` directory… you get 90% of the modularity for 20% of the cost"). The evidence promotes
that hedge to the default. See §8.1.

And it is cheap to do: `sentinel/main.lua:1` calls `require("runtime/app")` **before**
`package.path` is extended at `main.lua:4-11`, which proves Sylvanas resolves requires relative to the
plugin root natively. The `package.path` block exists only for the offline harness. An in-repo
`rotations/` directory needs no new loader machinery.

## 2.4 `_G` sharing is confirmed, and the repo already has the right pattern

Two-sided proof: `SentinelNavClient/main.lua:85` publishes `_G.SentinelNavClient`, and
`sentinel/integrations/nav_client/adapter.lua:51` consumes it.

Better, `SentinelNavClient/main.lua:106` wraps the export in a metatable whose `__index` makes
`.client` a **live getter**, so it returns the current client whether accessed before or after
`on_load`:

```lua
setmetatable(_G.SentinelNavClient, {
    __index = function(t, k)
        if k == "client" then return SentinelNavClient:get_client() end
    end
})
```

**Adopt this for `_G.Sentinel`.** It solves the load-order problem more cleanly than a deferred queue,
and it is already proven in this codebase. Keep the deferred `__SentinelPending` queue as well — the
getter fixes *reads*, the queue fixes *registration*.

## 2.5 `gcd_remaining()` is not implementable as specified

ADR-000 §8 lists `Sentinel.timing:gcd_remaining()`. **Remaining GCD is not readable.** Only
`core.spell_book.get_global_cooldown()` exists, and it returns the GCD *duration*, not the remainder.
The kernel must derive the remainder itself by timestamping its own casts.

Two adjacent traps that the Timing service must absorb:

- **Two incompatible clocks.** `core.time()` is **seconds since injection**; `core.game_time()` is
  **milliseconds since game start**. Every server-derived timestamp — buff `expire_time`, cast end,
  cooldown `start_time` — is on the `game_time` millisecond axis *only*. The docs warn explicitly
  against mixing them.
- **`get_spell_cooldown_information` mixes units within one return value**: `start_time` is game-time
  ms while `duration` is documented in seconds.

Timing is the single most bug-prone service. It gets one owner and a test suite.

## 2.6 The spell queue is already a cross-plugin arbitration channel

This is the most important discovery for the IntentQueue design. The injector's `spell_queue` library
is **not** an intra-rotation ordering mechanism — it is a **cross-plugin arbitration channel**, with a
documented convention: use priority `1` for essentially everything you author, `7` is reserved for
interrupts, `9` for manual player input. It also uses the **colon call convention**, as do all
`common/` modules (`mod:fn()`, never `mod.fn()`).

So the kernel's IntentQueue is **not** the bottom of the stack. It layers on top of an existing
arbiter it does not own. The commit stage must map Sentinel bands onto that convention rather than
fight it, and must not add fallback logic to `queue_position`.

Meanwhile `core.input.cast_target_spell` performs **zero validation** — no range, no facing, no ready
check; it only sends a packet. That is exactly the gap the commit stage exists to fill, and it
validates the two-phase design.

## 2.7 The frozen snapshot must hold values, not object handles

**Every `game_object` is a raw 8-byte pointer into game memory that can become invalid between uses**,
and the docs say to guard before *every* use, not just at acquisition.

A "snapshot frozen for the tick" that stores `game_object` references is therefore unsound — the
pointer can die inside the tick that froze it. The snapshot must store **extracted values**
(position, health, entry id, aura ids, distances), with handles held only transiently inside the
sensor that read them.

This also constrains enumeration: `core.object_manager.get_visible_objects()` is **not implemented**.
Only `get_all_objects()` (everything, documented as "computationally expensive to process every
frame") and the cached `unit_helper:get_enemy_list_around` / `get_ally_list_around` exist. Sense-once
is mandatory, not an optimisation.

## 2.8 Movement is key-based, which makes lease revocation safety-critical

There is **no `core.input.move(x,y,z)` and no click-to-move**. Movement is stateful key start/stop
pairs — `move_forward_start` / `move_forward_stop`, `turn_left_start` / `stop`, `strafe_*` — plus
`look_at(point)` / `look_at_3d(point)` / `set_pitch(radians)`.

Consequence: **if a `MOVEMENT` lease is revoked without the holder releasing its keys, the character
keeps running.** `on_revoke` is not a courtesy callback; it is the only thing standing between a
preemption and the bot sprinting into a lake. The broker must therefore treat MOVEMENT revocation as a
kernel-enforced key-release, not as a request the plugin may ignore.

### 2.8.1 The force-release must reach navigation, not just the keys

Releasing the eight movement keys is necessary and **not sufficient**, because the keys are not the
only authority over the character's motion. Four authorities exist, and the key sweep reaches one:

| Authority | Reached by the key sweep? |
|---|---|
| Kernel `move` intent → `movement_release` | yes |
| SDK `simple_movement` driven through NavClient's `MovementService` | no |
| NavClient's `Jump.lua` / `MoveBackward.lua`, calling `core.input` directly | no |
| `NavAdapter`'s own owner/preempt mechanism — a **second arbiter** over the same resource | no |

So the broker can revoke `MOVEMENT`, the sweep can stop all eight keys, and navigation can press them
again on the next tick. A revocation that the character does not obey is not a revocation.

Two consequences, both binding:

- **`release_all` stops navigation as well as keys**, via NavClient's high-level `client:stop()` —
  which stops all movement *and* resets active navigation state. Not `MovementService:stop()`, which
  only stops the follow. And the nav stop inherits the key sweep's fault tolerance: an absent or
  throwing nav client must not prevent the eight keys from being released. A safety path that a
  dependency can abort is not a safety path.
- **Navigation acquires the `MOVEMENT` lease** like any other consumer, and `NavAdapter`'s private
  owner/preempt mechanism retires in favour of the broker. Its own comments describe chase_controller
  preempting a questing Travel — a band-ordered preemption the broker expresses properly. Two
  arbiters over one resource is the condition the broker exists to end.

**Recorded and not fixed:** `Jump.lua` and `MoveBackward.lua` call `core.input` directly from a
separate Sylvanas plugin. That is ambient authority the kernel cannot reach (§2.3 — plugin A cannot
require plugin B), and it is a known hole rather than a solved one.

## 2.9 LazyBot's declarative rotation tier was never actually used

ADR-000 §6.4 says "LazyBot's `CombatEngine` gets this right and it's worth copying directly," praising
the `DamageActions` / `SelfBuffActions` / `SelfHealActions` `PAction` lists.

Reading the source at commit `def6716`: **that entire tier is dead code.** `DamageActions`,
`SelfBuffActions`, `SelfHealActions`, `LogicAttack`, `LogicSelfBuff` and `LogicSelfHeal` appear
**only inside `CombatEngine.cs` itself** across all 287 files. Nothing assigns them; nothing calls the
Logic methods. The one shipped rotation, `PVEBehavior/PVEBehaviorCombat.cs`, ignores the machinery
entirely and runs its own XML `Rule` system.

**Do not copy an unproven API on faith.** We have a declarative rotation DSL that *is* proven:
`sentinel/modules/combat/priority_builder.lua` (276 lines) with **9 production consumers**. Design
Tier 1 from that, not from LazyBot's aspiration.

What LazyBot *does* prove, and what we keep: the **`Pull() → PullResult` split from `Combat()`** is
real and load-bearing — pull failure (LoS, resist, path) needs different recovery than combat failure.

## 2.10 The tier-design rule worth stealing

From the LazyBot analysis, the single most transferable sentence:

> *A tier boundary is only as useful as the richest value that can cross it.*

LazyBot's Plugin tier is decorative because every method returns `void`. Its State tier is
half-working because `NeedToRun` is a rich inbound signal with **no outbound counterpart** —
`DoWork()` returns nothing, so the scheduler learns nothing from running it.

**Design rule adopted:** every extension entry point must return a status to the host. A `tick` that
returns `void` is an observer, not a participant. See §8.3.

----------

# 3. D3 — The three inversions (retained)

## 3.1 Combat is a service, not a peer module

Today combat and questing are peers at priorities 10 and 50 (`module_registry.lua:32-57`). That is
wrong because combat is not a goal — it is an interruption to a goal, and each goal wants different
combat behaviour:

| Goal | Wanted combat policy |
|---|---|
| Grind | Kill everything in leash radius, pull proactively |
| Quest | Kill only what blocks the objective, no adds |
| Gather | Avoid entirely, flee, use escapes |
| Travel | Break combat, run |

ADR 07 §5.6 confirms this from the guide corpus: `.mob` steps want *objective* stance, while `#loop`
grind circuits want *aggressive*. Same field, opposite behaviour, both present in real content.

## 3.2 Two-phase tick: plugins emit intents, the kernel commits

Plugins never call `core.cast` / `core.input.*` directly. They emit intents; the kernel dedupes, gates
(GCD / range / LoS / facing / rate), logs, and commits. Justified independently by §2.6 — the raw cast
call validates nothing at all.

**Latency mitigation:** an `immediate = true` flag on the intent, restricted to leases at band ≥ 70,
still routed through the same gates. Reactive abilities (interrupts, defensive cooldowns) cannot
afford a tick of latency.

**One intent *type* per channel, and every intent acts under the lease that authorised it.** Both
halves are load-bearing, and the first is narrower than it first reads — this paragraph previously
claimed a channel commits at most one intent per tick, which is **not what the kernel does**:

- `Executors.CHANNEL_FOR` is a total map from intent *type* to channel — `cast`→CASTING,
  `move`→MOVEMENT, `pet_command`→PET, and so on. That binding is what makes a channel claim mean
  something specific. It says nothing about how many intents of that type may commit in one tick.
- `IntentQueue:commit` dedupes on `type | sorted payload key=value`, so two intents of the same type
  with **identical** payloads collapse to one (highest band wins, submission order breaks ties) while
  two with **different** payloads both survive and both run the gates. That is deliberate and
  load-bearing: `PetController:passive()` emits `passive` and then `follow` as two `pet_command`
  intents in the same tick precisely so each can be individually gated, rejected and observed.

  A per-channel exclusivity rule would make `follow` the silent casualty of `passive`. If one is ever
  wanted, it must be added knowing that.
- An intent may only act inside the lease that authorised it. An intent that outlives its lease, or
  that acts on a channel its lease does not cover, is the revocation race §6.1's generation counter
  closes. Emitting one is a defect even when it happens to work.

  A corollary that is easy to get backwards: **a caller must not release its lease immediately after
  submitting.** `is_generation_valid` resolves an intent's lease by lookup in the broker's held set,
  so a tidy release before COMMIT kills the very intent it just emitted, as `stale_generation`. The
  lease must outlive the submission that used it.

**`move` is a desired state, not an imperative.** The name reads like a command and is not one: a
`move` intent commits by *recording the desired key state* and touching no key. The keys are driven
later in the same COMMIT stage by `movement_release.reconcile`, once the queue has drained and the
tick's desire is final. That ordering is deliberate — reconciling mid-drain would act on a desire that
a later intent in the same tick could still change.

Two things follow. Reconciliation is COMMIT's work and not ACCOUNT's, so it sits inside the frame
budget it costs rather than after the measurement. And because `move` declares rather than acts,
`release_all` can clear the desire without the broker needing to know the reconciler exists.

**`fast` is a delivery variant, not a second intent type.** A `cast` may carry `fast = true`, which
selects `queue_spell_target_fast` / `queue_spell_position_fast` instead of the plain verb. It is a
payload **flag** and deliberately not a `cast_fast` type, because a type is the thing a channel and a
lease attach to — and `fast` changes neither. **No gate reads it:** `gcd_gate` branches on
`payload.off_gcd`, `castable_gate` branches on neither, and the channel is CASTING either way. It
selects which SDK verb carries an already-authorised packet, which is transport.

**The tests that distinguish those two readings** are the three in
`tests/kernel/test_intent_executors.lua`:

| Test | What it settles |
|---|---|
| `test_a_fast_cast_reaches_the_fast_queue_verb` | `fast` changes the **verb** — and only the verb |
| `test_a_fast_ground_targeted_cast_reaches_the_fast_position_verb` | the choice is (destination × speed), so it cannot be a type without four of them |
| `test_a_fast_cast_is_refused_when_the_sdk_has_no_fast_verb` | an absent verb is a refusal, not a silent downgrade to the slow one — serving a `fast` request slowly would undo the only reason it was asked for |

Read together they pin that a `fast` cast and a plain one traverse the *same* gates for the *same*
reasons and differ only at the SDK boundary. If `fast` ever became a type, every gate case would have
to be duplicated per type — that duplication is the signal it has stopped being a flag.

Related, and stated here because it is the same confusion from the other side: `fast` and `off_gcd`
are the same fact told to two different authorities — `off_gcd` tells the *kernel's* gate not to wait
on the GCD, `fast` tells the *spell queue* not to. **The kernel does not make them agree**, and both
mismatches are reachable. See §6.5 for the rule that governs `off_gcd` itself.

**A `UnitRef` is two flat scalars, never a nested table.** `Units:mint_ref` returns
`(guid, generation)` and callers spread them into the payload as `unit_guid` and `unit_ref_tick`.
This is a **constraint on the payload shape**, not a style preference: `IntentQueue:dedupe_key`
flattens exactly one level with `tostring(payload[k])`, so a nested `{ guid, generation }` table would
key on its **address**. Two refs naming the *same* unit would dedupe as distinct — two packets at one
mob — and the same ref submitted twice would not dedupe at all. The two-return-value shape also makes
the mistake impossible rather than merely discouraged: a caller writing
`payload.ref = units:mint_ref(...)` captures the guid alone, loses the stamp, and is refused at commit
as `unstamped_unit_ref`.

The same constraint binds any future payload field: **anything that must participate in dedupe has to
be a scalar.** A field whose value is a table is, for dedupe purposes, unique per submission.

## 3.3 The kernel ships zero behaviour not expressible through the public API

Built-in loot, vendor, rest and corpse-run are **built-in plugins** using the same manifest and the
same API as third-party ones. This is the only reliable way to keep the API adequate — if the kernel
can privilege itself, the public API silently rots.

----------

# 4. D4 — Layer model

```
┌───────────────────────────────────────────────────────────────────────┐
│  SYLVANAS INJECTOR   (single Lua state, shared _G, single thread)      │
│                                                                       │
│  ┌─────────────────────────────────────────────────────────────────┐  │
│  │ sentinel-core                                                   │  │
│  │                                                                 │  │
│  │  KERNEL      Scheduler · Snapshot · EventBus · ControlBroker    │  │
│  │              IntentQueue · ErrorBoundary · Registry · Quarantine│  │
│  │                                                                 │  │
│  │  SERVICES    Nav(NavClient) · Timing · Catalogs · Objectives    │  │
│  │              Facts · Config · Persist · Log · UIHost            │  │
│  │                                                                 │  │
│  │  LIBRARY     BT · PriorityBuilder · Geometry · JSON             │  │
│  │                                                                 │  │
│  │  API         _G.Sentinel  (semver'd, live-getter metatable)     │  │
│  └────────────────────────────┬────────────────────────────────────┘  │
│                               │ manifest registration                 │
│  ┌──────────────┬─────────────┴──────┬──────────────┬──────────────┐  │
│  │ builtin/     │ rotations/         │ activities/  │ strategies/  │  │
│  │ loot vendor  │ mage paladin       │ quest grind  │ target-sel   │  │
│  │ rest corpse  │ warlock            │ gather       │ pull-sel     │  │
│  │ antistuck    │                    │              │              │  │
│  └──────────────┴────────────────────┴──────────────┴──────────────┘  │
│         in-repo, same manifest, same API, zero privileges             │
└───────────────────────────────────────────────────────────────────────┘
                               ▲
                  Runtime Profile (offset-indexed JSON, ADR 07)
                               │
                    ┌──────────┴───────────┐
                    │ sentinel-compiler    │  Rust, out of process
                    └──────────────────────┘
```

Two plugins exist at the Sylvanas level today and that stays true: `sentinel` and
`SentinelNavClient`. Everything inside the box is one plugin's `require` graph.

----------

# 5. D5 — What is built in

**The test.** Something is kernel if **(a)** multiple unrelated plugins need it, **(b)** it needs
privileged singleton access, or **(c)** it must be arbitrated to prevent conflicts. If none hold, it
is a plugin.

**The tie-breaker, when ambiguous:** the *mechanism* is kernel, the *decision* is a plugin. The kernel
knows how to vendor; a behaviour decides when.

**Combat is a KERNEL SERVICE. It is not a plugin of any kind — not third-party, not built-in.** §3.1
already says so in its title and §5.4 implies it; §5.1–5.3 never state it, and that omission has been
propagating. At least two headers in the tree were written asserting "combat registers through the
plugin registry" — it does not, and never has. `ModuleRegistry.modules` registers it (enabled,
priority 10), `runtime/app.lua` calls `register_all` on that registry, and **nothing anywhere calls
`PluginRegistry:register`**. Both headers were corrected in Phase 4e; the reason they were written at
all is that this section did not say the thing they had to guess at.

Two consequences a reader needs, because they are not derivable from the tables below:

- **Any policy the ModuleRegistry applies reaches the rotation engine.** Its 3-strike degrade rule
  governs combat, not questing alone. Somebody deciding what that policy may safely do is deciding it
  for the thing that fights.
- **The migration lands in Phase 6**, together with the *grind activity* that delegates to it. Combat
  is a service with no activity in front of it until then, which is why it still sits behind the
  ModuleRegistry rather than behind the ActivityStack. Where a class *rotation* sits is a different
  question with a different answer — §5.3, always a plugin.

## 5.1 Kernel — non-negotiable

The **Status** column below was written from the pre-kernel inventory and is now the most stale table
in this document. It is re-measured here against `sentinel/kernel/` on `62c98de`; the original verdict
is kept in parentheses where it changed, because "was New, is built" is the information a reader
needs and "built" alone erases it.

| Subsystem | Why it cannot be a plugin | Status, measured |
|---|---|---|
| **Scheduler** | One thing drives the tick; also enforces per-plugin frame budget. No documented tick rate exists (§2.5), so it derives cadence from `core.delta_time`. | **Built.** `kernel/scheduler.lua`, all seven §7 stages (`Scheduler.STAGES`), frame budget in `report.over_budget`. *(was: "app.lua, 4-step frame")* |
| **Snapshot** | Sense once per tick, frozen, **values not handles** (§2.7). Independent scanning gives O(n×m) and inconsistent views inside one tick. | **Built, hot tier only.** `kernel/snapshot.lua` (`Builder:freeze` → `Frozen`), captured by `kernel/snapshot_source.lua::SnapshotSource.capture_player`. Warm and cold tiers do not exist — see §13.1 item 14 and §8.4.1's 42. *(was: New)* |
| **ControlBroker** | §6. The arbiter. | **Built.** `kernel/control_broker.lua`, driven at ARBITRATE and retired at ACCOUNT by `runtime/app.lua::SentinelApp:_register_kernel_stages`. *(was: New)* |
| **IntentQueue** | §3.2. The commit choke point, layered over `spell_queue` (§2.6). | **Built.** `kernel/intent_queue.lua` (`:submit` → `:commit`), executors in `kernel/intent_executors.lua`, band mapping in `IntentQueue.spell_queue_priority`. *(was: New)* |
| **EventBus** | Singleton by nature. | `core/event_bus.lua` — unchanged, sync, per-handler pcall, re-publishes `system:error`. Not yet moved under `kernel/`. |
| **Timing** | GCD, cast/channel state, swing timers, cooldowns. Must be authoritative or two plugins double-cast. Owns the two-clock problem (§2.5). | **Built.** `kernel/timing.lua` — `now_ms`, `gcd_duration_ms`, `note_cast`, `gcd_remaining_est`, `is_gcd_ready`. Swing timers are **not** in it; `combat/swing_tracker.lua` still owns those. *(was: Partial)* |
| **Catalogs** | Shared reference data; duplicating it costs memory and drifts. | **Built and moved.** `kernel/catalogs/spell.lua` + `kernel/catalogs/aura.lua`; `combat/spell_catalog.lua` and `combat/aura_catalog.lua` are **gone from the tree**. §6.5's GCD-truth audit lives on the spell catalog. *(was: Partial, "both need rework")* |
| **Nav** | Wraps SentinelNavClient. One path at a time; coupled to `MOVEMENT`. | `integrations/nav_client/adapter.lua` — polled at SENSE, now error-wrapped (§7). Its private `can_claim` survives only as the no-broker fallback (§13.1 item 20). |
| **ErrorBoundary + Quarantine** | Mandatory once third-party code runs. No engine-level error isolation is documented — every callback must self-pcall. | **Built and unified.** `core/error_boundary.lua` plus `kernel/fault_tracker.lua`, which is now the single home of the 3-strike policy: `runtime/module_registry.lua` used to hold its own copy and its header records that it no longer does. Both registries strike against the same tracker — `ModuleRegistry` into `DEGRADED`, `PluginRegistry:_record_fault` into `QUARANTINED`. |
| **Facts** | Per-tick memoized derived truth. The `snapshot` argument to `objectives:satisfied()`. | **Still absent.** No `kernel/facts.lua`, and deliberately unstubbed. The frozen snapshot does part of this job for the hot tier only. |
| **Objectives** | §9.2. Single completion authority. | **Still absent.** No `kernel/objectives.lua`. `Truth` (`kernel/truth.lua`) and the 17 predicates in `kernel/cond/` are the type it would answer in; the evaluator does not exist. **§15 is the consequence.** |
| **Config + UIHost** | Plugins declare schema; kernel renders and persists. **Menu IDs share one global namespace**, so allocation must be centralised. | **Config built** (`kernel/config.lua`, fed by `PluginRegistry:discover` → `_config:declare`). **UIHost absent** — `main.lua` still owns every frame and every menu id. |
| **Persist** | Namespaced save state. Sandboxed to `scripts_data/`; no `io` table in-game. | Unchanged — questing `.save.json` only, no kernel service. |
| **Log** | With plugin attribution, or this is undebuggable. | **Built.** `kernel/log.lua`, published as `Sentinel.log`. The attribution defect this table used to describe is closed; the *reporting* one is not (§13.1 item 16). |

## 5.2 Kernel-adjacent — built-in plugins, replaceable, zero privileges

Corpse recovery, loot, vendor/repair/mail, rest/eat/drink, anti-stuck, mount handling, blacklists —
plus the five ADR 07 §5.5 found missing from the original list: **trainer, flightpath, hearth, bank,
stable**, covering 3,322 command instances in the guide corpus.

**Exception:** anti-stuck and corpse recovery run as kernel-priority interrupts (band 90–99) even
though they are plugins. They are the safety net.

Two capability notes carried over from ADR 07: `vendor` needs a **buy** mode with an item list, and
`corpse` needs an **intent** flag so deliberate `.deathskip` death is not "rescued" by the safety net.

## 5.3 Always a plugin

Class rotations. Grind / quest / gather / fish / travel activities. Target and pull selection
strategies. Profile authoring tooling.

## 5.4 The calls worth arguing about

- **Gathering** — split it. Gameobject proximity sensing is a kernel *sensor* (questing needs it too
  for `.collect`); node selection, route policy and skill gating are a Gathering Activity plugin.
- **Combat** — split it. The *engine* (target primitives, threat, LoS, range, cast gating) is kernel;
  the *rotations* are plugins. `spell_dispatcher.lua`, `action_library.lua`, `state_machine.lua`,
  `chase_controller.lua` and `combat_helpers.lua` are already kernel-shaped.
- **Target selection** — same split. `target_selector_v2.lua` (60 lines) and
  `strategies/default_target_strategy.lua` (252 lines, mature) become the kernel selector; other
  strategies become plugin-contributed.
- **PriorityBuilder** — **promote to the kernel library.** It is the best existing asset and it is
  currently trapped inside the combat module. It is also the honest basis for the Tier-1 rotation DSL
  (§2.9).

  **Correction (Phase 4).** This section claimed "proven by 9 consumers". The real figure is **3**:
  `profiles/mage/frost_tbc.lua`, `profiles/paladin/retribution_tbc.lua` and
  `profiles/warlock/affliction_tbc.lua` are the only files that `require` it. `core/bt/composites.lua`
  names it in a doc comment about RUNNING semantics but does not consume it, and the remaining
  matches were tests and prose. The promotion argument does not depend on the count — 3 independent
  profiles is still the evidence that the shape generalises — but the number was wrong and every
  later section that leaned on "9" was leaning on nothing.

  Promotion cost was also lower than the section implies: the file's only load-bearing dependencies
  were `core/bt/*`. It bound `condition_library` and `action_library` at the top and never referenced
  either — they survived solely in comments — so the two requires that appeared to tie it to
  `modules/combat/` were dead on arrival.

----------

# 6. D6 — ControlBroker

## 6.1 Channels and leases

```
MOVEMENT · FACING · CASTING · TARGETING · INTERACTION · ITEMS · MODAL_UI · PET
```

(`CAMERA` deleted per §2.1; `MODAL_UI` added per §2.2; `PET` added per §2.2.1.)

```lua
local lease = Sentinel.control:acquire{
  channel   = Sentinel.Channel.CASTING,
  owner     = "sentinel.rotation.frost_mage",
  band      = "COMBAT", offset = 10,    -- resolves to 60; NEVER a bare integer (§6.2)
  ttl_ticks = 2,                        -- MUST be renewed; expires automatically
  on_revoke = function(reason) ... end,
}
if lease then
  lease:cast(SPELL.Frostbolt, target)   -- reachable only through the lease
end
```

Properties that matter:

(The sample above originally read `priority = 60`, which contradicted §6.2's named-band rule. The
broker refuses a bare integer with `band_must_be_named`; the resolved integer lives on the lease.)

- **All game-affecting calls hang off the lease**, not off a global. Unauthorised action becomes
  structurally impossible rather than merely discouraged. This is the object-capability pattern:
  authority travels with the reference, no ambient authority.

  **The sample above is aspirational and the shipped lease does not match it.** There is no
  `lease:cast` and no `lease:follow`. The caretaker exposes exactly ten members — `is_valid`, `owner`,
  `priority`, `band`, `generation`, `channels`, `has`, `submit`, `release`, `renew` — of which
  `submit` is the only one that can affect the game: one generic emit verb, not a typed one per
  capability, and `control_broker.lua` records that any movement or cast verb is *deliberately* absent
  so that the kernel's force-release remains the single `core.input.*` call site. That
  is a materially different object-capability story: `lease:cast(...)` would make authority typed per
  verb, so a CASTING lease could not structurally express a move; `lease:submit(intent)` makes the
  lease a **stamping** authority that attaches owner, band and generation, after which the verb rides
  in the payload and the channel binding is enforced downstream by the gate (§3.2). The second is
  weaker at the call site and equivalent at the commit point. Either is defensible; shipping one and
  documenting the other is not.
- **TTL on every lease.** A plugin that faults mid-tick cannot permanently hold `MOVEMENT`. Leases
  are Gray & Cheriton's core idea — authority reverts at term end *without the holder's cooperation*,
  which is exactly why a wedged holder cannot deadlock the resource.
- **Preemption fires `on_revoke`.** For `MOVEMENT` this is safety-critical, not cosmetic (§2.8): the
  kernel force-releases movement keys after calling `on_revoke`, because a plugin that ignores the
  callback would otherwise leave the character running. The force-release must also stop navigation,
  which is a co-authority over the same motion and is not reached by releasing keys (§2.8.1).
- **One intent *type* per channel, and every intent only under the lease that authorised it** (§3.2).
  The lease is what makes an intent legible: an intent that cannot be traced to a live lease cannot be
  gated, cannot be revoked, and cannot be attributed when it misbehaves.

  This bullet read "one intent per channel per tick" until Phase 4e, which is **not what the kernel
  does** and contradicted §3.2 inside the same document. `IntentQueue:submit`/`:commit` dedupe on
  `type | sorted payload key=value`, so two same-type intents with *different* payloads both survive
  and both run the gates — which `PetController` depends on. §3.2 carries the full argument; this
  bullet is only the cross-reference.
- **Re-acquire by the same owner is a renewal**, not a conflict.
- **Channels are independent.** This is what buys kiting: the rotation holds `CASTING`+`TARGETING`
  while the activity keeps `MOVEMENT` and backpedals. The current fixed-priority module design cannot
  express that at all.

Two hardening measures taken from the distributed-systems prior art, both cheap:

- **Generation counter.** Every lease carries a monotonic generation, re-checked at the commit point.
  This closes the revocation race where an intent emitted under a now-dead lease still commits.
- **Caretaker wrapper.** Plugins receive a per-tick wrapper whose `revoked` flag the kernel flips at
  tick end, not the lease itself. A stashed reference becomes inert rather than merely impolite.

## 6.2 Priority bands

Fixed bands so numbers are not folklore. Bare integers are the documented failure mode in extensible
systems — LazyBot's priorities are magic numbers scattered across state classes with nothing
preventing collisions.

```
90–99  Safety      death, corpse run, stuck, zone transition, loading screen
70–89  Survival    defensive CDs, emergency heal, flee, escape
50–69  Combat      rotation, pull
30–49  Goal        the active activity: grind / quest / gather
10–29  Housekeep   loot, vendor, repair, mail, mount
 0–9   Idle        rest, buff, afk
```

The manifest declares `{ band = "COMBAT", offset = 0 }`; the kernel **rejects a manifest requesting a
band its tier is not permitted** — an Ambient plugin cannot declare `SAFETY`.

## 6.3 Mapping onto the injector's own arbitration

The kernel does not own the bottom of the casting stack (§2.6). Band → `spell_queue` priority:

| Sentinel band | `spell_queue` priority | Rationale |
|---|---|---|
| 90–99 Safety | 7 | Documented as the interrupt slot |
| 70–89 Survival | 7 | Reactive, must not queue behind rotation |
| 50–69 Combat | 1 | The documented "everything you author" value |
| ≤ 49 | 1 | As above |
| *(never emitted)* | 9 | Reserved for manual player input |

Colon call convention throughout. No fallback logic on `queue_position`.

## 6.4 ActivityStack

One active Activity; interrupts push and pop.

```
[ Grind ]                     ← base activity, holds all channels
[ Grind → Combat(policy) ]    ← delegates CASTING+TARGETING, keeps MOVEMENT
[ Grind → Recover ]           ← death pushes at band 90, revokes everything
```

```lua
ctx.control:delegate(Sentinel.Channel.CASTING, "service.combat", {
  policy = "objective", leash = 30, allow_adds = false,
})
```

## 6.5 The off-GCD bypass needs TWO authorities to agree

An intent carrying `payload.off_gcd = true` skips the kernel's GCD gate. **That bypass is granted only
when the rotation asks for it AND the spell catalog corroborates it.** Neither authority may grant it
alone:

| Authority | Says | Why it is not enough by itself |
|---|---|---|
| The rotation's action (`opts.off_gcd`) | "I mean this to be fired off the GCD" | Only it knows intent — but a hardcoded list inside a plugin is exactly the drift the catalog exists to prevent |
| `Sentinel.catalogs.spell:is_ogcd_spell` | "the game agrees this ability is off the GCD" | A catalog-only rule would have handed **Ice Barrier** a bypass for three phases; the entry was wrong |

**The `AND` is directional, and that is the whole design.** Either authority being wrong on its own
*closes* the gate rather than opening it, so drift can only ever cost a delayed cast — never an
illegal one. This is the same direction `kernel/timing.lua` already chose for itself: over-gating
delays a cast by one window, under-gating double-casts.

**Ask `is_ogcd_spell`, never `is_gcd_spell`.** Both return a plain boolean and neither can say "I have
never heard of this key" — but they default in opposite directions, and an unknown key is exactly what
a renamed spell or a stale catalog produces:

```
is_gcd_spell("typo")  -> false   reads as "not on the GCD"  -> BYPASS GRANTED
is_ogcd_spell("typo") -> false   reads as "not off the GCD" -> bypass refused
```

**`gcd` and `ogcd` are two questions, not a flag and its negation.** MaNGOS answers them from
different columns: `Player::AddGCD` takes its duration from `StartRecoveryTime`, while
`WorldObject::HasGCD` looks the spell's own `StartRecoveryCategory` up in the live category map.
Avenging Wrath (category 133, time 0) opens *no* global cooldown and is *still blocked* by one — both
flags false. Deriving either from the other gets that case wrong, in the direction that sends a packet
the server refuses.

Phase 4e audited all 64 catalog entries carrying ids against `spell_template` (tbcmangos.sqlite, TBC
2.4.3) and found **four** wrong — Judgement, Counterspell, Avenging Wrath and all six ranks of Ice
Barrier. The flags had been set from intuition about whether something felt like a rotational ability.
`tests/kernel/test_spell_catalog_gcd_truth.lua` pins them and states what the audit could not see:
it is a one-off script against a 300 MB database, not re-runnable from the offline suite, so an entry
added after Phase 4e is unaudited and nothing will say so.

**Separately: `off_gcd` is not `fast`.** They are the same fact told to two different authorities —
`off_gcd` tells this gate not to wait, `fast` (§3.2) tells the *spell queue* not to. The kernel does
not fuse them, so `off_gcd` without `fast` passes the kernel and may still be swallowed by the queue's
own GCD check, silently.

----------

# 7. D7 — Tick pipeline

```
1. SENSE      hot sensors → Snapshot, frozen for the tick (VALUES, not handles)
2. EVENTS     drain queue, fire subscribers (inside ErrorBoundary)
3. INTERRUPT  safety evaluators may push/pop the ActivityStack
4. ARBITRATE  ControlBroker resolves leases, fires revocations, force-releases keys
5. ACT        active activity + delegated services run → emit intents
6. COMMIT     IntentQueue: dedupe → gate (GCD/range/LoS/facing/rate) → generation-check → execute
7. ACCOUNT    frame budget, quarantine checks, telemetry
```

**All seven stages are built.** `Scheduler.STAGES` in `kernel/scheduler.lua` is
`{ SENSE, EVENTS, INTERRUPT, ARBITRATE, ACT, COMMIT, ACCOUNT }`, and
`runtime/app.lua::SentinelApp:_register_kernel_stages` registers a named, attributed handler on each
one. COMMIT is not registrable from outside: the scheduler drains the IntentQueue itself, then runs
`movement_release.reconcile` inside the same stage for the reason §3.2 gives.

This section previously described `runtime/app.lua` as "a 4-step version"
(`callback_bridge → sensor_hub:refresh → nav_adapter:poll → registry:tick_all`) and named two defects
in it. **Both are closed:**

| Defect | Closed by |
|---|---|
| `nav_adapter:poll()` was the one call in the frame with no error wrapper | It is now an ordinary `sched:register("SENSE", "nav_adapter", …)` handler, so `Scheduler:_run_handler` wraps it **by construction** rather than by remembering to |
| `_izi_bridge` was constructed and never read | `runtime/app.lua::SentinelApp:new` passes it into `Forecast:new{ bridge = … }`, and `SentinelApp:get_izi_bridge` hands the same instance to the combat wrapper |

The first fix is the more interesting one, and it generalises: the old frame could omit a wrapper
because wrapping was a per-call-site decision. Registration made the safe thing structural. That is
the same move the lease makes for authority (§6.1) and the intent makes for `core.*` access (§3.2) —
three instances of one pattern, and worth naming as such.

Note what is registered at **ACT**: a single handler, `module_registry`, calling
`self._registry:tick_all(delta_ms)`. The kernel drives the *old* registry as one attributed unit. No
plugin tick and no plugin tree runs at ACT — that is §14.

**Sensor tiering** — mandatory, because `get_all_objects()` is documented as expensive per-frame and
`get_visible_objects()` is not implemented (§2.7):

| Tier | Contents | Cadence |
|---|---|---|
| Hot | player vitals, target, GCD, cast state, position | every tick |
| Warm | nearby units, auras, threat, loot windows | every N ticks or on event |
| Cold | bags, quest log, talents, reputation, gear | on demand, cached, **poll-only** |

**Correction to the cold tier.** ADR-000 said cold refreshes "on event / on demand". There are **no
quest events** — the registered event list contains no `QUEST_LOG_UPDATE`, no `QUEST_ACCEPTED`, no
`PLAYER_ENTERING_WORLD`. Cold-tier quest state must be **polled**, and there is no signal for "the log
is populated now". This is why `Objectives` must be tri-state (§9.2), not because of caution.

----------

# 8. D8 — The plugin contract

## 8.1 Where plugins live

**Decision: in-repo directories, same manifest, same API, zero privileges. Not separate Sylvanas
plugins — yet.**

Justified by §2.3: no load order, no dependency mechanism, shared `package.loaded` collisions, a
per-plugin callback cap, and **no per-plugin reload**. You pay the full ABI cost and receive none of
the hot-swap benefit.

Promotion later is mechanical **if and only if** no plugin ever reaches past the public API. That
discipline is the thing to enforce now; the packaging is a detail you can change in an afternoon once
third parties are real.

## 8.2 Manifest

```lua
{
  id      = "sentinel.rotation.frost_mage",
  kind    = "rotation",            -- rotation | activity | behavior | strategy | sensor | ambient
  version = "1.2.0",
  api     = "^1.0",                -- semver range against Sentinel.API_VERSION

  applies_to = { class = "Mage", spec = "Frost", min_level = 10, max_level = 70 },

  provides  = { "combat_routine" },
  requires  = { "nav", "catalogs.spell", "timing.gcd" },
  conflicts = { "sentinel.rotation.mage_generic" },

  priority  = { band = "COMBAT", offset = 0 },

  config = {
    { key = "use_water_elemental", type = "bool", default = true },
    { key = "blink_threshold",     type = "int",  default = 35, min = 0, max = 100 },
  },

  preflight = function(ctx) ... end,           -- veto activation
  build     = function(ctx) return tree end,   -- declarative (preferred)
  tick      = function(ctx, leases) ... end,   -- imperative escape hatch
}
```

`provides` / `requires` are what make this genuinely modular: the kernel resolves the dependency graph
at load and **refuses to load a plugin whose requirements are unmet**. Note that today
`ModuleRegistry`'s `capabilities` field is **declared but never consumed outside tests** — capability
resolution is new work, not existing.

## 8.3 Lifecycle, and the return-value rule

```
DISCOVERED → VALIDATED → LOADED → ELIGIBLE → ACTIVE ⇄ SUSPENDED → UNLOADED
                  │                              │
                  └→ REJECTED                    └→ QUARANTINED (3 faults)
```

`ELIGIBLE` is separate from `ACTIVE` because `applies_to` is evaluated against live state — a Mage
rotation is eligible but inactive until you are actually on the Mage.

**Every entry point returns a status to the host** (§2.10). This is the correction to LazyBot's
half-working State tier, where `NeedToRun` is a rich inbound signal but `DoWork()` returns nothing:

```lua
Sentinel.Status = { DONE, RUNNING, YIELD, BLOCKED, FAILED }
```

`YIELD` means "I could run but I am deferring" — the scheduler may then give the tick to a lower band.
`BLOCKED` carries a reason string, which is what feeds the runner cockpit's blocked-reason display.
A `tick` returning `nil` is a manifest validation error, not a default.

## 8.4 Two-tier rotation API

Tier 1 is built on `priority_builder.lua`, which is proven in-tree by **3** independent rotation
profiles — **not** on LazyBot's `PAction` lists, which never ran (§2.9).

*(This sentence said "9 consumers" until now, and §5.4 already carried the correction while this
section kept repeating the wrong figure. One document contradicting itself about its own evidence is
worse than being wrong once. The three are `rotations/mage_frost/frost_tbc.lua`,
`rotations/paladin_retribution/retribution_tbc.lua` and
`rotations/warlock_affliction/affliction_tbc.lua`.)*

**The promotion §5.4 argued for is done, and went one step further than the argument asked.**
`combat/priority_builder.lua` is gone from the tree; the file lives at
`kernel/lib/priority_builder.lua`; and the three profiles no longer require it directly at all — they
reach it as `Sentinel.rotation`, published by `kernel/api.lua`. Only the kernel requires the library
by path now. That is the §8.1 discipline holding on its first real test: the consumers went through
the public surface rather than around it, so the packaging can move again without touching them.

```lua
-- Tier 1: declarative. Target ~90% of rotations.
rotation:damage  { spell = "Frostbolt", priority = 10 }
rotation:damage  { spell = "Ice Lance", priority = 20, when = Cond.TargetHasAura("Frozen") }
rotation:selfbuf { spell = "Ice Armor", priority = 10, wait_ready = true }
rotation:defense { spell = "Ice Block", priority = 90, when = Cond.HealthBelow(15) }
rotation:pull    { spell = "Frostbolt", range = 30 }

-- Tier 2: imperative override.
function rotation:tick(ctx, leases) ... end
```

Keep the **pull/combat split**: `pull(target) → PullResult` is the one part of LazyBot's rotation tier
that demonstrably works, because pull failure (LoS, resist, path) needs different recovery than combat
failure, and the framework acts on the returned value.

### 8.4.1 Measured, not estimated

The declarative tier's reach was asserted before it was counted. Counted:

| Measure | Figure |
|---|---|
| `frost_tbc.lua` rotation entries expressible in Tier 1 | **25 / 25** |
| Combinators in `modules/combat/condition_library.lua` | **65** |
| Of those, blocked purely by sensors that do not exist | **42** |
| Ported to `kernel/cond` on the `Truth` type | **17** |

The 42 break down as auras (16), proximity counts (3), temporal forecast (5), bag contents (4),
spellbook and cooldowns (4), a pet tier that the snapshot does not have at all (5), target detail
including cast state and role (4), and one needing module state. A further 5 are not world state —
they are rotation configuration — and 3 are superseded by `Truth`'s own combinators.

**The 17 are a fixture proving the type, not a usable vocabulary**, and were chosen for coverage of
type behaviour rather than for the mage: Unknown propagating through Kleene composition, policy
resolving at the call site, `resolve` raising when given none, and the `TreatTrue` diagnostic. The
Unknown that drives them comes from real missing data — there is no pet tier — rather than a stub,
which is the only way to know the tri-state works for the reason claimed.

**The gap is a sensor gap, not an expressiveness gap.** That distinction decides where Phase 1b
spends: 42 of 65 are one warm/cold capture away, and none of them is waiting on the DSL.

----------

# 9. D9 — Hardening compile-before-execute

The load-bearing wall stays: Rust resolves offline, Lua executes. Three additions.

## 9.1 Fail-closed dispatch

```rust
#[derive(Serialize)]
#[serde(tag = "type", content = "payload")]   // adjacently tagged, enforced
pub enum Action { /* ... */ }
```

On profile load the kernel: compares `schema_hash` against its compiled-in hash → mismatch =
**refuse**; asserts every tag in `tags_used` has a registered handler → missing = **refuse**;
shape-validates each node → else **refuse**. No profile ever runs partially gated.

This repo has already been bitten: `RuntimeCondition` was externally tagged, so every non-unit
condition fell through to fail-open `true` and gating silently stopped gating.

ADR 07 §5.4.1 adds `ContentIntegrity` (content hash + world-source provenance) plus a first-touch name
probe, because `schema_hash` guards the tag set but nothing guards resolved entry IDs.

## 9.2 ObjectiveLedger — one completion authority, tri-state

```lua
Sentinel.objectives:satisfied(predicate, snapshot) -- pure, no side effects, testable offline
```

Nothing else is allowed to answer "is this done?" This is the fix for the ~7 scattered completion
checks already logged against this codebase — and RXPGuides is the cautionary example of the endpoint,
with completion truth spread across ~120 independent handlers.

**`satisfied()` returns `Truth { True, False, Unknown }`, not `bool`.** Forced by three documented
facts: there are no quest events so all quest state is polled with no readiness signal (§7);
`is_complete` is a documented integer tri-state `1 / -1 / 0` where `-1` means *failed*, while a second
API treats the same field as a boolean — and in Lua both `0` and `-1` are truthy, so the vendor's own
example reports a failed quest as COMPLETE; and the profession API returns safe defaults
(`0`/`false`/`nil`/`{}`) that are indistinguishable from real zeroes.

The `Predicate` enum and its 15 required additions are specified in ADR 07 §5.1.1.

### 9.2.1 The tri-state's one unclosable hole: Lua has no `__toboolean`

`Truth` composes through Kleene AND / OR / NOT, and `Truth.resolve` **raises when given no policy** —
there is deliberately no default, because a default policy is how a tri-state quietly degrades back
into a boolean at the one call site nobody reviewed.

But the type cannot defend its own truthiness. Lua dispatches `if x then` on the value being neither
`nil` nor `false`, and offers **no `__toboolean` metamethod to intercept it**. A `Truth` is a table.
Therefore:

```lua
if truth then          -- ALWAYS taken. True, False and Unknown are all truthy tables.
if truth == Truth.True -- correct, but only if you remember
```

`False` and `Unknown` are *indistinguishable from `True`* in a bare conditional, which means the exact
mistake the type exists to prevent is one forgotten `.resolve` away, and it fails **open and silent**.
This is the same failure shape as the externally-tagged `RuntimeCondition` in §9.1: gating that
stopped gating without anything going red.

No metamethod closes it, so the mitigations are structural rather than typed — make the mistake hard
to reach and loud when reached, and treat any bare `if <truth>` as a review-blocking defect. Anything
consuming a `Truth` resolves it at the call site, with an explicit policy, or does not consume it.

## 9.3 Normalize at the sensor boundary — and model unavailability

Raw Sylvanas types stop at the sensor boundary. `get_class()` returns a numeric id;
`enums.class_id_to_name` yields **UPPERCASE** while RestedXP class tails are Title-Case — a live trap
already recorded in this repo.

**Addition:** you cannot normalize what you cannot read. The sensor layer needs an explicit
`Unavailable` state, because **reputation is entirely absent from the API**, there is **no race enum
or `race_id_to_name` table**, and `get_faction_id()` returns a unit faction template rather than
Alliance/Horde player side. Without an explicit unavailable value, every unreadable field silently
becomes a plausible-looking zero.

----------

# 10. D10 — API surface

```
Sentinel.API_VERSION = "1.0.0"

Sentinel.register(manifest)
Sentinel.control      :acquire, :release, :delegate, :who_owns
Sentinel.state        :get, :set, :watch, :snapshot           (frozen per tick, values only)
Sentinel.facts        :quest, :inventory, :player, :combat, :nav   (per-tick memoized truth)
Sentinel.events       :on, :off, :emit, :once
Sentinel.nav          :request_path, :follow, :stop, :is_reachable, :distance_along
Sentinel.catalogs     .spell, .aura, .item, .object
Sentinel.timing       :gcd_duration, :gcd_remaining_est, :is_casting, :cooldown, :swing_remaining
Sentinel.objectives   :satisfied, :register_predicate
Sentinel.units        :player, :target, :nearby, :by_id, :hostiles_within
Sentinel.config       :get, :set, :declare
Sentinel.persist      :load, :save                             (namespaced, scripts_data/ only)
Sentinel.log          :debug, :info, :warn, :error             (auto-attributed)
Sentinel.bt           node/composites/decorators/factory       (library)
Sentinel.rotation     priority-builder DSL                     (library)
Sentinel.intent       :move_to, :cast, :target, :interact, :use_item   (queued)
```

Note `gcd_remaining_est` — deliberately named for what it is. Remaining GCD is not readable (§2.5); the
kernel derives an estimate from its own cast timestamps and must not pretend otherwise.

**Read this list as a target, not an inventory.** Measured against `kernel/api.lua`: `facts`,
`objectives` and `persist` do **not** exist and are deliberately not stubbed; `intent` is the
IntentQueue itself with the verb carried in the payload's `type`, not the five per-verb methods listed
above; and the surface additionally publishes `activities`, `bands`, `cond`, `spells`, `forecast`,
`scheduler`, `plugins`, `app`, plus the enums and the tri-state as `Status`, `Channel`, `Band` and
`Truth` — none of which this list anticipated. §16 rows 8 and 9 carry the detail.

Two of those additions are worth reading the reasons for, because both are cases where publishing the
obvious thing alone would have satisfied nobody: `Truth` ships **with** `cond` because a plugin may not
`require("kernel/truth")` — the require audit forbids reaching into the kernel — so a predicate's
answer would be unnameable without it; and `bands` ships alongside the `Band` enum because a plugin
cannot emit an intent without *computing* a band from `{ band, offset }`.

**Missing entirely from this list, and the subject of §15: the loader for the ADR 07 artifact.**

**Nav is async.** `request_path` returns a handle; the tick never blocks on the NavServer.

```lua
local h = Sentinel.nav:request_path(from, to)
if h:ready() then lease:follow(h:path()) end
```

`_G.Sentinel` is published behind a live-getter metatable (§2.4) plus a deferred `__SentinelPending`
registration queue drained on init and re-drained for the first ~60 ticks.

----------

# 11. D11 — Migration from the current tree

The inventory verdict, condensed. **This is promotion, not a rewrite.**

**Baseline, measured on committed `62c98de`:** `luajit sentinel/tests/run_offline.lua` from the repo
root reports **1,117 passed / 0 failed**, plus **22 suites that ran opaquely through `run()`** — 22 ok,
0 failed, case counts unknown and *not* included in that 1,117.

Three things about that figure, each of which has already misled someone:

- **It is not comparable to the older numbers in this section's history.** This paragraph has read
  "605 passed / 0 failed" and before that "127 passed / 1 failed". The harness itself changed: suites
  exporting only `run()` were formerly counted as **one** case each. The growth from 605 to 1,117 is
  therefore part real work and part corrected arithmetic, and no honest split between the two is
  recoverable after the fact.
- **The 22 opaque suites are an unmeasured region, not a rounding error.** A suite that runs opaquely
  reports pass/fail for itself and nothing about how many assertions it made. Quoting 1,117 as "the
  coverage" overstates precision in one direction and understates volume in the other.
- **Re-measure on a clean tree or do not quote the number.** Measuring this section while writing it
  produced *1,118 passed / 2 failed* — and both failures were newly-added red tests sitting
  uncommitted in `tests/modules/questing/test_module_control.lua` from concurrent work, not kernel
  defects. That is the same trap this paragraph already documents from the other direction: the
  earlier "127 passed / 1 failed (the failure is in questing vendor maintenance)" was a symptom of an
  uncommitted `execute_vendor` re-scan, while committed `HEAD` was green. **A baseline recorded from a
  dirty tree is not a baseline** — it attributes someone's work-in-progress to the codebase, and the
  resulting "known failure" gets budgeted for rather than fixed.

## 11.1 Promote to kernel — largely as-is

`core/blackboard.lua` (46) + `blackboard_schema.lua` (35) · `core/event_bus.lua` (83) ·
`core/error_boundary.lua` (30) · `runtime/module_registry.lua` (381, **DEGRADED quarantine already
implemented**) · `runtime/app.lua` (124) · `runtime/sensor_hub.lua` (77) ·
`runtime/callback_bridge.lua` (109) · the `runtime/sensors/*` set ·
`integrations/nav_client/adapter.lua` (392, mature).

From combat, the kernel-shaped pieces: `spell_dispatcher.lua` (258) · `action_library.lua` (358) ·
`state_machine.lua` (55) · `events.lua` (45) · `chase_controller.lua` (129) ·
`cooldown_tracker.lua` (49) · `target_selector_v2.lua` (60) ·
`strategies/default_target_strategy.lua` (252) · `shared/combat_helpers.lua` (129).

**`priority_builder.lua` (276) → kernel library.** The single highest-value promotion.

## 11.2 Port as plugins

`combat/profiles/mage/` (1,743) · `profiles/paladin/` (606) · `profiles/warlock/affliction_tbc.lua`
(171) → `rotations/`. `modules/questing/*` → `activities/quest/`, consuming the ADR 07 artifact.

**Judgement call, recorded as a disagreement with the inventory pass:** it classified
`questing/runtime_profile.lua` (2,401) and `module.lua` (750) as kernel. They are not — they are the
Quest Activity's execution engine, which is exactly the policy the plugin tier exists to hold. Only
`runner_state.lua` (369, pure view-model) has a kernel-shaped sibling in UIHost.

## 11.3 Keep as library

`core/bt/` (427–447, standalone; its only Sentinel coupling is a `:get`/`:set` duck-type) ·
`core/geometry.lua` (64) · `core/JSON.lua` (579, **required** — the sandbox ships no JSON) ·
`shared/compat.lua` · `shared/class_names.lua` · `shared/humanization.lua` · `shared/spell_helper.lua`.

## 11.4 Promote with rework

`combat/module.lua` (1,170 — becomes the combat *service*) · `spell_catalog.lua` (270) ·
`aura_catalog.lua` (167) · `condition_library.lua` (536) · `context_builder.lua` (205) ·
`profiles/registry.lua` (43) · `strategies/factory.lua` (15).

**This section previously read "Rewrite", and that was the wrong verdict.** These files are not being
replaced; they are moving into the kernel with specific, enumerable defects corrected on the way. The
distinction is not cosmetic — it decides whether their existing tests are a liability to be discarded
or an asset to be carried, and the tests are an asset. Calling promotion a rewrite licenses throwing
away the only evidence that the behaviour was ever right.

It also has a concrete consequence the audits already encode. `tests/kernel/audit_scope.lua` tracks
these as `PROMOTION_CANDIDATES` and counts every `module.*` blackboard key they touch — **including
keys in what is currently their own namespace**, because kernel code owns no `module.*` namespace and
"its own" stops being its own the moment the file lands in the kernel. Those reads are legal today
and illegal after promotion, which is exactly why they are tracked separately from a cross-namespace
violation. The violation list is the migration worklist.

**Layering inversion to fix during the rework:** `runtime/sensors/aura_sensor.lua` requires
`modules/combat/aura_catalog` and writes paladin seal policy — a kernel sensor reaching into module
policy.

## 11.5 Delete

`combat/pvp_target_selector.lua` (627) · `strategies/grind_target_strategy.lua` (315) ·
`shared_subtrees.lua` (295) · `target_strategy.lua` (20) · `strategies/pvp_target_strategy.lua` (17) ·
`runtime/runtime_context.lua` (44, zero production callers) · `shared/types.lua` (5, zero references).

**Measured on `62c98de`: all seven are still present. Nothing on this list has been deleted.**

Recorded plainly because a deletion list nobody executes is worse than no list — it reads as
completed cleanup on every subsequent skim. Two of the seven also gained a reason to stay pending:
`strategies/grind_target_strategy.lua` is the only consumer of `IziBridge` outside `Forecast`, and it
is the natural seed for the Phase 6 grind activity rather than dead weight. The remaining five have no
such defence and are simply undone.

## 11.6 Testability debt — CLEARED

`SentinelApp:new()` and `initialize()` were **provably untestable offline** because
`integrations/izi_bridge.lua` did an unguarded `require("common/izi_sdk")`, an injector-only module, so
the file encoding the kernel's boot contract was asserted by nobody.

**Closed.** `izi_bridge.lua` now routes every injector require through a local `try_require` that
`pcall`s and returns `nil` on failure, and its header records the change against this section. The
composition root is constructible offline, which is what Phase 1's exit criterion asked for and what
`tests/integration/test_kernel_end_to_end.lua` now depends on to exist at all.

Worth keeping as the precedent: this was the only item in §11 whose cost was *paid entirely before*
anything depended on it, and it is the reason the kernel has an end-to-end test rather than a
hand-stubbed imitation of one.

----------

# 12. D12 — Build order

| Phase | Deliverable | Exit criterion |
|---|---|---|
| 1 | Kernel: scheduler, frozen snapshot, bus, boundary, intent queue. **Guard the IziBridge require.** | Tick runs with nothing registered, budget accounted, `SentinelApp:new()` constructible offline |
| 2 | ControlBroker + ActivityStack + generation counters | Two dummy plugins contend for `MOVEMENT`; preempted holder's keys are force-released |
| 3 | API surface + manifest + capability resolution + version gate + live-getter handshake | A rotation registers in either load order; a plugin with unmet `requires` is refused with a named reason |
| 4 | **Port the frost mage as the first plugin** | It uses only the public API — anything it cannot do is an API gap, fixed now |
| 5 | Built-in plugins (loot / rest / corpse / antistuck) | Same manifest as external, zero privileges |
| 6 | Grind activity + combat-as-service with policy | Grind delegates `CASTING`, retains `MOVEMENT`, kites |
| 7 | Quest activity + ObjectiveLedger + fail-closed loader (ADR 07) | A malformed profile refuses to run with a named reason |

### 12.1 Delivered — measured against the tree, not against intent

The exit criteria above are the honest yardstick, and they are applied here literally. "Built" means
the code exists **and** the criterion is demonstrable; a phase whose code exists but whose criterion
is not reachable in production is **not** exited, and saying otherwise is how a plan starts lying.

| Phase | Verdict | Evidence, and what is missing |
|---|---|---|
| **1** | **EXITED** | `kernel/scheduler.lua` (7 stages, `report.over_budget`), `kernel/snapshot.lua`, `core/event_bus.lua`, `core/error_boundary.lua`, `kernel/intent_queue.lua`. IziBridge require guarded (§11.6). `tests/integration/test_kernel_end_to_end.lua` constructs the real app offline. |
| **2** | **EXITED** | `kernel/control_broker.lua` + `kernel/activity_stack.lua`, both driven from `_register_kernel_stages` (ARBITRATE, INTERRUPT, and caretaker retirement at ACCOUNT). Generation counters at `IntentQueue:set_generation_validator`. Force-release reaches keys *and* navigation via `kernel/movement_release.lua` (§2.8.1), pinned by `tests/kernel/test_movement_release.lua` and `test_nav_under_broker.lua`. |
| **3** | **EXITED** | `kernel/api.lua` (live-getter metatable, `__SentinelPending` drain), `kernel/manifest.lua`, `kernel/capabilities.lua`, `kernel/semver.lua`. Refusals are named: `PluginRegistry:resolve` writes `rejection.reason .. ":" .. detail` precisely so `requires_unmet` never lands anonymously. |
| **4** | **BUILT, NOT EXITED** | Three rotation plugin packages exist under `rotations/` with valid manifests, and `tests/kernel/test_plugin_require_audit.lua` + `test_plugin_core_access_audit.lua` enforce API-only access mechanically. But the criterion is *"it uses only the public API"* as a **running** plugin, and no manifest is ever registered. **§14.** The API gaps the port did find are in `08a_API_GAPS.md`. |
| **5** | **NOT STARTED** | No `sentinel/builtin/` directory. INTERRUPT runs the real hook with **zero** evaluators registered, which is the seam left open for anti-stuck and corpse recovery. |
| **6** | **NOT STARTED** | No `sentinel/activities/`. Combat still runs behind `ModuleRegistry` at priority 10 exactly as §5 predicts it would until this phase. |
| **7** | **NOT STARTED** | No ObjectiveLedger, no Facts, and no loader for the ADR 07 artifact on either side of the boundary. **§15.** |

**Phase 4's shape is the finding.** The phase was defended in this section on the grounds that
"finding the API inadequate at Phase 4 is cheap." That held: the port drove four new capabilities
(`rotation`, `units`, `spells`, `catalogs.spell`) into the kernel and exposed three fail-open bugs, all
recorded in `08a_API_GAPS.md`. What it did **not** do is prove the plugin *contract* — because
proving a contract requires exercising it, and discovery, resolution and activation were never wired.
The API is now evidenced; the lifecycle is not.

**Phase 4 before Phase 6 is deliberate and worth defending.** Combat has the tightest timing and the
most state; if the public API can express a frost rotation it can express anything else. Finding the
API inadequate at Phase 4 is cheap; finding it at Phase 6 is not.

**Add to Phase 3, not later: a manifest validator and a load-time diagnostic report.** RXPGuides ships
without one — an unresolved `#completewith foo` silently never fires. LazyBot is worse:
`GrindingProfile.LoadFile` is eight independent `try { } catch { }` blocks with **empty catch bodies**,
each falling back to a hardcoded default, so a profile can be 90% broken and still "load". Fail-closed
loading must exist before anything depends on it.

----------

# 13. D13 — Risks and open questions

**Every item below now carries a verdict measured against `62c98de`.** A risk register without dates
is indistinguishable from a wishlist; one that is never re-read is worse, because it launders "we
thought about this once" into "this is handled". The verdicts use four words and mean exactly them:

- **DISCHARGED** — the thing the risk warned about was built, and built the way the risk asked.
- **MATERIALISED** — the risk happened. It is now a defect with a location, not a probability.
- **OPEN** — unchanged, and still correct as written.
- **OPEN (SDK)** — open because the injector does not offer what would close it. No amount of our
  work closes these; they need a live client or a vendor change.

**Risks.**

1. **Two-phase intent commit costs a tick of latency** on reactive abilities. Mitigated by
   `immediate = true` at band ≥ 70, still gated. Watch it in Phase 4.

   **DISCHARGED as designed, UNMEASURED as a cost.** `IntentQueue:submit` refuses
   `immediate` below band 70 with the named reason `immediate_requires_band_70`, and the threshold
   lives in `kernel/bands.lua` citing this section rather than as a literal at the check. So the
   *mechanism* exists and is bounded. What has never been measured is the thing the risk was actually
   about — whether one tick of latency is survivable for an interrupt — because that needs a live
   client and a real cast. Do not read the mechanism's existence as evidence about the latency.

2. **The frozen snapshot is new and subtle.** Storing values rather than handles (§2.7) means the
   sensor layer decides *in advance* what downstream consumers may ask about. Under-capture forces a
   mid-tick live read, which reintroduces exactly the inconsistency the snapshot exists to prevent.

   **MATERIALISED, exactly as written.** `SnapshotSource.capture_player` captures the hot tier and
   nothing else. Under-capture is now measured three ways: §8.4.1's **42 of 65** combinators blocked
   purely on sensors that do not exist, §13.1 item 19's missing `selected_target.*`, and the absence of
   any warm or cold capture at all. This was the most accurate risk in the register — it named the
   failure mode and the failure mode is what happened.

3. **Timing is the highest-bug-density service** (§2.5): two incompatible clocks, one API mixing units
   inside a single return value, and a GCD remainder that must be inferred. It needs disproportionate
   test coverage.

   **DISCHARGED for GCD, OPEN for swings, and the clock question got worse before it got better.**
   `kernel/timing.lua` owns `now_ms`, `gcd_duration_ms`, `note_cast`, `gcd_remaining_est`,
   `is_gcd_ready`, and got the disproportionate coverage the risk asked for
   (`tests/kernel/test_timing.lua`, plus `test_tick_clock.lua` and `test_cadence_meter.lua`). Swing
   timers were in scope for this service and are **not** in it — `combat/swing_tracker.lua` still owns
   them, so the "must be authoritative or two plugins double-cast" argument is only two-thirds
   applied. And the two-clock trap produced a live descendant: see open question 7.

4. **`applies_to` / `ELIGIBLE` is over-engineering for one character.** Correct and cheap, but do not
   build multi-spec resolution until there is a second rotation.

   **DISCHARGED, and the restraint held under pressure.** There are now three rotations, so the
   premise expired. `applies_to` is implemented (`PluginRegistry:refresh_eligibility` → the local
   `applies`), and multi-*spec* resolution still is not: all three manifests deliberately omit `spec`
   and each says why in a comment citing this risk. That is the rare case of a "do not build X yet"
   note surviving contact with the code that would have built X.

5. **Rewrite risk.** The combat DSL, target selector and BT library are the mature parts. Port them;
   do not rewrite them. The genuinely new code is the broker, the intent queue, the snapshot and the
   ledger.

   **DISCHARGED.** Nothing mature was rewritten. `priority_builder.lua` moved to
   `kernel/lib/priority_builder.lua` "unchanged except for the two dead requires" (§5.4), and §11.4's
   verdict was itself corrected from *Rewrite* to *Promote with rework* — the correction that decides
   whether existing tests are a liability or an asset. Three of the four genuinely-new pieces are
   built; the ledger is not, which is §15.

6. **Do not cache predicates that depend on live state.** RXPGuides caches gate results in a table
   (`GuideLoader.lua:29`) that is **never invalidated anywhere in the addon**, and reads `playerLevel`
   *inside* the cached computation — so level-conditional content freezes at whatever level the player
   was on first evaluation. Facts must be per-tick memoized, never persistent.

   **OPEN, and now load-bearing in a place the risk did not anticipate.** Facts does not exist, so the
   rule has nothing to govern yet. But the *same* hazard arrived through eligibility:
   `refresh_eligibility` reads class, spec and level — cold-tier data — and is therefore throttled
   rather than per-tick, with `invalidate_eligibility` as the escape hatch for a caller that knows
   live state moved. `_register_kernel_stages` names this risk at the call site and names the
   symmetric error too: re-reading cold data sixty times a second burns the frame budget. A throttle
   with an explicit invalidator is the correct answer to both; it is also precisely the design
   RXPGuides omitted.

**Open questions.**

7. **No documented tick rate.** `on_render` is once per frame; `on_update` is described *both* as
   "reduced speed, relative to On Render" *and* "executed on each frame update" in the same file. The
   scheduler must measure rather than assume — but the frame-budget design depends on knowing the
   real cadence. Measure it in Phase 1.

   **OPEN (SDK) — the instrument was built, the reading has not been taken.** `kernel/tick_clock.lua`
   + `kernel/cadence_meter.lua` measure cadence at runtime, and `Scheduler` publishes
   `system.tick_cadence` only once there are enough samples — `runtime/app.lua` notes it "never
   reports a guessed rate". The design got this right by refusing to assume.

   It also surfaced a **second** undocumented quantity underneath the first: `core.delta_time`'s unit.
   The docs say milliseconds; three sites in this repo assumed seconds. `TickClock` now refuses to
   pick, carrying `"unknown"` / `"milliseconds"` / `"seconds"` / `"ambiguous"` and publishing the
   verdict as `system.delta_time_unit`. **A cadence figure read before that field resolves is
   meaningless**, and the resolution requires a live client. Neither number exists yet.

8. **The per-plugin callback cap is undocumented.** We are near it already with 7 callbacks in
   `main.lua`. If UIHost needs more, we may hit an undocumented ceiling.

   **OPEN (SDK), unchanged and still 7.** `main.lua` registers exactly seven: `on_pre_tick`,
   `on_update`, `on_spell_cast`, `on_legit_spell_cast`, `on_render`, `on_render_window`,
   `on_render_menu`. UIHost is the phase that would test the ceiling and it has not been built, so this
   question is not closed — it is untested. Worth noting the mitigation the current design already
   provides: because the Scheduler multiplexes stages inside one `on_pre_tick`, adding kernel work
   costs zero callbacks. The ceiling is only reachable by adding *engine* callbacks.

9. **No vendor/merchant frame-open predicate exists**, so the vendor behaviour cannot reliably detect
   its own modal state. `MODAL_UI` gives us a *claim* but not an *observation*.

   **OPEN (SDK).** Unchanged, and no vendor behaviour exists yet to be blocked by it (Phase 5).

10. **No documented unload/teardown callback.** The `{ name, version, unload }` return-table
    convention used by all three plugins in this repo is **not documented anywhere** in the Sylvanas
    docs. We rely on undocumented behaviour for cleanup.

    **OPEN (SDK), and the surface area grew.** `PluginRegistry` now has `suspend` and `unload` states,
    so the kernel has an internal teardown path — but nothing guarantees the *injector* ever calls
    into it. Internal lifecycle correctness does not close an undocumented external contract.

11. **Escort quests have no owner.** Starting one is `Op::Interact`; following and protecting an NPC
    is a behaviour nothing in this design covers. It appears in the guide corpus only as human prose.

    **OPEN, and now half-owned, which is worse than unowned.** The Rust side models it —
    `ActionPayload::Escort` lowers through `compiler/src/lib.rs` to `RuntimeAction::Escort`, and
    `kernel/task_graph.rs` gives it a tag. So an artifact can *say* escort. Nothing in `sentinel/`
    can do it. A representable instruction with no executor is the fail-open shape §9.1 exists to
    prevent, arriving through the op set instead of the tag set — and it is one of the concrete cases
    the §15 loader's `tags_used` assertion would catch at load rather than at the NPC.

12. **Coroutines are undocumented and unused anywhere in this repo.** If they work, incremental
    long-running work (profile prefetch, large route computation) gets much easier. Worth a Phase 1
    spike.

    **OPEN — the spike was not run, and the design was built to not need it.** Coroutines still appear
    nowhere in production Lua except two comments, in `kernel/scheduler.lua` and `runtime/app.lua`,
    both explaining that scheduling here is *cooperative* precisely because coroutines are
    undocumented: a handler that burns the frame cannot be preempted mid-call. That is the honest
    consequence, stated at the site that suffers it. The frame budget therefore *detects* an overrun
    and cannot *interrupt* one — `report.over_budget` is a diagnosis, never a control.

13. **`Facts` vs `Objectives` boundary.** They are distinct — Facts is the per-tick memoized truth
    cache, Objectives is the evaluator over a compiled `Predicate` AST, and Objectives consumes Facts
    as its `snapshot` argument. Both are new; the risk is that they blur under implementation
    pressure and we recreate scattered completion truth inside the kernel.

    **OPEN, and the risk has not been *taken* yet — neither exists.** `kernel/api.lua` states
    plainly that `objectives`, `facts` and `persist` are Phase 5+ services and are **not stubbed**.
    Refusing to stub them is the right call: a stub named `objectives` is how the seventh scattered
    completion check gets written and then blessed. What does exist is the *type* they would speak in
    (`kernel/truth.lua`) and 17 predicates over the frozen snapshot (`kernel/cond/`). The boundary is
    still undrawn, and §15 is where drawing it becomes unavoidable.

----------

## 13.1 Measured in Phase 4b D3 — defects, not risks

Five tracks converted plugin call sites in parallel. What they found is worth more than what they
converted, and none of it is speculative.

**Each item below is followed by a verdict re-measured on `62c98de`.** Four are closed, three are not,
and one of the three not-closed is closed *in the wrong place* — which is the most interesting of them.

**14. `Sentinel.snapshot` always returns `nil`, and the capability list says it works.** `api.lua`
resolves it as `scheduler and scheduler.current_snapshot and scheduler:current_snapshot()`, and
`current_snapshot` appears **exactly once in the whole repository — on that line.** `Scheduler` has
no such method. The frozen snapshot exists only as a local inside `Scheduler:tick()`, passed to stage
handlers as `ctx.snapshot`; a rotation action runs deep inside a ModuleRegistry ACT handler holding a
blackboard and nothing else.

Meanwhile `Api.KERNEL_CAPABILITIES["snapshot"] = true`. This is the **identical failure** the same
file documents for `log` — a capability admitted at manifest time and absent at first use — except
worse: the `and` chain makes it fail *silent* rather than at first use. **This is the single highest
priority item in the tree.** Everything downstream is blocked on it: §8.4.1's 42 sensor-blocked
combinators, the entire deferred handle worklist, and every predicate the tri-state was built for.
Phase 1b's first task is not a warm tier; it is making the snapshot reachable at all.

> **CLOSED.** `kernel/scheduler.lua::Scheduler:current_snapshot` exists and returns the tick's frozen
> snapshot *itself*, not a copy — `tests/kernel/test_scheduler.lua` pins identity deliberately, because
> a copy would answer a subtly different question than the one COMMIT gated on. It answers before the
> first tick too, with an empty frozen snapshot rather than `nil`, so the `and`-chain that made the
> original defect silent has nothing left to short-circuit on. `tests/kernel/test_api.lua` asserts
> `_G.Sentinel.snapshot == kernel.scheduler:current_snapshot()`, and
> `tests/integration/test_kernel_end_to_end.lua` reads a real value through the published surface after
> a real tick. The *read path* is closed. **The capture gap behind it is not** — §13 risk 2 and item 19.

**15. Nothing in production emits an intent.** The only `:submit(` sites outside tests are the
definition in `intent_queue.lua` and the caretaker forwarding to it in `control_broker.lua`. All six
intent types are built, gated, tested and unwired. This is not an argument for deleting any of them —
it is the reason none of them can be judged unused yet.

> **CLOSED IN THE PLUGINS, AND THAT IS NOT THE SAME AS CLOSED.** There are now six production
> `caretaker:submit` sites — `rotations/mage_frost/frost_support.lua` and `frost_actions.lua` (cast and
> `use_item`), `rotations/mage_frost/pet_controller.lua` and `rotations/warlock_affliction/pet_controller.lua`
> (`pet_command`), and `support.lua` in both the warlock and paladin packages (cast). Every one of them
> lives inside a rotation package, and **no rotation package is reachable in production** (§14). So the
> emitters exist, are covered offline, and cannot fire in a live client. Read this item as *"the code
> that would emit an intent is written"* — not as *"intents are emitted."* The distinction is the whole
> subject of §14.

**16. `report.intents` has no production consumer.** `scheduler.lua` populates `committed` /
`deduped` / `rejected` / `failed` every tick and only tests read it. The point of routing a
fail-silent `pcall` through the queue is that refusal becomes *named*; until something logs that
report at runtime, every name this phase produced is observed by nobody.

> **OPEN, unchanged, and now the cheapest high-value item in the register.** `Scheduler:tick` still
> populates all four lists every tick; `main.lua` calls `app:on_pre_tick()` and **discards the return
> value**; the only readers of `.intents` outside the scheduler are
> `tests/integration/test_kernel_end_to_end.lua` and `tests/kernel/test_scheduler.lua`. The scheduler
> does publish `system.frame_ms`, `system.tick_index`, `system.frame_over_budget`,
> `system.tick_cadence` and `system.delta_time_unit` to the blackboard — so the *accounting* half of
> ACCOUNT reaches a consumer and the *intent* half does not. Since item 14 closed, `Sentinel.log` now
> exists with automatic per-plugin attribution, which is exactly the sink this needs. Nothing is
> blocking it but the wiring.

**17. The raw-handle count was 22 because the audit could only see `.object`.** `HANDLE_KEY` matches
keys ending `.object`; a mechanical recount of one file — `frost_actions.lua` — found **94 distinct
source lines touching a live handle**, including `combat.target`, `player.target` and
`combat.low_health_add`, none of which the pattern can name. Structural rejection in `blackboard:set`
now carries the defence and the audit is its backstop (§2.7).

> **CLOSED, by replacing the check rather than by fixing the pattern.** `HANDLE_KEY` is *still*
> `'"([%w_%.]-)%.object"'` — deliberately, because it was never made load-bearing again. The defence
> moved into `core/blackboard.lua`, which now asks what a value **contains** rather than what a key is
> **spelled**: it refuses userdata, functions, threads, or a table holding one at any depth, and
> refuses a table whose `__index` it cannot see through. Its header enumerates its own four blind
> spots — writes bypassing `set` via `bb._data[key]`, post-`set` mutation of a stored table, mock adds
> that are plain tables where live ones are handles, and a shrink-only ledger of keys still permitted
> to hold a handle. **That enumeration is the actual fix.** The lesson from these five tracks was
> "before a check is believed, state what it cannot see", and this is the only place in the tree where
> a check states it about itself.

**18. The truthiness lint cannot see the kernel, and widening its scope alone would not help.**
`Scope.PACKAGE_ROOTS` is `sentinel/rotations`, so no kernel file is scanned — and the kernel is now
where `Truth` values are *produced*. But the lint seeds its detection on `Sentinel.cond` and aliases
of it, so a kernel file doing `require("kernel/cond/…")` is not recognised as a Truth source at all.
Running it over `sentinel/kernel` today reports **zero violations, and that zero measures nothing**.
The seed list must learn the require form *before* the scope is widened, or widening it installs a
check that is green because it is blind.

> **OPEN, both halves, exactly as written.** The lint is
> `tests/kernel/test_plugin_core_access_audit.lua` check 4; `Scope.PACKAGE_ROOTS` in
> `tests/kernel/audit_scope.lua` is still `{ "sentinel/rotations" }`; and `collect_truth_locals` still
> seeds on `Sentinel.cond` plus `local X = Sentinel.cond` aliases and nothing else. A kernel file
> requiring `kernel/cond/init` is invisible to it. The lint *does* document its own limits honestly —
> single-file local dataflow, file-level name scoping, and a test that proves a `Truth` handed to a
> helper escapes detection — which is the right shape. It is the scope and the seed list that have not
> moved. **Fix the seed list first.** Widening the scope first installs a green check over the code
> that produces the values, which is the worst of the three possible orderings.
>
> One correction to this item's own diagnosis, recorded by `kernel/api.lua`: the seed list was not the
> deepest reason the lint measured zero. **`Sentinel.cond` did not exist as a field at all** — 17
> predicates, a test suite, and no route to a plugin — so there were no consumers of *either* form to
> find. That half is closed; `cond` is published now, together with `Truth`, which is what makes the
> lint's seed the binding constraint rather than a secondary one.

**19. The snapshot's `target` is not the rotation's target.** The snapshot captures
`player:get_target()`; rotations act on `combat.target` (written by the combat module) falling back to
`player.target`. They usually agree and are not guaranteed to. Converting target reads to the snapshot
as it stands would **silently retarget the rotation**. Phase 1b needs `selected_target.*` as a distinct
capture, not just `target.*`.

> **OPEN IN THE SNAPSHOT — and closed elsewhere, which is the trap.**
> `SnapshotSource.capture_player` still captures a single `target.*` prefix from `player:get_target()`,
> and there is no `selected_target.*` in the snapshot. What *was* built is
> `runtime/app.lua::SentinelApp:selected_target`, with `SentinelApp:unit_target_resolver` handing it to
> `Executors.install` — so **intent execution** resolves the rotation's target correctly while
> **snapshot reads** still resolve the player's. Two different answers to "the target", both live, in
> one tick.
>
> That is strictly more dangerous than the original finding, because the original was uniformly wrong
> and this is selectively right. A reader who checks the executor path concludes the issue is handled.
> `tests/integration/test_kernel_end_to_end.lua` is explicit that it does **not** pin the precedence
> inside `selected_target`. The item stands as written: the snapshot needs `selected_target.*` as a
> distinct capture, and until it has one, no target read may be converted to the snapshot.

**20. Smaller, verified, and each one live:** `combat.potion_cd_until_ms` now has three readers and
zero writers, so `potion_ready()` is permanently true. The potion path is unreachable in production
anyway — nothing writes `combat.health_potion_id`, `mana_potion_id`, `has_health_potion` or
`has_mana_potion`. `SpellQueue` is an undeclared global at `frost_actions.lua:375,377` and
`use_mana_gem` would raise on first use. `tests/runtime/test_sensor_hub.lua:156` sets `_G.core` to
`nil` mid-suite, so offline suite *order* is load-bearing. And `NavAdapter:can_claim` survives only as
the no-broker fallback: full retirement of the second arbiter needs `chase_controller.lua` and
`combat/module.lua` to take their own leases, neither of which was in this wave's scope.

> **Item by item:**
>
> | Sub-item | Verdict |
> |---|---|
> | `combat.potion_cd_until_ms` has readers and no writer | **OPEN, and now deliberate.** `frost_actions.lua` records that the hard-coded 120 s timer was *removed* rather than repaired, because the client owns that number and two sources of truth for one fact diverge in both directions — too permissive when a human drinks, too strict when something clears the cooldown early. The kernel's ITEMS gate asks `get_item_cooldown` instead. Three reads remain and each is permanently "ready"; they are tracked in `08a_API_GAPS.md`. A known-dead read left in place with a written reason is a different thing from an unnoticed one. |
> | Potion path unreachable — nothing writes `health_potion_id` etc. | **OPEN.** Still no writer. |
> | `SpellQueue` undeclared global would raise | **CLOSED.** `frost_actions.lua` records the defect in the past tense and the item path now goes through a `use_item` intent under an ITEMS lease. |
> | `_G.core = nil` mid-suite makes offline suite order load-bearing | **PARTIALLY CLOSED.** The assignment moved out of the suite and into the shared harness, `tests/harness/mocks/sylvannas_api.lua`. One owner instead of one suite reaching into global state is the right direction; it does not by itself prove order-independence, and nothing asserts it. |
> | `NavAdapter:can_claim` survives as the no-broker fallback | **OPEN, unchanged, and correctly reasoned.** `integrations/nav_client/adapter.lua` carries a header block titled "why `can_claim` survives as a fallback rather than being deleted": when a broker is reachable it is the only arbiter consulted, and `can_claim` is dead code. Retiring the second arbiter still needs `chase_controller.lua` and `combat/module.lua` to take their own leases. |

**The shape they share.** Items 14, 17 and 18 are the same defect the three earlier ones were: an
audit that globbed its own scope, a handle pattern matching only `.object`, a force-release pin that
could only see keys the kernel pressed. Each check was **right about what it saw and wrong about what
it looked at**, and each reported green. Before a check is believed, state what it cannot see.

----------

# 14. D14 — The rotation-plugin gap

**Phase 4 built three plugins and wired none of them. The plugin architecture has never run.**

This is the most important thing this document has to say about its own implementation status, and it
is stated first because every other Phase 4 claim reads differently once you know it. §12.1 marks the
phase BUILT, NOT EXITED for this reason alone.

## 14.1 What exists

Both sides of the contract are real, tested, and complete enough to use.

**Plugin side.** Three packages under `sentinel/rotations/`, each self-contained:

| Package | Files | Manifest |
|---|---|---|
| `rotations/mage_frost/` | 11 | `sentinel.rotation.mage_frost` |
| `rotations/paladin_retribution/` | 7 | `sentinel.rotation.paladin_retribution` |
| `rotations/warlock_affliction/` | 8 | `sentinel.rotation.warlock_affliction` |

Every manifest carries the full §8.2 shape — `id`, `kind = "rotation"`, `version`, `api = "^1.0"`,
`applies_to`, `provides = { "combat_routine" }`, `requires`, `priority = { band = "COMBAT", offset = 0 }`,
`config`, `preflight` and `build`. They are not sketches: the frost `preflight` refuses activation when
`catalogs.spell` or `timing` is missing, with the reason spelled out (a rotation that activates without
a catalog resolves every spell key to `nil` and silently casts nothing — a refusal is far cheaper to
diagnose). Each package reaches the kernel only through its own `sentinel_api.lua` shim, and
`tests/kernel/test_plugin_require_audit.lua` plus `test_plugin_core_access_audit.lua` enforce that
mechanically rather than by inspection. **The §8.1 discipline is real and it is checked.**

**Kernel side.** The whole §8.3 lifecycle is implemented in `kernel/plugin_registry.lua`:
`discover` → `resolve` → `refresh_eligibility` → `activate` → `tick`, plus `suspend`, `unload`,
`_record_fault` into `kernel/fault_tracker.lua`, and `report` / `report_lines` for the §12 load-time
diagnostic. `kernel/api.lua` publishes `surface.register` (→ `registry:discover`), and both halves of
§2.4's handshake exist: the live-getter metatable for reads and `Api.enqueue` / `Api.drain_pending` /
`Api.tick_pending` over `_G.__SentinelPending` for registration, re-drained for the first 60 ticks.

## 14.2 What is unreachable, and exactly where the chain breaks

**Measured: nothing in `sentinel/` calls `Sentinel.register`, and nothing pushes onto
`_G.__SentinelPending`.** The only non-test references to either are the definitions themselves in
`kernel/api.lua`, and comments in the rotation manifests recording this very fact.

The break is worth tracing precisely, because "the plugins are not registered" understates how far
the gap goes. Follow the lifecycle from the top:

| Step | Method | Production callers |
|---|---|---|
| 1. DISCOVERED | `PluginRegistry:discover` | **none** — reachable only via `surface.register` / `drain_pending`, and nothing calls either |
| 2. VALIDATED → LOADED | `PluginRegistry:resolve` | **none** |
| 3. LOADED ⇄ ELIGIBLE | `PluginRegistry:refresh_eligibility` | **one** — the SENSE stage in `_register_kernel_stages` |
| 4. ELIGIBLE → ACTIVE | `PluginRegistry:activate` | **none** |
| 5. tick | `PluginRegistry:tick` | **none** |

So production drives **exactly one** method on the plugin registry, and it is step 3 — the middle of
a chain whose first two steps never run. That single call iterates `self._order`, which is populated
**only** by `resolve()`. It therefore iterates an empty table on every tick, forever, and cannot
report that it did: it returns `true` for "yes, I did the work", because it did do the work, on
nothing.

**A green lifecycle call over an empty set is item 14/17/18's shape one more time** — a check that is
right about what it saw and wrong about what it looked at. It belongs in §13.1's list and is recorded
here instead only because it is about the plugin path rather than about an audit.

Two further consequences follow, and both matter for planning:

- **`activate` is where `build` is called.** `PluginRegistry:activate` runs `manifest.build(ctx)` and
  stores the result as `entry.tree` "for the host to drive". Since `activate` never runs, no plugin
  tree is ever constructed.
- **There is no host that drives one.** Even given an ACTIVE plugin with a built tree, nothing walks
  the registry's ACTIVE set. The ACT stage registers a single handler — `module_registry`, calling
  `self._registry:tick_all(delta_ms)`. The declarative half of the manifest (`build`) has no consumer
  and the imperative half (`tick`) has no caller.

## 14.3 What actually runs, today

```
ModuleRegistry.modules  (combat, enabled, priority 10)
  └ runtime/app.lua  ACT stage → registry:tick_all
      └ modules/combat/module.lua
          └ ProfileRegistry.resolve(class_id, spec_id)      ← modules/combat/profiles/registry.lua
              └ PROFILE_REGISTRY[class_id]                   ← a literal table: 8→Mage, 2→Paladin, 9→Warlock
                  └ Profile.build(blackboard, event_bus)
```

`modules/combat/profiles/registry.lua` `require`s the three rotation profile modules **directly by
path** and maps them by `class_id` in a table literal. `modules/combat/module.lua` calls
`ProfileRegistry.resolve` at two sites and builds whatever comes back. That is the live path. It works,
it is covered, and it is the reason the rotations are not dead code despite the manifests being inert.

Note what this path does *not* consult: `applies_to`, `requires`, `provides`, `conflicts`, `api`,
`preflight`, `config`, or `priority`. A class id indexes a table. Every guarantee the manifest exists
to provide is bypassed — not violated, simply not asked for.

## 14.4 What wiring would take

Four steps, in this order. None is large; the ordering is the part that matters.

1. **Register.** Something must hand each manifest to the kernel. Two shapes work and they are not
   equivalent: a `require` of the three `manifest.lua` files followed by `Sentinel.register(m)` binds
   the set at load time, while pushing onto `_G.__SentinelPending` is what an *externally* loaded
   plugin would do and therefore exercises §2.4's ordering for real. Prefer the second for at least
   one plugin, or the deferred queue keeps being tested only by `tests/kernel/test_api.lua`.
2. **Resolve.** Call `PluginRegistry:resolve()` after the registration wave settles. Until this runs,
   `_order` is empty and eligibility is a no-op. It is idempotent and `discover` already marks
   `_resolved = false` on a late arrival, so re-running it after each drain is correct.
3. **Activate.** Something must decide *which* eligible plugin activates and call
   `activate(id, ctx)` with a `ctx` carrying `api`, `blackboard` and `event_bus` — the three fields the
   shipped manifests read. With one rotation per class and `conflicts` unused, "the highest-priority
   ELIGIBLE plugin providing `combat_routine`" is sufficient and needs no new mechanism.
4. **Drive.** A host at ACT must tick the ACTIVE set: `manifest.tick` through `PluginRegistry:tick`
   for Tier-2 plugins, and `entry.tree` for Tier-1 declarative ones. This is the only genuinely new
   code in the list, and it is the natural seam for the Phase 6 combat service — which is why doing it
   as part of Phase 6 rather than as a Phase 4 retrofit is defensible.

## 14.5 The hazard: activating a plugin whose profile `Registry.resolve` also builds

**Do not do steps 1–4 while `modules/combat/profiles/registry.lua` is still live.** Every shipped
manifest's `build` is a one-line delegation to the same module the combat path already builds:

```lua
build = function(ctx) return Profile.build(ctx.blackboard, ctx.event_bus) end
```

So `Registry.resolve` → `Profile.build` and `PluginRegistry:activate` → `manifest.build` →
`Profile.build` would each construct a rotation tree, from the same module, over the **same blackboard
and the same event bus**. All three manifests carry a comment warning about this; the warning is
correct and it is worth spelling out *why*, because "the tree is built twice" sounds merely wasteful
and it is not. Reading `Profile.build` in `rotations/mage_frost/frost_tbc.lua`, three distinct
failures follow, in increasing order of nastiness:

1. **A duplicate lifecycle event.** `build` publishes `rotation:profile_loaded` on the event bus.
   Two builds publish it twice, so every subscriber sees a second load that did not happen.
2. **A blackboard slot with two claimants, and a duplicate-suppression check that stops working.**
   `build` constructs a `PetController` and writes it to `module.combat.pet_controller`; the second
   build overwrites that key with *its own* instance, while tree A keeps ticking the controller it
   holds in `o._pet_controller`. Two live controllers over one pet is bad on its own, but the specific
   breakage is worse than duplication: `PetController` carries `_state` and `_sent_guid`, and
   `already_sent_to(target)` compares against `_sent_guid` to avoid re-issuing a command. That state is
   **per instance**. Controller A sends an attack and records the guid; controller B has never heard of
   it and sends again. The suppression exists precisely to stop that, and splitting the instance is the
   one thing that defeats it.
3. **Two trees silently rate-limiting each other.** This is the one that would be hardest to diagnose.
   Each tree's three roots are wrapped in `BT.cooldown(…, { key = … })`, and `Cooldown:tick` in
   `core/bt/decorators.lua` stores its last-tick timestamp at `module.bt.cooldown.<key>` on the shared
   blackboard, **preferring the stored value over its own instance field**. Both trees use the same
   three keys. So whichever ticks first stamps the key, and the second one's
   `now_ms - last_ms < interval_ms` check fails — it returns `FAILURE` and never reaches its child. At
   a 75 ms interval on the GCD root with both trees ticked in one tick, **one of the two rotations
   simply does not run**, reports failure, and there is nothing in the log to say why.

Failure 3 is why the blackboard-keyed cooldown is a sharper hazard than a duplicate object: it makes
two independent trees over one blackboard *interfere* rather than merely coexist. It is also
`08a_API_GAPS.md` §3.0's blind spot arriving from a new direction — the require audit proves the two
trees share no imports, and they still share state, because the coupling is through blackboard keys the
audit cannot see.

**Therefore the migration is a swap, not an addition.** Whatever wires the plugin path must remove
`ProfileRegistry.resolve` from `modules/combat/module.lua` in the same change, and the swap must be
atomic. There is no safe interval in which both paths are live, and no configuration flag makes one
safe — the interference is through shared blackboard keys, so it does not care which path the operator
believes is authoritative.

The cheap way to make that guarantee mechanical rather than remembered: an offline test asserting that
for any class id, `PROFILE_REGISTRY` and the ACTIVE plugin set are never both non-empty. That is a
property the current tree already satisfies trivially, which is exactly when it is cheapest to pin.

----------

# 15. D15 — Who loads and executes an ADR 07 `kernel::RuntimeProfile`

**Nobody. Measured, on both sides of the boundary. This is the largest gap in the stack, and ADR 08
is where it belongs, so it is specified here rather than left absent.**

## 15.1 The measurement

`rg` over every `.lua` file under `sentinel/` for the ADR 07 artifact's own vocabulary:

| Marker | Hits in all of `sentinel/` |
|---|---|
| `tags_used` | **0** |
| `waypoint_pool` | **0** |
| `unknown_policy` | **0** |
| `terminate_on` | **0** |
| `schema_hash` | **0** |
| `SNTL` (the container magic) | **0** |

Not "partially implemented" — **absent**. No Lua file has ever seen this artifact.

The gap is **symmetric**, which is the part that is easy to miss and changes the priority. Nothing
produces one either:

- `SentinelQuesting/shared/src/kernel/profile.rs::RuntimeProfile` is the ADR 07 type — `magic`,
  `schema_version`, `schema_hash`, `tags_used`, `integrity`, `archetype`, `meta`, `defaults`,
  `waypoint_pool`, `tasks`.
- `Compiler::compile_kernel` in `compiler/src/lib.rs` is the only thing that builds one, and it has
  **zero non-test callers**. The `sentinel-compile` binary (`compiler/src/main.rs`) calls
  `Compiler::compile` — the *other* `RuntimeProfile`.
- Every artifact `compile_kernel` returns carries a `KERNEL_PROFILE_INCOMPLETE` warning enumerating
  its own gaps and ending with the sentence **"Do not execute this artifact."**

That last point is the honest state of affairs and deserves credit rather than embarrassment: the
producer refuses to let a caller mistake a partial artifact for a shippable one. But it means there is
no correct thing for an executor to consume yet, which is why "write the executor" is not the next
action.

## 15.2 What Lua *does* execute, and why it is not a starting point

There are **two Rust types named `RuntimeProfile`** and the Lua runtime consumes the older one:

| | `runtime::RuntimeProfile` (ADR 02/05) | `kernel::RuntimeProfile` (ADR 07) |
|---|---|---|
| Shape | `schema_version: String`, `name`, `operations`, `variables`, `areas`, `npcs`, `quests`, `content_hash` | `magic`, `schema_version: u16`, `schema_hash`, `tags_used`, `integrity`, `archetype`, `meta`, `defaults`, `waypoint_pool`, `tasks` |
| Producer | `Compiler::compile`, wired into the `sentinel-compile` binary | `Compiler::compile_kernel`, no binary |
| Lua consumer | `modules/questing/runtime_profile.lua` — reads `_profile.operations`, `.variables`, `.npcs`, `.content_hash` | none |

`modules/questing/runtime_profile.lua` is a working recovery state machine over the ADR-05 shape, and
§11.2 already rules on its disposition: it is the Quest Activity's execution engine, which is policy,
which is the plugin tier. It is not a kernel component and it is not the ADR 07 loader.

**It is also the wrong dispatch discipline, which settles the "extend or build new" question.**
`RuntimeAction.evaluate_condition` in `modules/questing/runtime_action.lua` has **three** `return true`
fallbacks for a condition it does not recognise, with the rationale stated in a comment: the runtime
should never block an action because it does not know a condition a newer compiler emitted. Action
dispatch is an `if action_type == … elseif …` chain with no registry to enumerate.

That is **fail-open on unknown tags** — the exact inverse of §9.1, and the same failure this repo has
already been bitten by once when `RuntimeCondition` was externally tagged and every non-unit condition
fell through to `true`. The rationale is not stupid, it is just the wrong trade for this artifact:
tolerating an unknown *gate* means running an action the profile said to gate. §9.1's answer is that
the loader refuses the whole artifact up front, so the executor never has to choose between blocking
and guessing. **You cannot get there by adding a fallback to a fail-open dispatcher.** The refusal has
to happen before execution begins, which means a separate loader.

## 15.3 Specification: the loader is kernel, the executor is a plugin

§5's tie-breaker decides this, and it decides it cleanly: **the mechanism is kernel, the decision is a
plugin.**

- **`Sentinel.profile` — the fail-closed loader. KERNEL.** *(A name proposed here, not a thing that
  exists; it belongs on §10's surface when it does.)* It is §9.1, which is already a kernel duty;
  every consumer of a compiled artifact needs it; and it must be arbitrated in the sense that matters
  most — exactly one component may decide an artifact is admissible, or "fail-closed" means "closed
  wherever somebody remembered".
- **The Quest Activity — the executor. PLUGIN**, per §5.3 and §11.2. It decides *what to do* with an
  admitted artifact, and that is policy.

**The loader's contract.** Load returns an artifact or a named refusal — never a partial. Every check
below is a refusal, in this order, and the reason is always named because §12 already establishes that
an anonymous refusal is the RXPGuides / LazyBot failure:

1. `magic ~= "SNTL"` → refuse `bad_magic`.
2. `schema_version` not the compiled-in value → refuse `schema_version_mismatch`.
3. `schema_hash` not the compiled-in hash → refuse `schema_hash_mismatch` (§9.1).
4. **Any tag in `tags_used` without a registered handler → refuse `unregistered_tag:<tag>`.** This is
   the check that makes the whole design work, and it needs something the tree does not have: a
   **handler registry** to assert against. `runtime_action.lua`'s `if/elseif` chain cannot answer "do
   you handle `Op::Delegate`?" — only a table can. Building that registry is a precondition for the
   loader, not a detail of it.
5. Shape validation per node → refuse.
6. `ContentIntegrity` — content hash plus world-source provenance, and the first-touch name probe
   (ADR 07 §5.4.1). `schema_hash` guards the *tag set*; nothing else guards resolved entry ids.

**What the executor needs from the kernel that does not exist.** This is the useful part of specifying
it now — the artifact was designed against this kernel's vocabulary, so the mapping is direct, and it
exposes exactly which kernel services Phase 7 depends on:

| ADR 07 artifact concept | Kernel counterpart | Status |
|---|---|---|
| `Task.complete_when` / `applies_when` / `abort_when` (`Predicate`) | `Sentinel.objectives:satisfied(predicate, snapshot)` → `Truth` (§9.2) | **Absent.** `kernel/truth.lua` is the type; the evaluator is not built |
| `Task.unknown_policy` (§5.1.2) | The policy argument `Truth.resolve` *deliberately has no default* for (§9.2.1) | Type exists, per-task plumbing does not |
| `#sticky` task: hold `channels` at `band` until `terminate_on` | A ControlBroker lease whose TTL is a predicate rather than a tick count (§6.1) | Broker exists; predicate-TTL leases do not |
| `Task.combat` (`CombatPolicy`) | §3.1's combat-as-service policy argument | Phase 6 |
| `waypoint_pool` + route indices | `Sentinel.nav` (async handles, §10) | Nav exists |
| `Op::Travel / Interact / UseItem / Cast / …` | Intents through the IntentQueue (§3.2) | Built and gated |
| `Op::Delegate` | `ActivityStack:delegate` (§6.4) | Built |

Two entries in that table are the whole story. **`terminate_on` is a lease with a predicate TTL** — the
artifact is asking the broker for something it does not offer, and noticing that now is cheaper than
discovering it in Phase 7. And **`Predicate` evaluation is the ObjectiveLedger**, which is the one
"genuinely new" piece from §1 that was never built. Phase 7 is not blocked on a loader; it is blocked
on §9.2.

## 15.4 What is explicitly out of scope here, and what would decide it

Specified above: the loader's ownership, its refusal contract, the handler-registry precondition, and
the executor's disposition as a plugin.

**Not specified, deliberately** — and each is named with what would settle it, because an unspecified
item with no owner is how this section came to be missing in the first place:

| Open | What decides it |
|---|---|
| Offset-indexed lazy access — how the loader reads a 19.7 MB artifact without paying full materialisation | ADR 07 §7's container design and its measured decode budget (~306 ms, ~53 ms of it irreducible LuaJIT table allocation). This is ADR 07's decision; the loader implements it |
| The two BLAKE3 digests and world provenance | `compile_kernel` emits zero placeholders today. Producer-side; ADR 07 §9 tracks it. The loader's checks 3 and 6 are unimplementable until then |
| Resume semantics across sessions | ADR 07's `ResumeCursor` vs. the existing `<profile>.save.json`. Two persistence models for one fact; picking one is Phase 7 scope |
| Whether the Quest Activity is a port of `runtime_profile.lua` or a new engine | Phase 7, once §9.2 exists. §11.2 already rules the file is plugin-tier either way, and §15.2 rules that its *dispatch* cannot be reused |
| The `Predicate` enum's 15 required additions | ADR 07 §5.1.1 specifies them |

**The one-line summary for anyone planning work against this document:** the ADR 07 artifact has a
complete Rust model, a partial and self-deprecating producer, no producer binary, and no consumer of
any kind. Do not schedule the executor before the ObjectiveLedger (§9.2) and the two digests, because
until those exist there is nothing correct for it to execute.

----------

# 16. D16 — Where this document and the built kernel disagree

Every disagreement found while re-measuring, with a verdict on which side is ahead. "The kernel is
ahead" means the code learned something the design had not; "the ADR is ahead" means the design is
still right and the code has not caught up. Both are useful; conflating them is not.

| # | Disagreement | Which is ahead |
|---|---|---|
| 1 | §5.1 marked Snapshot, ControlBroker, IntentQueue, Facts and Objectives all "**New**". Three are built and driven from the tick; two are not. | **Kernel.** §5.1's status column is corrected above. |
| 2 | §5.1 put swing timers inside the Timing service. `kernel/timing.lua` owns GCD and cast timestamps; `combat/swing_tracker.lua` still owns swings. | **ADR.** The "must be authoritative or two plugins double-cast" argument applies to swings too and has not been applied. |
| 3 | §6.1 said "one intent per channel per tick"; §3.2 said one intent *type* per channel and documented deliberate multi-intent commits. The document contradicted itself. | **Kernel**, and §3.2 was already right. Fixed above. |
| 4 | §6.1's lease sample shows `lease:cast(...)`. The shipped caretaker exposes exactly `is_valid`, `owner`, `priority`, `band`, `generation`, `channels`, `has`, `submit`, `release`, `renew` — **one** generic emit verb and no typed one. (§6.1's own prose undercounts it as seven members; it is ten.) | **Undecided, and §6.1 says so.** Either is defensible; shipping one and documenting the other is not. This is the one row where a choice is genuinely owed: change the sample, or add typed verbs. Note the kernel's own reason for the generic verb, recorded in `control_broker.lua` — "any movement or cast verb" is *deliberately absent* so the force-release stays the single `core.input.*` call site. That is an argument the ADR never made and should absorb. |
| 5 | §8.4 said `priority_builder` was "proven by 9 consumers" while §5.4 had already corrected it to 3. | **Kernel.** Fixed above; the file is at `kernel/lib/priority_builder.lua` and consumers reach it as `Sentinel.rotation`. |
| 6 | §8.4 assumes Tier 1 declarative authoring covers ~90% of rotations. The one rotation measured against it ports its 25-entry priority list and **none** of its 37 conditions or 32 actions, because the declarative vocabulary does not exist. | **Kernel**, decisively. `08a_API_GAPS.md` §1 is the finding; all three shipped rotations are Tier 2. |
| 7 | §7 described `runtime/app.lua` as a 4-step frame with two named defects. Seven stages exist and both defects are closed. | **Kernel.** Fixed above. |
| 8 | §10's API surface lists `Sentinel.facts`, `Sentinel.objectives` and `Sentinel.persist`. None exists, and `kernel/api.lua` says so explicitly rather than stubbing them. | **Kernel's *behaviour* is ahead, §10's *list* is ahead as a target.** The kernel is right to refuse to stub; §10 should be read as a roadmap, not an inventory. |
| 9 | §10 lists `Sentinel.intent :move_to, :cast, :target, :interact, :use_item`. The shipped surface is `Sentinel.intent` = the IntentQueue, with the verb in the payload's `type`. | **Kernel.** The verb-in-payload shape is what dedupe and channel binding require (§3.2). §10's per-verb list predates that. |
| 10 | §11.1's promotion list is largely undone: `core/`, `runtime/` and `integrations/` files are still at their original paths. Only `priority_builder` and the two catalogs actually moved. | **ADR.** The promotions are still the right target; they have not happened. Note `runtime/app.lua` is now the kernel's composition root *in function* while still living outside `kernel/` *in path*. |
| 11 | §11.5's seven deletions: none done. | **ADR.** Recorded in §11.5. |
| 12 | §11 quoted "605 passed / 0 failed". Measured 1,117 / 0 on `62c98de`, and the harness's counting rule changed underneath the comparison. | **Kernel.** Corrected in §11, with the reason the two figures are not comparable. |
| 13 | §12 phases 5, 6 and 7 have no code at all; the table gave no way to tell that from phases 1–3, which are complete. | **Kernel.** §12.1 now carries the per-phase verdict. |
| 14 | §13's risk register carried no dates or verdicts, so a discharged risk and an untouched one read identically. | **Kernel.** Every item now carries a verdict. |
| 15 | §13.1 item 15 said "nothing in production emits an intent". Six production submit sites now exist — all inside rotation packages that never load (§14). | **Both, in different senses.** The emitters are written; nothing emits. The item's *wording* is closed and its *substance* is not. |
| 16 | ADR 07's artifact vocabulary appears **nowhere** in `sentinel/`, and ADR 08 did not say who would consume it. | **Neither — it was a hole in the design.** §15 fills it. |
| 17 | §5's combat disposition, and the two tree headers that once claimed "combat registers through the plugin registry". | **ADR, after correction.** §5 now states the rule those headers had to guess at. Kept as the example of what an unstated decision costs: two files asserted the opposite of the truth, and the document that should have settled it was silent. |

**The pattern across seventeen rows.** Twelve are the document lagging code that got built; five are
code lagging a design that is still right. Only one — row 4 — is a genuine open disagreement where
neither side is ahead and a choice is owed.

That ratio is the healthy direction for an ADR whose phases are being delivered, and it is also the
warning: a design document that lags its implementation by twelve rows stops being consulted, and the
first symptom is exactly what §5 recorded — people write code against what they guess the document
would have said. **Re-measure §12.1, §13 and §16 at the end of every phase.** They are the three
sections whose value decays.
