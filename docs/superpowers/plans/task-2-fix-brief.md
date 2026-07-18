### Task 2: Create Dashboard Component (FIX REQUEST)

**Previous Task Brief:**
docs/superpowers/plans/task-2-brief.md

**Reviewer Feedback:**
### 1. Spec Compliance
- **Missing:** The component fails to fulfill the "Consumes" interface contract. It never calls `app:get_module("quest")` or `app:get_blackboard()` to retrieve state, leaving the routing policy hardcoded as "N/A".

### 2. Code Quality
- **Unused Import:** `SentinelUI` is required at the top of the file but never used.
- **Unused Parameter:** The `app` parameter in `Dashboard.draw` is declared but never utilized. 

**Your Job:**
Fix the implementation in `sentinel/ui/quest_ui/dashboard.lua`. 
1. Use the `app` parameter to get the blackboard via `app:get_blackboard()`.
2. Retrieve the active routing policy from the blackboard. You can use a reasonable mock path like `module.quest.routing.active_policy` if the exact key isn't known. If it exists, render its name, otherwise fallback to "N/A".
3. Remove the unused `SentinelUI` requirement.
4. Commit your changes with a message like `fix: address task 2 review feedback`.
