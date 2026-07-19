I have addressed the review feedback for Task 2. Here are the specific changes made in `sentinel/ui/quest_ui/dashboard.lua`:

1.  **Removed the unused `SentinelUI` import** from the top of the file.
2.  **Utilized the `app` parameter** within `Dashboard.draw` to fetch the blackboard instance using `app:get_blackboard()`.
3.  **Fetched the active routing policy** dynamically from the blackboard state (`module.quest.routing.active_policy`). It now gracefully falls back to "N/A" if it doesn't exist, and is rendered properly in the Top Info Bar.

The changes have been verified and successfully committed to the repository with the message `fix: address task 2 review feedback`.
