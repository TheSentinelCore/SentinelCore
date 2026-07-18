# 01 — Profile Editor Window Shell

**What to build:** A new Sylvannas ImGui window (`ProfileEditorWindow`) with a tab bar containing 5 tabs: Statechart, Map, Quests, Deps, Code. The window opens from the quest UI, loads the currently selected profile via `ProfileLoader`, and displays basic profile info in a header bar. Each tab renders placeholder content for now.

**Blocked by:** None — can start immediately.

**Status:** ready-for-agent

- [ ] Create `sentinel/ui/quest_ui/profile_editor/` directory with `init.lua`
- [ ] `ProfileEditorWindow` creates a Sylvannas window with tab bar
- [ ] Tab bar has 5 tabs: Statechart, Map, Quests, Deps, Code
- [ ] Header bar shows profile name, version, author, level range
- [ ] Window loads profile via `ProfileLoader:setActiveProfile()`
- [ ] Add "Edit Profile" button to existing quest UI header that opens the editor
- [ ] Each tab renders placeholder text ("Coming soon: ...")
- [ ] `ProfileEditorController` manages profile data state and coordinates between tabs
- [ ] Window persists position/size across sessions
