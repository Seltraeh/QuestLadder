# Quest Ladder (WoW: Forever)

A step-by-step questing guide, similar to RuneLite's Quest Helper. It looks at the quests in your log and the ones you could pick up nearby. It plans the shortest route through all of them, then shows one step at a time ("Talk to Marshal McBride", "Clear area: kill 6 Kobold Vermin and loot 8 Tough Wolf Meat"). You follow the arrow.

It also covers the things people forget when they skip quest text, keeps your bags ready for what's coming, and picks gear: quest rewards first, then affordable Auction House upgrades from Auctionator's prices.

## Install

1. Install **Questie** for WoW: Forever from CurseForge. It brings **QuestieDB**, the quest database this add-on reads. Make sure the CurseForge instance is set to the Forever flavor.
2. Optional: **Auctionator** for AH prices and gear upgrades. **TomTom** gives a crazy-arrow instead of Blizzard's map pin. Without it, the arrow is the game's own navigation marker. Forever rates far-away targets "Invalid" and draws that arrow see-through, so Quest Ladder shows it for its own pins (`/ladder arrow` turns that off). **HereBeDragons** (the library) draws the squares on the minimap and world map.
3. Install **Quest Ladder** from CurseForge, or unzip a `QuestLadder-<version>.zip` into the same `Interface\AddOns` folder where CurseForge put Questie (`World of Warcraft\_forever_\Interface\AddOns`). Check that you end up with `AddOns\QuestLadder\QuestLadder.toc`, with no extra folder in between.
4. Log in. The guide appears on the right. `/ladder help` lists the commands, and `/ladder options` (or Game Menu > Options > AddOns > Quest Ladder) has every setting.

Problems or ideas: open an issue at https://github.com/Seltraeh/QuestLadder (there's a form for bugs and one for ideas), or comment on CurseForge. In the game, **Options > AddOns > Quest Ladder > Having trouble?** has the links to copy, your details to paste, and a **Run diagnostics** button. Diagnostics save what the add-on sees to `WTF\Account\<account>\SavedVariables\QuestLadder.lua` when you reload, which helps a lot.

## What you see

**Guide window**
- The current step, with a checklist and live progress ("Kobold Vermin slain: 2/6").
- Distance and travel time to the step, and a waypoint on your map.
- The next few steps.
- A line for bag space and a line for the next gear upgrade.
- Buttons: **Skip** (ignore this step's new quests or push them to the end), **Replan**, **Bags**, **Gear**, and **-** for compact mode.
- The Quest Ladder icon in its corner opens the options; right-click it for compact mode.

**Make it yours** (0.6.0: `/ladder options`, Game Menu > Options > AddOns > Quest Ladder, or the minimap's add-on menu)
- **Colors.** Seven themes: Cyan (the original look), Pink, Lavender, Gold, Fel green, Crimson and Frost. A theme colors the boxes and nameplate markers, the map squares, the "Quest Ladder" title, the window backgrounds and borders. Or click any one of those six colors and pick your own in Blizzard's color picker (it shows as you drag; Cancel puts back what you had). Right-click a color for the theme's again. `/ladder theme pink` switches from chat.
- **Compact mode** for when you need the screen: the current step only (3 lines by default), 1 upcoming step, no buttons, no bag or gear line, and at most 2 hint lines. The window's **-/+** button, a right-click on its icon, `/ladder compact` or a key binding switch it. How many lines and upcoming steps it shows is up to you.
- **The window**: scale, width (the hint box matches it), background opacity, how many upcoming steps (0-6) and hint lines (1-4) it shows, whether the buttons and the bag and gear lines show, lock it in place (`/ladder lock`), or put it back where it started.
- **Less clutter**: the map squares have their own switches, one for the minimap and one for the world map (`/ladder minimap`, `/ladder worldmap`), for when Questie's icons are enough. Also the square size, box line thickness, the fade, the "Use" / "Kill" labels, the ping when you face an object, and the notes on item tooltips.
- **Every slash command is there too** (a test makes sure of it): switches for quest dialogs, which quests are planned (levels above you, the minimum XP, how far to look for quest givers, group, dungeon and escort quests), speed-leveling and travel; buttons for Replan, Skip this step, Un-skip all quests, the skipped-quest and dungeon-quest lists, the bag and gear panels and Blizzard's interact icons and friendly nameplates; a box for the gold to keep for training; and a box per stat weight (your class's values, the ones you change in gold). **Reset all settings** puts back the defaults (it asks first; learned flight paths, graveyards and ignored quests stay).
- **Having trouble?** at the bottom of the main page: **Reload UI**, **Run diagnostics** (when they're done it offers to reload, which is what saves them), **Report a bug or idea** (a window with the GitHub and CurseForge links to copy, since add-ons can't open web pages, and your details to paste: versions, level and class, zone, other add-ons, the last diagnostics and any errors; no character names), **List commands**, **Clear saved diagnostics** and debug messages.
- The minimap's add-on menu (the button by the minimap in Forever) lists Quest Ladder with its icon: click for the options, right-click to show or hide the guide.

**How the route is chosen**
- **As many quests as possible.** Up to 25 quests you haven't accepted yet are planned in at once: the givers nearest you and nearest the places your quests already send you, up to 2 levels above you. More quests in an area means more of their mobs overlap.
- **But only ones worth the time.** Each new quest is valued by the XP it gives *you*, from QuestieDB's quest XP data (Classic's table plus XP recorded in Forever for the new quests), with Classic's rule for lower-level quests: full XP until you are 5 levels above the quest, then 20% less per level. A quest giving less than half of what a solid quest at your level gives (the 75th percentile of quests within 2 levels) is skipped. It stays in the plan anyway if its reward is gear you'd wear, if it leads to a quest that is worth it (breadcrumbs, chain starts), or if it's a quest for your class. Quests QuestieDB has no XP for are kept. Quests already in your log stay unless you've outgrown them (below). Pickups and turn-ins show the XP, e.g. "Accept Pyrewood Ambush (+1350 XP)". `/ladder minxp 30` lowers the bar to 30%, and `/ladder minxp 0` plans everything.
- **And worth the walk.** Where a hub sends you all over the zone (The Barrens), a quest's XP alone says nothing about the trip. So once the route is planned, each new quest is taken out of it on paper, with its follow-ups: the travel that saves is weighed against the quest's XP. It stays unless its XP is clearly less than killing mobs for that long would give (under 75% of 45 + 5 x your level XP per 20 s kill; real grinding has eating and drinking in it, so a near tie stays). A quest whose mobs you pass anyway costs next to nothing and always stays. Quests whose work is within 400 yards of each other are also weighed together, so two quests sharing one long walk can't each look cheap. Quests in a region (1,500 yards) are weighed together too, and so is everything on another continent, since one ocean crossing can carry a dozen quests that each look cheap on their own. Class quests, gear upgrades and the must-do extras below are never dropped, and neither are quests in your log at your level. The hint box says how many were skipped, `/ladder skipped` lists them with the travel each would add, and `/ladder trips` turns the check off.
- **Move on from quests you've outgrown.** A quest in your log 3 or more levels under you gets the same "worth the walk" check, so the route stops dragging you back to an old zone for it. It stays while it's on the way or its XP still pays for the walk: Classic only cuts quest XP once you're 6 levels above a quest, so most do at first; it goes when the trip is what it costs. A chain that leads on to a quest still worth doing carries that quest's XP. Class quests, gear upgrades, must-do extras and timed quests always stay. The hint box names the ones left out: "Outgrown: 2 quests in your log are not worth the trip any more: Arugal's Folly [15], ... - abandon them to free log space (log 34/40)". Abandoning one means it isn't suggested again. `/ladder outgrown` lists them with the XP and travel.
- **A full quest log.** With 39 or 40 quests in your log, the hint box says which to drop first to make room: the outgrown ones the route left out, then outgrown ones you haven't started, least XP first ("Quest log 40/40: to make room, drop the weakest first: ..."). Never a quest you've made progress on or one at your level.
- **Take it or leave it.** Talk to a quest giver and the hint box says, for each quest they offer, whether to take it and why: "Take: Raptor Horns - on your route (step 12)", "Skip: Southsea Freebooters - grey for you (level 14): next to no XP", "Skip: ... - not worth the walk: 740 XP for 6:10 of travel", "Take: ... - worth its XP but not planned yet: take it and the route adds it". Other reasons: too little XP for your level, too high for now, a dungeon quest, one you dropped before, a full log. It's only advice; accepting stays yours (auto-accept only ever takes quests on the route).
- **Where to go next.** When fewer than 5 quests worth doing are left near you, the hint box names the area on your continent with the most of them, and how far it is: "Next area: 12 quests worth doing in Hillsbrad Foothills (around Magistrate Burnside), ~4:10 by flight". Once you're there, the plan picks them up.
- **Accept it while you're standing there.** A quest giver the route passes twice gets visited for that quest the first time, so its mobs are killed together with the others' instead of on a second trip out.
- **Finish what's around you first.** Work within 200 yards of you (quests to accept, mobs, turn-ins) goes before anything far away, as long as that adds no more than 90 s of walking.
- **Mobs 2+ levels above you wait.** Kill or loot steps whose mobs (from QuestieDB) are 2 or more levels above you come after enough of your other quests are turned in to level you up. That's about 4-7 turn-ins per level (more at higher levels); "go talk to" quests count less, and the bar in your XP counts too. It never waits for more turn-ins than the plan has, so nothing gets stuck. NPCs friendly to you don't count: "speak to Neeru Fireblade" is a level-37 "monster" in QuestieDB, but it's a talk. Kill steps show the mobs' level, in orange when they're 2+ above you.
- **Timed quests go first.** Once a timed quest is in your log (Apothecary Zamah: bring the Rendered Spores to Thunder Bluff before the time limit is up), what's left of it moves to the front of the route, nearest first, ahead of everything else; mob levels don't hold it back, and no hearth, inn or flight-path detour is put before it. The guide's first line counts down every second: "[watch] Timed: Apothecary Zamah - 23:41 left - bring [Rendered Spores] to Apothecary Zamah (it goes first)", in red for the last 2 minutes. The time comes from the game's quest timer; when the game doesn't report one but the quest text says there's a time limit, the quest still goes first and the line points at the timer in your quest log. A timed quest you skipped with `/ladder skip` isn't rushed.

**Speed-leveling** (0.5.0: what Classic speed-levelers do, as rules on QuestieDB's data; no guide's route is bundled)
- **Grind here first.** When the plan runs out of turn-ins before mobs that would be 2+ levels above you, a stop goes in right before that step: "Grind first: kill Bristleback Quilboar (lvl 19-20) around here until 6 bars into level 20 (about 15 min) - Witchwing Raptor ahead is level 24". It picks mobs at your level near where you'd leave from: the route's own quest mobs first, else QuestieDB's. It's at most about 15 minutes, gets the mobs a "Grind" nameplate box, and ends by itself when your bar gets there (`/ladder grind` turns it off).
- **Die and res, when that's quicker.** Dying on purpose sends your spirit to the nearest graveyard. When that graveyard is next to your next stop and that beats walking or flying by a clear margin, the hint box says so: "Faster: die on purpose and res at the spirit healer - you'd appear at the graveyard by Razor Hill, 30 yd from your next stop: about 0:40 instead of 2:47 (no res sickness up to level 10; 25% durability)". Classic's res sickness counts: none up to level 10, a minute per level over 10, ten minutes from 20. It only costs time when you'd have to fight before it wears off; turn-ins and flights right after count against it. Graveyards come from the game's own list when Forever gives one, plus every graveyard you've released at (`/ladder dietravel` turns the tip off).
- **Watch for named mobs whose drop starts a quest** (Owatanka, Washte Pawne, Lakota'mani). When your route passes where one lives: "Watch for: Owatanka (lvl 24) around here in The Barrens - its drop starts Owatanka (+1650 XP). /tar Owatanka shows if it's up". Its nameplate gets a "Quest drop" box.
- **Hearth on cooldown.** When the route says hearth but the stone is cooling down, the hint box counts it down. From 2 minutes up it adds that it's a good moment for a break, since the cooldown keeps ticking while you're logged out.
- **Learn a profession for an XP quest.** A quest worth doing that only needs Cooking, First Aid or Fishing gets a line naming the nearest trainer (click for a map pin), the quest and its XP, for example Soothing Turtle Bisque or Forever's Camping 101: First Aid.
- **Escorts and group quests.** An escort's ~4 minutes of walking count in the "worth the walk" check. A new quest whose mobs are all elites at or near your level needs a group: solo, it's left out (`/ladder skipped` and the quest dialog say so) unless it's a class quest, an upgrade or a must-do extra. `/ladder groupquests` plans them anyway, and elite objectives show "(lvl 21 elite)".

**Hint box** (under the guide)
- "Don't leave yet: grab [Old Book] from the Dusty Bookshelf nearby". It appears when an item objective sits within about 70 yards of the quest giver. If you walk away without it you get "You left without [Old Book]".
- "You were given [item] for <quest>" when the giver hands you something to use later. "Use [item] on <NPC> for <quest>" when the current step needs an item you carry, once you've selected what it's used on; before that, "Select <NPC or object> (target it, or face it) to use [item]". The game flags some of these; the rest come from QuestieDB: items the quest requires, the item its giver handed you, and quest items linked to it. That includes quests with no tracked objectives, like using the Symbol of Life to resurrect Deathguard Falgan; the step's line then reads "Use [item] on <NPC>, then turn in â€¦". These hints are worked out live, so they're still there after a `/reload`.
- "Right-click [item] in your bags, it starts a quest".
- Questie's hidden-objective notes, escort warnings, timed-quest countdowns (when the guide is hidden; otherwise the guide shows them), "turn in X right here".
- Reward picks ("Reward: pick Kobold Boots (upgrade +40%)") and bag warnings ("free 2 more slots before step 5").
- A **use-item button** next to the hint box. A quest item shows up there only when it's for the step you're on and you've selected what it's used on: you target the NPC, or face the object (soft target). Standing within 40 yards of where QuestieDB has the target also counts, because some targets, like the spot at the bottom of the Stagnant Oasis, can't be selected. When nothing is known to aim at, being within 60 yards of the step's place counts. Going somewhere out of order works too: an item for a step further down the ladder shows by the same rule, as "Use [item] on <target> for <quest> (step N, but you're here)", and this step's item gets the button first when both are ready the same way. An item for what you've selected comes before one you're only standing near, so the button always holds the item the hint tells you to use, and that hint ends with how: " - click the use button", or " - press <key>" once you've bound one. From afar, a later step's item stays out of the hint box and off the button. In combat the game doesn't let add-ons change the button, so target first, then pull. The button also offers quest-starting items in your bags and the Hearthstone when the route says to hearth. Bind a key to it under Options â†’ Keybindings â†’ AddOns â†’ "Quest Ladder: use the suggested quest item".

**Boxes in the interface** (RuneLite-style, cyan unless you pick another color; `/ladder highlights` to toggle)
- The quest item to use, or the Hearthstone when it's time to hearth, gets boxed inside your open bags.
- If your bags are closed, the bag button that holds the item is boxed with "Open".
- Upgrades in your bags get "Equip".
- With a vendor window open, the junk and old gear to sell get "Sell".
- In the quest-complete window, the reward to pick gets "Pick this".
- Works with **Blizzard's bags, Bagnon (and Bagnonium) and Baganator**: the box goes on the item inside their window. With a one-big-inventory add-on, closed bags show the box on the backpack button, because that's what opens everything.

**Markers in the world** (`/ladder marks` to toggle)
- **NPCs**: quest mobs, quest givers, turn-ins, innkeepers and flight masters for the current step get a box on their nameplate, with a label ("Kill", "Turn in", "Use item on") under it so the name above stays readable. Quest givers are friendly NPCs, so turn on friendly nameplates with `/ladder npcplates`. Quest mobs, including mobs that drop a quest item, need enemy nameplates (press V). If they're off, the add-on tells you once per session.
- **Objects** (books, crates, ore, herbs): WoW doesn't let add-ons draw on 3D objects. Instead, when the thing you're facing is the objective, the hint box shows ">> This one: Loot Dusty Bookshelf - press your Interact key" and plays a ping. When it's something you use a quest item on instead, like the Bubbling Fissure at the Stagnant Oasis, the line says so: ">> This one: Use [Dried Seeds] on Bubbling Fissure for The Stagnant Oasis - click the use button". The same goes for your target: "Target is right" gives way to the use line. The game also gives the object you face a small nameplate, and that gets the box around its name. `/ladder interacticons` turns on Blizzard's own icons over interactable objects so you can see them coming.
- **Places**: small squares on the minimap and world map at the objective's spawn points (`/ladder minimap` and `/ladder worldmap` switch each one). This needs the **HereBeDragons** library installed from CurseForge. Questie ships its own copy, but it's private to Questie and other add-ons can't use it.

**Travel: hearthstone and flight paths** (`/ladder flights|hearth|bind|discover`)
- **Flights count as AFK time.** Time in the air is weighted at about a third of walking time, since your character travels safely while you're away. A flight is only used when it's a real shortcut: less hands-on time than walking, and no more than 15% longer in total, so no detours. Flight times are rough estimates; the game doesn't expose real ones.
- **Both ways are shown, and either one works.** The step's travel line compares walking with the best flight from where you stand, for example "Fly: Undercity -> The Sepulcher - 2:31 total, 1:05 of it AFK in the air (walking takes 3:04)" or "Walk: 1:53 (flying Undercity -> The Sepulcher: 3:43, 1:05 AFK)". A flight more than twice as slow isn't mentioned. It's re-checked every second. Walk off instead of taking the bat and the guide switches to walking, with the arrow on the objective, once that's quicker from where you are. Take a flight it didn't suggest and it carries on from where you land. The arrow points at the flight master only while flying is the way.
- **Zeppelins are connector rides, not shortcuts.** What players report: Forever has Classic's three Horde zeppelins (Orgrimmarâ€“Undercity, Orgrimmarâ€“Grom'gol, Undercityâ€“Grom'gol). Each docks for 60 s and leaves every 3-5 minutes. There's no departure timer in the game, so the wait is anywhere from 0 to a full cycle, and at Forever's launch some got lost for 10+ minutes. Guides use them to change continents, or to reach Grom'gol in the mid-30s.
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
- **Grab flight paths on the way**: undiscovered flight masters within about a 1 minute detour get a step: "Discover flight path: ...". Talking to the flight master is enough. Blizzard's retired test points ("zzOLD Powderfuse Port", which sits on top of Ratchet's) are ignored.
- **It learns which flight paths you know** each time you open a flight map, from the paths the map lets you fly to. The game's own "undiscovered" flag is always off on Forever, so until you've opened a flight map once, it assumes you know none and plans no flights.
- It learns your inn's location when you bind or hearth. It learns the cooldown the first time you use it.

**Bags panel** (`/ladder bags`)
- What to sell (junk, gear worse than yours or unusable), what to destroy (quest items no quest needs), what's worth more on the AH, and upgrades sitting in your bags.
- **Crafting materials are never "Sell" or "Destroy".** Cloth, leather, herbs, ore and bars, meat, elemental and enchanting materials, gems, recipes, and anything the game itself flags as a crafting reagent are money: when your bags are short they're suggested for the bank (or the AH), never boxed for the vendor, and a vendor stop doesn't count them. Plain gray junk is still sold.
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

**Forever extras** (for an easy, casual climb; from Wowhead's Forever guides, with the facts read from QuestieDB and the game)
- **Must-do quests stay in the plan** whatever their XP, and their step says why: Camping 101 and The Great Outdoors (they unlock your camp items: a tent for rested XP, a chair for crit and so on), Library book quests, the Cozy Sleeping Bag chain, supply crate quests, and any quest that rewards a bag bigger than your smallest one.
- **Quests that start from an item you find** (a Library book, a note on a plank) are planned at the spot where the item lies: "Pick up The Dalaran Digest, Vol. 23 here and right-click it to start The Dalaran Digest". Only items from a few fixed spots, never mob drops.
- **Bags.** A reward choice with a bigger bag than your smallest one beats the best sell value. While your smallest bag has under 10 slots, the hint box suggests the biggest bag a vendor near you sells that you can afford after the gold kept for training and riding ("More bag space: a Heavy Brown Bag (10 slots, about 1g) from ...").
- **Riding at 40.** From level 35 Quest Ladder keeps 100g aside for Apprentice Riding (AH suggestions don't spend it); from 38 the hint box says so, and at 40 it names your race's riding trainer. The mount vendor next to them gives your first mount free. Paladins and Warlocks get their mount and riding from a class mount quest instead, so nothing is kept aside for them.
- **Click for a map pin.** Hint lines that name a place (where the Cozy Sleeping Bag chain starts, a bag vendor, your riding trainer, the supply crate NPC) end with "(click for a map pin)". Clicking puts the map pin (or a TomTom arrow) there and says where in chat; the route's own pin comes back when you move on to the next step.
- **Cozy Sleeping Bag.** From level 14, until you have it: where the 6-step chain starts, with coordinates and its levels ("quests level 22-32, you can start from level 14"), for a +3% XP sleeping bag and a 12-slot bag on the way. Once a step is in your log, the route plans it like any quest.
- **Waylaid supply crates.** When one drops, the hint box says what it wants and who takes the finished Supply Shipment for Merchant's Favor (your faction's "Inventory Intake" NPC, from QuestieDB). Their quartermaster sells 10-18 slot bags.
- **Dungeon quests.** `/ladder dungeons` lists the dungeon quests around your level you can pick up now, by dungeon, with who gives them. In Forever most dungeon XP comes from these quests, so grab them before you go.
- Worth knowing (not automated): Well Fed food now adds 5% XP from kills; the Legacy perks Thrill of Adventure, Well Rested and Talented help levelling; on a flight, Request Stop drops you at the next flight point on the route.

## Commands

| Command | |
|---|---|
| `/ladder` | show/hide |
| `/ladder options` | the options window (also Game Menu > Options > AddOns > Quest Ladder) |
| `/ladder compact` | compact mode on/off: just the current step |
| `/ladder theme [name]` | list the color themes, or switch: cyan, pink, lavender, gold, green, red, frost |
| `/ladder minimap` / `worldmap` | the squares on the minimap / world map on/off |
| `/ladder lock` | lock the guide window in place, or unlock it |
| `/ladder replan` / `skip` / `unignore [id]` | rebuild route / skip step / clear skipped quests (or just one). A quest you abandon isn't suggested again either; accept it again, or `unignore <id>`, to change your mind |
| `/ladder bags` / `gear` | panels |
| `/ladder reserve 4` | bag slots to keep free (default 2) |
| `/ladder gold 5g` / `gold auto` | gold kept for training |
| `/ladder minxp <percent>` | skip new quests worth less than this share of a solid quest's XP at your level (default 50, 0 = plan all) |
| `/ladder skipped` / `outgrown` | the quests left out of the plan, and why: new ones (not worth the walk, or too little XP), quests in your log you've outgrown, and with a full log, the weakest to drop first |
| `/ladder trips` | the "worth the walk" check on/off, for new and outgrown quests (default on) |
| `/ladder dungeons` | dungeon quests you can pick up now, by dungeon |
| `/ladder dungeons plan` | plan dungeon quests or not (default not) |
| `/ladder groupquests` | plan new quests against elites at your level (default off: they need a group) |
| `/ladder grind` | "Grind first" stops before mobs that would be too high (default on) |
| `/ladder dietravel` | the "die and res, it's quicker" tip (default on) |
| `/ladder arrow` | show Blizzard's arrow to Quest Ladder's pin when the game draws it see-through (default on) |
| `/ladder weight agi 1.5` / `weight reset` | stat-weight overrides |
| `/ladder auto` | auto accept/turn-in on/off |
| `/ladder autopick` | also auto-choose the best reward (default off) |
| `/ladder unstarted` | plan only your current log, or nearby quests too |
| `/ladder waypoints` / `hints` | toggles |
| `/ladder flights` / `hearth` / `bind` / `discover` | travel features on/off |
| `/ladder highlights` / `marks` | interface boxes / nameplate markers and the "This one" cue on/off |
| `/ladder interacticons` | Blizzard's icons over interactable objects |
| `/ladder npcplates` | friendly NPC nameplates (so quest givers can be marked) |
| `/ladder diag [label]` / `diag now` / `diag clear` | run the in-game checks below and save the results (see "Verify in game"); it waits until the route is planned, `diag now` doesn't |

## Rules: what it does and doesn't do

Everything runs inside the normal add-on sandbox. It uses only read APIs (quest log, map, bags, items) and the public APIs of QuestieDB and Auctionator. Nothing reads memory, network traffic or files.

- **No movement, targeting or combat automation.** You walk the route. The waypoint is the same map pin you'd place yourself.
- **Quest automation only happens inside an NPC dialog you opened**, the same way Leatrix Plus and Questie work. It only accepts quests in the plan, completes quests that are done, and takes the reward only when there's no choice (or when you turn on `autopick`). Hold **Shift** while talking to an NPC to suspend it.
- **Item use is always your click or key press**, through a standard secure action button.
- **Highlights and markers are display-only.** They're overlay frames on Blizzard's buttons and nameplates and pins on the map, the same kind of thing Pawn, Plater and Questie do. The CVar presets only change settings you could change yourself in Options, and only when you type the command or click its button in Quest Ladder's options. The one change to a Blizzard frame is making its arrow to Quest Ladder's own pin visible when Forever draws it see-through (`/ladder arrow`), from a hook that runs after Blizzard's own update.
- **AH purchases are manual.** The add-on only recommends and opens a search.
- It is free and the code is fully visible, as Blizzard's add-on policy requires.

## How it works (for review)

| File | Role |
|---|---|
| `Core.lua` | settings, events, background-job scheduler (5 ms/frame budget), slash commands |
| `Theme.lua` | the color themes, your own color picks on top, and the icon's path; everything that draws asks it for colors and repaints when they change |
| `Geo.lua` | AreaIDâ†’UiMap (QuestieDB support data), mapâ†’world yards via `C_Map.GetWorldPosFromMapPos`, spawn clustering |
| `Data.lua` | QuestieDB adapter: quest projection, spawn points, availability rules (Questie's `IsDoable` when loaded, its own rules otherwise), background indexes (quest givers by area, chain follow-ups, quest-reward gear, gear by level, vendors, trainers) |
| `QuestState.lua` | live quest log, objectives, rewards, special items, bags |
| `Planner.lua` | **pure logic**: tasks (pickup â†’ objectives â†’ turn-in, chain edges), greedy nearest-feasible route, then Or-opt block moves (1-8 tasks, so a whole stop can move at once) with O(1) travel deltas and 2-opt reversals of stretches of stops (turns a there-and-back zigzag into one sweep; tasks at one stop keep their order); respects precedence, quest-log capacity and skipped-quest tiers. Because the improvement step only moves stops a little at a time, it also starts over from two other first guesses, one with flights counted at full time and one walking only, polishes each under the normal costs, and keeps whichever route is cheapest (by at least 10 s). At Sun Rock Retreat that turned "walk to the north Barrens and fly back for two turn-ins 150 yd away" into finishing Sun Rock first, about 5 minutes faster. Plans over 90 tasks only get the normal start, so the guide keeps up. New quests whose detour earns less than grinding would are dropped one at a time, worst first, and the route is polished again ("worth the walk", above). Then "while you're here": quests that are already finished get turned in at the earliest point where you're within 600 yd of the NPC and it costs little extra travel (10 s, plus 0.1 s per second you'd otherwise carry the quest, at most 2 min). It never adds a flight there and back. Level waits (objectives with mobs 2+ above you wait for turn-ins): planned by travel alone first, then fitted in at the cheapest valid places and polished. Pickups move to the first visit to their giver; work within 200 yd of you goes first. The "worth the walk" check (PruneTrips) takes new quests, and quests in your log you've outgrown, out of the route on paper one at a time, by area (400 yd), by region (1,500 yd) and by continent, and drops the worst while its XP is under 75% of grinding for the time it saves. It groups tasks within 90 yd into steps and simulates bag usage along the route |
| `Travel.lua` | cost model (walk / mount / AFK-weighted flights with a no-detour rule); hearth-aware routing (try the best split points, re-solve the rest from the inn, keep a split only if it passes the dead-end / full-cooldown rules, up to two hearths); inn comparison; flight-path pickups; learning bind point and cooldown |
| `Highlight.lua` / `WorldMarks.lua` | boxes on bag items (Blizzard, Bagnon, Baganator), bag buttons, rewards; nameplate markers, soft-target cue, minimap/map squares |
| `Ladder.lua` | builds the planning context (quests you haven't picked up are searched around you and around the places on your continent your quests already send you, so nearby work gets bundled into those trips), matches live objectives to QuestieDB entries by name, picks each objective's camp on the quest's own continent near its NPC (murlocs live in Silverpine and Darkshore), falls back to the game's own quest POI for new Forever quests, marks the quests in your log you've outgrown (3+ levels under you; MarkOutgrown), says whether to take a quest an NPC offers (QuestVerdict) and which to drop when the log is full (WeakestInLog), tracks progress, sets waypoints, adds trainer and vendor stops |
| `Hints.lua` | reminder rules, the use-button rule, and the take-or-leave lines while a quest dialog is open |
| `Bags.lua` / `Gear.lua` | bag suggestions; stat-weight scoring, reward choice, AH search via Auctionator |
| `Goodies.lua` | Forever extras: must-do quests, bag upgrades, riding at 40, the Cozy Sleeping Bag chain, supply crates, dungeon quests |
| `Speed.lua` | speed-leveling rules: "Grind first" stops (GrindStop, on the planner's turn-ins-per-level estimate), die-and-res travel (graveyards from C_DeathInfo plus ones you've released at; Classic res sickness), named mobs whose drop starts a quest (QuestieDB item `startQuest`, 3 droppers or fewer), the hearth-cooldown break, secondary professions that unlock a quest, escort time and elite (group) quests |
| `Automation.lua` | dialog automation described above |
| `UI.lua` | guide (compact mode, width, lock), hint box, secure use button (parented to UIParent so the add-on's frames never become protected in combat), panels, tooltip notes |
| `Options.lua` | the options pages in Blizzard's options window (canvas pages built from plain frames on first open), Blizzard's color picker, and the minimap add-on menu entry (`AddonCompartmentFunc`) |
| `Diag.lua` | `/ladder diag`: runs the "Verify in game" checks (read-only, pcall'd, secret-safe) and stores the last 10 runs in the `QuestLadderDiag` saved variable |

Tests: `cd tests && lua5.1 run.lua` (820 checks against a fake client and a fake QuestieDB) and `lua5.1 bench.lua` (about 0.3 s to plan 108 tasks offline; the improvement step walks about 25% less than nearest-next).

## Verify in game (not testable offline)

The logic is tested offline. These client behaviours need a first in-game pass, and each is wrapped in `pcall` or a feature check so a mismatch degrades instead of erroring.

**`/ladder diag`** runs all of them at once and prints anything that isn't OK. Some checks need a situation, so run it again where it matters, with a label: `/ladder diag turnin` in a quest-complete window, `/ladder diag mobs` near quest mobs, `/ladder diag object` while facing a quest object, `/ladder diag bags` with your bags open. Right after `/reload` it first waits (up to 30 s) until the quest index is built and the route is planned, so it doesn't save the first, log-only plan; wait for its results in chat before you `/reload`. `/ladder diag now` skips the wait. Then `/reload`: the client writes the last 10 runs to `WTF\Account\<account>\SavedVariables\QuestLadder.lua` (`QuestLadderDiag`), where they can be read outside the game. It also records errors Quest Ladder caught this session. Nothing else reads that table, so it's unaffected by the SavedVariables restore bug. `/ladder diag clear` empties it.

1. `C_Map.GetWorldPosFromMapPos` returns positions on Forever maps. If it doesn't, distances are unknown and the guide says "location unknown".
2. The waypoint pin appears (`C_Map.SetUserWaypoint` + super-tracking), or TomTom's arrow. Without TomTom, the arrow on screen is the game's In-Game Navigation marker. Forever's settings have no option for it (its settings code leaves the In-Game Navigation checkbox out, and the `showInGameNavigation` CVar isn't there). The diag's waypoint check records what the game is navigating to, whether it made a navigation frame, and its alpha and edge arrow. On 2026-11-22 the arrow frame was placed and its edge arrow pointed the right way, but the game rated a pin 5,300 yd away "Invalid" (state 0), which Blizzard draws at alpha 0 (the user's own pin too). Since 0.5.0 a hook that runs after the frame's UpdateAlpha (hooksecurefunc) shows it while the tracked pin is Quest Ladder's.
   - 2b. **Graveyards (0.5.0)**: whether `C_DeathInfo.GetGraveyardsForMap` lists the graveyards on an open-world map in Forever. The diag's "Speed-leveling" check records what it returned for the map you're on. If it lists none, the die-and-res tip only uses graveyards you've released at.
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
13. **Options window, icon, add-on menu and Reload (0.6.0)**: Reload UI calls `ReloadUI` (Forever's own AddOns list does the same); the pages register with Blizzard's options (`Settings.RegisterCanvasLayoutCategory`), the color picker opens (`ColorPickerFrame:SetupColorPickerAndShow`), Quest Ladder is listed in the minimap's add-on menu, and the icon shows in the AddOns list, the options list, the guide's corner and chat. Forever's UI code has all four (its own AddonCompartment and ColorPickerFrame files); the diag's "options" check records what this client did.

## Known limits

- QuestieDB doesn't have every new Forever quest yet. Those use the game's own quest POI once they're in your log, and they can't be suggested before you pick them up.
- Stat weights are leveling heuristics per class. Random-enchant AH items ("of the Bear") can't be scored from their base ID and are flagged.
- Weapons are compared one item at a time. With a two-hander equipped, a one-hander or a shield is compared against that two-hander (it would replace it), but a one-hander + shield *pair* isn't scored as a set. One-handers only count for the off hand if you can dual wield.
- The trainer reminder assumes new ranks on even levels.
- Walking distances are straight lines. WoW gives add-ons no terrain or pathing data, so mountains, cliffs and rivers aren't known: the arrow can point across a ridge you have to walk around, and arrival times run short in rough terrain.
- Flight times are estimates (straight line x1.25 at ~32 yd/s). They only decide whether a flight is a detour, and you can AFK on it anyway. Zeppelin waits and rides are estimates too (about 2:30 on average, up to 5:30, and 1:40 aboard); the real schedule isn't available to add-ons. If a zeppelin doesn't show up, the guide can't know. Boats aren't modelled: QuestieDB has no masters for them. Without a zeppelin, another continent counts as a flat 15-minute cost.
- Step time estimates (about 20 s per kill, 28 s per drop) feed the "an hour of steps" rule, so treat it as approximate.
- The level wait counts turn-ins (about 4-7 per level) rather than adding up quest and kill XP. It replans when you level up, so a wait that was too long or too short corrects itself then. Mob levels come from QuestieDB; Forever may have changed some.
- Nothing can be drawn around 3D objects. That's a WoW limit, not this add-on's; the soft-target cue, the box on the faced object's nameplate and the map boxes stand in for it.
- Forever has a known bug where SavedVariables sometimes fail to load after a full restart. Settings can then fall back to defaults, but the route is always rebuilt live.

## License

MIT, see [LICENSE](LICENSE). Quest Ladder reads QuestieDB, Questie, Auctionator and HereBeDragons only through their public APIs and includes none of their code.
