# Quest Authoring IDE
## Volume 9 — Sylvanas Addon API Integration Layer

Version: 1.1
Status: Verified — API details confirmed against Sylvanas documentation

---

# 0. Why This Volume Exists

Every prior volume treats "the Sylvanas API" as a box on a diagram:

```
Volume 1  §0 header    "Target UI: In-game Overlay (ImGui-style assumed
                        until Sylvanas Addons API confirms otherwise)"

Volume 2  §2, §10      Event Pipeline diagram has a box labeled
                        "Sylvanas API" between Game and Event Dispatcher

Volume 2  §18           Query Client talks to QueryServer, not the game
                        — but never states what talks to the game

Volume 3  §8, §19, §20  Capture Panel, Path Recorder, Polygon Recorder
                        all assume live target/position data from
                        somewhere

Volume 8  §20           Explicitly hands this off as the Volume 9 topic
```

This volume defines that box. Everything here sits at the seam between
Sentinel and the actual WoW client — it is the only place in the whole
system where "the game" is a real dependency instead of a database or a
compiled data structure.

---

# 1. Two APIs, Two Jobs

Project Sylvanas exposes (per the original project research) two
distinct API surfaces, and this volume treats them as two distinct
integration concerns rather than one blob:

```
Quest API     → interaction primitives: accept, turn in, read quest
                 log, objective status, gossip, trainer interaction

Addons API     → overlay rendering, input handling, targeting,
                 world/unit queries, event hooks
```

The Quest API is what the **Action Executor** (Volume 2 §6) calls when
running a compiled `RuntimeAction`. The Addons API is what the
**editor's capture workflow** (Volume 3) and the **runtime's event
pipeline** (Volume 2 §10) both depend on. They have different
consumers, different failure modes, and should not share one wrapper.

---

# 2. Design Goals

- **Thin** — this layer translates, it does not decide. No planning
  logic, no optimization, no state beyond what's needed to translate
  a call or an event.
- **Hide the raw API** — nothing outside this layer calls a Sylvanas
  function directly. Everything else in Sentinel — Action Executor,
  capture panel, event dispatcher — talks to this layer's trait
  interface.
- **Testable without a game client** — a mock implementation of every
  trait in this volume must exist, so the Compiler, QueryServer, and
  editor logic can all be tested in CI without WoW running.
- **Fail loud, fail locally** — if the Sylvanas API changes shape or an
  addon isn't loaded, that failure should surface as a clear diagnostic
  at this boundary, not as a mysterious null somewhere in the Action
  Executor three layers up.
- **Renderer-agnostic where the answer isn't known yet** — see §7.

---

# 3. Architecture

```
                    Editor (Volume 3)
                          │
              Capture calls, render calls
                          │
                          ▼
              ┌─────────────────────────┐
              │   sentinel-bridge        │
              │                           │
              │   AddonsClient trait      │
              │   QuestClient trait        │
              │   RenderSurface trait      │
              └─────────────┬─────────────┘
                            │
                    Sylvanas Addon API
                    Sylvanas Quest API
                            │
                            ▼
                        Game Client


              Action Executor (Volume 2 §6)
                          │
                 RuntimeAction execution
                          │
                          ▼
              ┌─────────────────────────┐
              │   sentinel-bridge        │
              │   (same QuestClient)      │
              └─────────────┬─────────────┘
                            │
                            ▼
                    Sylvanas Quest API
```

Both the editor and the runtime depend on the same `sentinel-bridge`
crate. Neither depends on the other, and neither talks to Sylvanas
directly. This mirrors the same principle Volume 4 established for
QueryServer ("the editor should never query SQLite directly") — applied
here to the live game connection instead of the static database.

---

# 4. QuestClient Trait

```rust
pub trait QuestClient {

    fn accept_quest(&self, npc: NpcHandle, quest_id: u32) -> Result<(), BridgeError>;

    fn turn_in_quest(&self, npc: NpcHandle, quest_id: u32, reward_choice: Option<u32>) -> Result<(), BridgeError>;

    fn quest_log_entry(&self, quest_id: u32) -> Result<Option<QuestLogEntry>, BridgeError>;

    fn objective_status(&self, quest_id: u32) -> Result<Vec<ObjectiveStatus>, BridgeError>;

    fn gossip_options(&self, npc: NpcHandle) -> Result<Vec<GossipOption>, BridgeError>;

    fn select_gossip(&self, npc: NpcHandle, option: GossipOption) -> Result<(), BridgeError>;

    fn trainer_interact(&self, npc: NpcHandle) -> Result<TrainerMenu, BridgeError>;

}
```

`NpcHandle` wraps GUID strings from `get_guid()`. Every `RuntimeAction` variant that maps to a
quest interaction (`PickupQuestAction`, `TurnInQuestAction`,
`TrainAction`, and the gossip portion of `TalkToNpc`) lowers to exactly
one `QuestClient` call.

**Lua Implementation Note:** The actual `core.quests.*` API is frame-centric:
- `accept_quest()` / `complete_quest()` take no parameters - require dialog open
- Quest log queries iterate by index, not by quest_id
See `integrations/sentinel_bridge/quest_bridge.lua` for the adapter.

---

# 5. AddonsClient Trait

```rust
pub trait AddonsClient {

    fn current_target(&self) -> Result<Option<UnitHandle>, BridgeError>;

    fn player_position(&self) -> Result<Waypoint, BridgeError>;

    fn nearby_units(&self, radius: f32) -> Result<Vec<UnitHandle>, BridgeError>;

    fn nearby_game_objects(&self, radius: f32) -> Result<Vec<GameObjectHandle>, BridgeError>;

    fn unit_info(&self, unit: UnitHandle) -> Result<UnitInfo, BridgeError>;

    fn subscribe(&self, event: GameEvent, handler: EventHandler) -> SubscriptionHandle;

    fn unsubscribe(&self, handle: SubscriptionHandle);

}
```

This is what backs Volume 3's capture workflow directly:

```
Target Capture Panel  → current_target() + unit_info()
Path Recorder          → player_position(), sampled on a timer
Polygon Recorder        → player_position(), sampled on vertex placement
NPC role detection      → unit_info() combined with QueryServer lookup
```

Note the split: **live identity and position** come from `AddonsClient`;
**semantic knowledge** (is this NPC a vendor, what does it sell) still
comes from QueryServer (Volume 4). This layer never duplicates the
Mangos database — it only supplies what QueryServer structurally cannot
know, because QueryServer has no concept of "where the player currently
is."

---

# 6. Event Bridge

Volume 2 §10 defined a semantic event vocabulary (`QuestAccepted`,
`InventoryChanged`, `QuestCompleted`, `NPCReached`, `VendorVisited`,
`FlightLearned`, `AreaEntered`) but never specified where those events
originate. They originate here, as a translation table between raw
`GameEvent` values from `AddonsClient::subscribe` and Volume 2's
semantic events:

```
Raw GameEvent                    Semantic Event (Volume 2 §10)

QUEST_LOG_UPDATE          →      QuestAccepted / QuestCompleted
                                   (diffed against last known quest log
                                    state — see below; requires polling since
                                    no push event exists)

BAG_UPDATE                →      InventoryChanged

PLAYER_MOVED (polled)      →      NPCReached (when within an Action's
                                    arrival_radius), AreaEntered (when
                                    crossing a zone/subzone boundary,
                                    checked against QueryServer)

TAXINODE_LEARNED           →      FlightLearned
```

`QuestAccepted` and `QuestCompleted` specifically require diffing two
`quest_log_entry()` snapshots rather than trusting a single raw event,
because a single `QUEST_LOG_UPDATE` firing doesn't say *which* quest
changed or in *which* direction. This diffing logic lives in the Event
Bridge, not in the Runtime Event Dispatcher — the Dispatcher (Volume 2
§10) should only ever see clean, unambiguous semantic events.

---

# 7. Overlay Rendering — Confirmed Immediate-Mode (2026-07-18)

The Sylvanas Addons API explicitly supports immediate-mode overlay drawing via:
- `core.register_on_render_callback()` — for graphics rendering
- `core.register_on_render_window_callback()` — for window-style panels
- `core.graphics` module with SDF shaders for panels, text, and primitives

This confirms Volume 1's "ImGui-style assumed" guess. The `RenderSurface` trait
maps directly to these callbacks.

---

# 8. Capture Flow, End to End

Tying Volume 3's UX to this volume's primitives, using the Target
Capture Panel (Volume 3 §8) as the concrete example:

```
Author targets an NPC in-game

    │
    ▼
AddonsClient::current_target() → UnitHandle

    │
    ▼
AddonsClient::unit_info(handle) → position, GUID, faction, reaction

    │
    ▼
QueryServer lookup on entry ID → name, known roles, zone (Volume 4 §8)

    │
    ▼
Editor merges live + database data → NpcReference (Volume 5)

    │
    ▼
Author clicks "Quest Giver" → NpcReference added to Profile's
NPC Library, tagged with QuestGiver role
```

No step in this flow requires the author to type an ID, a name, or a
coordinate — which was Volume 1 §15's explicit success criterion. This
volume is what actually makes that promise deliverable rather than
aspirational.

---

# 9. Action Execution Flow

The mirror case, for a compiled `RuntimeAction` (Volume 8 §10) being
executed:

```
Action Executor (Volume 2 §6) receives RuntimeAction

    │
    ▼
Match on ResolvedActionPayload

    │
    ├── PickupQuestAction  → QuestClient::accept_quest(npc, quest_id)
    │
    ├── TurnInQuestAction  → QuestClient::turn_in_quest(npc, quest_id, reward)
    │
    ├── TrainAction        → QuestClient::trainer_interact(npc), then
    │                         resolve requested spell against TrainerMenu
    │
    ├── GoToAction         → NOT this layer's concern. Per Volume 1 §3,
    │                         navigation is out of scope; this action
    │                         type is handed to the existing navigation
    │                         layer as a goal, not executed here.
    │
    └── KillTargetAction   → NOT this layer's concern. Handed to the
                              existing combat layer as a goal, same as
                              GoToAction.
```

This is the concrete boundary the Non-Goals section in Volume 1 §3 was
gesturing at: Sentinel's bridge layer owns quest interaction and world
sensing, and explicitly does not own movement or combat execution — it
only formulates *what* those systems should accomplish and passes that
intent along, exactly as the original bot-design research described
("Navigation shouldn't receive Go to X — instead, Goal: Complete Quest
1234").

---

# 10. Error Handling

```rust
pub enum BridgeError {

    ApiUnavailable,

    NpcNotFound,

    QuestNotFound,

    InteractionOutOfRange,

    Timeout,

    UnexpectedGameState(String),

}
```

Every `BridgeError` propagates up through the Action Executor as a
retryable failure (Volume 5's `RetryPolicy`, already defined per-Action)
rather than a hard crash. `ApiUnavailable` specifically — meaning
Sylvanas itself isn't responding, not that a specific NPC/quest lookup
failed — should halt the current Operation and surface a top-level
diagnostic rather than retrying blindly, since retrying against an
unavailable API wastes time without ever succeeding.

---

# 11. Mock Bridge

```rust
pub struct MockBridge {

    pub quest_log: RefCell<HashMap<u32, QuestLogEntry>>,

    pub player_position: RefCell<Waypoint>,

    pub scripted_responses: RefCell<VecDeque<ScriptedResponse>>,

}
```

Implements both `QuestClient` and `AddonsClient` entirely in memory.
This is what makes Volume 8 §18's Northshire compile-and-execute trace
testable in CI: script the mock to report quest 33 as accepted after
`accept_quest` is called, feed that through the real Event Bridge
translation logic, and assert the Runtime Event Dispatcher receives a
clean `QuestAccepted` event — without a WoW client anywhere in the test.

---

# 12. Versioning and API Drift

Sylvanas's own API surface can change between client patches or
Sylvanas releases. This layer isolates that risk the same way
QueryServer isolates Mangos schema risk (Volume 4 §29's
`WorldProvider` trait pattern):

```rust
trait SylvanasApiVersion {

    fn quest_client(&self) -> Box<dyn QuestClient>;

    fn addons_client(&self) -> Box<dyn AddonsClient>;

}
```

A version mismatch at startup should produce a clear, actionable error
— "Sentinel bridge built against Sylvanas API vN, detected vM" — rather
than a wrapper silently missing fields or panicking on an unexpected
struct layout deep in a capture call.

---

# 13. Module Layout

```
sentinel-bridge

├── quest_client
├── addons_client
├── render_surface
├── event_bridge
│   ├── translation
│   └── quest_log_diff
├── mock
├── errors
└── versioning
```

---

# 14. What This Volume Deliberately Does Not Cover

- **Combat and navigation execution** — explicitly out of scope per
  Volume 1 §3 and §9 above; this layer only formulates goals for those
  existing systems, never executes them.
- **Telemetry storage** — the Event Bridge produces events; what happens
  to them after the Runtime Event Dispatcher receives them (aggregation,
  persistence, the Analytics panel) is Volume 10's job, not this one's.
- **On-disk profile format** — irrelevant to this volume; this is purely
  the live-game seam. Volume 11's job.

---

# 15. Design Decisions

## Why split QuestClient from AddonsClient instead of one GameClient trait?

Different failure semantics and different consumers. A `QuestClient`
call failing mid-Operation is a runtime execution problem with a retry
policy attached. An `AddonsClient` call failing during authoring is an
editor UX problem — the author just sees "capture failed, try again."
Conflating them would force one error-handling strategy onto two
situations that need different ones.

## Actual API Confirmation (vs §16 placeholders)

The actual Sylvanas API (`core.quests` and `core.game_ui`) differs from the
original Rust-trait placeholders as follows:

| Placeholder Trait Method | Actual Sylvanas API |
|---------------------------|---------------------|
| `accept_quest(npc, quest_id)` | `core.quests.accept_quest()` — no params; requires quest dialog open |
| `turn_in_quest(npc, quest_id, reward)` | `core.quests.complete_quest()` — no params; assumes dialog open |
| `quest_log_entry(quest_id)` | `core.game_ui.get_quest_log_info(index)` + `core.quests.get_quest_log_title(index)` |
| `trainer_interact(npc)` | `core.quests.get_trainer_service_info(index)` then `buy_trainer_service(index)` |

The Lua API is **frame-centric**: quest interactions require the NPC dialog
to be open, and state is queried by iterating quest log indices (not quest IDs).
The Rust wrapper will need to:

1. Accept quest: Target NPC → interact → wait for dialog → call `accept_quest()`
2. Turn in quest: Target NPC → interact → wait for dialog → call `complete_quest()`
3. Quest log query: Iterate `get_quest_log_count()` and call `get_quest_log_info(i)`

**NPC/Unit Identity**: Uses GUID strings (`get_guid()`) as primary identity.
`get_npc_id()` returns the entry ID when available. Resolved via
`core.object_manager.get_object_from_guid(guid)`.

**Quest Log State**: Queryable on demand via `core.game_ui.get_quest_log_info()`
and `core.quests.get_quest_log_title()`. No push event for quest log changes;
the Event Bridge must poll on a timer (e.g., 500ms) to detect changes.

**Rendering**: Immediate-mode via `core.register_on_render_callback()` and
`core.register_on_render_window_callback()`. Full graphics suite with SDF shaders
in `core.graphics` (lines, circles, rectangles, textures, 2D/3D text). This is
ImGui-style immediate mode, NOT native Frame/XML construction.

## Why does the Event Bridge diff quest log snapshots instead of trusting raw events?

Because the raw `QUEST_LOG_UPDATE` event (assumed name, see §15) doesn't
carry enough information to know which semantic event actually
occurred. Diffing against known state is the only way to produce the
unambiguous events Volume 2's Runtime Context already assumes it's
receiving.

## Why leave RenderSurface abstract instead of picking ImGui or native frames now?

Because picking wrong here is expensive — Volume 3's entire UI spec
would need no changes either way, but every concrete panel
implementation would need a rewrite if the wrong backend gets locked in
before the actual API is confirmed. One unresolved trait is cheaper than
a wrong commitment.

---

# 16. Verification Resolved (2026-07-18)

Confirmed against `Documentation - Project Sylvannas/dev/api/`:

| Question | Answer |
|----------|--------|
| Function names | `core.quests.accept_quest()`, `core.quests.complete_quest()`, `core.quests.get_quest_log_title()`, `core.quests.get_gossip_options()`, `core.quests.buy_trainer_service()` |
| NPC identity | GUID strings (`get_guid()`) are the primary identity. Entry ID available via `get_npc_id()`. |
| Addons API rendering | Immediate-mode via `register_on_render_callback()`. Full graphics suite in `core.graphics` with SDF shaders. NOT native Frame/XML. |
| Quest log queryability | On-demand via `core.game_ui.get_quest_log_info()` and `core.quests` functions. No push events; Event Bridge must poll. |
| Thread affinity | All API calls run on main thread; callbacks fire within Sylvanas tick context (`on_update`). No special threading concerns. |

The architecture in this volume remains valid. The Lua implementation uses the
actual `core.*` function names, while the trait boundaries abstracted by this
volume hide those details from the rest of Sentinel.

---

# 17. Before Volume 10

With this volume, every piece of the pipeline from "author captures an
NPC in-game" through "compiler produces a RuntimeProfile" through
"Action Executor calls the Quest API" is now specified. What's still
open is what happens to the data generated *while* that pipeline runs —
Volume 2 §21 and Volume 7 §19 both assume a telemetry stream exists, and
this volume's Event Bridge is exactly what would feed it, but nothing
yet defines where that data goes, how it's aggregated across runs, or
what the Analytics panel (Volume 3 §5, §16) actually renders.

Volume 10 should define that: the Analytics & Telemetry System.

---

End of Volume 9
