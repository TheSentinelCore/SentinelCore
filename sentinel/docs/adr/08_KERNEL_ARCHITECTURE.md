
# 08_KERNEL_ARCHITECTURE.md

## Sentinel

### Kernel and Plugin Architecture — API-first bot on Project Sylvanas

**Version:** 1.0 Draft
**Status:** Proposal
**Supersedes:** the uncommitted `ADR-000 — Sentinel Kernel: API-First Plugin Architecture` proposal
**Supersedes:** the current `module_registry` peer-module design (combat p10 / questing p50)
**Consumed by:** `07_RUNTIME_PROFILE_SCHEMA.md` (the Quest Activity's artifact)

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

**One intent per channel per tick, under the lease that authorised it.** Two rules, and the second is
the one that is easy to lose:

- A channel commits at most one intent per tick. Two `move` intents in one tick are not "both
  applied" — they are an unresolved contention that the broker exists to resolve *before* commit, and
  silently taking the last one writes the arbitration policy into an ordering accident.
- An intent may only act inside the lease that authorised it. An intent that outlives its lease, or
  that acts on a channel its lease does not cover, is the revocation race §6.1's generation counter
  closes. Emitting one is a defect even when it happens to work.

**`move` is a desired state, not an imperative.** The name reads like a command and is not one: a
`move` intent commits by *recording the desired key state* and touching no key. The keys are driven
later in the same COMMIT stage by `movement_release.reconcile`, once the queue has drained and the
tick's desire is final. That ordering is deliberate — reconciling mid-drain would act on a desire that
a later intent in the same tick could still change.

Two things follow. Reconciliation is COMMIT's work and not ACCOUNT's, so it sits inside the frame
budget it costs rather than after the measurement. And because `move` declares rather than acts,
`release_all` can clear the desire without the broker needing to know the reconciler exists.

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

## 5.1 Kernel — non-negotiable

| Subsystem | Why it cannot be a plugin | Status today |
|---|---|---|
| **Scheduler** | One thing drives the tick; also enforces per-plugin frame budget. No documented tick rate exists (§2.5), so it derives cadence from `core.delta_time`. | `runtime/app.lua:62-90` — exists, 4-step frame |
| **Snapshot** | Sense once per tick, frozen, **values not handles** (§2.7). Independent scanning gives O(n×m) and inconsistent views inside one tick. | **New.** `core/blackboard.lua` is mutated live and its `snapshot(prefix)` has *zero callers*. |
| **ControlBroker** | §6. The arbiter. | **New** |
| **IntentQueue** | §3.2. The commit choke point, layered over `spell_queue` (§2.6). | **New** |
| **EventBus** | Singleton by nature. | `core/event_bus.lua:54-81` — sync, per-handler pcall, re-publishes `system:error` |
| **Timing** | GCD, cast/channel state, swing timers, cooldowns. Must be authoritative or two plugins double-cast. Owns the two-clock problem (§2.5). | Partial — `combat/cooldown_tracker.lua`, `swing_tracker.lua` |
| **Catalogs** | Shared reference data; duplicating it costs memory and drifts. | Partial — `combat/spell_catalog.lua`, `aura_catalog.lua` (both need rework) |
| **Nav** | Wraps SentinelNavClient. One path at a time; coupled to `MOVEMENT`. | `integrations/nav_client/adapter.lua` (392 lines, mature) |
| **ErrorBoundary + Quarantine** | Mandatory once third-party code runs. No engine-level error isolation is documented — every callback must self-pcall. | `core/error_boundary.lua` + `module_registry.lua:232-270` **3-strike DEGRADED already implemented** |
| **Facts** | Per-tick memoized derived truth. The `snapshot` argument to `objectives:satisfied()`. | **New** |
| **Objectives** | §9.2. Single completion authority. | **New** |
| **Config + UIHost** | Plugins declare schema; kernel renders and persists. **Menu IDs share one global namespace**, so allocation must be centralised. | Partial — `main.lua` owns frames |
| **Persist** | Namespaced save state. Sandboxed to `scripts_data/`; no `io` table in-game. | Partial — questing `.save.json` |
| **Log** | With plugin attribution, or this is undebuggable. | Partial |

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
- **TTL on every lease.** A plugin that faults mid-tick cannot permanently hold `MOVEMENT`. Leases
  are Gray & Cheriton's core idea — authority reverts at term end *without the holder's cooperation*,
  which is exactly why a wedged holder cannot deadlock the resource.
- **Preemption fires `on_revoke`.** For `MOVEMENT` this is safety-critical, not cosmetic (§2.8): the
  kernel force-releases movement keys after calling `on_revoke`, because a plugin that ignores the
  callback would otherwise leave the character running. The force-release must also stop navigation,
  which is a co-authority over the same motion and is not reached by releasing keys (§2.8.1).
- **One intent per channel per tick, and only under the lease that authorised it** (§3.2). The lease
  is what makes an intent legible: an intent that cannot be traced to a live lease cannot be gated,
  cannot be revoked, and cannot be attributed when it misbehaves.
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

`runtime/app.lua:62-90` already implements a 4-step version of this
(`callback_bridge → sensor_hub:refresh → nav_adapter:poll → registry:tick_all`). Two defects to fix
while promoting it: `nav_adapter:poll()` at `app.lua:68` is **not** error-wrapped while its neighbours
are, and `_izi_bridge` at `app.lua:29` is constructed and never read.

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

Tier 1 is built on `priority_builder.lua`, which is proven in-tree by 9 consumers — **not** on
LazyBot's `PAction` lists, which never ran (§2.9).

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

**Nav is async.** `request_path` returns a handle; the tick never blocks on the NavServer.

```lua
local h = Sentinel.nav:request_path(from, to)
if h:ready() then lease:follow(h:path()) end
```

`_G.Sentinel` is published behind a live-getter metatable (§2.4) plus a deferred `__SentinelPending`
registration queue drained on init and re-drained for the first ~60 ticks.

----------

# 11. D11 — Migration from the current tree

The inventory verdict, condensed. **This is promotion, not a rewrite** — and the offline suite
currently reports **605 passed / 0 failed**.

That figure previously read *"127 passed / 1 failed (the failure is in questing vendor maintenance)"*.
Both halves were stale, and the second half was also a misattribution: the vendor failure was not a
pre-existing module bug but a symptom of an uncommitted re-scan in `execute_vendor` on the working
tree at the time. Committed `HEAD` was green. **A baseline recorded from a dirty tree is not a
baseline** — it attributes the author's work-in-progress to the codebase, and the resulting "known
failure" then gets budgeted for rather than fixed.

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

## 11.6 Testability debt to clear first

`SentinelApp:new()` and `initialize()` are **provably untestable offline** because
`integrations/izi_bridge.lua:6` does an unguarded `require("common/izi_sdk")`, an injector-only module.
`tests/runtime/test_app_tick.lua:23-26` documents this and hand-stubs the whole app to work around it.

So the file that encodes the kernel's boot contract is asserted by nobody. Fix this in Phase 1 — guard
the require — or the kernel inherits an untestable composition root.

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

**Risks.**

1. **Two-phase intent commit costs a tick of latency** on reactive abilities. Mitigated by
   `immediate = true` at band ≥ 70, still gated. Watch it in Phase 4.
2. **The frozen snapshot is new and subtle.** Storing values rather than handles (§2.7) means the
   sensor layer decides *in advance* what downstream consumers may ask about. Under-capture forces a
   mid-tick live read, which reintroduces exactly the inconsistency the snapshot exists to prevent.
3. **Timing is the highest-bug-density service** (§2.5): two incompatible clocks, one API mixing units
   inside a single return value, and a GCD remainder that must be inferred. It needs disproportionate
   test coverage.
4. **`applies_to` / `ELIGIBLE` is over-engineering for one character.** Correct and cheap, but do not
   build multi-spec resolution until there is a second rotation.
5. **Rewrite risk.** The combat DSL, target selector and BT library are the mature parts. Port them;
   do not rewrite them. The genuinely new code is the broker, the intent queue, the snapshot and the
   ledger.
6. **Do not cache predicates that depend on live state.** RXPGuides caches gate results in a table
   (`GuideLoader.lua:29`) that is **never invalidated anywhere in the addon**, and reads `playerLevel`
   *inside* the cached computation — so level-conditional content freezes at whatever level the player
   was on first evaluation. Facts must be per-tick memoized, never persistent.

**Open questions.**

7. **No documented tick rate.** `on_render` is once per frame; `on_update` is described *both* as
   "reduced speed, relative to On Render" *and* "executed on each frame update" in the same file. The
   scheduler must measure rather than assume — but the frame-budget design depends on knowing the
   real cadence. Measure it in Phase 1.
8. **The per-plugin callback cap is undocumented.** We are near it already with 7 callbacks in
   `main.lua`. If UIHost needs more, we may hit an undocumented ceiling.
9. **No vendor/merchant frame-open predicate exists**, so the vendor behaviour cannot reliably detect
   its own modal state. `MODAL_UI` gives us a *claim* but not an *observation*.
10. **No documented unload/teardown callback.** The `{ name, version, unload }` return-table
    convention used by all three plugins in this repo is **not documented anywhere** in the Sylvanas
    docs. We rely on undocumented behaviour for cleanup.
11. **Escort quests have no owner.** Starting one is `Op::Interact`; following and protecting an NPC
    is a behaviour nothing in this design covers. It appears in the guide corpus only as human prose.
12. **Coroutines are undocumented and unused anywhere in this repo.** If they work, incremental
    long-running work (profile prefetch, large route computation) gets much easier. Worth a Phase 1
    spike.
13. **`Facts` vs `Objectives` boundary.** They are distinct — Facts is the per-tick memoized truth
    cache, Objectives is the evaluator over a compiled `Predicate` AST, and Objectives consumes Facts
    as its `snapshot` argument. Both are new; the risk is that they blur under implementation
    pressure and we recreate scattered completion truth inside the kernel.
