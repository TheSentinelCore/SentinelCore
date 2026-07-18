# 06 — Quest Browser

**What to build:** A quest browser panel that queries the database for available quests, displays them in a filterable list, and allows dragging quests to the statechart canvas to create new states.

**Blocked by:** 01 — Editor Window Shell

**Status:** ready-for-agent

- [ ] Create `sentinel/ui/quest_ui/profile_editor/quest_browser.lua`
- [ ] Query `QueryClient` for quests by zone, level range, faction
- [ ] Display quest list: name, level, required level, faction, rewards
- [ ] Filter controls: zone dropdown, level range slider, faction toggle
- [ ] Text search: filter by quest name
- [ ] Click quest to show details: description, prerequisites, objectives, rewards
- [ ] Drag quest to statechart canvas: creates new state with quest accept/complete actions
- [ ] Show quest prerequisite indicators (icons or badges)
- [ ] Integration with `QueryClient:get_quests_by_zone()`, `QueryClient:get_quest_details()`
