# GrindBuddy Update (r13)

This update focuses on Warlock behavior quality for TBC grinding.

## What was improved

- Warlock auto profile detection now uses `core.spell_book.get_specialization_id()` first.
  - Spec `3` correctly maps to **Destruction**.
  - Signature-spell fallback is still kept for resilience.
- Debuff casting got anti-spam protection for repeated DoTs/curses.
  - Added per-target retry cooldowns (notably for Curse of Elements and Immolate).
  - Added stable target key fallback when GUID is unavailable.
- Patrol mount support was added.
  - Auto-mount on long patrol moves.
  - Auto-dismount before pull/combat.
- Grind settings UI now exposes mount controls.
  - `Auto Mount On Patrol`
  - `Mount Threshold`
  - Scan radius slider extended to `300 yd`.

## Result

The bot should stop defaulting to Affliction on Destruction setups, reduce curse/immolate spam, and travel patrol routes faster while still dismounting safely for combat.
