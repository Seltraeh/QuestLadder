# Changelog

Newest first. 0.6.0 is the release on CurseForge. It includes 0.5.0, which wasn't released on its own.

## 0.6.0: make it yours

- **An options window.** Game Menu > Options > AddOns > Quest Ladder, `/ladder options`, a key
  binding, the icon in the guide's corner, or the minimap's add-on menu. Five pages: the main one
  (show/hide, compact mode, colors), the guide window, markers and map, route and quests, and
  travel, bags and more. Every slash-command switch is a checkbox or slider there too, and so are
  settings that only had a default before: levels above you, how far to look for quest givers.
  **Reset all settings** asks first, and keeps learned flight paths, graveyards and ignored quests.
- **Every /ladder command is in the options** (a test checks this). That includes buttons for Replan,
  Skip this step, Un-skip all quests, the skipped and dungeon quest lists, and the bag and gear
  panels. There's also a box for the gold to keep for training, and one per stat weight (your
  class's values; the ones you change show in gold).
- **Having trouble?** at the bottom of the main page:
  - **Reload UI**.
  - **Run diagnostics**: when they're done it offers to reload, which is what saves them.
  - **Report a bug or idea**: a window with the GitHub and CurseForge links to copy (add-ons can't
    open web pages) and your details to paste: versions, level and class, zone, other add-ons, the
    last diagnostics and errors caught this session, with no character names.
  - **List commands** and **Clear saved diagnostics**.
  - The GitHub repo now has a bug report form and an idea form.
- **Colors.** Seven themes: Cyan (the original look), Pink, Lavender, Gold, Fel green, Crimson and
  Frost. A theme colors the boxes and nameplate markers, the map squares, the title text, and the
  window backgrounds and borders. Or pick any of those six colors yourself in Blizzard's color
  picker; right-click puts the theme's back. `/ladder theme pink` works from chat.
- **Compact mode** (`/ladder compact`, the window's -/+ button, or right-click its icon): the
  current step only, 3 lines and 1 upcoming step by default (both adjustable), no buttons, no bag or
  gear line, at most 2 hint lines. When a step has more lines than fit, the last one says
  "(+2 more)", in full mode too.
- **The window**: scale, width, background opacity, upcoming steps (0-6), hint lines (1-4), the
  buttons and the bag and gear lines can each be switched off, and it can be locked in place
  (`/ladder lock`) or put back where it started.
- **Less clutter**: the minimap and world map squares have their own switches (`/ladder minimap`,
  `/ladder worldmap`), so they can go when Questie's icons are enough. Turning off nameplate
  markers (`/ladder marks`) no longer hides them; if you had marks off, the squares stay off too.
  Also adjustable: square size, box line thickness, the fade, the "Use"/"Kill" labels, the ping
  when you face an object, the notes on item tooltips.
- **The Quest Ladder icon** is in the AddOns list, Blizzard's options list, the minimap's add-on
  menu, the guide's corner, the bag and gear panels, chat lines and tooltip notes.
- `/ladder diag` has a new "options" check: whether the pages registered, the color picker
  is there, and Quest Ladder is in the add-on menu.

## 0.5.0: speed-leveling techniques

Six things Classic speed-levelers do, rebuilt as planner rules on QuestieDB's data and the game's
API. No leveling guide's steps or route order are included.

- **Grind here first.** When the plan runs out of turn-ins before mobs that would be 2+ levels
  above you, a "Grind first" stop goes in right before that step. It names mobs at your level near
  where you'd leave from (the route's own quest mobs first, else QuestieDB's), how far to go ("6 bars
  into level 20") and roughly how long. It's at most about 15 minutes of killing, and it ends by
  itself when your bar gets there. The mobs get a "Grind" box. `/ladder grind` turns it off.
- **Die and res, when that's quicker.** Dying on purpose sends your spirit to the nearest
  graveyard. When that graveyard is next to your next stop and dying is clearly faster than walking
  or flying, the hint box says so, with both times. It counts Classic's res sickness: none up to
  level 10, then a minute per level over 10, ten minutes from level 20. Sickness only counts as lost
  time when you'd have to fight before it wears off. The tip also mentions the 25% durability cost.
  The graveyards come from the game's own list when Forever gives one, plus every graveyard you've
  released at. `/ladder dietravel` turns it off.
- **Watch for named mobs whose drop starts a quest** (Owatanka, Washte Pawne, Lakota'mani). When
  your route passes where one lives, the hint box names it, its level, the quest its drop starts and
  that quest's XP. It also suggests `/tar <name>` to check whether it's up. Its nameplate gets a
  "Quest drop" box. Only quests worth doing, and mobs no more than 3 levels above you.
- **Hearth on cooldown? Take a break.** When the route says hearth but the stone is cooling down,
  the hint box shows the countdown. From 2 minutes up it adds that the cooldown keeps ticking while
  you're logged out.
- **Learn a profession for an XP quest.** A quest worth doing that only needs Cooking, First Aid or
  Fishing (learn-and-go, no profession slot): the hint box names the nearest trainer (click for a map
  pin), the quest and its XP. Examples: Soothing Turtle Bisque, Forever's Camping 101: First Aid.
- **Escorts and group quests.** An escort's walking time now counts in the "worth the walk" check
  (about 4 minutes each), so a slow escort for little XP is left out. A new quest whose mobs are all
  elites at or near your level needs a group. Solo, it's left out unless it's a class quest, a gear
  upgrade or a must-do extra. `/ladder skipped` and the quest dialog say so, and
  `/ladder groupquests` plans them anyway. Elite objectives show "(lvl 21 elite)".
- `/ladder diag` has a new "Speed-leveling" check. It records whether Forever lists graveyards, and
  what each of the tips above found.

Also in 0.5.0:

- **The arrow to Quest Ladder's pin is back.** Forever rates far-away targets "Invalid", and Blizzard's
  arrow frame draws those fully see-through, even though the frame is placed and its edge arrow points
  the right way. Your own pins did the same. Quest Ladder now shows the arrow while the tracked pin is
  one it placed (the route's, or one from clicking a hint line). It runs after Blizzard's own update,
  so Blizzard's code is untouched, and your own pins and tracked quests look as Blizzard draws them.
  `/ladder arrow` turns it off.
- **No arrow to the map pin?** On clients with the game's In-Game Navigation setting, chat says once
  per session when it's off (`/console showInGameNavigation 1`). Forever turned out not to have that
  setting, so there it never shows. `/ladder diag` now records Blizzard's arrow itself instead: what
  the game is navigating to, whether it made a navigation frame for the pin, and the frame's alpha
  and edge arrow. The speed-leveling check also asks for graveyards on the continent map.

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
