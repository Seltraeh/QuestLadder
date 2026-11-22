# Changelog

Newest first. 0.3.18 is the release on CurseForge; the versions after it are development builds,
not released yet.

## 0.4.0: level without thinking about it

- **Move on from quests you've outgrown.** A quest in your log 3 or more levels under you now gets
  the same "worth the walk" check new quests get. It stays while it's on the way or its XP still
  pays for the trip (Classic gives full quest XP until you're 6 levels above a quest), and is left
  out when the route would drag you back to an old zone for it. Class quests, gear upgrades,
  Forever's must-do extras and timed quests always stay. A quest that leads on to one still worth
  doing carries that quest's XP.
- The hint box names the outgrown quests the route left out and says to abandon them to free log
  space: "Outgrown: ... (log 34/40)". `/ladder outgrown` lists them with their XP and travel.
- **A full log says what to drop.** At 39 or 40 quests the hint box names the weakest first: the
  outgrown ones the route left out, then outgrown ones you haven't started, least XP first. Never
  a quest you've made progress on or one at your level.
- **Take it or leave it.** Talking to a quest giver shows a line for each quest they offer:
  "Take: ... - on your route (step 12)", "Skip: ... - grey for you", "Skip: ... - not worth the
  walk: 740 XP for 6:10 of travel", and so on. Advice only: accepting stays yours, and
  auto-accept still only takes quests on the route.
- The "worth the walk" check also weighs quests by region (1,500 yards) and everything on another
  continent together, since one ocean crossing can carry a dozen quests that each look cheap on
  their own. On the saved routes this changed nothing for new quests.
- `/ladder diag` saves which quests in your log count as outgrown, and which were left out.

## 0.3.29

- Hint lines that name a place (where the Cozy Sleeping Bag chain starts, a bag vendor, your
  riding trainer, the supply crate NPC) can be clicked for a map pin (or a TomTom arrow). The
  route's own pin comes back at the next step. Checked in game.
- The Cozy Sleeping Bag hint gives coordinates and the chain's levels ("quests level 22-32, you can
  start from level 14").

## 0.3.28

- Facing or targeting what a quest item is used on gives one line that names the item and the
  button ("Use [Dried Seeds] on Bubbling Fissure ... - click the use button", or your key), instead
  of "press your Interact key".
- An item for what you've selected gets the button before one you're only standing near.

## 0.3.27

- Nameplate labels ("Kill", "Turn in", "Loot" and the rest) sit under the cyan box, so the mob's
  name above stays readable.

## 0.3.26

- A quest item for a step further down the ladder shows on the use button once you select or
  reach its target, so going somewhere out of order works ("step 19, but you're here").

## 0.3.25

- The use button only shows a quest item for the step you're on, once you've targeted or faced
  what it's used on (or stand within 40 yards of it). Before, any quest item in your log could sit
  there, far from where it's used. Checked in game at the Stagnant Oasis.
- Quests you abandon aren't suggested again. `/ladder unignore <id>` (or accepting the quest
  again) undoes it.

## 0.3.24

- The planner tries more than one first guess for the route (flights at full time, walking only)
  and keeps the cheapest. Fixes a walk to the north Barrens and a flight back for turn-ins 150 yards
  away. On ten saved routes it was never worse and up to 3.5 minutes better.
- `/ladder diag` waits until the route is planned before it runs (`diag now` runs it at once).

## 0.3.23

- Timed quests go first, with a countdown in the guide and the item to deliver.

## 0.3.22

- Crafting materials (cloth, leather, herbs, ore, bars, meat, elemental and enchanting materials,
  gems, recipes) are never marked Sell or Destroy; they're suggested for the bank or the AH.
- NPCs friendly to you don't count as high-level mobs ("speak to Neeru Fireblade" no longer
  pushes Orgrimmar to the end and adds ocean crossings).

## 0.3.21

- New quests must be worth the walk: one whose XP is clearly less than grinding for the travel it
  adds is left out (`/ladder skipped`, `/ladder trips`).
- A quest's mobs are looked for on the quest's own continent (Silverpine murlocs were placed in
  Darkshore).
- Blizzard's retired "zzOLD" flight points are ignored. `/ladder dungeons plan` toggles planning
  dungeon quests.

## 0.3.20

- Forever extras: must-do quests (camping unlocks, Library books, the Cozy Sleeping Bag chain,
  supply crates, bag rewards), bag upgrades to buy, riding at 40, Waylaid supply crates, and
  `/ladder dungeons`.

## 0.3.19

- New quests worth under half of a solid quest's XP at your level are skipped, using QuestieDB's
  quest XP (`/ladder minxp`). A "Next area" hint when few good quests are left near you.

## 0.3.18

- First public release.
