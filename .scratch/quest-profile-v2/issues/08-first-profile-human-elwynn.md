---
id: 8
title: "First Profile — Alliance Human 1-10 Elwynn Forest"
state: done
labels: ["enhancement", "ready-for-agent", "area:quest", "priority:high", "size:large"]
created: "2026-07-16T00:00:00Z"
updated: "2026-07-16T00:00:00Z"
---

# First Profile — Alliance Human 1-10 Elwynn Forest

## Description

Write the complete `alliance_human_01_10_elwynn.yaml` profile implementing the Northshire → Goldshire → Eastvale → Jasperlode leveling path. This is the validation target for the entire v2 system.

## Profile Structure

```yaml
schemaVersion: "2.0"
profile:
  id: "alliance_human_01_10_elwynn"
  name: "Human 1-10 Elwynn Forest"
  author: "Sentinel"
  expansion: "TBC"
  faction: "Alliance"
  race: ["Human"]
  class: ["*"]
  levelRange: {min: 1, max: 10}

variables:
  playerLevel: {type: "number", bind: "player.level"}
  bagSlotsFree: {type: "number", bind: "inventory.freeSlots"}
  durabilityPct: {type: "number", bind: "equipment.lowestDurabilityPct"}
  activeQuest: {type: "number", init: null}
  phase: {type: "string", init: "northshire"}
  hearthstoneBound: {type: "boolean", init: false}

states:
  Questing:
    type: "exclusive"
    initial: "Initialize"
    states:
      Initialize:
        type: "atomic"
        onEnter: ["core.log('Profile starting: Human 1-10 Elwynn')"]
        transitions:
          - event: "ProfileStart"
            target: "AcceptNorthshireQuests"

      AcceptNorthshireQuests:
        type: "atomic"
        onEnter:
          - "coreActions.quest.acceptAllQuestsAtNpc(197)"  -- Marshal McBride
          - "profile.activeQuest = 783"
        transitions:
          - event: "QuestAccepted"
            guard: "event.questId == 783"
            target: "TravelToKoboldCamp"
            actions: ["profile.phase = 'kobolds'"]

      TravelToKoboldCamp:
        type: "atomic"
        onEnter:
          - "coreActions.nav.followPolicy('northshire_to_kobolds')"
        transitions:
          - event: "NavigationArrived"
            guard: "event.policy == 'northshire_to_kobolds'"
            target: "KillKobolds"

      KillKobolds:
        type: "atomic"
        meta:
          objectiveGroup: "Northshire Kobolds"
          objectiveType: "kill"
          questIds: [783]
          npcIds: [80, 257]
        onEnter:
          - "coreActions.combat.setTargetFilter({80, 257})"
        transitions:
          - event: "ObjectiveProgress"
            guard: "event.questId == 783 and event.current >= 10"
            target: "TurnInKoboldCleanup"
        onExit:
          - "coreActions.combat.clearTargetFilter()"

      TurnInKoboldCleanup:
        type: "atomic"
        onEnter:
          - "coreActions.nav.followPolicy('kobolds_to_northshire')"
        transitions:
          - event: "NavigationArrived"
            guard: "event.policy == 'kobolds_to_northshire'"
            target: "AcceptNextNorthshire"
            actions: ["coreActions.quest.turnInQuest(783)"]

      AcceptNextNorthshire:
        type: "atomic"
        onEnter:
          - "coreActions.quest.acceptAllQuestsAtNpc(197)"
        transitions:
          - event: "QuestAccepted"
            guard: "event.questId in {7, 15, 3104}"
            target: "TravelToGoldshire"

      TravelToGoldshire:
        type: "atomic"
        onEnter:
          - "coreActions.nav.followPolicy('northshire_to_goldshire')"
        transitions:
          - event: "NavigationArrived"
            guard: "event.policy == 'northshire_to_goldshire'"
            target: "GoldshireHub"

      GoldshireHub:
        type: "compound"
        meta:
          objectiveGroup: "Goldshire Hub"
        initial: "AcceptGoldshireQuests"
        states:
          AcceptGoldshireQuests:
            type: "atomic"
            onEnter:
              - "coreActions.quest.acceptAllQuestsAtNpc(295)"  -- Remy "Two Times"
              - "coreActions.quest.acceptAllQuestsAtNpc(296)"  -- Marshal Dughan
              - "coreActions.quest.acceptAllQuestsAtNpc(297)"  -- William Pestle
              - "coreActions.quest.acceptAllQuestsAtNpc(298)"  -- Auntie Bernice
              - "coreActions.quest.acceptAllQuestsAtNpc(299)"  -- Smith Argus
            transitions:
              - event: "QuestAccepted"
                guard: "event.questId in {54, 87, 91, 2158, 47}"
                target: "GoldshireObjectives"

          GoldshireObjectives:
            type: "exclusive"
            initial: "KillKoboldsGoldshire"
            states:
              KillKoboldsGoldshire:
                type: "atomic"
                meta:
                  objectiveGroup: "Goldshire Kobolds"
                  objectiveType: "kill"
                  questIds: [54]
                  npcIds: [474]
                onEnter:
                  - "coreActions.combat.setTargetFilter({474})"
                  - "coreActions.nav.followPolicy('goldshire_kobold_camp')"
                transitions:
                  - event: "ObjectiveProgress"
                    guard: "event.questId == 54 and event.current >= 10"
                    target: "CollectApples"
                onExit:
                  - "coreActions.combat.clearTargetFilter()"

              CollectApples:
                type: "atomic"
                meta:
                  objectiveGroup: "Goldshire Apples"
                  objectiveType: "collect"
                  questIds: [87]
                  itemId: 1930
                transitions:
                  - event: "ObjectiveProgress"
                    guard: "event.questId == 87 and event.current >= 4"
                    target: "KillMurlocs"

              KillMurlocs:
                type: "atomic"
                meta:
                  objectiveGroup: "Goldshire Murlocs"
                  objectiveType: "kill"
                  questIds: [91]
                  npcIds: [482, 483]
                onEnter:
                  - "coreActions.combat.setTargetFilter({482, 483})"
                  - "coreActions.nav.followPolicy('goldshire_murloc_coast')"
                transitions:
                  - event: "ObjectiveProgress"
                    guard: "event.questId == 91 and event.current >= 8"
                    target: "TurnInGoldshire"
                onExit:
                  - "coreActions.combat.clearTargetFilter()"

              TurnInGoldshire:
                type: "atomic"
                onEnter:
                  - "coreActions.nav.followPolicy('goldshire_to_town')"
                transitions:
                  - event: "NavigationArrived"
                    guard: "event.policy == 'goldshire_to_town'"
                    target: "TravelToEastvale"
                    actions:
                      - "coreActions.quest.turnInQuest(54)"
                      - "coreActions.quest.turnInQuest(87)"
                      - "coreActions.quest.turnInQuest(91)"

          TravelToEastvale:
            type: "atomic"
            onEnter:
              - "coreActions.nav.followPolicy('goldshire_to_eastvale')"
            transitions:
              - event: "NavigationArrived"
                guard: "event.policy == 'goldshire_to_eastvale'"
                target: "EastvaleObjectives"

          # ... continue: Eastvale Logging Camp → Jasperlode Mine → Level 10

      Finished:
        type: "final"
        onEnter: ["core.log('Profile complete: Human 1-10 Elwynn')"]

  Survival:
    # Standard regions from ADR-0004 template
    type: "parallel"
    regions:
      HealthManagement: {...}
      Combat: {...}
      Safety: {...}

  Logistics:
    type: "parallel"
    regions:
      Inventory: {...}
      Equipment: {...}
      Travel: {...}

actions:
  # Core actions referenced by "coreActions." prefix
  # Profile-specific composite actions
  smartTurnIn: |
    local questId = profile.activeQuest
    if not questId then return false end
    local reward = coreActions.engine.selectBestReward(questId, profile.playerClass)
    return coreActions.quest.turnInQuest(questId, reward)
```

## Routing Policies Required

| Policy Name | From → To |
|-------------|-----------|
| `northshire_to_kobolds` | Northshire Abbey → Kobold Camp |
| `kobolds_to_northshire` | Kobold Camp → Northshire Abbey |
| `northshire_to_goldshire` | Northshire Abbey → Goldshire |
| `goldshire_kobold_camp` | Goldshire → Kobold Camp (north) |
| `goldshire_murloc_coast` | Goldshire → Murloc Coast (east) |
| `goldshire_to_town` | Farm areas → Goldshire town |
| `goldshire_to_eastvale` | Goldshire → Eastvale Logging Camp |
| `eastvale_to_jasperlode` | Eastvale → Jasperlode Mine |
| `jasperlode_to_goldshire` | Jasperlode → Goldshire |

## Acceptance Criteria

- [ ] Profile YAML compiles without errors (all quest IDs, NPC IDs, policy names resolve)
- [ ] Profile loads and starts at `Initialize` → transitions to `AcceptNorthshireQuests`
- [ ] Accepts all available quests at Marshal McBride (NPC 197)
- [ ] Travels to Kobold Camp via policy
- [ ] Kills 10 Kobold Laborers/Vermin (quest 783)
- [ ] Returns to Northshire, turns in quest 783
- [ ] Accepts next batch of Northshire quests (7, 15, 3104)
- [ ] Travels to Goldshire, accepts all hub quests
- [ ] Completes Goldshire objective groups (Kobolds, Apples, Murlocs)
- [ ] Turns in Goldshire quests
- [ ] Continues to Eastvale → Jasperlode → Level 10
- [ ] Survival/Logistics regions handle eating, combat, vending, repair automatically
- [ ] Death recovery works: corpse run → resurrect → resume from history state
- [ ] Bag full → vendor → sell junk → resume
- [ ] Low durability → repair → resume

## Blocked by

- **01-profile-compiler** — must compile this profile
- **02-statechart-executor** — must execute this profile
- **03-engine-event-system** — must publish all events this profile consumes
- **04-quest-registry** — must resolve quest/NPC IDs
- **06-core-action-registry** — must provide all `coreActions.*` used
- **07-routing-policies** — must load and execute all 9 routing policies

## Files to Create

- `sentinel/data/profiles/quests/alliance_human_01_10_elwynn.yaml`
- `sentinel/data/routing_policies/northshire_to_kobolds.yaml` (and 8 others)