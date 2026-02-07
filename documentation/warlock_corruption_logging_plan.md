# Warlock Corruption Logging Plan

## 1. Goal
`Corruption` is sometimes issued twice in quick succession even though the game already reports the debuff. This plan documents:

- what the new logging outputs,
- how to enable/disable it,
- which signals to inspect when hunting the duplicate cast,
- and a recommended workflow for correlating logs with in-game behavior.

## 2. Enabling the logs

- **UI toggle** – The new **Enable DoT Debug Logs** checkbox lives next to the DoT timing sliders in both the original rotation tree and the custom Warlock UI. Turning it on routes additional statements through `core.log(...)`.
- **Scope** – Logging is gated behind `menu.enable_dot_logging`; nothing is emitted while the checkbox is off, so you can leave the rotation running without spamming the log.
- **Delivery** – Logs appear in the same console window that already receives `[Warlock]` error messages. Capture the console or the log file while reproducing the issue.

## 3. Logged Signals

| Event | Prefix | What is captured | Purpose |
| --- | --- | --- | --- |
| **DoT evaluation** | `[Warlock][Curse]`, `[Warlock][Corruption]`, `[Warlock][Immolate]` (AOE versions append `(AOE)` &rarr; `Corruption (AOE)`) | Target name & GUID, whether the debuff was missing, remaining duration, pandemic threshold, and whether a refresh was considered. | Shows why `should_cast_dot` said “yes” or “no”. Look for repeated `should_cast=true` lines that precede back-to-back casts. |
| **Global cooldown check** | `[Warlock][AOE]` and `[Warlock][Corruption]` | Time left on the 200 ms DOT throttle. | Confirms whether the system was forced to wait before the next attempt. |
| **Guard block** | `[Warlock][Corruption]` (or the DoT name in AoE mode) | How many milliseconds remain on the dot guard. | Ensures `dot_apply_guard.should_block` is preventing redundant casts. |
| **Cast request** | `[Warlock][Corruption]` / `[Warlock][Corruption (AOE)]` | Logged once right after `dot_apply_guard.on_cast_requested` fires. | Marks the moment the script actually asked the client to cast. |
| **Cast result** | Same prefix as "Cast request" | Success or failure after `cast_safe` returns (guard renewed on success, guard cleared on failure). | Use this to see if two `Cast requested` entries were issued because the first cast failed (client didn’t learn the debuff yet). |

Example entry:

```
[Warlock][Corruption] target=Kul Tiran Witch guid=0xF1301E0000001234 - Eval down=false remaining=5200 threshold=5400 -> should_cast=true (remaining=5200 < 5400)
[Warlock][Corruption] target=Kul Tiran Witch guid=0xF1301E0000001234 - Cast requested
[Warlock][Corruption] target=Kul Tiran Witch guid=0xF1301E0000001234 - Cast succeeded
[Warlock][Corruption] target=Kul Tiran Witch guid=0xF1301E0000001234 - Eval down=false remaining=180 threshold=5400 -> should_cast=true (remaining=180 < 5400)
[Warlock][Corruption] target=Kul Tiran Witch guid=0xF1301E0000001234 - Guard active (312ms left)
```

## 4. Investigation workflow

1. **Prepare the fight** – Enable logs, set the rotation to use `Corruption`, and stand on a target that remains in place for 10+ seconds. If you suspect AoE logic, enable `AOE DOT Spread`.
2. **Copy the console** – Run the rotation until you see the duplicate cast in-game. Immediately save the console output (scrollback or log file) so you capture the timeline.
3. **Scan by prefix** – Filter for `[Warlock][Corruption]` (and `[Warlock][Corruption (AOE)]` if AoE logging is active). Look for:
   - consecutive `Cast requested` entries with little time between them,
   - identical GUIDs (the same enemy),
   - an earlier guard block that never fired (guard left should be `nil` or `0` if misbehaving),
   - `should_cast=true` lines preceding the unwanted cast attempt.
4. **Check cause** – If `cast_safe` succeeded but the duplicate cast still fires, examine the following guard evaluation to prove the guard window expired too soon or the remaining time was misread. If `cast_safe` failed, you now know why the script tried again immediately.
5. **Repeat with variations** – Toggle AoE mode, disable internal wand usage, force the target to move, and note how the log entries change. This isolates whether the double cast happens in a narrow scenario.

## 5. Follow-up

- Once you identify the sequence that creates the double cast, capture both the log excerpt and an explanation of whether the guard or pandemic thresholds were bypassed.
- If the log consistently shows `Cast requested` → `Cast succeeded` → immediate re-evaluate, the new guard durations (600 ms by default) may be too short; consider increasing the grace slider.
- Keep the log toggle off during normal play to avoid clutter.

