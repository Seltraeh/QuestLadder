# Quest Ladder (WoW: Forever)

A step-by-step questing guide, similar to RuneLite's Quest Helper. It looks at the quests in your log and the ones you could pick up nearby. It plans the shortest route through all of them, then shows one step at a time ("Talk to Marshal McBride", "Clear area: kill 6 Kobold Vermin and loot 8 Tough Wolf Meat"). You follow the arrow.

It also covers the things people forget when they skip quest text, keeps your bags ready for what's coming, and picks gear: quest rewards first, then affordable Auction House upgrades from Auctionator's prices.

## Install

1. Install **Questie** for WoW: Forever from CurseForge. It brings **QuestieDB**, the quest database this add-on reads. Make sure the CurseForge instance is set to the Forever flavor.
2. Optional: **Auctionator** for AH prices and gear upgrades. **TomTom** gives a crazy-arrow instead of Blizzard's map pin. **HereBeDragons** (the library) draws the cyan boxes on the minimap and world map.
3. Install **Quest Ladder** from CurseForge, or unzip a `QuestLadder-<version>.zip` into the same `Interface\AddOns` folder where CurseForge put Questie (`World of Warcraft\_forever_\Interface\AddOns`). Check that you end up with `AddOns\QuestLadder\QuestLadder.toc`, with no extra folder in between.
4. Log in. The guide appears on the right. `/ladder help` lists the commands.

Problems or ideas: open an issue at https://github.com/Seltraeh/QuestLadder. A `/ladder diag` run (then `/reload`) saves what the add-on sees to `WTF\Account\<account>\SavedVariables\QuestLadder.lua`, which helps a lot.

## What you see

**Guide window**
- The current step, with a checklist and live progress ("Kobold Vermin slain: 2/6").
- Distance and travel time to the step, and a waypoint on your map.
- The next few steps.
- A line for bag space and a line for the next gear upgrade.
- Buttons: **Skip** (ignore this step's new quests or push them to the end), **Replan**, **Bags**, **Gear**.

**How the route is chosen**
- **As many quests as possible.** Up to 25 quests you haven't accepted yet are planned in at once: the givers nearest you and nearest the places your quests already send you, up to 2 levels above you. More quests in an area means more of their mobs overlap.
- **Accept it while you're standing there.** A quest giver the route passes twice gets visited for that quest the first time, so its mobs are killed together with the others' instead of on a second trip out.
- **Finish what's around you first.** Work within 200 yards of you (quests to accept, mobs, turn-ins) goes before anything far away, as long as that adds no more than 90 s of walking.
- **Mobs 2+ levels above you wait.** Kill or loot steps whose mobs (from QuestieDB) are 2 or more levels above you come after enough of your other quests are turned in to level you up. That's about 4-7 turn-ins per level (more at higher levels); "go talk to" quests count less, and the bar in your XP counts too. It never waits for more turn-ins than the plan has, so nothing gets stuck. Kill steps show the mobs' level, in orange when they're 2+ above you.

**Hint box** (under the guide)
- "Don't leave yet: grab [Old Book] from the Dusty Bookshelf nearby". It appears when an item objective sits within about 70 yards of the quest giver. If you walk away without it you get "You left without [Old Book]".
- "Right-click [item] (just given to you) to progress <quest>". "Use [item] on <NPC> for <quest>" when the current step needs an item you carry. The game flags some of these; the rest come from QuestieDB: items the quest requires, the item its giver handed you, and quest items linked to it. That includes quests with no tracked objectives, like using the Symbol of Life to resurrect Deathguard Falgan; the step's line then reads "Use [item] on <NPC>, then turn in …". These hints are worked out live, so they're still there after a `/reload`.
- "Right-click [item] in your bags, it starts a quest".
- Questie's hidden-objective notes, escort warnings, timed-quest countdowns, "turn in X right here".
- Reward picks ("Reward: pick Kobold Boots (upgrade +40%)") and bag warnings ("free 2 more slots before step 5").
- A **use-item button** next to the hint box for the most relevant quest item. Bind a key to it under Options → Keybindings → AddOns → "Quest Ladder: use the suggested quest item".

**Cyan boxes in the interface** (RuneLite-style, `/ladder highlights` to toggle)
- The quest item to use, or the Hearthstone when it's time to hearth, gets boxed inside your open bags.
- If your bags are closed, the bag button that holds the item is boxed with "Open".
- Upgrades in your bags get "Equip".
- With a vendor window open, the junk and old gear to sell get "Sell".
- In the quest-complete window, the reward to pick gets "Pick this".
- Works with **Blizzard's bags, Bagnon (and Bagnonium) and Baganator**: the box goes on the item inside their window. With a one-big-inventory add-on, closed bags show the box on the backpack button, because that's what opens everything.

**Markers in the world** (`/ladder marks` to toggle)
- **NPCs**: quest mobs, quest givers, turn-ins, innkeepers and flight masters for the current step get a cyan box and a label ("Kill", "Turn in", "Use item on") on their nameplate. Quest givers are friendly NPCs, so turn on friendly nameplates with `/ladder npcplates`. Quest mobs, including mobs that drop a quest item, need enemy nameplates (press V). If they're off, the add-on tells you once per session.
- **Objects** (books, crates, ore, herbs): WoW doesn't let add-ons draw on 3D objects. Instead, when the thing you're facing is the objective, the hint box shows ">> This one: Loot Dusty Bookshelf - press your Interact key" and plays a ping. The game also gives the object you face a small nameplate, and that gets the cyan box around its name. `/ladder interacticons` turns on Blizzard's own icons over interactable objects so you can see them coming.
- **Places**: small cyan boxes on the minimap and world map at the objective's spawn points. This needs the **HereBeDragons** library installed from CurseForge. Questie ships its own copy, but it's private to Questie and other add-ons can't use it.

**Travel: hearthstone and flight paths** (`/ladder flights|hearth|bind|discover`)
- **Flights count as AFK time.** Time in the air is weighted at about a third of walking time, since your character travels safely while you're away. A flight is only used when it's a real shortcut: less hands-on time than walking, and no more than 15% longer in total, so no detours. Flight times are rough estimates; the game doesn't expose real ones.
- **Both ways are shown, and either one works.** The step's travel line compares walking with the best flight from where you stand, for example "Fly: Undercity -> The Sepulcher - 2:31 total, 1:05 of it AFK in the air (walking takes 3:04)" or "Walk: 1:53 (flying Undercity -> The Sepulcher: 3:43, 1:05 AFK)". A flight more than twice as slow isn't mentioned. It's re-checked every second. Walk off instead of taking the bat and the guide switches to walking, with the arrow on the objective, once that's quicker from where you are. Take a flight it didn't suggest and it carries on from where you land. The arrow points at the flight master only while flying is the way.
- **Zeppelins are connector rides, not shortcuts.** What players report: Forever has Classic's three Horde zeppelins (Orgrimmar–Undercity, Orgrimmar–Grom'gol, Undercity–Grom'gol). Each docks for 60 s and leaves every 3-5 minutes. There's no departure timer in the game, so the wait is anywhere from 0 to a full cycle, and at Forever's launch some got lost for 10+ minutes. Guides use them to change continents, or to reach Grom'gol in the mid-30s.
  - The towers come from QuestieDB's zeppelin masters (masters standing together form a tower; with two per tower every pair is linked). If the masters ever stand in a layout that can't be paired, no zeppelins are used and `/ladder diag` says so.
  - A trip counts the way to the tower (walking or flying), about 2:30 waiting (hands-on: you have to board), about 1:40 aboard (AFK, like a flight), and the way on from the far tower.
  - Another continent goes by zeppelin. On the same continent a zeppelin is only used when it still beats walking if you just missed it (a 5:30 wait).
  - The guide says so: "Zeppelin: Tirisfal Glades -> Stranglethorn Vale - about 6:08, up to 9:08 if you just miss it (no departure timer in the game; 1:40 aboard is AFK)". At the tower it adds that each side flies somewhere else and the zeppelin master on each platform says where. The arrow points at the tower first.
  - Flights and zeppelins share the `/ladder flights` switch.
- **The hearthstone is part of the plan, not an afterthought.** The planner works out where it would hearth and re-plans everything after that point starting from your inn, so quests near the inn can move after the hearth. It only recommends a hearth when it saves a large chunk of time (at least 4 minutes and 8% of the route) **and** one of these is true:
  - the area is done, with nothing left within about 2 minutes of where you stand ("nothing left out here"), or
  - about a full cooldown (~1 hour) of steps follows, so you won't want the stone again before it's back.
  - **Or a fast return:** your next stop has turn-ins within about 20 s of your inn, getting there any other way takes more than 3 minutes, and the whole route still saves 2+ minutes ("your turn-ins are right by the inn"). When both kinds are possible and save about the same (within 30 s), the hearth that leaves a finished area wins, since it uses the cooldown better.
  Otherwise you walk. The hearth gets its own step, and the hint box puts the Hearthstone on the use button. If you walk on instead, the step is skipped automatically.
- **Set your hearth**: suggested only when binding at a different inn produces a hearth that passes the rules above and saves 3+ minutes more than your current inn, after the detour.
- **Grab flight paths on the way**: undiscovered flight masters within about a 1 minute detour get a step: "Discover flight path: ...". Talking to the flight master is enough.
- **It learns which flight paths you know** each time you open a flight map, from the paths the map lets you fly to. The game's own "undiscovered" flag is always off on Forever, so until you've opened a flight map once, it assumes you know none and plans no flights.
- It learns your inn's location when you bind or hearth. It learns the cooldown the first time you use it.

**Bags panel** (`/ladder bags`)
- What to sell (junk, gear worse than yours or unusable), what to destroy (quest items no quest needs), what's worth more on the AH, and upgrades sitting in your bags.
- Gear is checked before anything is called junk, so a gray piece that beats what you wear (or fills an empty slot) gets "Equip", not "Sell". An upgrade you can wear within 3 levels is kept.

**Gear choices**
- The reward to pick is the one you can wear now that beats what you wear the most. Anything you can wear beats an empty slot ("fills your empty Legs slot"). Only when no choice beats your gear does it pick the one that sells for most, and it says so.
- Small upgrades count: better by 0.5 points (stat weights) or by 2%. At low levels most gear only has armor, which is read from the tooltip when the game's stat list leaves it out.
- It keeps `reserve` slots free for gathering and profession mats. It never suggests consumables, reagents or quest items still in use.
- **Profession tools are never sold.** QuestieDB lists the Mining Pick, Blacksmith Hammer, Skinning Knife and Arclight Spanner as "miscellaneous" weapons, and fishing poles as their own weapon type, so they used to read as weapons you can't train. Those, plus the enchanting rods, Philosopher's Stone and Gyromatic Micro-Adjustor, are always kept. A gray broken one is still junk.
- If the route would overflow your bags, a **vendor stop** is added to the route before that point. It compares the vendor nearest you with the ones near the next steps, and sells where you are when that costs about the same, instead of carrying junk across a flight.

**Gear panel** (`/ladder gear`)
- Upgrades coming from quests in the plan, so you don't buy that slot.
- **Find AH upgrades**: checks equippable items near your level that Auctionator has priced and that you can afford after keeping gold for training (`/ladder gold 5g` or `auto`). It scores them against what you wear and shows the best one per slot. **Find** opens Auctionator's search; you buy it yourself.
- Auctionator only knows prices from your own scans. Run a scan at the AH first.

## Commands

| Command | |
|---|---|
| `/ladder` | show/hide |
| `/ladder replan` / `skip` / `unignore` | rebuild route / skip step / clear skipped quests |
| `/ladder bags` / `gear` | panels |
| `/ladder reserve 4` | bag slots to keep free (default 2) |
| `/ladder gold 5g` / `gold auto` | gold kept for training |
| `/ladder weight agi 1.5` / `weight reset` | stat-weight overrides |
| `/ladder auto` | auto accept/turn-in on/off |
| `/ladder autopick` | also auto-choose the best reward (default off) |
| `/ladder unstarted` | plan only your current log, or nearby quests too |
| `/ladder dungeons` / `waypoints` / `hints` | toggles |
| `/ladder flights` / `hearth` / `bind` / `discover` | travel features on/off |
| `/ladder highlights` / `marks` | cyan boxes / world markers on/off |
| `/ladder interacticons` | Blizzard's icons over interactable objects |
| `/ladder npcplates` | friendly NPC nameplates (so quest givers can be marked) |
| `/ladder diag [label]` / `diag clear` | run the in-game checks below and save the results (see "Verify in game") |

## Rules: what it does and doesn't do

Everything runs inside the normal add-on sandbox. It uses only read APIs (quest log, map, bags, items) and the public APIs of QuestieDB and Auctionator. Nothing reads memory, network traffic or files.

- **No movement, targeting or combat automation.** You walk the route. The waypoint is the same map pin you'd place yourself.
- **Quest automation only happens inside an NPC dialog you opened**, the same way Leatrix Plus and Questie work. It only accepts quests in the plan, completes quests that are done, and takes the reward only when there's no choice (or when you turn on `autopick`). Hold **Shift** while talking to an NPC to suspend it.
- **Item use is always your click or key press**, through a standard secure action button.
- **Highlights and markers are display-only.** They're overlay frames on Blizzard's buttons and nameplates and pins on the map, the same kind of thing Pawn, Plater and Questie do. The CVar presets only change settings you could change yourself in Options, and only when you type the command.
- **AH purchases are manual.** The add-on only recommends and opens a search.
- It is free and the code is fully visible, as Blizzard's add-on policy requires.

## How it works (for review)

| File | Role |
|---|---|
| `Core.lua` | settings, events, background-job scheduler (5 ms/frame budget), slash commands |
| `Geo.lua` | AreaID→UiMap (QuestieDB support data), map→world yards via `C_Map.GetWorldPosFromMapPos`, spawn clustering |
| `Data.lua` | QuestieDB adapter: quest projection, spawn points, availability rules (Questie's `IsDoable` when loaded, its own rules otherwise), background indexes (quest givers by area, chain follow-ups, quest-reward gear, gear by level, vendors, trainers) |
| `QuestState.lua` | live quest log, objectives, rewards, special items, bags |
| `Planner.lua` | **pure logic**: tasks (pickup → objectives → turn-in, chain edges), greedy nearest-feasible route, then Or-opt block moves (1-8 tasks, so a whole stop can move at once) with O(1) travel deltas and 2-opt reversals of stretches of stops (turns a there-and-back zigzag into one sweep; tasks at one stop keep their order); respects precedence, quest-log capacity and skipped-quest tiers. Then "while you're here": quests that are already finished get turned in at the earliest point where you're within 600 yd of the NPC and it costs little extra travel (10 s, plus 0.1 s per second you'd otherwise carry the quest, at most 2 min). It never adds a flight there and back. Level waits (objectives with mobs 2+ above you wait for turn-ins): planned by travel alone first, then fitted in at the cheapest valid places and polished. Pickups move to the first visit to their giver; work within 200 yd of you goes first. It groups tasks within 90 yd into steps and simulates bag usage along the route |
| `Travel.lua` | cost model (walk / mount / AFK-weighted flights with a no-detour rule); hearth-aware routing (try the best split points, re-solve the rest from the inn, keep a split only if it passes the dead-end / full-cooldown rules, up to two hearths); inn comparison; flight-path pickups; learning bind point and cooldown |
| `Highlight.lua` / `WorldMarks.lua` | cyan boxes on bag items (Blizzard, Bagnon, Baganator), bag buttons, rewards; nameplate markers, soft-target cue, minimap/map boxes |
| `Ladder.lua` | builds the planning context (quests you haven't picked up are searched around you and around the places on your continent your quests already send you, so nearby work gets bundled into those trips), matches live objectives to QuestieDB entries by name, falls back to the game's own quest POI for new Forever quests, tracks progress, sets waypoints, adds trainer and vendor stops |
| `Hints.lua` | reminder rules |
| `Bags.lua` / `Gear.lua` | bag suggestions; stat-weight scoring, reward choice, AH search via Auctionator |
| `Automation.lua` | dialog automation described above |
| `UI.lua` | guide, hint box, secure use button (parented to UIParent so the add-on's frames never become protected in combat), panels, tooltip notes |
| `Diag.lua` | `/ladder diag`: runs the "Verify in game" checks (read-only, pcall'd, secret-safe) and stores the last 10 runs in the `QuestLadderDiag` saved variable |

Tests: `cd tests && lua5.1 run.lua` (328 checks against a fake client and a fake QuestieDB) and `lua5.1 bench.lua` (about 0.3 s to plan 108 tasks offline; the improvement step walks about 25% less than nearest-next).

## Verify in game (not testable offline)

The logic is tested offline. These client behaviours need a first in-game pass, and each is wrapped in `pcall` or a feature check so a mismatch degrades instead of erroring.

**`/ladder diag`** runs all of them at once and prints anything that isn't OK. Some checks need a situation, so run it again where it matters, with a label: `/ladder diag turnin` in a quest-complete window, `/ladder diag mobs` near quest mobs, `/ladder diag object` while facing a quest object, `/ladder diag bags` with your bags open. Then `/reload`: the client writes the last 10 runs to `WTF\Account\<account>\SavedVariables\QuestLadder.lua` (`QuestLadderDiag`), where they can be read outside the game. It also records errors Quest Ladder caught this session. Nothing else reads that table, so it's unaffected by the SavedVariables restore bug. `/ladder diag clear` empties it.

1. `C_Map.GetWorldPosFromMapPos` returns positions on Forever maps. If it doesn't, distances are unknown and the guide says "location unknown".
2. The waypoint pin appears (`C_Map.SetUserWaypoint` + super-tracking), or TomTom's arrow.
3. `GetQuestLogChoiceInfo`/`GetQuestLogItemLink` with a quest ID return reward items without opening the quest.
   - 3b. **Gear scoring**: whether armor comes from `C_Item.GetItemStats` or has to be read from the tooltip (`C_TooltipInfo.GetHyperlink`), and for each reward choice and bag item: the comparison, whether it counts as an upgrade, and the bag suggestion.
4. `GetQuestLogSpecialItemInfo` and `C_Container.GetContainerItemQuestInfo` behave as on retail.
5. The use-item button fires the item, and its key binding works.
6. The Auctionator API exists in your Auctionator build (`/dump Auctionator.API.v1`).
7. Questie's `IsDoable` is reachable (`/dump Questie.API.isReady`). If it isn't, the add-on falls back to its own rules, which ignore Questie's blacklists and events.
8. **Bag boxes**:
   - **Bagnon:** buttons are found through `BagBrother.Frames` (or the global `BagBrotherContainerItemN` buttons) and `button:GetBag()`.
   - **Baganator:** buttons are found inside `Baganator_SingleViewBackpackViewFrame<skin>` / `CategoryView...` and `button:GetBagID()`.
   - **Blizzard:** buttons are found through `ContainerFrameCombinedBags` / `ContainerFrameUtil_EnumerateContainerFrames`.
9. **Reward box**: `QuestInfoRewardsFrame.RewardButtons` (or `QuestInfoRewardsFrameQuestInfoItemN`).
10. **Nameplate boxes** show on quest mobs (out of combat at least; nameplates in instances are off-limits to add-ons).
11. **Soft-target cue**: `PLAYER_SOFT_INTERACT_CHANGED` fires when you face an object. Try `/ladder interacticons` if nothing happens.
12. **Flight paths**: `C_TaxiMap.GetTaxiNodesForMap` lists nodes with `isUndiscovered` outside a flight master. Bind it once (or hearth once) so the inn is learned.

## Known limits

- QuestieDB doesn't have every new Forever quest yet. Those use the game's own quest POI once they're in your log, and they can't be suggested before you pick them up.
- Stat weights are leveling heuristics per class. Random-enchant AH items ("of the Bear") can't be scored from their base ID and are flagged.
- Weapons are compared one item at a time. With a two-hander equipped, a one-hander or a shield is compared against that two-hander (it would replace it), but a one-hander + shield *pair* isn't scored as a set. One-handers only count for the off hand if you can dual wield.
- The trainer reminder assumes new ranks on even levels.
- Walking distances are straight lines. WoW gives add-ons no terrain or pathing data, so mountains, cliffs and rivers aren't known: the arrow can point across a ridge you have to walk around, and arrival times run short in rough terrain.
- Flight times are estimates (straight line x1.25 at ~32 yd/s). They only decide whether a flight is a detour, and you can AFK on it anyway. Zeppelin waits and rides are estimates too (about 2:30 on average, up to 5:30, and 1:40 aboard); the real schedule isn't available to add-ons. If a zeppelin doesn't show up, the guide can't know. Boats aren't modelled: QuestieDB has no masters for them. Without a zeppelin, another continent counts as a flat 15-minute cost.
- Step time estimates (about 20 s per kill, 28 s per drop) feed the "an hour of steps" rule, so treat it as approximate.
- QuestieDB has no quest XP, so the level wait counts turn-ins (about 4-7 per level) instead of real XP. It replans when you level up, so a wait that was too long or too short corrects itself then. Mob levels come from QuestieDB; Forever may have changed some.
- Nothing can be drawn around 3D objects. That's a WoW limit, not this add-on's; the soft-target cue, the box on the faced object's nameplate and the map boxes stand in for it.
- Forever has a known bug where SavedVariables sometimes fail to load after a full restart. Settings can then fall back to defaults, but the route is always rebuilt live.

## License

MIT, see [LICENSE](LICENSE). Quest Ladder reads QuestieDB, Questie, Auctionator and HereBeDragons only through their public APIs and includes none of their code.
