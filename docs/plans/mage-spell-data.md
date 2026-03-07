# Mage Spell Data (CMaNGOS-TBC)

Queried from `tbcmangos.spell_template` on 2026-03-07.
Spell IDs verified against `spell_chain` and `npc_trainer_template`.

---

## Frost Combat

### Frostbolt

| spell_id | rank    | req_level | mana_cost |
|----------|---------|-----------|-----------|
| 116      | Rank 1  | 4         | 25        |
| 205      | Rank 2  | 8         | 35        |
| 837      | Rank 3  | 14        | 50        |
| 7322     | Rank 4  | 20        | 65        |
| 8406     | Rank 5  | 26        | 100       |
| 8407     | Rank 6  | 32        | 130       |
| 8408     | Rank 7  | 38        | 160       |
| 10179    | Rank 8  | 44        | 195       |
| 10180    | Rank 9  | 50        | 225       |
| 10181    | Rank 10 | 56        | 260       |
| 25304    | Rank 11 | 60        | 290       |
| 27071    | Rank 12 | 63        | 300       |
| 27072    | Rank 13 | 69        | 330       |
| 38697    | Rank 14 | 70        | 345       |

### Frost Nova

| spell_id | rank   | req_level | mana_cost |
|----------|--------|-----------|-----------|
| 122      | Rank 1 | 10        | 55        |
| 865      | Rank 2 | 26        | 85        |
| 6131     | Rank 3 | 40        | 115       |
| 10230    | Rank 4 | 54        | 145       |
| 27088    | Rank 5 | 67        | 185       |

### Cone of Cold

| spell_id | rank   | req_level | mana_cost |
|----------|--------|-----------|-----------|
| 120      | Rank 1 | 26        | 210       |
| 8492     | Rank 2 | 34        | 290       |
| 10159    | Rank 3 | 42        | 380       |
| 10160    | Rank 4 | 50        | 465       |
| 10161    | Rank 5 | 58        | 555       |
| 27087    | Rank 6 | 65        | 645       |

### Blizzard

| spell_id | rank   | req_level | mana_cost |
|----------|--------|-----------|-----------|
| 10       | Rank 1 | 20        | 320       |
| 6141     | Rank 2 | 28        | 520       |
| 8427     | Rank 3 | 36        | 720       |
| 10185    | Rank 4 | 44        | 935       |
| 10186    | Rank 5 | 52        | 1160      |
| 10187    | Rank 6 | 60        | 1400      |
| 27085    | Rank 7 | 68        | 1645      |

### Ice Lance

| spell_id | rank   | req_level | mana_cost |
|----------|--------|-----------|-----------|
| 30455    | Rank 1 | 66        | 150       |

> Ice Lance is a Frost talent (no additional ranks).

---

## Fire / Arcane Combat

### Fire Blast

| spell_id | rank   | req_level | mana_cost |
|----------|--------|-----------|-----------|
| 2136     | Rank 1 | 6         | 40        |
| 2137     | Rank 2 | 14        | 75        |
| 2138     | Rank 3 | 22        | 115       |
| 8412     | Rank 4 | 30        | 165       |
| 8413     | Rank 5 | 38        | 220       |
| 10197    | Rank 6 | 46        | 280       |
| 10199    | Rank 7 | 54        | 340       |
| 27078    | Rank 8 | 61        | 400       |
| 27079    | Rank 9 | 70        | 465       |

### Counterspell

| spell_id | rank | req_level | mana_cost |
|----------|------|-----------|-----------|
| 2139     | --   | 24        | 100       |

> Single rank, no progression.

---

## Defensive

### Ice Barrier

| spell_id | rank   | req_level | mana_cost |
|----------|--------|-----------|-----------|
| 11426    | Rank 1 | 40        | 305       |
| 13031    | Rank 2 | 46        | 360       |
| 13032    | Rank 3 | 52        | 420       |
| 13033    | Rank 4 | 58        | 480       |
| 27134    | Rank 5 | 64        | 495       |
| 33405    | Rank 6 | 70        | 565       |

> Ice Barrier is a Frost talent.

### Ice Block

| spell_id | rank | req_level | mana_cost |
|----------|------|-----------|-----------|
| 45438    | --   | 30        | 15        |

> Frost talent, single rank. Formerly required Ice Block training (block of ice).

### Blink

| spell_id | rank | req_level | mana_cost        |
|----------|------|-----------|------------------|
| 1953     | --   | 20        | 21% of base mana |

> `ManaCost=0`, `ManaCostPercentage=21`. Single rank.

### Mana Shield

| spell_id | rank   | req_level | mana_cost |
|----------|--------|-----------|-----------|
| 1463     | Rank 1 | 20        | 40        |
| 8494     | Rank 2 | 28        | 60        |
| 8495     | Rank 3 | 36        | 80        |
| 10191    | Rank 4 | 44        | 100       |
| 10192    | Rank 5 | 52        | 120       |
| 10193    | Rank 6 | 60        | 140       |
| 27131    | Rank 7 | 68        | 155       |

---

## Cooldowns

### Evocation

| spell_id | rank | req_level | mana_cost |
|----------|------|-----------|-----------|
| 12051    | --   | 20        | 0         |

> Channeled mana regeneration. Single rank.

### Cold Snap

| spell_id | rank | req_level | mana_cost |
|----------|------|-----------|-----------|
| 11958    | --   | 30        | 0         |

> Frost talent. Resets all Frost cooldowns. Single rank.

### Icy Veins

| spell_id | rank | req_level | mana_cost       |
|----------|------|-----------|-----------------|
| 12472    | --   | 20        | 3% of base mana |

> Frost talent. `ManaCost=0`, `ManaCostPercentage=3`. Single rank.

---

## Buffs

### Frost Armor

| spell_id | rank   | req_level | mana_cost |
|----------|--------|-----------|-----------|
| 168      | Rank 1 | 1         | 60        |
| 7300     | Rank 2 | 10        | 110       |
| 7301     | Rank 3 | 20        | 170       |

> Replaced by Ice Armor at level 30.

### Ice Armor

| spell_id | rank   | req_level | mana_cost |
|----------|--------|-----------|-----------|
| 7302     | Rank 1 | 30        | 240       |
| 7320     | Rank 2 | 40        | 320       |
| 10219    | Rank 3 | 50        | 410       |
| 10220    | Rank 4 | 60        | 500       |
| 27124    | Rank 5 | 69        | 630       |

### Arcane Intellect

| spell_id | rank   | req_level | mana_cost |
|----------|--------|-----------|-----------|
| 1459     | Rank 1 | 1         | 25        |
| 1460     | Rank 2 | 14        | 100       |
| 1461     | Rank 3 | 28        | 250       |
| 10156    | Rank 4 | 42        | 415       |
| 10157    | Rank 5 | 56        | 575       |
| 27126    | Rank 6 | 70        | 700       |

---

## Conjure

### Conjure Food

| spell_id | rank   | req_level | mana_cost | item_id |
|----------|--------|-----------|-----------|---------|
| 587      | Rank 1 | 6         | 60        | 5349    |
| 597      | Rank 2 | 12        | 105       | 1113    |
| 990      | Rank 3 | 22        | 180       | 1114    |
| 6129     | Rank 4 | 32        | 285       | 1487    |
| 10144    | Rank 5 | 42        | 420       | 8075    |
| 10145    | Rank 6 | 52        | 585       | 8076    |
| 28612    | Rank 7 | 60        | 650       | 22895   |
| 33717    | Rank 8 | 70        | 885       | 22019   |

### Conjure Water

| spell_id | rank   | req_level | mana_cost | item_id |
|----------|--------|-----------|-----------|---------|
| 5504     | Rank 1 | 4         | 60        | 5350    |
| 5505     | Rank 2 | 10        | 105       | 2288    |
| 5506     | Rank 3 | 20        | 180       | 2136    |
| 6127     | Rank 4 | 30        | 285       | 3772    |
| 10138    | Rank 5 | 40        | 420       | 8077    |
| 10139    | Rank 6 | 50        | 585       | 8078    |
| 10140    | Rank 7 | 60        | 780       | 8079    |
| 37420    | Rank 8 | 65        | 845       | 30703   |
| 27090    | Rank 9 | 70        | 885       | 22018   |

---

## Duplicate / NPC Entries (Excluded)

The following entries exist in `spell_template` but were excluded as NPC/triggered versions
(not in `spell_chain` or `npc_trainer_template`, zero mana cost, or duplicate rank numbers):

| spell_id | spell_name       | rank   | reason                                    |
|----------|------------------|--------|-------------------------------------------|
| 9915     | Frost Nova       | Rank 3 | Duplicate; 6131 is the player version      |
| 27618    | Blizzard         | Rank 6 | Duplicate; 10187 is the player version     |
| 8736     | Conjure Food     | Rank 1 | Duplicate (level 15); 587 is player version|
| 10143    | Conjure Water    | Rank 7 | SpellLevel=0, ManaCost=0; broken entry     |
| 29975    | Conjure Water    | Rank 8 | Duplicate; 37420 is the player version     |
| 16876    | Arcane Intellect | Rank 5 | ManaCost=0; NPC cast                       |
| 39235    | Arcane Intellect | Rank 6 | ManaCost=0; NPC cast                       |
| 42208-42213 | Blizzard      | Rank 1-6 | ManaCost=0; triggered/visual effects     |
| 42198    | Blizzard         | Rank 7 | ManaCost=0; triggered/visual effect        |
