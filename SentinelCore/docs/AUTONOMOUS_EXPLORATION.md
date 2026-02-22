# Autonomous Exploration (Profile-Free Grind)

## Problem
Without waypoint profiles, the combat kernel previously entered `scout` and did nothing. The grinder could only react to mobs already inside `TargetingService` pull radius, causing idle time and missed visible targets.

## Core Design
`ExplorationService` is now a first-class engine service used by `Scout`:

1. `Pursuit Layer`:
- Reuses `TargetingService:get_visible_candidates()` legality/faction/risk filters.
- If a valid enemy is visible but outside engage radius (and inside pursuit envelope), it issues navigation toward the target.
- Uses destination hysteresis + stale timeout + move/repath cooldowns to avoid thrash.

2. `Frontier Layer`:
- If no pursuit candidate exists, it scores frontier points around the grind anchor using a spatial cell memory.
- Utility balances novelty, recent sighting density, travel cost, and failure history.
- Unreachable/failing cells are temporarily cooled down to prevent loops.

3. `Kernel Integration`:
- `Scout` now ticks exploration each frame, but still returns `BT.SUCCESS` so the selector reevaluates high-priority branches every tick (`RunCombat`, recovery, loot, objective).
- This preserves combat preemption and avoids blocking target reacquisition.

## Why This Is a Core Solution
- It solves acquisition dead-time at the engine layer, not per-rotation heuristics.
- It centralizes target legality and faction policy in `TargetingService`.
- It is mode-aware (`exploration.enabled_modes`) and profile-independent for grind.
- It adds reusable substrate for quest/gather/bg objective providers later.

## Configuration Surface
Runtime section: `exploration`
- Enablement: `enabled`, `enabled_modes`
- Spatial memory: `cell_size`, `cell_memory_ttl`, `cell_memory_max_entries`, `recent_cells`
- Pursuit envelope: `pursuit_extra_radius`, `pursuit_min_gap`, `pursuit_distance_weight`, `pursuit_stale_timeout`
- Frontier search: `frontier_min_radius`, `frontier_max_radius`, `frontier_ring_count`, `frontier_rays`
- Utility weights: `weight_novelty`, `weight_sighting`, `weight_travel`, `weight_recent`, `weight_failure`
- Movement contract: `move_to_cooldown`, `soft_repath_cooldown`, `soft_repath_distance`, `destination_switch_*`

## Research Basis (Peer-Reviewed / Canonical)
- Yamauchi, B. (1997). Frontier-based exploration for autonomous robots. CIRA.  
  https://dblp.org/rec/conf/cira/Yamauchi97
- Elfes, A. (1989). Using occupancy grids for mobile robot perception and navigation. IEEE Computer.  
  DOI: 10.1109/2.30720
- Koenig, S., & Likhachev, M. (2002). D* Lite. AAAI.  
  https://idm-lab.org/bib/abstracts/Koen02e.html
- Choset, H. (2001). Coverage for robotics: A survey of recent results. Annals of Mathematics and Artificial Intelligence.  
  https://www.ri.cmu.edu/publications/coverage-for-robotics-a-survey-of-recent-results/
- Auer, P., Cesa-Bianchi, N., & Fischer, P. (2002). Finite-time analysis of the multiarmed bandit problem. Machine Learning.  
  https://dblp.org/rec/journals/ml/AuerCF02.html
- Krause, A., Singh, A., & Guestrin, C. (2008). Near-optimal sensor placements in Gaussian processes. JMLR.  
  https://jmlr.csail.mit.edu/papers/v9/krause08a.html

The implemented scorer maps these ideas into a practical grinder context:
- Frontier novelty for coverage.
- Reward-memory from recent sightings.
- Exploration/exploitation balance via weighted utility.
- Failure-aware replanning to avoid repeated bad destinations.
