-- Quest Ladder: speed-leveling techniques (0.5.0). These are rules modelled on what Classic
-- speed-levelers do, worked out from QuestieDB's data and the game's own API. No leveling guide's
-- steps or route order are bundled.
--   * Grind here first: when the next quests' mobs would be too high for you, kill mobs at your
--     level where you are before you leave, instead of walking into fights 2+ levels up.
--   * Die and res: dying on purpose sends your spirit to the nearest graveyard. When that's next
--     to where you're going, it beats walking (no res sickness up to level 10).
--   * Watch for: named mobs near your route whose drop starts a quest worth doing.
--   * Hearth on cooldown: a good moment for a break, since the cooldown ticks while logged out.
--   * Learn Cooking, First Aid or Fishing when that unlocks a quest worth its XP.
--   * Escorts take time, and quests against elites need a group.

local _, ns = ...
local Speed = {}
ns.Speed = Speed

local Geo, Data = ns.Geo, ns.Data

local function clock(seconds)
    seconds = math.max(0, math.floor((seconds or 0) + 0.5))
    return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

local function plainNumber(v)
    if type(v) == "number" and not ns.IsSecret(v) then return v end
    return nil
end

local function zoneName(mapId)
    if not (mapId and C_Map and C_Map.GetMapInfo) then return nil end
    local ok, info = pcall(C_Map.GetMapInfo, mapId)
    if ok and type(info) == "table" and type(info.name) == "string" and not ns.IsSecret(info.name) then return info.name end
    return nil
end

local function mineFaction(faction)
    return (faction == "Horde" and "H") or (faction == "Alliance" and "A") or nil
end

local function friendlyTo(npcId, faction)
    local friendly = Data.Npc(npcId, "friendlyToFaction")
    local mine = mineFaction(faction)
    return friendly == "AH" or (mine ~= nil and friendly == mine)
end

---------------------------------------------------------------------------
-- Escorts and group quests
---------------------------------------------------------------------------
-- An escort is minutes of walking next to an NPC with next to no kills: its time counts in the
-- "worth the walk" check (Planner.PruneTrips adds quest.extraSeconds to the travel it saves).
-- A quest whose mobs are all elites at or near your level needs a group: solo, it's skipped
-- unless it's a class quest, a gear upgrade or a must-do extra (/ladder groupquests plans them).
Speed.ESCORT_SECONDS = 240
Speed.GROUP_RANKS = { [1] = true, [2] = true, [3] = true } -- elite, rare elite, boss (cmangos ranks)
Speed.GROUP_LEVELS_BELOW = 3 -- an elite this many levels under you is soloable
Speed.MAX_REAL_LEVEL = 100

--- The elite that makes an objective a group fight: every hostile NPC that counts for it is an
--- elite not far under you. Returns its name and level, or nil.
function Speed.EliteTarget(o, level, faction)
    if not o or (o.type ~= "monster" and o.type ~= "item") then return nil end
    local npcs = o.targets and o.targets.npc
    if type(npcs) ~= "table" or #npcs == 0 then return nil end
    local name, lowest
    for _, id in ipairs(npcs) do
        if not friendlyTo(id, faction) then
            local rank = tonumber(Data.Npc(id, "rank")) or 0
            local l = tonumber(Data.Npc(id, "minLevel")) or 0
            -- (some of Forever's own NPCs carry a placeholder level of 9999: not a real fight)
            if not Speed.GROUP_RANKS[rank] or l <= 0 or l > Speed.MAX_REAL_LEVEL
                or l <= (level or 1) - Speed.GROUP_LEVELS_BELOW then return nil end
            if not lowest or l < lowest then name, lowest = Data.NpcName(id), l end
        end
    end
    return name, lowest
end

--- The elite a quest's unfinished objectives are against, or nil: name, level.
function Speed.NeedsGroup(q, level, faction)
    for _, o in ipairs((q and q.objectives) or {}) do
        if not o.finished then
            local name, l = Speed.EliteTarget(o, level, faction)
            if name or l then return name or "an elite", l end
        end
    end
    return nil
end

---------------------------------------------------------------------------
-- Learn a secondary profession to unlock a quest
---------------------------------------------------------------------------
-- Some quests need a profession you can learn in a minute for a few silver: Cooking for "Soothing
-- Turtle Bisque" in Hillsbrad, First Aid for Forever's "Camping 101: First Aid". Only secondary
-- professions (they don't take a profession slot), and only quests that need just the skill.
Speed.PROFESSIONS = { [185] = "Cooking", [129] = "First Aid", [356] = "Fishing" }
Speed.PROFESSION_MAX_SKILL = 1
Speed.SKILL_UNLOCKS_MAX = 3

--- When a secondary profession you don't have is all that keeps you from this quest: skill ID
--- and its name.
function Speed.SkillUnlock(questId, db, state)
    local rs = db and db.reqSkill
    if type(rs) ~= "table" then return nil end
    local skillId, value = rs[1], rs[2] or 0
    local name = Speed.PROFESSIONS[skillId]
    if not name or value > Speed.PROFESSION_MAX_SKILL then return nil end
    if state.skills and state.skills[skillId] then return nil end
    local with = {}
    for k, v in pairs(state.skills or {}) do with[k] = v end
    with[skillId] = math.max(1, value)
    local withSkill = setmetatable({ skills = with }, { __index = state })
    if Data.IsAvailable(questId, withSkill) then return skillId, name end
    return nil
end

--- The trainer for a profession nearest `point`: { name, point } or nil.
function Speed.ProfessionTrainer(skillName, point)
    if not (skillName and point) then return nil end
    local needle = skillName:lower() .. " trainer"
    local best, bestD
    for _, e in ipairs(Data.trainers or {}) do
        if type(e.subName) == "string" and e.subName:lower() == needle then
            local d = Geo.Distance(point, e.point)
            if d and (not bestD or d < bestD) then best, bestD = e, d end
        end
    end
    return best
end

---------------------------------------------------------------------------
-- Watch for named mobs whose drop starts a quest
---------------------------------------------------------------------------
-- Owatanka, Washte Pawne and Lakota'mani in The Barrens each drop an item that starts a quest.
-- QuestieDB lists the drops (Data.questDrops); many of these mobs wander, so when it has no spawn
-- points the zone they live in is what counts. Only quests worth doing, mobs no more than
-- WATCH_LEVELS_ABOVE over you, near the next WATCH_STEPS steps of your route.
Speed.WATCH_YARDS = 350
Speed.WATCH_STEPS = 15
Speed.WATCH_MAX = 3
Speed.WATCH_LEVELS_ABOVE = 3

local function inBags(itemId)
    local count = (C_Item and C_Item.GetItemCount) or GetItemCount
    if not count then return false end
    local ok, n = pcall(count, itemId)
    return ok and plainNumber(n) ~= nil and n > 0
end

--- Named mobs near your route worth watching for: { questId, title, itemId, npcId, npcName, level,
--- step (0 = where you are), point (a spawn, or nil when only the zone is known), mapId, xp }.
function Speed.WatchFor(plan, player, state, byId)
    local out = {}
    if not (plan and player and player.point and Data.questDrops and ns.Ladder) then return out end
    local Ladder, QS = ns.Ladder, ns.QuestState
    local opts = ns.db
    local level = player.level or 1
    local green = QS.GreenRange(level)
    -- where the route goes: you (step 0) and the next steps
    local places, maps = { { i = 0, loc = player.point } }, { [player.point.mapId or -1] = 0 }
    for i, s in ipairs(plan.steps or {}) do
        if i > Speed.WATCH_STEPS then break end
        if s.loc then
            places[#places + 1] = { i = i, loc = s.loc }
            if s.loc.mapId and maps[s.loc.mapId] == nil then maps[s.loc.mapId] = i end
        end
    end
    local seen = {}
    for _, e in ipairs(Data.questDrops) do
        local qid = e.questId
        local db = not seen[qid] and Data.Quest(qid)
        seen[qid] = true
        local ql = db and ((db.level and db.level > 0) and db.level or level)
        if db and not (byId and byId[qid]) and not QS.IsComplete(qid) and not ns.charDB.ignored[qid]
            and (db.reqLevel or 0) <= level and ql >= level - green and ql <= level + (opts.levelsAbove or 2)
            and Data.IsAvailableNow(qid, state) and (Ladder.WorthDoing(qid, player)) and not inBags(e.itemId) then
            for _, npcId in ipairs(e.npcs or {}) do
                local lvl = tonumber(Data.Npc(npcId, "minLevel")) or 0
                if lvl > 0 and lvl <= level + Speed.WATCH_LEVELS_ABOVE and not friendlyTo(npcId, player.faction) then
                    local found
                    local spawns = Data.NpcPoints(npcId)
                    if #spawns > 0 then
                        for _, pl in ipairs(places) do
                            local near, d = nil, nil
                            for _, sp in ipairs(spawns) do
                                local dd = Geo.Distance(pl.loc, sp)
                                if dd and dd <= Speed.WATCH_YARDS and (not d or dd < d) then near, d = sp, dd end
                            end
                            if near then found = { step = pl.i, point = near, mapId = near.mapId } break end
                        end
                    else
                        local zoneId = tonumber(Data.Npc(npcId, "zoneID"))
                        local mapId = zoneId and Geo.AreaToUiMap(zoneId)
                        if mapId and maps[mapId] then found = { step = maps[mapId], mapId = mapId } end
                    end
                    if found then
                        local _, xp = Ladder.QuestWorth(qid, level)
                        found.questId, found.title, found.itemId = qid, db.name, e.itemId
                        found.npcId, found.npcName, found.level, found.xp = npcId, Data.NpcName(npcId), lvl, xp
                        out[#out + 1] = found
                        break
                    end
                end
            end
        end
        if ns.MaybeYield then ns.MaybeYield(40) end
    end
    table.sort(out, function(a, b)
        if a.step ~= b.step then return a.step < b.step end
        return (a.xp or 0) > (b.xp or 0)
    end)
    while #out > Speed.WATCH_MAX do table.remove(out) end
    return out
end

---------------------------------------------------------------------------
-- Grind here first
---------------------------------------------------------------------------
-- The planner holds kill steps whose mobs are 2+ levels above you until enough other turn-ins
-- have levelled you, but it can't wait for turn-ins it doesn't have. When the plan runs short,
-- you'd arrive under-levelled. Speed-levelers grind where they are before they leave, so a
-- "Grind first" stop goes in before that step: mobs at your level near where you leave from
-- (the route's own quest mobs first, else QuestieDB's mobs around there), until about the level
-- that fight needs (LEVEL_SLACK under the mobs). It ends by itself when you get there.
Speed.GRIND_MIN_LEVELS = 0.25  -- 5 bars of XP: anything less isn't worth a stop
Speed.GRIND_MAX_SECONDS = 900  -- a stop is a few bars, never an hour: at most ~15 minutes of killing
Speed.GRIND_MAX_STEPS = 25
Speed.GRIND_NEAR_YARDS = 500

--- XP for a whole level: the game's figure for your level, else Classic's curve (close up to 30).
function Speed.XPPerLevel(level)
    if UnitXPMax then
        local ok, v = pcall(UnitXPMax, "player")
        v = ok and plainNumber(v)
        if v and v > 0 then return v end
    end
    level = level or 1
    return 40 * level * level + 360 * level
end

--- Your level with the bar: 22.35 = 7 bars into 22. nil when the game hides it.
function Speed.LevelNow()
    local okL, level = pcall(UnitLevel, "player")
    level = okL and plainNumber(level)
    if not level then return nil end
    if UnitXP and UnitXPMax then
        local okA, xp = pcall(UnitXP, "player")
        local okB, max = pcall(UnitXPMax, "player")
        xp, max = okA and plainNumber(xp), okB and plainNumber(max)
        if xp and max and max > 0 then return level + math.max(0, math.min(1, xp / max)) end
    end
    return level
end

function Speed.ReachedLevel(target)
    local now = Speed.LevelNow()
    return now ~= nil and target ~= nil and now >= target - 0.001
end

--- "level 23", or "6 bars into level 22" (a level is 20 bars).
function Speed.LevelText(target)
    local l = math.floor(target)
    local bars = math.floor((target - l) * 20 + 0.5)
    if bars <= 0 then return "level " .. l end
    if bars >= 20 then return "level " .. (l + 1) end
    return string.format("%d bar%s into level %d", bars, bars == 1 and "" or "s", l)
end

--- Mobs to grind near `point` in [lo, hi]: the route's own quest mobs (objectives before step `k`)
--- first, then QuestieDB's. Returns { name, npcIds, point, lo, hi } or nil.
function Speed.GrindMobs(plan, k, point, lo, hi)
    local best, bestD
    for i = 1, (k or 1) - 1 do
        local s = plan.steps[i]
        for _, t in ipairs((s and s.tasks) or {}) do
            local ml = t.kind == "objective" and t.mobLevel
            local npcs = t.obj and t.obj.targets and t.obj.targets.npc
            if ml and ml >= lo and ml <= hi and t.loc and type(npcs) == "table" and npcs[1] then
                local d = Geo.Distance(point, t.loc)
                if d and d <= Speed.GRIND_NEAR_YARDS and (not bestD or d < bestD) then
                    best, bestD = { name = Data.NpcName(npcs[1]), npcIds = npcs, point = t.loc, lo = ml,
                                    hi = tonumber(Data.Npc(npcs[1], "maxLevel")) or ml }, d
                end
            end
        end
    end
    if best then return best end
    local mobs = Data.MobsNear and Data.MobsNear(point, Speed.GRIND_NEAR_YARDS, lo, hi) or {}
    local m = mobs[1]
    if m then return { name = m.name, npcIds = { m.npcId }, point = m.point, lo = m.minLevel, hi = m.maxLevel } end
    return nil
end

--- Where the plan would send you under-levelled, and the stop to put before it. Returns the step
--- index to insert at and the task, or nil.
function Speed.GrindStop(plan, player)
    if not (ns.db.grindFirst and plan and plan.steps and player and player.level) then return nil end
    local P = ns.Planner
    local per = P.TurninsPerLevel(player.level)
    local now = player.level + (player.xpFrac or 0)
    local credits = 0
    local at, need, short, gated
    for i, s in ipairs(plan.steps) do
        if i > Speed.GRIND_MAX_STEPS then break end
        local predicted = now + credits / per
        for _, t in ipairs(s.tasks) do
            if t.kind == "objective" and not t.isDone and t.mobLevel and not t.urgent and not t.deferred then
                local n = t.mobLevel - P.LEVEL_SLACK
                if n - predicted >= Speed.GRIND_MIN_LEVELS and (not short or n - predicted > short) then
                    at, need, short, gated = i, n, n - predicted, t
                end
            end
        end
        if at then break end
        for _, t in ipairs(s.tasks) do
            if t.kind == "turnin" and not t.isDone then credits = credits + (t.xpWeight or 1) end
        end
    end
    if not at then return nil end
    local predicted = now + credits / per
    local xpPer, rate = Speed.XPPerLevel(player.level), P.GrindRate(player.level)
    local seconds = short * xpPer / rate
    if seconds > Speed.GRIND_MAX_SECONDS then
        -- a few bars closer is what a stop is for; the planner's level waits handle the rest
        seconds = Speed.GRIND_MAX_SECONDS
        short = seconds * rate / xpPer
        need = predicted + short
    end
    local from = (at > 1 and plan.steps[at - 1].loc) or player.point
    if not from then return nil end
    local base = math.floor(predicted)
    local mobs = Speed.GrindMobs(plan, at, from, base - 2, base + 1)
    local gatedNpc = gated.obj and gated.obj.targets and gated.obj.targets.npc and gated.obj.targets.npc[1]
    local gatedName = gatedNpc and Data.NpcName(gatedNpc) or (gated.quest and gated.quest.title)
    local what = mobs and string.format("kill %s (lvl %s)", mobs.name or "the mobs",
        (mobs.hi and mobs.hi > mobs.lo) and (mobs.lo .. "-" .. mobs.hi) or tostring(mobs.lo)) or "kill mobs at your level"
    local task = {
        id = "V:grind", kind = "visit", visit = "grind", loc = (mobs and mobs.point) or from,
        est = seconds, deps = {}, targetLevel = need, npcIds = mobs and mobs.npcIds or nil,
        mobName = mobs and mobs.name, forLevel = gated.mobLevel, forName = gatedName,
        label = string.format("Grind first: %s around here until %s (about %d min) - %s ahead %s level %d",
            what, Speed.LevelText(need), math.max(1, math.floor(seconds / 60 + 0.5)),
            gatedName or "the next mobs", gatedName and "is" or "are", gated.mobLevel),
    }
    return at, task
end

---------------------------------------------------------------------------
-- Die and res at the spirit healer
---------------------------------------------------------------------------
-- When you release your spirit you appear at the graveyard nearest where you died (in that
-- zone). Speed-levelers die on purpose when that graveyard is next to where they're going.
-- Classic's rules: no resurrection sickness up to level 10, then a minute per level over 10, ten
-- minutes from level 20; the spirit healer also costs 25% durability. Sickness only hurts when
-- you have to fight, so turn-ins and flights right after count against it.
-- Graveyards: the game's own list for the map when it gives one (C_DeathInfo), plus the ones the
-- add-on has seen you appear at (saved account-wide; nice to have, so the SavedVariables restore
-- bug only costs the learned ones).
Speed.DEATH_OVERHEAD = 35    -- find a mob, die, release, talk to the spirit healer
Speed.DEATH_MIN_SAVING = 60
Speed.DEATH_MAX_SHARE = 0.75 -- and it has to take at most 75% of the best other way
Speed.DEATH_MIN_WAY = 120    -- only for trips longer than 2 minutes
Speed.GRAVEYARD_SAME_YARDS = 40
Speed.CALM_MAX = 900

function Speed.ResSicknessSeconds(level)
    level = level or 1
    if level <= 10 then return 0 end
    if level < 20 then return (level - 10) * 60 end
    return 600
end

local gameGraveyards = {}
function Speed.ResetGraveyards() gameGraveyards = {} end

--- The game's graveyards on a map (cached for the session): points with .gyName.
function Speed.GameGraveyards(mapId)
    if not mapId then return {} end
    local cached = gameGraveyards[mapId]
    if cached then return cached end
    local out = {}
    local fn = C_DeathInfo and C_DeathInfo.GetGraveyardsForMap
    if fn then
        local ok, list = pcall(fn, mapId)
        if ok and type(list) == "table" and not ns.IsSecret(list) then
            for _, g in ipairs(list) do
                local pos = type(g) == "table" and g.position
                local x, y
                if type(pos) == "table" then
                    if pos.GetXY then
                        local okXY, px, py = pcall(pos.GetXY, pos)
                        if okXY then x, y = px, py end
                    else
                        x, y = pos.x, pos.y
                    end
                end
                x, y = plainNumber(x), plainNumber(y)
                if x and y then
                    local p = Geo.Point(mapId, x, y)
                    if p then
                        p.gyName = (type(g.name) == "string" and not ns.IsSecret(g.name)) and g.name or nil
                        out[#out + 1] = p
                    end
                end
            end
        end
    end
    gameGraveyards[mapId] = out
    return out
end

--- Graveyards you've appeared at (any map): points with .gyName.
function Speed.LearnedGraveyards()
    local out = {}
    for _, g in ipairs((ns.db and ns.db.graveyards) or {}) do
        local p = type(g) == "table" and g.mapId and Geo.Point(g.mapId, g.x, g.y)
        if p then p.gyName = g.name; out[#out + 1] = p end
    end
    return out
end

--- Remember where your spirit appeared (called after you release).
function Speed.LearnGraveyard(point, name)
    if not (point and point.mapId and point.x and point.y) then return false end
    ns.db.graveyards = ns.db.graveyards or {}
    for _, g in ipairs(ns.db.graveyards) do
        local p = g.mapId and Geo.Point(g.mapId, g.x, g.y)
        local d = p and Geo.Distance(p, point)
        if d and d <= Speed.GRAVEYARD_SAME_YARDS then return false end
    end
    ns.db.graveyards[#ns.db.graveyards + 1] = { mapId = point.mapId, x = point.x, y = point.y, name = name }
    return true
end

--- The graveyard you'd appear at if you died at `here`: the nearest one on the same map, else the
--- nearest on the continent.
function Speed.NearestGraveyard(here)
    if not here then return nil end
    local all = {}
    for _, p in ipairs(Speed.GameGraveyards(here.mapId)) do all[#all + 1] = p end
    for _, p in ipairs(Speed.LearnedGraveyards()) do all[#all + 1] = p end
    local sameMap, sameD, any, anyD
    for _, p in ipairs(all) do
        local d = Geo.Distance(here, p)
        if d and d < math.huge then
            if p.mapId == here.mapId and (not sameD or d < sameD) then sameMap, sameD = p, d end
            if not anyD or d < anyD then any, anyD = p, d end
        end
    end
    return sameMap or any
end

--- Seconds of no fighting from step `k` on: its turn-ins, pickups and stops, and the walks and
--- flights between them, until a step with mobs to kill.
function Speed.CalmSeconds(plan, k, net)
    local calm = 0
    local steps = (plan and plan.steps) or {}
    for i = k or 1, #steps do
        local s = steps[i]
        for _, t in ipairs(s.tasks or {}) do
            if t.kind == "objective" and not t.isDone and t.obj and (t.obj.type == "monster" or t.obj.type == "item") then
                return math.min(calm, Speed.CALM_MAX)
            end
        end
        calm = calm + (s.est or 20)
        local nxt = steps[i + 1]
        if nxt and nxt.loc and s.loc then
            if nxt.travel and nxt.travel.air then
                calm = calm + nxt.travel.air
            elseif net and ns.Travel and ns.Travel.Walk then
                calm = calm + ns.Travel.Walk(net, s.loc, nxt.loc)
            end
        end
        if calm >= Speed.CALM_MAX then break end
    end
    return math.min(calm, Speed.CALM_MAX)
end

--- Dying at `here` to get to `dest`: { graveyard, name, total, after, sickness, wait, yards } or nil.
function Speed.DeathOption(net, here, dest, level, calm)
    if not (here and dest) or here.cont ~= dest.cont then return nil end
    local gy = Speed.NearestGraveyard(here)
    if not gy or gy.cont ~= dest.cont then return nil end
    local after = (ns.Travel and ns.Travel.Walk) and ns.Travel.Walk(net, gy, dest) or Geo.TravelSeconds(gy, dest)
    local sick = Speed.ResSicknessSeconds(level)
    local wait = math.max(0, sick - (calm or 0))
    return { graveyard = gy, name = gy.gyName, total = Speed.DEATH_OVERHEAD + after + wait, after = after,
             sickness = sick, wait = wait, yards = Geo.Distance(gy, dest) }
end

--- Is dying the clearly quicker way? `best` = seconds of the best other way.
function Speed.DeathWorthIt(die, best)
    return die ~= nil and best ~= nil and best >= Speed.DEATH_MIN_WAY
        and die.total <= best - Speed.DEATH_MIN_SAVING and die.total <= best * Speed.DEATH_MAX_SHARE
end

-- After you release, your spirit stands at the graveyard: remember it.
if ns.RegisterEvent then
    ns.RegisterEvent("PLAYER_ALIVE", function()
        local function learn()
            local okG, ghost = pcall(UnitIsGhost, "player")
            if not (okG and ghost == true and not ns.IsSecret(ghost)) then return end
            local here = Geo.PlayerPoint()
            local name
            for _, fn in ipairs({ GetSubZoneText, GetZoneText }) do
                local ok, v = pcall(fn)
                if ok and type(v) == "string" and v ~= "" and not ns.IsSecret(v) then name = v break end
            end
            if here and Speed.LearnGraveyard(here, name) then ns.Debug("graveyard learned: %s", tostring(name)) end
        end
        if C_Timer and C_Timer.After then C_Timer.After(1, learn) else learn() end
    end)
end

---------------------------------------------------------------------------
-- Hints (called from Hints.Compute)
---------------------------------------------------------------------------
Speed.BREAK_MIN_SECONDS = 120

--- The route says hearth, but the stone is cooling down.
function Speed.HearthWaitHint(readyIn)
    if not readyIn or readyIn <= 0 then return nil end
    if readyIn >= Speed.BREAK_MIN_SECONDS then
        return { priority = 60, kind = "info",
                 text = string.format("|cff66ccffHearth ready in %s:|r a good moment for a break - the cooldown keeps ticking while you're logged out",
                     clock(readyIn)) }
    end
    return { priority = 60, kind = "info", text = string.format("|cff66ccffHearth ready in %s|r", clock(readyIn)) }
end

local function pinFor(point, title)
    if not (point and point.mapId and point.x and point.y) then return nil end
    return { mapId = point.mapId, x = point.x, y = point.y, title = title }
end

local function placeText(point)
    if not (point and point.x and point.y) then return nil end
    local zone = zoneName(point.mapId)
    return string.format("%s%.1f, %.1f", zone and (zone .. " ") or "", point.x * 100, point.y * 100)
end

local function xpText(xp)
    if not xp then return "" end
    return string.format(" (+%d XP)", math.floor(xp + 0.5))
end

function Speed.Hints(push, env)
    local plan = env.plan
    if not plan then return end
    -- a named mob whose drop starts a quest, near your route
    for i, w in ipairs(plan.watchFor or {}) do
        if i > 2 then break end
        local where = (w.step == 0 and "around here") or string.format("near step %d", w.step)
        local zone = zoneName(w.mapId)
        push({ priority = 47, kind = "info", pin = pinFor(w.point, w.npcName),
               text = string.format("|cff66ccffWatch for:|r %s (lvl %d) %s%s - its drop starts |cffffd100%s|r%s. /tar %s shows if it's up",
                   w.npcName or "a named mob", w.level or 0, where, zone and (" in " .. zone) or "", w.title or "a quest",
                   xpText(w.xp), w.npcName or "") })
    end
    -- a profession you can learn in a minute unlocks a quest worth doing
    local u = plan.skillUnlocks and plan.skillUnlocks[1]
    if u then
        local trainer = Speed.ProfessionTrainer(u.skill, (plan.player and plan.player.point) or u.point)
        local where = trainer and placeText(trainer.point)
        push({ priority = 44, kind = "info", pin = trainer and pinFor(trainer.point, trainer.name),
               text = string.format("|cff66ccffLearn %s:|r %s unlocks |cffffd100%s|r%s - Apprentice is cheap and takes no profession slot",
                   u.skill, trainer and string.format("%s%s", trainer.name or "the trainer", where and (" (" .. where .. ")") or "")
                       or ("any " .. u.skill .. " trainer"), u.title or "a quest", xpText(u.xp)) })
    end
    -- the current step: grinding first, or a faster way there by dying
    local step = env.step
    if not step then return end
    for _, t in ipairs(step.tasks or {}) do
        if t.kind == "visit" and t.visit == "grind" and not t.isDone then
            local now = Speed.LevelNow()
            local left = now and t.targetLevel and math.max(0, t.targetLevel - now)
            local bars = left and math.max(1, math.floor(left * 20 + 0.5))
            push({ priority = 80, kind = "info",
                   text = string.format("|cff66ccffGrind first:|r %s to go (to %s)%s - %s ahead %s level %d",
                       bars and string.format("%d bar%s", bars, bars == 1 and "" or "s") or "a little",
                       Speed.LevelText(t.targetLevel or 0), t.mobName and (", " .. t.mobName .. " here are fine") or "",
                       t.forName or "the next mobs", t.forName and "is" or "are", t.forLevel or 0) })
        end
    end
    local live = env.point and ns.Ladder and ns.Ladder.LiveTravel and ns.Ladder.LiveTravel(step, env.point)
    local die = live and live.die
    if die then
        local note = (die.sickness == 0 and "no res sickness up to level 10")
            or (die.wait == 0 and string.format("the %s of res sickness wears off while you turn in", clock(die.sickness)))
            or string.format("%s of res sickness", clock(die.sickness))
        push({ priority = 57, kind = "info",
               text = string.format("|cff66ccffFaster: die on purpose|r and res at the spirit healer - you'd appear at the %s, %d yd from your next stop: about %s instead of %s (%s; 25%% durability) /ladder dietravel turns this off",
                   die.name and ("graveyard by " .. die.name) or "graveyard", math.floor((die.yards or 0) + 0.5),
                   clock(die.total), clock(live.dieVs), note) })
    end
end

return Speed
