-- Quest Ladder: QuestieDB adapter. Reads quest/NPC/object/item facts through the public
-- LibQuestieDB API (docs/api.md in the QuestieDB repo), builds the indexes the planner needs,
-- and answers "can this character take this quest?".

local _, ns = ...
local Data = {}
ns.Data = Data

local Geo = ns.Geo
local CONTRACT = 4

Data.ready = false          -- indexes built
Data.reason = nil           -- why the DB is unavailable, for the UI

---------------------------------------------------------------------------
-- Provider access
---------------------------------------------------------------------------
local Q, N, O, I -- QuestDB, NpcDB, ObjectDB, ItemDB

function Data.Init()
    local lib = Data.libOverride or LibQuestieDB
    if not lib then
        Data.reason = "QuestieDB is not installed (install Questie for WoW: Forever)"
        return false
    end
    if lib.RequireContract then
        local ok, message = lib.RequireContract(CONTRACT)
        if not ok then
            Data.reason = "QuestieDB is too old: " .. tostring(message)
            return false
        end
    end
    Q, N, O, I = lib.Quest, lib.Npc, lib.Object, lib.Item
    if not (Q and N and O and I) then
        Data.reason = "QuestieDB API missing entity tables"
        return false
    end
    Data.lib = lib
    Data.reason = nil
    Data.ResetXP()
    return true
end

--- Test hook: inject fake entity tables.
function Data.InitWith(fakeLib)
    Data.libOverride = fakeLib
    Data.ready = false
    Data.questCache, Data.pointCache = {}, {}
    return Data.Init()
end

---------------------------------------------------------------------------
-- Quest XP: QuestieDB's support data (Classic's table, plus XP observed on Forever for the
-- new quests), read through `Support.Get("QuestXP").db` = { [questId] = { questLevel, fullXP } }.
---------------------------------------------------------------------------
local xpDB, solidXP

function Data.ResetXP() xpDB, solidXP = nil, nil end

local function xpTable()
    if xpDB == nil then
        xpDB = false
        local lib = Data.lib
        if lib and lib.Support and lib.Support.Get then
            local ok, mod = pcall(lib.Support.Get, "QuestXP")
            if ok and type(mod) == "table" and type(mod.db) == "table" then xpDB = mod.db end
        end
    end
    return xpDB or nil
end

--- A quest's full XP and the quest level it is worth that at, or nil when QuestieDB doesn't know.
function Data.QuestXP(questId)
    local db = xpTable()
    local row = db and db[questId]
    if type(row) ~= "table" then return nil end
    local level, xp = tonumber(row[1]), tonumber(row[2])
    if not (level and xp) then return nil end
    return xp, level
end

--- XP the quest gives you at `level` (Classic's rule, as Questie and cmangos compute it): full
--- until you are 5 levels above it, then 20% less per level, never under 10%.
function Data.XPAtLevel(xp, questLevel, level)
    if not (xp and questLevel and level) then return nil end
    local m = 2 * (questLevel - level) + 20
    if m < 1 then m = 1 elseif m > 10 then m = 10 end
    return xp * m / 10
end

--- What a solid quest at `level` is worth: the 75th percentile of QuestieDB's full quest XP
--- within 2 levels. (A median wobbled: every level has many tiny "go talk to" quests.)
function Data.SolidQuestXP(level)
    if not solidXP then
        local db = xpTable()
        if not db then return nil end
        solidXP = {}
        local byLevel, maxLevel = {}, 0
        for _, row in pairs(db) do
            local lv = type(row) == "table" and tonumber(row[1])
            local xp = type(row) == "table" and tonumber(row[2])
            if lv and xp and xp > 0 then
                byLevel[lv] = byLevel[lv] or {}
                byLevel[lv][#byLevel[lv] + 1] = xp
                if lv > maxLevel then maxLevel = lv end
            end
        end
        for lv = 1, maxLevel do
            local pool = {}
            for d = -2, 2 do
                for _, x in ipairs(byLevel[lv + d] or {}) do pool[#pool + 1] = x end
            end
            if #pool > 0 then
                table.sort(pool)
                solidXP[lv] = pool[math.max(1, math.ceil(#pool * 0.75))]
            end
        end
    end
    return solidXP[level]
end

local function num(v) return (type(v) == "number") and v or 0 end

---------------------------------------------------------------------------
-- Bit tests on masks wider than 32 bits (Skyborne race bits 32/33):
-- plain arithmetic, never bit.band.
---------------------------------------------------------------------------
local function hasBit(mask, bitValue)
    if not mask or mask == 0 or not bitValue or bitValue == 0 then return false end
    return math.floor(mask / bitValue) % 2 == 1
end
Data.HasBit = hasBit

---------------------------------------------------------------------------
-- Quest projection (cached)
---------------------------------------------------------------------------
Data.questCache = {}

function Data.Quest(id)
    if not id then return nil end
    local q = Data.questCache[id]
    if q ~= nil then return q or nil end
    if not Q or not Q.Exists or not Q.Exists(id) then
        Data.questCache[id] = false
        return nil
    end
    local G = Q.Get
    q = {
        id = id,
        name = G(id, "name"),
        startedBy = G(id, "startedBy") or {},
        finishedBy = G(id, "finishedBy") or {},
        reqLevel = num(G(id, "requiredLevel")),
        level = num(G(id, "questLevel")),
        races = num(G(id, "requiredRaces")),
        classes = num(G(id, "requiredClasses")),
        objectivesText = G(id, "objectivesText"),
        triggerEnd = G(id, "triggerEnd"),
        objectives = G(id, "objectives") or {},
        sourceItemId = num(G(id, "sourceItemId")),
        preGroup = G(id, "preQuestGroup"),
        preSingle = G(id, "preQuestSingle"),
        exclusiveTo = G(id, "exclusiveTo"),
        zone = num(G(id, "zoneOrSort")),
        reqSkill = G(id, "requiredSkill"),
        reqMinRep = G(id, "requiredMinRep"),
        reqMaxRep = G(id, "requiredMaxRep"),
        requiredSourceItems = G(id, "requiredSourceItems"),
        nextInChain = num(G(id, "nextQuestInChain")),
        specialFlags = num(G(id, "specialFlags")),
        parentQuest = num(G(id, "parentQuest")),
        breadcrumbFor = num(G(id, "breadcrumbForQuestId")),
        extraObjectives = G(id, "extraObjectives"),
        reqMaxLevel = num(G(id, "requiredMaxLevel")),
    }
    Data.questCache[id] = q
    return q
end

function Data.NpcName(id) return N and N.Get(id, "name") end
function Data.ObjectName(id) return O and O.Get(id, "name") end
function Data.ItemName(id) return I and I.Get(id, "name") end
function Data.Item(id, key) return I and I.Get(id, key) end
function Data.Npc(id, key) return N and N.Get(id, key) end

---------------------------------------------------------------------------
-- Spawn points (cached world points)
---------------------------------------------------------------------------
Data.pointCache = {}

local function entityPoints(kind, id)
    local key = kind .. id
    local cached = Data.pointCache[key]
    if cached then return cached.points, cached.instance end
    local spawns
    if kind == "n" then spawns = N and N.Get(id, "spawns")
    else spawns = O and O.Get(id, "spawns") end
    local points, instance = Geo.PointsFromSpawns(spawns, 80)
    Data.pointCache[key] = { points = points, instance = instance }
    return points, instance
end

function Data.NpcPoints(id) return entityPoints("n", id) end
function Data.ObjectPoints(id) return entityPoints("o", id) end

--- Where an item comes from: NPCs that drop it and objects that contain it.
--- Returns points, inInstance, sourceKind ("npc"/"object"/nil), sourceIds.
function Data.ItemSourcePoints(itemId)
    local key = "i" .. itemId
    local cached = Data.pointCache[key]
    if cached then return cached.points, cached.instance, cached.kind, cached.ids end
    local points, instance, kind, ids = {}, false, nil, {}
    local objectDrops = I and I.Get(itemId, "objectDrops")
    local npcDrops = I and I.Get(itemId, "npcDrops")
    local function addFrom(list, fn, k)
        if type(list) ~= "table" then return end
        for i = 1, math.min(#list, 12) do
            local pts, inst = fn(list[i])
            if inst then instance = true end
            if #pts > 0 then
                kind = kind or k
                ids[#ids + 1] = list[i]
                for j = 1, #pts do points[#points + 1] = pts[j] end
            end
        end
    end
    addFrom(objectDrops, Data.ObjectPoints, "object")
    addFrom(npcDrops, Data.NpcPoints, "npc")
    Data.pointCache[key] = { points = points, instance = instance, kind = kind, ids = ids }
    return points, instance, kind, ids
end

--- Points for a quest giver/finisher table { npcIds?, objectIds?, itemIds? }.
function Data.GiverPoints(givers)
    local points, names = {}, {}
    if type(givers) ~= "table" then return points, names end
    if type(givers[1]) == "table" then
        for _, npcId in ipairs(givers[1]) do
            local pts = Data.NpcPoints(npcId)
            for j = 1, #pts do
                pts[j].giverName = pts[j].giverName or Data.NpcName(npcId)
                pts[j].giverId = npcId
                points[#points + 1] = pts[j]
            end
            names[#names + 1] = Data.NpcName(npcId)
        end
    end
    if type(givers[2]) == "table" then
        for _, objId in ipairs(givers[2]) do
            local pts = Data.ObjectPoints(objId)
            for j = 1, #pts do
                pts[j].giverName = pts[j].giverName or Data.ObjectName(objId)
                pts[j].giverId = -objId
                points[#points + 1] = pts[j]
            end
            names[#names + 1] = Data.ObjectName(objId)
        end
    end
    -- Quests started by an item you find (Library books, the Cozy Sleeping Bag notes): the
    -- "giver" is where the item lies. Only items from a few fixed objects, never mob drops, so
    -- the planner doesn't send you farming for a lucky quest starter.
    if type(givers[3]) == "table" then
        for _, itemId in ipairs(givers[3]) do
            local pts, _, kind, sourceIds = Data.ItemSourcePoints(itemId)
            if kind == "object" and #pts > 0 and #pts <= Data.FOUND_ITEM_MAX_SPOTS then
                local itemName = Data.ItemName(itemId)
                for j = 1, #pts do
                    local p = {}
                    for k, v in pairs(pts[j]) do p[k] = v end
                    p.giverName = itemName or p.giverName
                    p.giverId = sourceIds[1] and -sourceIds[1] or 0 -- the object, for the "this one" cue
                    p.foundItem = itemId
                    points[#points + 1] = p
                end
                names[#names + 1] = itemName
            end
        end
    end
    return points, names
end
Data.FOUND_ITEM_MAX_SPOTS = 4

---------------------------------------------------------------------------
-- Player facts used by availability checks
---------------------------------------------------------------------------
function Data.PlayerMasks(player)
    local lib = Data.lib or LibQuestieDB
    local raceMask, classMask = 0, 0
    if lib and lib.Enum then
        if lib.Enum.raceMaskById and player.raceId then raceMask = lib.Enum.raceMaskById[player.raceId] or 0 end
        if lib.Enum.classKeys and player.classFile then classMask = lib.Enum.classKeys[player.classFile] or 0 end
    end
    return raceMask, classMask
end

---------------------------------------------------------------------------
-- Availability
---------------------------------------------------------------------------
local REPEATABLE_FLAG = 1

local function questieDoable(questId)
    -- Questie's own rules include its blacklists and world-event gating, so prefer them.
    if not (Questie and Questie.API and Questie.API.isReady and QuestieLoader) then return nil end
    local ok, mod = pcall(QuestieLoader.ImportModule, QuestieLoader, "QuestieDB")
    if not ok or type(mod) ~= "table" or type(mod.IsDoable) ~= "function" then return nil end
    local ok2, result = pcall(mod.IsDoable, questId)
    if not ok2 then return nil end
    return result and true or false
end
Data.QuestieDoable = questieDoable

--- Own availability rules. `state` = { level, raceMask, classMask, isComplete(id), isActive(id),
--- skills = { [skillId] = rank }, assumeDone = { [questId] = true } }.
function Data.IsAvailable(questId, state)
    local q = Data.Quest(questId)
    if not q then return false, "unknown" end
    local function done(id)
        return state.isComplete(id) or (state.assumeDone and state.assumeDone[id]) or false
    end
    if state.isComplete(questId) then return false, "completed" end
    if state.isActive(questId) then return false, "active" end
    if hasBit(q.specialFlags, REPEATABLE_FLAG) then return false, "repeatable" end
    if q.reqLevel > state.level then return false, "level" end
    if q.reqMaxLevel ~= 0 and state.level > q.reqMaxLevel then return false, "maxlevel" end
    if q.races ~= 0 and not hasBit(q.races, state.raceMask) then return false, "race" end
    if q.classes ~= 0 and not hasBit(q.classes, state.classMask) then return false, "class" end
    if q.reqMinRep or q.reqMaxRep then return false, "reputation" end -- conservative without Questie
    if q.reqSkill then
        local skillId, value = q.reqSkill[1], q.reqSkill[2] or 0
        local rank = state.skills and state.skills[skillId]
        if not rank or rank < value then return false, "skill" end
    end
    if q.preSingle and #q.preSingle > 0 then
        local any = false
        for _, pre in ipairs(q.preSingle) do
            if done(pre) then any = true break end
        end
        if not any then return false, "prequest" end
    elseif q.preGroup and #q.preGroup > 0 then
        for _, pre in ipairs(q.preGroup) do
            -- negative IDs mean "must be active", rare; treat as satisfied when active
            if pre > 0 and not done(pre) then return false, "prequestgroup" end
            if pre < 0 and not state.isActive(-pre) then return false, "prequestgroup" end
        end
    end
    if q.exclusiveTo then
        for _, other in ipairs(q.exclusiveTo) do
            if state.isComplete(other) or state.isActive(other) then return false, "exclusive" end
        end
    end
    if q.nextInChain ~= 0 and (state.isComplete(q.nextInChain) or state.isActive(q.nextInChain)) then
        return false, "chainpassed"
    end
    if q.breadcrumbFor ~= 0 and (state.isComplete(q.breadcrumbFor) or state.isActive(q.breadcrumbFor)) then
        return false, "breadcrumb"
    end
    if q.parentQuest ~= 0 and not state.isActive(q.parentQuest) then return false, "parent" end
    return true
end

--- Availability for quests the player could take right now (no assumptions):
--- Questie's verdict when present, else ours.
function Data.IsAvailableNow(questId, state)
    if state.isComplete(questId) or state.isActive(questId) then return false end
    local verdict = questieDoable(questId)
    if verdict ~= nil then
        if not verdict then return false end
        -- Questie does not know our repeatable/level-window preferences; apply the cheap ones.
        local q = Data.Quest(questId)
        if q and hasBit(q.specialFlags, REPEATABLE_FLAG) then return false end
        return true
    end
    return Data.IsAvailable(questId, state)
end

---------------------------------------------------------------------------
-- Indexes (built once per session in the background)
--   starterGrid[cont][cellKey] = { {questId, point}, ... }
--   followUps[questId]         = { questId, ... }     (quests unlocked by it)
--   rewardItems[questId]       = { itemId, ... }      (equippable quest rewards)
--   gearByLevel[reqLevel]      = { itemId, ... }      (weapons/armor, for AH suggestions)
--   vendors / trainers / flightMasters / innkeepers = { {npcId, point, name, subName}, ... }
---------------------------------------------------------------------------
local CELL = 400
Data.starterGrid = {}
Data.followUps = {}
Data.rewardItems = {}
Data.gearByLevel = {}
Data.vendors = {}
Data.trainers = {}
Data.flightMasters = {}
Data.innkeepers = {}
Data.transportMasters = {} -- zeppelin and boat masters
Data.bagRewards = {}       -- [questId] = { bag itemId, ... }
Data.vendorBags = {}       -- { {itemId, vendors = {npcId...}}, ... } plain bags vendors sell
Data.questDrops = {}       -- 0.5.0: { {itemId, questId, npcs = {npcId...}}, ... } named mobs' drops that start a quest
Data.mobGrid = {}          -- 0.5.0: mobGrid[cont][cellKey] = { {npcId, point, minLevel, maxLevel}, ... } mobs to grind
Data.QUEST_DROP_MAX_NPCS = 3 -- more droppers than this: a lucky drop off common mobs, not a named mob
Data.MOB_GRID_POINTS = 12    -- spawn points kept per mob for "grind here"
local TRANSPORT_TITLES = { "zeppelin", "dockmaster", "harbormaster", "boat" }

local function cellKey(wx, wy) return math.floor(wx / CELL) .. ":" .. math.floor(wy / CELL) end

local function addStarter(questId, p)
    local grid = Data.starterGrid[p.cont]
    if not grid then grid = {}; Data.starterGrid[p.cont] = grid end
    local key = cellKey(p.wx, p.wy)
    local cell = grid[key]
    if not cell then cell = {}; grid[key] = cell end
    cell[#cell + 1] = { questId = questId, point = p }
end

function Data.BuildIndexes(player, onDone)
    if not Q then
        if onDone then onDone(false) end
        return
    end
    local raceMask, classMask = Data.PlayerMasks(player)
    local npcFlags = (Data.lib and Data.lib.Enum and Data.lib.Enum.npcFlags) or {}
    local VENDOR, TRAINER = npcFlags.VENDOR or 0, npcFlags.TRAINER or 0
    local FLIGHT, INN = npcFlags.FLIGHT_MASTER or 0, npcFlags.INNKEEPER or 0

    ns.Async("QuestLadder.index", function()
        Data.starterGrid, Data.followUps, Data.rewardItems = {}, {}, {}
        Data.gearByLevel, Data.vendors, Data.trainers = {}, {}, {}
        Data.flightMasters, Data.innkeepers, Data.transportMasters = {}, {}, {}
        Data.bagRewards, Data.vendorBags = {}, {}
        Data.questDrops, Data.mobGrid = {}, {}

        -- Quests: starters (spatial) + reverse prerequisites (chains)
        local ids = Q.GetAllIds()
        for i = 1, #ids do
            local id = ids[i]
            local races = num(Q.Get(id, "requiredRaces"))
            local classes = num(Q.Get(id, "requiredClasses"))
            if (races == 0 or hasBit(races, raceMask)) and (classes == 0 or hasBit(classes, classMask)) then
                local pre = Q.Get(id, "preQuestSingle") or Q.Get(id, "preQuestGroup")
                if pre then
                    for _, p in ipairs(pre) do
                        if p > 0 then
                            local list = Data.followUps[p]
                            if not list then list = {}; Data.followUps[p] = list end
                            list[#list + 1] = id
                        end
                    end
                end
                local starters = Q.Get(id, "startedBy")
                if starters then
                    local pts = Data.GiverPoints(starters)
                    -- index up to 3 spawn points per quest (some givers wander or have copies)
                    for j = 1, math.min(#pts, 3) do addStarter(id, pts[j]) end
                end
            end
            ns.MaybeYield(25)
        end

        -- Items: equippable gear by level, and which quests reward them; bags (quest rewards and
        -- ones vendors sell)
        local itemIds = I.GetAllIds()
        for i = 1, #itemIds do
            local id = itemIds[i]
            -- a named mob's drop that starts a quest (Owatanka's Tailspike): "watch for" hints
            local starts = num(I.Get(id, "startQuest"))
            if starts > 0 then
                local drops = I.Get(id, "npcDrops")
                if type(drops) == "table" and #drops >= 1 and #drops <= Data.QUEST_DROP_MAX_NPCS then
                    Data.questDrops[#Data.questDrops + 1] = { itemId = id, questId = starts, npcs = drops }
                end
            end
            local class = num(I.Get(id, "class"))
            if class == 1 and num(I.Get(id, "subClass")) == 0 then
                for _, qid in ipairs(I.Get(id, "questRewards") or {}) do
                    local list = Data.bagRewards[qid]
                    if not list then list = {}; Data.bagRewards[qid] = list end
                    list[#list + 1] = id
                end
                local vendors = I.Get(id, "vendors")
                if type(vendors) == "table" and #vendors > 0 then
                    Data.vendorBags[#Data.vendorBags + 1] = { itemId = id, vendors = vendors }
                end
            elseif class == 2 or class == 4 then
                local req = num(I.Get(id, "requiredLevel"))
                local bucket = Data.gearByLevel[req]
                if not bucket then bucket = {}; Data.gearByLevel[req] = bucket end
                bucket[#bucket + 1] = id
                local rewards = I.Get(id, "questRewards")
                if rewards then
                    for _, qid in ipairs(rewards) do
                        local list = Data.rewardItems[qid]
                        if not list then list = {}; Data.rewardItems[qid] = list end
                        list[#list + 1] = id
                    end
                end
            end
            ns.MaybeYield(60)
        end

        -- NPCs: vendors and class trainers that are friendly to the player
        local faction = player.faction == "Horde" and "H" or "A"
        local npcIds = N.GetAllIds()
        for i = 1, #npcIds do
            local id = npcIds[i]
            local flags = num(N.Get(id, "npcFlags"))
            local isVendor = VENDOR ~= 0 and hasBit(flags, VENDOR)
            local isTrainer = TRAINER ~= 0 and hasBit(flags, TRAINER)
            local isFlight = FLIGHT ~= 0 and hasBit(flags, FLIGHT)
            local isInn = INN ~= 0 and hasBit(flags, INN)
            local sub = N.Get(id, "subName")
            local isTransport = false
            if type(sub) == "string" then
                local lower = sub:lower()
                for _, word in ipairs(TRANSPORT_TITLES) do
                    if lower:find(word, 1, true) then isTransport = true break end
                end
            end
            if isVendor or isTrainer or isFlight or isInn or isTransport then
                local friendly = N.Get(id, "friendlyToFaction")
                if friendly == nil or friendly == "AH" or friendly == faction then
                    local pts = Data.NpcPoints(id)
                    if pts[1] then
                        local entry = { npcId = id, point = pts[1], name = N.Get(id, "name"), subName = sub }
                        if isVendor then Data.vendors[#Data.vendors + 1] = entry end
                        if isTrainer then Data.trainers[#Data.trainers + 1] = entry end
                        if isFlight then Data.flightMasters[#Data.flightMasters + 1] = entry end
                        if isInn then Data.innkeepers[#Data.innkeepers + 1] = entry end
                        if isTransport then Data.transportMasters[#Data.transportMasters + 1] = entry end
                    end
                end
            elseif flags == 0 and N.Get(id, "friendlyToFaction") == nil then
                -- an ordinary mob (no service, nobody's friend, not elite): somewhere to grind
                local rank = num(N.Get(id, "rank"))
                local lo = num(N.Get(id, "minLevel"))
                if rank == 0 and lo >= 2 and not N.Get(id, "questStarts") then
                    local hi = math.max(lo, num(N.Get(id, "maxLevel")))
                    local pts = Geo.PointsFromSpawns(N.Get(id, "spawns"), Data.MOB_GRID_POINTS)
                    for j = 1, #pts do
                        local p = pts[j]
                        local grid = Data.mobGrid[p.cont]
                        if not grid then grid = {}; Data.mobGrid[p.cont] = grid end
                        local key = cellKey(p.wx, p.wy)
                        local cell = grid[key]
                        if not cell then cell = {}; grid[key] = cell end
                        cell[#cell + 1] = { npcId = id, point = p, minLevel = lo, maxLevel = hi }
                    end
                end
            end
            ns.MaybeYield(80)
        end
    end, function()
        Data.ready = true
        ns.Debug("indexes ready")
        if onDone then onDone(true) end
    end)
end

--- Quest givers within `radius` yards of `point`: { {questId, point, dist}, ... } nearest first.
function Data.StartersNear(point, radius)
    local out = {}
    if not point then return out end
    local grid = Data.starterGrid[point.cont]
    if not grid then return out end
    local cx, cy = math.floor(point.wx / CELL), math.floor(point.wy / CELL)
    local r = math.ceil(radius / CELL)
    local seen = {}
    for dx = -r, r do
        for dy = -r, r do
            local cell = grid[(cx + dx) .. ":" .. (cy + dy)]
            if cell then
                for k = 1, #cell do
                    local e = cell[k]
                    local d = Geo.Distance(point, e.point)
                    if d and d <= radius then
                        local prev = seen[e.questId]
                        if not prev or d < prev.dist then
                            local entry = { questId = e.questId, point = e.point, dist = d }
                            seen[e.questId] = entry
                        end
                    end
                end
            end
        end
    end
    for _, e in pairs(seen) do out[#out + 1] = e end
    table.sort(out, function(a, b) return a.dist < b.dist end)
    return out
end

--- 0.5.0: mobs to grind within `radius` of `point` whose level range overlaps [lo, hi]:
--- { {npcId, name, minLevel, maxLevel, count, dist, point}, ... }, most spawns nearby first.
function Data.MobsNear(point, radius, lo, hi)
    local out = {}
    if not point then return out end
    local grid = Data.mobGrid[point.cont]
    if not grid then return out end
    local cx, cy = math.floor(point.wx / CELL), math.floor(point.wy / CELL)
    local r = math.ceil(radius / CELL)
    local byNpc = {}
    for dx = -r, r do
        for dy = -r, r do
            for _, e in ipairs(grid[(cx + dx) .. ":" .. (cy + dy)] or {}) do
                if e.maxLevel >= lo and e.minLevel <= hi then
                    local d = Geo.Distance(point, e.point)
                    if d and d <= radius then
                        local m = byNpc[e.npcId]
                        if not m then
                            m = { npcId = e.npcId, minLevel = e.minLevel, maxLevel = e.maxLevel, count = 0 }
                            byNpc[e.npcId] = m
                        end
                        m.count = m.count + 1
                        if not m.dist or d < m.dist then m.dist, m.point = d, e.point end
                    end
                end
            end
        end
    end
    for _, m in pairs(byNpc) do
        m.name = Data.NpcName(m.npcId)
        out[#out + 1] = m
    end
    table.sort(out, function(a, b)
        if a.count ~= b.count then return a.count > b.count end
        if a.dist ~= b.dist then return a.dist < b.dist end
        return a.npcId < b.npcId
    end)
    return out
end

local function nearestFrom(list, point, filter)
    local best, bestD
    for i = 1, #list do
        local e = list[i]
        if not filter or filter(e) then
            local d = Geo.Distance(point, e.point)
            if d and (not bestD or d < bestD) then best, bestD = e, d end
        end
    end
    return best, bestD
end

function Data.NearestVendor(point) return nearestFrom(Data.vendors, point) end

--- Innkeepers within `radius` of any of the points, nearest-first, deduplicated.
function Data.InnkeepersNear(points, radius, cap)
    local scored = {}
    for _, inn in ipairs(Data.innkeepers) do
        local best
        for _, p in ipairs(points) do
            local d = Geo.Distance(p, inn.point)
            if d and d <= radius and (not best or d < best) then best = d end
        end
        if best then scored[#scored + 1] = { inn = inn, d = best } end
    end
    table.sort(scored, function(a, b) return a.d < b.d end)
    local out = {}
    for i = 1, math.min(cap or 6, #scored) do out[i] = scored[i].inn end
    return out
end

function Data.NearestClassTrainer(point, className)
    if not className then return nil end
    local needle = className:lower() .. " trainer"
    return nearestFrom(Data.trainers, point, function(e)
        return e.subName and e.subName:lower() == needle
    end)
end

--- Equippable item IDs with required level in [minLevel, maxLevel].
function Data.GearInLevelRange(minLevel, maxLevel)
    local out = {}
    for lvl = math.max(0, minLevel), maxLevel do
        local bucket = Data.gearByLevel[lvl]
        if bucket then
            for i = 1, #bucket do out[#out + 1] = bucket[i] end
        end
    end
    return out
end
