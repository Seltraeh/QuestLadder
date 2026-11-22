-- Quest Ladder: WoW: Forever extras that make levelling easier for a casual player.
--   * must-do quests the low-XP filter would otherwise skip (camping unlocks, Library books,
--     the Cozy Sleeping Bag chain, supply crates, quests that reward a bigger bag)
--   * bag upgrades: bag quest rewards, and a bigger bag to buy when you have room for one
--   * riding at 40: where to train (the gold is kept aside in Gear.Reserve)
--   * the Cozy Sleeping Bag chain, Waylaid supply crates, dungeon quests to pick up
-- Facts come from QuestieDB (quests, items, NPCs) and the game (bags, money, skills).
-- Everything here only plans and hints: nothing is bought, used or accepted for you.

local _, ns = ...
local Goodies = {}
ns.Goodies = Goodies

local Data, Geo = ns.Data, ns.Geo

Goodies.COZY_BAG = 211527                 -- Cozy Sleeping Bag: up to +3% XP while it lasts
Goodies.COZY_LEVEL = 14
-- "...and that note you found" (one per faction) -> Stepping Stones -> Scramble -> Wet Job ->
-- Eagle's Fist -> This Must Be The Place (QuestieDB's nextQuestInChain links)
Goodies.COZY_CHAIN = { 79007, 79008, 79192, 79980, 79974, 79975, 79976 }
Goodies.COZY_FINAL = 79976
Goodies.LIBRARY_SORT = -284               -- QuestieDB's quest category for the Library books
Goodies.SHIPPING_LABEL_QUESTS = { [98247] = true, [98248] = true }
Goodies.SEALED_CRATE_QUEST = 91899        -- "A Sealed Crate": its NPCs take the supply shipments
Goodies.RIDING_LEVEL = 40

local cozySet = {}
for _, id in ipairs(Goodies.COZY_CHAIN) do cozySet[id] = true end
Goodies.IsCozyChain = function(id) return cozySet[id] == true end

local function zoneName(mapId)
    if not (mapId and C_Map and C_Map.GetMapInfo) then return nil end
    local ok, info = pcall(C_Map.GetMapInfo, mapId)
    if ok and type(info) == "table" and type(info.name) == "string" and not ns.IsSecret(info.name) then return info.name end
    return nil
end
Goodies.ZoneName = zoneName

local function friendlyNpc(npcId, player)
    local f = Data.Npc(npcId, "friendlyToFaction")
    local mine = (player and player.faction == "Horde") and "H" or "A"
    return f == nil or f == "AH" or f == mine
end

---------------------------------------------------------------------------
-- Bags
---------------------------------------------------------------------------
local slotCache = {}

--- Slots of a bag item, from its tooltip ("10 Slot Bag"), or nil while unknown.
function Goodies.BagSlots(itemId)
    if not itemId then return nil end
    if slotCache[itemId] then return slotCache[itemId] end
    if not (C_TooltipInfo and C_TooltipInfo.GetItemByID) then return nil end
    local ok, data = pcall(C_TooltipInfo.GetItemByID, itemId)
    if not ok or type(data) ~= "table" or type(data.lines) ~= "table" then return nil end
    for _, line in ipairs(data.lines) do
        local text = type(line) == "table" and line.leftText
        if type(text) == "string" and not ns.IsSecret(text) then
            local n = tonumber(text:match("^(%d+) [Ss]lot"))
            if n then slotCache[itemId] = n; return n end
        end
    end
    return nil
end

--- Your four bag slots: { slots = n or 0 when empty, special = true for quivers/soul bags }.
function Goodies.EquippedBags()
    local out = {}
    for bag = 1, 4 do
        local e = { slots = 0 }
        if C_Container and C_Container.GetContainerNumSlots then
            local ok, n = pcall(C_Container.GetContainerNumSlots, bag)
            if ok and type(n) == "number" and not ns.IsSecret(n) then e.slots = n end
            if e.slots > 0 and C_Container.GetContainerNumFreeSlots then
                local okF, _, family = pcall(C_Container.GetContainerNumFreeSlots, bag)
                if okF and type(family) == "number" and not ns.IsSecret(family) and family ~= 0 then e.special = true end
            end
        end
        out[bag] = e
    end
    return out
end

--- The smallest of your normal bags (0 when a slot is empty). Special bags don't count.
function Goodies.SmallestBag()
    local smallest
    for _, e in ipairs(Goodies.EquippedBags()) do
        if not e.special and (not smallest or e.slots < smallest) then smallest = e.slots end
    end
    return smallest or 0
end

--- Would a bag with this many slots give you more room (replacing your smallest one)?
function Goodies.IsBagUpgrade(slots)
    return slots ~= nil and slots > Goodies.SmallestBag()
end

--- The best bag a quest rewards, if it's an upgrade: { itemId, slots } or nil.
function Goodies.BagReward(questId)
    local best
    for _, itemId in ipairs(Data.bagRewards[questId] or {}) do
        local slots = Goodies.BagSlots(itemId)
        if Goodies.IsBagUpgrade(slots) and (not best or slots > best.slots) then best = { itemId = itemId, slots = slots } end
    end
    return best
end

--- A bigger bag you could buy now: the most slots you can afford after the gold kept for
--- training and riding, from the nearest vendor that sells it. Only when your smallest bag has
--- under 10 slots. Price: vendors charge about 4x what they pay you.
Goodies.BAG_SHOPPING_BELOW = 10
function Goodies.BagToBuy(player)
    local smallest = Goodies.SmallestBag()
    if smallest >= Goodies.BAG_SHOPPING_BELOW or not player.point then return nil end
    local spare = (player.money or 0) - ns.Gear.Reserve(player.level, player)
    local best
    for _, e in ipairs(Data.vendorBags or {}) do
        local slots = Goodies.BagSlots(e.itemId)
        local info = ns.Gear.ItemInfo(e.itemId)
        local price = info and (info.sellPrice or 0) * 4
        if slots and slots > smallest and info and (info.minLevel or 0) <= player.level and price and price <= spare
            and (not best or slots > best.slots or (slots == best.slots and price < best.price)) then
            local vendor, dist
            for _, npcId in ipairs(e.vendors) do
                if friendlyNpc(npcId, player) then
                    for _, p in ipairs(Data.NpcPoints(npcId)) do
                        local d = Geo.Distance(player.point, p)
                        if d and d < math.huge and (not dist or d < dist) then vendor, dist = { id = npcId, point = p }, d end
                    end
                end
            end
            if vendor then
                best = { itemId = e.itemId, name = info.name, slots = slots, price = price,
                         vendor = Data.NpcName(vendor.id), point = vendor.point, dist = dist }
            end
        end
    end
    return best
end

---------------------------------------------------------------------------
-- Must-do quests: worth it whatever their XP (Ladder.WorthDoing asks)
---------------------------------------------------------------------------
--- A short note on why this quest matters, or nil.
function Goodies.MustDo(questId)
    local db = Data.Quest(questId)
    if not db then return nil end
    local name = db.name or ""
    if name:find("^Camping 101") then return "unlocks a camp item" end
    if name:find("^The Great Outdoors") then return "unlocks camping" end
    if db.zone == Goodies.LIBRARY_SORT then return "Library book" end
    if cozySet[questId] then return "Cozy Sleeping Bag chain" end
    if name == "A Sealed Crate" or Goodies.SHIPPING_LABEL_QUESTS[questId] then return "supply crate" end
    local bag = Goodies.BagReward(questId)
    if bag then return string.format("rewards a %d-slot bag", bag.slots) end
    return nil
end

---------------------------------------------------------------------------
-- Riding at 40
---------------------------------------------------------------------------
-- The trainer for your race's mount (QuestieDB subName), else the nearest riding trainer.
local RACE_MOUNT = {
    Orc = "Wolf", Scourge = "Undead Horse", Troll = "Raptor", Tauren = "Kodo",
    Human = "Horse", Dwarf = "Ram", NightElf = "Tiger", Gnome = "Mechastrider",
}

function Goodies.RidingTrainer(player)
    local want = RACE_MOUNT[player.raceFile or ""]
    local best, bestDist, bestRace
    for _, e in ipairs(Data.trainers or {}) do
        local sub = type(e.subName) == "string" and e.subName or ""
        if sub:find("Riding") and not (type(e.name) == "string" and e.name:find("^World ")) and friendlyNpc(e.npcId, player) then
            local isRace = want ~= nil and sub == (want .. " Riding Trainer")
            local d = player.point and e.point and Geo.Distance(player.point, e.point) or math.huge
            local better
            if not best then better = true
            elseif isRace ~= bestRace then better = isRace -- your race's trainer first
            else better = d < bestDist end                  -- then the nearest
            if better then best, bestDist, bestRace = e, d, isRace end
        end
    end
    return best
end

--- One line about riding, or nil: from level 38 until you can ride.
function Goodies.RidingHint(player)
    local level = player.level or 0
    if level < Goodies.RIDING_LEVEL - 2 then return nil end
    local riding = ns.Travel and ns.Travel.RIDING_SKILL
    if player.skills and riding and player.skills[riding] then return nil end
    if player.classFile == "PALADIN" or player.classFile == "WARLOCK" then
        if level < Goodies.RIDING_LEVEL then return nil end
        return "|cff66ccffRiding:|r your class mount quest is ready - ask your class trainer. It gives the mount and the riding skill, no gold needed."
    end
    local money = player.money or 0
    local cost = ns.Gear.RIDING_COST
    if level < Goodies.RIDING_LEVEL then
        return string.format("|cff66ccffRiding at 40:|r Apprentice Riding costs %s (the first mount is free). You have %s; Quest Ladder keeps it aside.",
            ns.FormatMoney(cost), ns.FormatMoney(money))
    end
    local t = Goodies.RidingTrainer(player)
    local where = t and string.format(" from %s%s", t.name or "your riding trainer",
        zoneName(t.point and t.point.mapId) and (" (" .. zoneName(t.point.mapId) .. ")") or "") or ""
    -- the trainer comes back too, for the hint's map pin
    if money >= cost then
        return string.format("|cff66ccffLearn Apprentice Riding|r (%s)%s - the mount vendor next to them gives your first mount free.",
            ns.FormatMoney(cost), where), t
    end
    return string.format("|cff66ccffRiding:|r Apprentice Riding costs %s%s; you have %s.", ns.FormatMoney(cost), where,
        ns.FormatMoney(money)), t
end

---------------------------------------------------------------------------
-- Cozy Sleeping Bag chain
---------------------------------------------------------------------------
--- Where the chain starts for you, once you're 14 and haven't got the bag:
--- { questId, title, point, giver } or nil. Steps already in your log are planned normally.
function Goodies.CozyStart(player, byId, state)
    if (player.level or 0) < Goodies.COZY_LEVEL then return nil end
    local QS = ns.QuestState
    if QS.IsComplete(Goodies.COZY_FINAL) then return nil end
    if ns.Hints and ns.Hints.ItemCount and ns.Hints.ItemCount(Goodies.COZY_BAG) > 0 then return nil end
    for _, id in ipairs(Goodies.COZY_CHAIN) do
        if byId and byId[id] then return nil end -- under way: the route has it
    end
    for _, id in ipairs(Goodies.COZY_CHAIN) do
        local db = Data.Quest(id)
        if db and Data.IsAvailableNow(id, state) then
            local pts = Data.GiverPoints(db.startedBy)
            local best = Geo.Nearest(pts, player.point) or pts[1]
            if best then return { questId = id, title = db.name, point = best, giver = best.giverName } end
        end
    end
    return nil
end

--- The chain's level range from QuestieDB: the lowest level you can start a step at, and the
--- lowest and highest quest levels (79007 can start at 14; its quests are 22 to 32).
function Goodies.CozyLevels()
    local req, lo, hi
    for _, id in ipairs(Goodies.COZY_CHAIN) do
        local db = Data.Quest(id)
        if db then
            local r, l = db.reqLevel, db.level
            if type(r) == "number" and r > 0 and (not req or r < req) then req = r end
            if type(l) == "number" and l > 0 then
                if not lo or l < lo then lo = l end
                if not hi or l > hi then hi = l end
            end
        end
    end
    return req, lo, hi
end

--- "The Barrens 46.4, 73.9" for a point, or nil.
function Goodies.PlaceText(point)
    if not (point and point.x and point.y) then return nil end
    local zone = zoneName(point.mapId)
    return string.format("%s%.1f, %.1f", zone and (zone .. " ") or "", point.x * 100, point.y * 100)
end

--- A map pin for a hint line (the hint box makes the line clickable): { mapId, x, y, title }.
local function pinFor(point, title)
    if not (point and point.mapId and point.x and point.y) then return nil end
    return { mapId = point.mapId, x = point.x, y = point.y, title = title }
end
Goodies.PinFor = pinFor

---------------------------------------------------------------------------
-- Waylaid supply crates
---------------------------------------------------------------------------
--- The NPC who takes supply shipments for your faction (from "A Sealed Crate"): { name, point }.
function Goodies.CrateNpc(player)
    local db = Data.Quest(Goodies.SEALED_CRATE_QUEST)
    if not db or type(db.finishedBy) ~= "table" or type(db.finishedBy[1]) ~= "table" then return nil end
    for _, npcId in ipairs(db.finishedBy[1]) do
        if friendlyNpc(npcId, player) then
            local pts = Data.NpcPoints(npcId)
            if pts[1] then return { name = Data.NpcName(npcId), point = pts[1] } end
        end
    end
    return nil
end

--- Crates in your bags: { {name, material, kind = "fill"|"turnin"} }.
function Goodies.CratesInBags(bags)
    local out = {}
    for _, s in ipairs((bags and bags.slots) or {}) do
        local info = s.link and ns.Gear.ItemInfo(s.link) or (s.itemId and ns.Gear.ItemInfo(s.itemId))
        local name = info and info.name
        if type(name) == "string" then
            local material = name:match("^Waylaid Supplies: (.+)$")
            if material then
                out[#out + 1] = { name = name, material = material, kind = "fill", itemId = s.itemId }
            elseif name:find("^Supply Shipment") then
                out[#out + 1] = { name = name, kind = "turnin", itemId = s.itemId }
            end
        end
    end
    return out
end

---------------------------------------------------------------------------
-- Dungeon quests to pick up before you go
---------------------------------------------------------------------------
--- Does any objective of this quest exist only inside an instance?
function Goodies.IsDungeonQuest(db)
    local objs = db and db.objectives
    if type(objs) ~= "table" then return false end
    local function instanceOnly(pts, inst) return inst and #pts == 0 end
    for _, row in ipairs(objs[1] or {}) do if instanceOnly(Data.NpcPoints(row[1])) then return true end end
    for _, row in ipairs(objs[2] or {}) do if instanceOnly(Data.ObjectPoints(row[1])) then return true end end
    for _, row in ipairs(objs[3] or {}) do
        local pts, inst = Data.ItemSourcePoints(row[1])
        if instanceOnly(pts, inst) then return true end
    end
    for _, kc in ipairs(objs[5] or {}) do
        local all, any = true, false
        for _, npcId in ipairs(kc[1] or {}) do
            local pts, inst = Data.NpcPoints(npcId)
            any = true
            if not instanceOnly(pts, inst) then all = false end
        end
        if any and all then return true end
    end
    return false
end

local function areaName(areaId)
    if not (areaId and areaId > 0 and C_Map and C_Map.GetAreaInfo) then return nil end
    local ok, name = pcall(C_Map.GetAreaInfo, areaId)
    if ok and type(name) == "string" and name ~= "" and not ns.IsSecret(name) then return name end
    return nil
end

--- Dungeon quests you can pick up now, around your level, grouped by dungeon:
--- { { dungeon = name, quests = { {id, title, level, giver, zone} } } } (sorted by quest level).
Goodies.DUNGEON_LEVELS_BELOW, Goodies.DUNGEON_LEVELS_ABOVE = 3, 6
function Goodies.DungeonQuests(player, state, ids)
    local groups, order = {}, {}
    for _, id in ipairs(ids or {}) do
        local db = Data.Quest(id)
        local ql = db and db.level or 0
        if db and ql >= player.level - Goodies.DUNGEON_LEVELS_BELOW and ql <= player.level + Goodies.DUNGEON_LEVELS_ABOVE
            and (db.reqLevel or 0) <= player.level and Data.IsAvailableNow(id, state) and Goodies.IsDungeonQuest(db) then
            local pts = Data.GiverPoints(db.startedBy)
            local giver = Geo.Nearest(pts, player.point) or pts[1]
            local key = areaName(db.zone) or "Other dungeons"
            if not groups[key] then groups[key] = { dungeon = key, quests = {}, minLevel = ql }; order[#order + 1] = groups[key] end
            local g = groups[key]
            g.quests[#g.quests + 1] = { id = id, title = db.name, level = ql, giver = giver and giver.giverName,
                                        zone = giver and zoneName(giver.mapId) }
            if ql < g.minLevel then g.minLevel = ql end
        end
        ns.MaybeYield(40)
    end
    table.sort(order, function(a, b) return a.minLevel < b.minLevel end)
    for _, g in ipairs(order) do table.sort(g.quests, function(a, b) return a.level < b.level end) end
    return order
end

--- /ladder dungeons: print them in chat (worked out in the background).
function Goodies.PrintDungeonQuests()
    if not (Data.ready and Data.lib and Data.lib.Quest and Data.lib.Quest.GetAllIds) then
        ns.Print("QuestieDB isn't ready yet - try again in a moment")
        return
    end
    local QS = ns.QuestState
    local player = QS.Player()
    local _, byId = QS.Snapshot()
    local state = ns.Ladder.AvailabilityState(player, byId)
    local result
    ns.Async("QuestLadder.dungeons", function()
        result = Goodies.DungeonQuests(player, state, Data.lib.Quest.GetAllIds())
    end, function()
        if not result or #result == 0 then
            ns.Print("no dungeon quests around your level to pick up right now")
            return
        end
        ns.Print("dungeon quests you can pick up now (most dungeon XP in Forever comes from these):")
        for _, g in ipairs(result) do
            local parts = {}
            for _, q in ipairs(g.quests) do
                parts[#parts + 1] = string.format("%s [%d]%s", q.title or "?", q.level or 0,
                    q.giver and (" - " .. q.giver .. (q.zone and (", " .. q.zone) or "")) or "")
            end
            print(string.format("  |cffffd100%s|r: %s", g.dungeon, table.concat(parts, "; ")))
        end
    end)
end

---------------------------------------------------------------------------
-- Hints (called from Hints.Compute)
---------------------------------------------------------------------------
function Goodies.Hints(push, env)
    local plan = env.plan
    local player = plan and plan.player
    if not player then return end
    -- riding
    -- 0.3.29: the hints that name a place carry a map pin; click the line to place it
    local ride, trainer = Goodies.RidingHint(setmetatable({ money = (GetMoney and GetMoney()) or player.money }, { __index = player }))
    if ride then
        push({ priority = 42, kind = "info", text = ride,
               pin = trainer and pinFor(trainer.point, trainer.name or "Riding trainer") })
    end
    -- a bigger bag to buy
    local buy = plan.bagToBuy
    if buy then
        push({ priority = 40, kind = "info", pin = pinFor(buy.point, buy.vendor or "Bag vendor"),
               text = string.format("|cff66ccffMore bag space:|r a %s (%d slots, about %s) from %s%s", buy.name or "bag",
                   buy.slots, ns.FormatMoney(buy.price), buy.vendor or "a vendor",
                   zoneName(buy.point and buy.point.mapId) and (" (" .. zoneName(buy.point.mapId) .. ")") or "") })
    end
    -- the Cozy Sleeping Bag chain: where it starts and its levels, so you can decide when to go
    local cozy = plan.cozyStart
    if cozy then
        local req, lo, hi = Goodies.CozyLevels()
        local levels = (lo and hi) and string.format(" (quests level %s%s)", lo == hi and lo or (lo .. "-" .. hi),
            req and (", you can start from level " .. req) or "") or ""
        local where = Goodies.PlaceText(cozy.point)
        push({ priority = 38, kind = "info", pin = pinFor(cozy.point, cozy.giver or cozy.title or "Cozy Sleeping Bag"),
               text = string.format("|cff66ccffCozy Sleeping Bag:|r a %d-step chain across 5 zones%s rewards a +3%% XP sleeping bag and a 12-slot bag. It starts at %s%s.",
                   #Goodies.COZY_CHAIN - 1, levels, cozy.giver or cozy.title or "a note",
                   where and (" in " .. where) or "") })
    end
    -- supply crates
    local crates = Goodies.CratesInBags(env.bags)
    if #crates > 0 then
        local npc = Goodies.CrateNpc(player)
        local who = npc and string.format("%s%s", npc.name or "the supply depot",
            zoneName(npc.point and npc.point.mapId) and (" (" .. zoneName(npc.point.mapId) .. ")") or "") or "your faction's supply depot"
        local pin = npc and pinFor(npc.point, npc.name or "Supply depot")
        for _, c in ipairs(crates) do
            if c.kind == "fill" then
                push({ priority = 48, kind = "info", itemId = c.itemId, pin = pin,
                       text = string.format("|cff66ccff%s:|r right-click it with the %s it asks for to make a Supply Shipment, then hand that to %s for Merchant's Favor.",
                           c.name, c.material, who) })
            else
                push({ priority = 52, kind = "info", itemId = c.itemId, pin = pin,
                       text = string.format("|cff66ccffSupply Shipment:|r hand it to %s for Merchant's Favor (their quartermaster sells 10-18 slot bags).", who) })
            end
        end
    end
end

return Goodies
