-- Quest Ladder: /ladder diag [label] - the README's "Verify in game" checks in one command.
--
-- Results go into the QuestLadderDiag saved variable. The client writes it to
--   WTF\Account\<account>\SavedVariables\QuestLadder.lua
-- on /reload or logout, so the results can be read outside the game. The last 10 runs are
-- kept; the optional label says where you were ("turnin", "facing book"). `/ladder diag clear`
-- empties the history.
--
-- Read-only like the rest of the add-on: only read APIs, every client call is feature-detected
-- and pcall'd, and secret values are recorded as "<secret>" without being used. Nothing else in
-- the add-on reads QuestLadderDiag, so Forever's SavedVariables restore bug can't affect play.

local _, ns = ...
local Diag = {}
ns.Diag = Diag

Diag.MAX_RUNS = 10
local SECRET = "<secret>"
local MAX_STRING, MAX_KEYS, MAX_DEPTH = 300, 160, 5

---------------------------------------------------------------------------
-- Safe helpers
---------------------------------------------------------------------------
local function try(fn, ...)
    if type(fn) ~= "function" then return false, "missing" end
    return pcall(fn, ...)
end

--- First return value of fn(...), or nil when fn is missing, errors or returns a secret.
local function value(fn, ...)
    local ok, v = try(fn, ...)
    if ok and not ns.IsSecret(v) then return v end
    return nil
end

--- v, or nil when it is a secret (for values we test or compare).
local function plain(v)
    if ns.IsSecret(v) then return nil end
    return v
end

local function str(v)
    if ns.IsSecret(v) then return SECRET end
    return tostring(v)
end

local function count(t)
    local n = 0
    for _ in pairs(t or {}) do n = n + 1 end
    return n
end

local function frameName(f)
    if type(f) ~= "table" then return nil end
    local ok, name = try(f.GetName, f)
    if ok and not ns.IsSecret(name) and type(name) == "string" then return name end
    return "<unnamed frame>"
end

--- A copy of v that SavedVariables can store: strings, finite numbers, booleans and tables of
--- those. Secrets become "<secret>", frames their name, functions are dropped, size is capped.
--- (inf/nan would be written as bare words and break the whole file on the next load.)
local function clean(v, depth)
    if ns.IsSecret(v) then return SECRET end
    local t = type(v)
    if t == "nil" or t == "boolean" then return v end
    if t == "number" then
        if v ~= v then return "nan" end
        if v == math.huge then return "inf" end
        if v == -math.huge then return "-inf" end
        return v
    end
    if t == "string" then
        return (#v > MAX_STRING) and (v:sub(1, MAX_STRING) .. "...") or v
    end
    if t ~= "table" then return "<" .. t .. ">" end
    local okAccess, accessible = try(canaccesstable, v)
    if okAccess and accessible == false then return SECRET end
    if type(rawget(v, 0)) == "userdata" then return "<frame " .. frameName(v) .. ">" end
    depth = (depth or 0) + 1
    if depth > MAX_DEPTH then return "<table>" end
    local out, n = {}, 0
    for k, val in pairs(v) do
        local kt = type(k)
        local keyOk = not ns.IsSecret(k) and (kt == "string"
            or (kt == "number" and k == k and k ~= math.huge and k ~= -math.huge))
        if keyOk and type(val) ~= "function" then
            n = n + 1
            if n > MAX_KEYS then out["..."] = "truncated" break end
            out[k] = clean(val, depth)
        end
    end
    return out
end
Diag.Clean = clean

local function cvar(name)
    return value((C_CVar and C_CVar.GetCVar) or GetCVar, name)
end

local function addonLoaded(name)
    local ok, v = try((C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded, name)
    return ok and plain(v) and true or false
end

---------------------------------------------------------------------------
-- Checks: each returns status ("ok"/"warn"/"fail"/"skip"/"info"), summary, data
---------------------------------------------------------------------------
local checks = {}
Diag.checks = checks
local function check(id, title, fn) checks[#checks + 1] = { id = id, title = title, fn = fn } end

check("env", "Client and add-on", function(ctx)
    local data = {
        addonVersion = ns.VERSION, secretApi = type(issecretvalue) == "function",
        savedSettingsRestored = ns.svRestored, addons = {}, settings = ns.db,
    }
    local okB, version, build, buildDate, toc = try(GetBuildInfo)
    if okB then data.client = { version = version, build = build, date = buildDate, toc = toc } end
    data.tocVersion = value((C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata, ns.ADDON, "Version")
    data.locale = value(GetLocale)
    data.inCombat = value(InCombatLockdown)
    local okI, inInstance, instanceType = try(IsInInstance)
    if okI then data.inInstance, data.instanceType = inInstance, instanceType end
    for _, n in ipairs({ "Questie", "QuestieDB", "Auctionator", "TomTom", "Bagnon", "BagBrother", "Baganator",
                         "BugSack", "!BugGrabber" }) do
        data.addons[n] = addonLoaded(n)
    end
    local p = ctx.player
    if p then
        data.player = { level = p.level, class = p.classFile, raceId = p.raceId, faction = p.faction,
                        logMax = p.logMax, money = p.money, skills = p.skills }
    end
    data.hands = { canDualWield = ns.Gear.CanDualWield(p and p.classFile, p and p.level) }
    local okMain, mainLink = try(GetInventoryItemLink, "player", 16)
    if okMain then data.hands.mainHand = mainLink end
    local okOff, offLink = try(GetInventoryItemLink, "player", 17)
    if okOff then data.hands.offHand = offLink end
    local summary = string.format("client %s build %s (toc %s), add-on %s", str(version), str(build), str(toc), ns.VERSION)
    if data.tocVersion and data.tocVersion ~= ns.VERSION then
        return "warn", summary .. ", but the TOC says " .. str(data.tocVersion) .. " (restart the game after updating)", data
    end
    return "info", summary, data
end)

check("questiedb", "QuestieDB data and indexes", function(ctx)
    local Data, lib = ns.Data, LibQuestieDB
    local data = { present = lib ~= nil, adapterReady = Data.lib ~= nil, reason = Data.reason,
                   indexesReady = Data.ready, indexJobRunning = ns.IsJobRunning("QuestLadder.index") }
    if type(lib) == "table" then
        data.contract, data.minContract, data.readMode = lib.contractVersion, lib.minSupportedContract, lib.readMode
        if type(lib.flavor) == "table" then data.flavor = { expansion = lib.flavor.expansion, rules = lib.flavor.rules } end
    end
    if not Data.lib then return "fail", "QuestieDB adapter not ready: " .. str(Data.reason), data end
    local raceMask, classMask = Data.PlayerMasks(ctx.player or {})
    data.raceMask, data.classMask = raceMask, classMask
    local areas, subZones = ns.Geo.ZoneMapStats()
    data.zoneMap = { areas = areas, subZones = subZones }
    local starters = 0
    for _, grid in pairs(Data.starterGrid or {}) do
        for _, cell in pairs(grid) do starters = starters + #cell end
    end
    data.index = { questGiverSpawns = starters, followUps = count(Data.followUps), questsWithGear = count(Data.rewardItems),
                   gearLevels = count(Data.gearByLevel), vendors = #Data.vendors, trainers = #Data.trainers,
                   flightMasters = #Data.flightMasters, innkeepers = #Data.innkeepers }
    local known, missing = 0, {}
    for _, q in ipairs(ctx.list or {}) do
        if Data.Quest(q.id) then known = known + 1 else missing[#missing + 1] = { id = q.id, title = q.title } end
    end
    data.logQuestsInDB, data.logQuestsNotInDB = known, missing
    if areas == 0 then return "fail", "zone map is empty, so no QuestieDB spawn can be placed on a map", data end
    if raceMask == 0 or classMask == 0 then
        return "fail", string.format("race/class mask unknown (race %s, class %s): restricted quests get filtered wrongly",
            str(raceMask), str(classMask)), data
    end
    local summary = string.format("contract %s, %d zones mapped, %d quest-giver spawns, %d vendors, %d flight masters, %d/%d log quests in DB",
        str(data.contract), areas, starters, #Data.vendors, #Data.flightMasters, known, known + #missing)
    if not Data.ready then return "warn", "indexes still building, run diag again in a minute; " .. summary, data end
    if starters == 0 then return "fail", "no quest givers indexed; " .. summary, data end
    return "ok", summary, data
end)

check("plan", "Route plan", function(ctx)
    local L = ns.Ladder
    local plan = L.plan
    local data = { status = L.status, planJobRunning = ns.IsJobRunning("QuestLadder.plan"), current = L.current }
    if not plan then
        if data.planJobRunning or L.status == "Indexing quests..." then
            return "warn", "no plan yet (" .. str(L.status) .. "), run diag again shortly", data
        end
        return "fail", "no plan: " .. str(L.status), data
    end
    data.steps = #plan.steps
    if GetTime and plan.builtAt then data.ageSeconds = GetTime() - plan.builtAt end
    data.candidates = #(plan.candidates or {})
    data.active = #(plan.active or {})
    data.dropped = plan.dropped
    local here = ctx.player and ctx.player.point
    local function yards(loc)
        local dist = here and loc and ns.Geo.Distance(here, loc)
        return dist and math.floor(dist + 0.5) or nil
    end
    data.next = {}
    for i = L.current, math.min(#plan.steps, L.current + 5) do
        local s = plan.steps[i]
        local okT, title = try(L.StepTitle, s)
        local tasks = {}
        for _, t in ipairs(s.tasks) do tasks[#tasks + 1] = t.id end
        data.next[#data.next + 1] = { index = i, title = okT and title or "?", tasks = tasks, yards = yards(s.loc),
                                      travel = s.travel and s.travel.mode or nil }
    end
    -- The whole route, one compact line per step, to review it for detours and ping-pong
    data.route = {}
    for i, s in ipairs(plan.steps) do
        if i > 80 then data.route[#data.route + 1] = "..." break end
        local okT, title = try(L.StepTitle, s)
        local ids = {}
        for _, t in ipairs(s.tasks) do ids[#ids + 1] = t.id end
        data.route[#data.route + 1] = string.format("%d%s %s | %s yd%s | %s", i, i < L.current and " (done)" or "",
            okT and title or "?", tostring(yards(s.loc) or "?"), s.travel and (" | " .. s.travel.mode) or "",
            table.concat(ids, ","))
    end
    -- Objectives held back by the mob-level rule: how many turn-ins they wait for, and where they landed
    data.levelWaits = {}
    local stepOfTask, turnedIn = {}, {}
    for i, s in ipairs(plan.steps) do for _, t in ipairs(s.tasks) do stepOfTask[t] = i end end
    local soFar = 0
    for _, t in ipairs(plan.order or {}) do
        turnedIn[t] = soFar
        if t.kind == "turnin" then soFar = soFar + (t.xpWeight or 1) end
    end
    for _, t in ipairs(plan.order or {}) do
        if t.mobLevel and ctx.player and t.mobLevel >= (ctx.player.level or 0) + 2 and #data.levelWaits < 20 then
            data.levelWaits[#data.levelWaits + 1] = string.format("%s mobs lvl %d | wait %s turn-ins | step %s after %.1f",
                tostring(t.id), t.mobLevel, t.minTurnins and string.format("%.1f", t.minTurnins) or "none",
                tostring(stepOfTask[t] or "?"), turnedIn[t] or 0)
        end
    end
    -- New quests left out for low XP (minQuestValue), and where the next good area is
    data.minQuestValue = ns.db.minQuestValue
    data.solidQuestXP = ctx.player and ns.Data.SolidQuestXP and ns.Data.SolidQuestXP(ctx.player.level) or nil
    data.skippedLowValue = {}
    for i, s in ipairs(plan.skippedLowValue or {}) do
        if i > 30 then break end
        data.skippedLowValue[#data.skippedLowValue + 1] = string.format("%s %s | %s XP | %s%% of a solid quest",
            tostring(s.id), tostring(s.title), s.xp and tostring(math.floor(s.xp + 0.5)) or "?",
            s.ratio and tostring(math.floor(s.ratio * 100 + 0.5)) or "?")
    end
    if plan.nextArea then
        local okT, text = try(L.NextAreaText, plan.nextArea)
        data.nextArea = okT and text or "?"
    end
    -- New quests left out because their detour earns less XP than killing mobs that long
    data.notWorthTrip = {}
    for i, p in ipairs(plan.pruned or {}) do
        if i > 30 then break end
        data.notWorthTrip[#data.notWorthTrip + 1] = string.format("%s %s | %s XP | adds %s s%s | %s%% of grinding",
            tostring(p.questId), tostring(p.title), p.xp and tostring(math.floor(p.xp + 0.5)) or "?",
            tostring(math.floor((p.seconds or 0) + 0.5)), (p.together or 1) > 1 and (" for " .. p.together .. " together") or "",
            tostring(math.floor((p.worth or 0) * 100 + 0.5)))
    end
    data.tripCheck = ns.db.tripCheck
    -- 0.4.0: quests in your log you've outgrown: which the route left out, and which it keeps
    data.outgrown = {}
    for i, p in ipairs(plan.outgrown or {}) do
        if i > 30 then break end
        local q = p.quest or {}
        data.outgrown[#data.outgrown + 1] = string.format("dropped %s %s [%s] | %s XP | saves %s s%s | %s%% of grinding",
            tostring(p.questId), tostring(p.title), tostring(q.level), p.xp and tostring(math.floor(p.xp + 0.5)) or "?",
            tostring(math.floor((p.seconds or 0) + 0.5)), (p.together or 1) > 1 and (" for " .. p.together .. " together") or "",
            tostring(math.floor((p.worth or 0) * 100 + 0.5)))
    end
    for _, q in ipairs(plan.active or {}) do
        local dropped = false
        for _, p in ipairs(plan.outgrown or {}) do if p.questId == q.id then dropped = true end end
        if q.outgrown and not dropped and #data.outgrown < 40 then
            data.outgrown[#data.outgrown + 1] = string.format("kept %s %s [%s] | %s XP", tostring(q.id), tostring(q.title),
                tostring(q.level), q.tripXP and tostring(math.floor(q.tripXP + 0.5)) or "?")
        end
    end
    -- which first guess the route grew from (Planner: "More than one first guess")
    data.routeStart = plan.seed or "normal"
    -- Timed quests: what the game's timer says, the item, and where the quest sits in the route
    data.timerApi = { getTimeAllowed = C_QuestLog ~= nil and C_QuestLog.GetTimeAllowed ~= nil,
                      legacy = GetQuestTimers ~= nil and GetQuestIndexForTimer ~= nil }
    data.timed = {}
    local firstStep = {}
    for i, s in ipairs(plan.steps) do
        for _, t in ipairs(s.tasks) do if t.urgent and t.questId and not firstStep[t.questId] then firstStep[t.questId] = i end end
    end
    for _, q in ipairs(plan.active or {}) do
        if q.timed then
            local tm = q.timer
            data.timed[#data.timed + 1] = string.format("%s %s | %s | item %s | first at step %s", tostring(q.id), tostring(q.title),
                tm and string.format("%s timer %.0f s, %.0f s gone", tostring(tm.source), tm.total, tm.elapsed) or "no timer read (quest text says timed)",
                tostring(q.timedItem), tostring(firstStep[q.id] or "?"))
        end
    end
    if #data.timed > 0 then
        local okT, list = try(L.TimedQuests)
        data.timerLines = {}
        for _, e in ipairs(okT and list or {}) do
            local okX, text = try(L.TimerText, e)
            data.timerLines[#data.timerLines + 1] = okX and text or "?"
        end
    end
    data.candidateList = {}
    for i, c in ipairs(plan.candidates or {}) do
        if i > 40 then data.candidateList[#data.candidateList + 1] = "..." break end
        data.candidateList[#data.candidateList + 1] = string.format("%s %s | %s yd%s | %s XP%s", tostring(c.id), tostring(c.title),
            tostring(yards(c.pickup) or "?"), c.chainedFrom and (" | after " .. tostring(c.chainedFrom)) or "",
            c.tripXP and tostring(math.floor(c.tripXP + 0.5)) or "?", c.keep and (" | keep: " .. tostring(c.worthWhy)) or "")
    end
    -- Replay data: the route's tasks (in order) and the travel network, so the planner can be
    -- re-run offline on your real map. One compact line each:
    -- id|kind|deps|cont|x|y|est|flags|mobLevel|xpWeight|wait|tripXP|keep (wait = turn-ins before it,
    -- as planned; tripXP and keep on new quests' pickups). replay.pruned: the tasks of the quests
    -- left out as not worth the trip, same format.
    local function xy(p)
        if type(p) ~= "table" or not p.wx then return "-|-|-" end
        return string.format("%s|%.1f|%.1f", tostring(p.cont), p.wx, p.wy or 0)
    end
    local replay = { start = xy(plan.player and plan.player.point), logCount = plan.logCount, logMax = plan.logMax,
                     level = plan.player and plan.player.level, xpFrac = plan.player and plan.player.xpFrac,
                     tasks = {}, nodes = {} }
    local function line(t)
        local flags = (t.deferred and "d" or "") .. (t.teleport and "t" or "") .. (t.visit and ("v:" .. t.visit) or "")
        -- tripXP: on new quests' pickups, and (0.4.0) on outgrown log quests' tasks, flagged "o"
        local q = (t.kind == "pickup" or (t.quest and t.quest.outgrown)) and t.quest or nil
        return table.concat({ tostring(t.id), tostring(t.kind), table.concat(t.deps or {}, ","),
            xy(t.loc), tostring(t.est or 0), flags, tostring(t.mobLevel or ""), tostring(t.xpWeight or ""),
            t.minTurnins and string.format("%.1f", t.minTurnins) or "",
            q and q.tripXP and tostring(math.floor(q.tripXP + 0.5)) or "",
            q and ((q.keep and "k") or (t.kind ~= "pickup" and q.outgrown and "o")) or "" }, "|")
    end
    for i, t in ipairs(plan.order or {}) do
        if i > 150 then break end
        replay.tasks[#replay.tasks + 1] = line(t)
    end
    replay.pruned = {}
    local prunedId = {}
    for _, p in ipairs(plan.pruned or {}) do prunedId[p.questId] = true end
    for _, p in ipairs(plan.outgrown or {}) do prunedId[p.questId] = true end
    for _, t in ipairs(plan.tasks or {}) do
        if t.questId and prunedId[t.questId] and #replay.pruned < 120 then replay.pruned[#replay.pruned + 1] = line(t) end
    end
    local net = plan.net
    if net then
        replay.speed, replay.hasHearth = net.speed, net.hasHearth
        replay.hearthReadyIn, replay.hearthCooldown, replay.bind = net.hearthReadyIn, net.hearthCooldown, net.bind and xy(net.bind)
        for i, nd in ipairs(net.nodes or {}) do
            if i > 60 then break end
            replay.nodes[#replay.nodes + 1] = string.format("%s|%s|%s", tostring(nd.name), xy(nd.point), nd.known and "known" or "-")
        end
    end
    data.replay = replay
    -- Finished quests: which step turns each one in, and how far away its NPC is
    local stepOf = {}
    for i, s in ipairs(plan.steps) do
        for _, t in ipairs(s.tasks) do stepOf[t.id] = i end
    end
    data.readyTurnins = {}
    for _, q in ipairs(ctx.list or {}) do
        if q.complete then
            local t = plan.byId and plan.byId["T" .. q.id]
            data.readyTurnins[#data.readyTurnins + 1] = { id = q.id, title = q.title, step = stepOf["T" .. q.id],
                                                          yards = t and yards(t.loc) or nil }
        end
    end
    local stops = {}
    for _, s in ipairs(plan.steps) do
        if s.travel and s.travel.mode then stops[s.travel.mode] = (stops[s.travel.mode] or 0) + 1 end
        for _, t in ipairs(s.tasks) do
            if t.kind == "visit" then stops[t.visit or "visit"] = (stops[t.visit or "visit"] or 0) + 1 end
        end
    end
    data.travelAndStops = stops
    if #plan.steps == 0 then return "warn", "the plan is empty (no quests in reach?)", data end
    local summary = string.format("%d steps, current: %s; %d quests ready to turn in; %d new quests planned, %d not worth the trip; %d outgrown left out",
        #plan.steps, data.next[1] and data.next[1].title or "?", #data.readyTurnins,
        data.candidates - #(plan.pruned or {}), #(plan.pruned or {}), #(plan.outgrown or {}))
    if data.planJobRunning then
        return "warn", summary .. "; a newer plan was still being worked out, run diag again in a few seconds", data
    end
    -- a finished quest whose NPC is close but whose turn-in waits several steps is worth a look
    for _, r in ipairs(data.readyTurnins) do
        if r.yards and r.yards <= 300 and r.step and r.step > L.current + 2 then
            return "warn", summary .. string.format("; %s is %d yd away but waits until step %d",
                str(r.title), r.yards, r.step), data
        end
    end
    return "ok", summary, data
end)

check("locations", "Task locations (QuestieDB spawns on the map)", function(ctx)
    local plan = ns.Ladder.plan
    if not plan then return "skip", "no plan yet", nil end
    local total, located, unknown = 0, 0, {}
    for _, t in ipairs(plan.order or {}) do
        total = total + 1
        if t.loc then
            located = located + 1
        elseif #unknown < 8 then
            local okT, text = try(ns.Ladder.TaskText, t)
            unknown[#unknown + 1] = { id = t.id, text = okT and text or nil }
        end
    end
    local data = { tasks = total, located = located, unknownSample = unknown }
    if total == 0 then return "skip", "the plan has no tasks", data end
    local summary = string.format("%d of %d tasks have a map location", located, total)
    if located == 0 then return "fail", summary, data end
    if located < total * 0.75 then return "warn", summary, data end
    return "ok", summary, data
end)

check("position", "1. World positions (C_Map.GetWorldPosFromMapPos)", function(ctx)
    local data = {}
    local okM, mapId = try(C_Map and C_Map.GetBestMapForUnit, "player")
    data.mapId = mapId
    if not okM then return "fail", "C_Map.GetBestMapForUnit failed", data end
    if ns.IsSecret(mapId) then return "fail", "the player's map ID is a secret value", data end
    if not mapId then return "fail", "no map for the player (loading screen or instance?)", data end
    data.mapName = value(function() return C_Map.GetMapInfo(mapId).name end)
    local okP, pos = try(C_Map.GetPlayerMapPosition, mapId, "player")
    if not okP or ns.IsSecret(pos) or not pos then
        data.mapPos = pos
        return "fail", "C_Map.GetPlayerMapPosition gave no usable position", data
    end
    local x, y
    if pos.GetXY then x, y = pos:GetXY() else x, y = pos.x, pos.y end
    data.mapPos = { x = x, y = y }
    if ns.AnySecret(x, y) or not x or not y then return "fail", "the map position is secret or missing", data end
    local okW, cont, world = try(C_Map.GetWorldPosFromMapPos, mapId, pos)
    if okW then
        data.raw = { continent = cont, world = world }
        if not ns.IsSecret(world) and type(world) == "table" then
            local wx, wy
            if world.GetXY then wx, wy = world:GetXY() else wx, wy = world.x, world.y end
            data.raw.world = { x = wx, y = wy }
        end
    else
        data.rawError = cont
    end
    local point = ns.Geo.PlayerPoint()
    data.addonPoint = point
    if not point then return "fail", "map position works but the world position doesn't, so distances are unknown", data end
    return "ok", string.format("%s (map %s) at %.3f, %.3f -> continent %s, world %.0f, %.0f",
        str(data.mapName), str(mapId), x, y, str(point.cont), point.wx, point.wy), data
end)

check("waypoint", "2. Waypoint pin (C_Map.SetUserWaypoint / TomTom)", function(ctx)
    local L = ns.Ladder
    local data = { enabled = ns.db.waypoints, tomtom = (TomTom and TomTom.AddWaypoint) and true or false }
    local okT, target, why = try(L.WaypointTarget, ctx.step, ns.Geo.PlayerPoint())
    if not okT then target = nil end
    if target then
        data.target = { mapId = target.mapId, x = target.x, y = target.y, why = why }
        data.canSetOnMap = value(C_Map and C_Map.CanSetUserWaypointOnMap, target.mapId)
    end
    local uw -- { mapId, x, y } when readable
    local okW, wp = try(C_Map and C_Map.GetUserWaypoint)
    if okW and not ns.IsSecret(wp) and type(wp) == "table" then
        local pos, px, py = wp.position, nil, nil
        if not ns.IsSecret(pos) and type(pos) == "table" then
            if pos.GetXY then px, py = pos:GetXY() else px, py = pos.x, pos.y end
        end
        data.userWaypoint = { mapId = wp.uiMapID, x = px, y = py }
        uw = { mapId = plain(wp.uiMapID), x = plain(px), y = plain(py) }
    elseif okW then
        data.userWaypoint = wp
    end
    data.superTracking = value(C_SuperTrack and C_SuperTrack.IsSuperTrackingUserWaypoint)
    if not ns.db.waypoints then return "skip", "waypoints are off (/ladder waypoints)", data end
    if not target then return "skip", "no current step with a location", data end
    if data.tomtom then return "info", "TomTom is installed, so the arrow is TomTom's (check it on screen)", data end
    if not (uw and uw.mapId) then
        if data.canSetOnMap == false then
            return "warn", "the game doesn't allow a pin on this map (" .. str(target.mapId) .. ")", data
        end
        return "fail", "no user waypoint is set although the step has a location", data
    end
    local same = uw.mapId == target.mapId and uw.x and uw.y
        and math.abs(uw.x - target.x) < 0.002 and math.abs(uw.y - target.y) < 0.002
    data.matchesTarget = same and true or false
    if not same then return "warn", "a pin is set, but not on the current step (your own pin, or another map)", data end
    if data.superTracking == false then return "warn", "the pin is set but not tracked (no arrow on screen)", data end
    return "ok", string.format("pin on map %s at %.3f, %.3f matches the current step", str(uw.mapId), uw.x, uw.y), data
end)

check("rewards", "3. Quest rewards by quest ID (no quest opened)", function(ctx)
    if type(GetNumQuestLogChoices) ~= "function" then return "fail", "GetNumQuestLogChoices is missing", nil end
    local itemIdFromLink = ns.QuestState.ItemIdFromLink
    local data = { selectedQuest = value(C_QuestLog and C_QuestLog.GetSelectedQuest), quests = {} }
    local signatures, withRewards, mismatches = {}, 0, 0
    for _, q in ipairs(ctx.list or {}) do
        if #data.quests >= 10 then break end
        local e = { id = q.id, title = q.title, choices = {}, fixed = {} }
        e.numChoices = value(GetNumQuestLogChoices, q.id, false)
        local nChoices = type(e.numChoices) == "number" and math.min(e.numChoices, 8) or 0
        for i = 1, nChoices do
            local link = value(GetQuestLogItemLink, "choice", i, q.id)
            local okI, _, _, _, _, _, itemId = try(GetQuestLogChoiceInfo, i, q.id)
            local fromInfo = okI and plain(itemId) or nil
            local fromLink = itemIdFromLink(link)
            e.choices[#e.choices + 1] = { link = link, itemId = fromInfo, linkItemId = fromLink }
            if fromInfo and fromLink and fromInfo ~= fromLink then mismatches = mismatches + 1 end
        end
        e.numFixed = value(GetNumQuestLogRewards, q.id)
        local nFixed = type(e.numFixed) == "number" and math.min(e.numFixed, 8) or 0
        for i = 1, nFixed do
            local link = value(GetQuestLogItemLink, "reward", i, q.id)
            if link then e.fixed[#e.fixed + 1] = link end
        end
        local sig = {}
        for _, c in ipairs(e.choices) do sig[#sig + 1] = tostring(c.itemId or c.linkItemId) end
        for _, l in ipairs(e.fixed) do sig[#sig + 1] = tostring(itemIdFromLink(l)) end
        if #sig > 0 then
            withRewards = withRewards + 1
            signatures[table.concat(sig, ",")] = true
        end
        data.quests[#data.quests + 1] = e
    end
    local distinct = count(signatures)
    data.questsWithItemRewards, data.distinctRewardSets, data.linkInfoMismatches = withRewards, distinct, mismatches
    if #data.quests == 0 then return "skip", "the quest log is empty", data end
    if withRewards == 0 then return "skip", "no quest in your log has item rewards to test with", data end
    if mismatches > 0 then return "warn", "GetQuestLogChoiceInfo and GetQuestLogItemLink disagree on item IDs", data end
    if withRewards >= 2 and distinct == 1 then
        return "warn", string.format("all %d quests return the same rewards: the API may ignore the quest ID", withRewards), data
    end
    return "ok", string.format("%d quests return item rewards by ID (%d different sets)", withRewards, distinct), data
end)

check("gear", "3b. Gear scoring (reward picks and gear in your bags)", function(ctx)
    local G, player = ns.Gear, ctx.player
    if not (G and player) then return "skip", "no player info", nil end
    local itemIdFromLink = ns.QuestState.ItemIdFromLink
    local data = { level = player.level, class = player.classFile, minGain = G.MIN_GAIN, minPct = G.MIN_PCT,
                   tooltipApi = C_TooltipInfo ~= nil and type(C_TooltipInfo.GetHyperlink) == "function",
                   equipped = {}, items = {}, picks = {} }
    local armorItems, fromStats, fromTooltip, unread = 0, 0, 0, 0
    local function armorOf(link, info, e)
        local sub = info.subClassID
        if info.classID ~= 4 or not sub or not (sub >= 1 and sub <= 4 or sub == 6) then return end
        armorItems = armorItems + 1
        local raw = G.GetStats(link)
        if raw and plain(raw.RESISTANCE0_NAME) then
            fromStats, e.armor, e.armorFrom = fromStats + 1, raw.RESISTANCE0_NAME, "stats"
        else
            local t = G.TooltipArmor(link)
            if t then fromTooltip, e.armor, e.armorFrom = fromTooltip + 1, t, "tooltip"
            else unread, e.armorFrom = unread + 1, "unread" end
        end
    end
    for slot = 1, 18 do
        local link = slot ~= 4 and value(GetInventoryItemLink, "player", slot)
        local info = link and G.ItemInfo(link)
        if info then
            local e = { slot = slot, name = info.name, score = G.Score(link, slot, player.classFile) }
            armorOf(link, info, e)
            data.equipped[#data.equipped + 1] = e
        end
    end
    local suggestion = {}
    local okS, list = try(ns.Bags.Suggestions, ctx.bags, ctx.byId, ns.Ladder and ns.Ladder.plan)
    for _, s in ipairs(okS and list or {}) do suggestion[tostring(s.bag) .. ":" .. tostring(s.slot)] = s end
    local function describe(link, source, extra)
        local info = G.ItemInfo(link)
        if not info then return { source = source, link = link, loaded = false } end
        local e = { source = source, name = info.name, equipLoc = info.equipLoc, class = info.classID,
                    subclass = info.subClassID, quality = info.quality, minLevel = info.minLevel, sell = info.sellPrice,
                    stats = G.GetStats(link) }
        armorOf(link, info, e)
        e.canWearNow = G.CanEquip(itemIdFromLink(link), info, player, 0)
        local up = G.CompareToEquipped(link, info, player.classFile, player.level)
        if up then
            e.compare = { slot = up.slot, old = up.old, new = up.new, delta = up.delta, pct = up.pct, empty = up.empty }
            e.upgrade = G.IsUpgrade(up)
        end
        for k, v in pairs(extra or {}) do e[k] = v end
        return e
    end
    for _, q in ipairs(ctx.list or {}) do
        local n = value(GetNumQuestLogChoices, q.id, false)
        local choices = {}
        for i = 1, (type(n) == "number" and math.min(n, 8) or 0) do
            local link = value(GetQuestLogItemLink, "choice", i, q.id)
            if link and G.SLOTS[(G.ItemInfo(link) or {}).equipLoc or ""] then
                choices[#choices + 1] = { index = i, itemId = itemIdFromLink(link), link = link }
                if #data.items < 20 then data.items[#data.items + 1] = describe(link, "reward " .. q.id) end
            end
        end
        if #choices > 1 then
            local okP, pick = try(G.BestChoice, choices, player)
            data.picks[#data.picks + 1] = { quest = q.title, pick = okP and pick and pick.name or nil,
                                            reason = okP and pick and pick.reason or nil }
        end
    end
    for _, s in ipairs((ctx.bags and ctx.bags.slots) or {}) do
        local info = s.link and G.ItemInfo(s.link)
        if info and (info.classID == 2 or info.classID == 4) and G.SLOTS[info.equipLoc or ""] and #data.items < 20 then
            local sug = suggestion[tostring(s.bag) .. ":" .. tostring(s.slot)]
            data.items[#data.items + 1] = describe(s.link, "bag " .. s.bag .. ":" .. s.slot,
                { bagAction = sug and sug.action or "keep", bagReason = sug and sug.reason or nil })
        end
    end
    data.armorItems, data.armorFromStats, data.armorFromTooltip, data.armorUnread = armorItems, fromStats, fromTooltip, unread
    if #data.items == 0 and #data.equipped == 0 then return "skip", "no gear to look at", data end
    if armorItems > 0 and unread == armorItems then
        return "warn", "armor can't be read (stats or tooltip), so plain armor pieces can't be compared", data
    end
    return "info", string.format("%d items looked at, %d reward picks; armor from stats %d, tooltip %d, unread %d",
        #data.items, #data.picks, fromStats, fromTooltip, unread), data
end)

check("goodies", "3c. Forever extras (bags, riding, sleeping bag chain, crates, must-do quests)", function(ctx)
    local G, p = ns.Goodies, ctx.player
    if not (G and p) then return "skip", "no player info", nil end
    local data = { bags = {}, tooltipApi = C_TooltipInfo ~= nil and type(C_TooltipInfo.GetItemByID) == "function" }
    for i, e in ipairs(G.EquippedBags()) do data.bags[i] = string.format("%d slots%s", e.slots, e.special and " (special)" or "") end
    data.smallestBag = G.SmallestBag()
    local plan = ns.Ladder.plan
    local buy = plan and plan.bagToBuy
    data.bagToBuy = buy and string.format("%s (%d slots, ~%s) from %s", tostring(buy.name), buy.slots, ns.FormatMoney(buy.price),
        tostring(buy.vendor)) or nil
    data.vendorBagsIndexed = #(ns.Data.vendorBags or {})
    data.questsWithBagRewards = count(ns.Data.bagRewards)
    local okR, ride = try(G.RidingHint, setmetatable({ money = value(GetMoney) or p.money }, { __index = p }))
    data.riding = okR and ride or nil
    data.ridingGoldKeptAside = ns.Gear.NeedsRidingGold(p)
    local cozy = plan and plan.cozyStart
    data.cozyStart = cozy and string.format("%s (%s) at %s", tostring(cozy.title), tostring(cozy.questId), tostring(cozy.giver)) or nil
    local okN, npc = try(G.CrateNpc, p)
    data.crateNpc = okN and npc and npc.name or nil
    local okC, crates = try(G.CratesInBags, ctx.bags)
    data.cratesInBags = okC and #crates or 0
    data.mustDoInPlan = {}
    for _, t in ipairs((plan and plan.order) or {}) do
        if t.kind == "pickup" and #data.mustDoInPlan < 15 then
            local note = G.MustDo(t.questId)
            if note then data.mustDoInPlan[#data.mustDoInPlan + 1] = string.format("%s %s | %s", t.questId, tostring(t.quest and t.quest.title), note) end
        end
    end
    if data.vendorBagsIndexed > 0 and not G.BagSlots(ns.Data.vendorBags[1].itemId) then
        return "warn", "couldn't read a bag's slot count from its tooltip; bag advice is off", data
    end
    return "info", string.format("smallest bag %d slots; %s; %d must-do quests in the plan; crate NPC %s",
        data.smallestBag, data.bagToBuy and ("buy: " .. data.bagToBuy) or "no bag to buy", #data.mustDoInPlan,
        tostring(data.crateNpc)), data
end)

check("questitems", "4. Quest items (GetQuestLogSpecialItemInfo, bag quest info)", function(ctx)
    local hasSpecial = type(GetQuestLogSpecialItemInfo) == "function"
    local hasBagInfo = C_Container ~= nil and type(C_Container.GetContainerItemQuestInfo) == "function"
    local data = { special = {}, bagQuestItems = {}, secretLinks = 0,
                   apis = { GetQuestLogSpecialItemInfo = hasSpecial, GetContainerItemQuestInfo = hasBagInfo } }
    if hasSpecial then
        for _, q in ipairs(ctx.list or {}) do
            local okS, link, _, charges = try(GetQuestLogSpecialItemInfo, q.logIndex)
            if not okS then
                data.specialError = link
            elseif ns.IsSecret(link) then
                data.secretLinks = data.secretLinks + 1
            elseif link then
                data.special[#data.special + 1] = { quest = q.id, title = q.title, logIndex = q.logIndex,
                                                    link = link, charges = charges }
            end
        end
    end
    local slots = (ctx.bags and ctx.bags.slots) or {}
    data.bagSlotsWithItems = #slots
    for _, s in ipairs(slots) do
        if s.questInfo then
            data.bagQuestItems[#data.bagQuestItems + 1] = { bag = s.bag, slot = s.slot, itemId = s.itemId, link = s.link,
                questID = s.questInfo.questID, isQuestItem = s.questInfo.isQuestItem, isActive = s.questInfo.isActive }
        end
    end
    local okU, use = try(ns.Hints.UsableItem)
    if okU and use then data.useItemHint = { itemId = use.itemId, text = use.text } end
    -- Items to use found from all sources (game flag, QuestieDB required/given items, linked bag items)
    data.toUse = {}
    local okB, bagUse = try(ns.Hints.BagUseItems, ctx.bags)
    for _, q in ipairs(ctx.list or {}) do
        local okI, items = try(ns.Hints.UseItemsFor, q.id, q, okB and bagUse or nil)
        if okI and #items > 0 then
            local names = {}
            for _, itemId in ipairs(items) do names[#names + 1] = itemId .. " " .. str(ns.Hints.ItemName(itemId)) end
            data.toUse[#data.toUse + 1] = string.format("%s %s: %s", tostring(q.id), str(q.title), table.concat(names, ", "))
        end
    end
    -- 0.3.25: the button only shows an item once you've selected (or reached) its target; this
    -- step's quests, and since 0.3.26 a later step's ("step N") when you go there out of order
    data.stepUse = {}
    local okTasks, per, later, at = try(ns.Hints.UseTasks, ns.Ladder and ns.Ladder.plan, ctx.step)
    if not okTasks then per, later, at = {}, {}, {} end
    local function useLine(qid, tasks, where)
        local q = ctx.byId and ctx.byId[qid]
        local okI, items = try(ns.Hints.UseItemsFor, qid, q, okB and bagUse or nil)
        if q and okI and #items > 0 then
            local okT, targets = try(ns.Hints.UseTargets, tasks)
            targets = okT and targets or nil
            local okR, ready, sel = try(ns.Hints.UseReady, targets, tasks, ctx.player and ctx.player.point)
            data.stepUse[#data.stepUse + 1] = string.format("%s %d %s: item %s | on %s | %s", where, qid, str(q.title),
                table.concat(items, ","),
                targets and table.concat(targets.names, ", ") or "nothing known (place)",
                not okR and "?" or ready and ("ready" .. (sel and (", selected " .. str(sel)) or ", standing at it")) or "waiting")
        end
    end
    for qid, tasks in pairs(per) do useLine(qid, tasks, "this step") end
    for qid, tasks in pairs(later) do useLine(qid, tasks, "step " .. tostring(at[qid])) end
    data.selected = {}
    local okSel, selected = try(ns.WorldMarks.Selected)
    for _, s in ipairs(okSel and selected or {}) do
        data.selected[#data.selected + 1] = string.format("%s: %s %s %s", str(s.unit), str(s.kind), tostring(s.id), str(s.name))
    end
    if not hasSpecial and not hasBagInfo then return "fail", "neither quest-item API exists", data end
    if data.specialError then return "fail", "GetQuestLogSpecialItemInfo errored: " .. str(data.specialError), data end
    local summary = string.format("%d quests with an item to use (%d flagged by the game), %d quest items in bags%s",
        #data.toUse, #data.special, #data.bagQuestItems,
        data.useItemHint and (", use button wants item " .. str(data.useItemHint.itemId)) or "")
    if data.secretLinks > 0 then return "warn", summary .. string.format(" (%d item links were secret)", data.secretLinks), data end
    if #data.toUse == 0 and #data.bagQuestItems == 0 then return "skip", summary .. " (nothing to test with)", data end
    return "ok", summary, data
end)

check("usebutton", "5. Use-item button and key binding", function(ctx)
    local b = _G.QuestLadderUseButton
    if not b then return "fail", "QuestLadderUseButton was not created", nil end
    local data = {
        shown = value(b.IsShown, b), parentIsUIParent = value(b.GetParent, b) == UIParent,
        type = value(b.GetAttribute, b, "type"), item = value(b.GetAttribute, b, "item"),
        itemId = b.itemId, protected = value(b.IsProtected, b), inCombat = value(InCombatLockdown),
        binding = value(GetBindingKey, "CLICK QuestLadderUseButton:LeftButton"),
        useKeyDown = cvar("ActionButtonUseKeyDown"),
    }
    if not data.parentIsUIParent then return "fail", "the button is not parented to UIParent", data end
    if data.type ~= "item" then return "fail", "the button's type attribute is " .. str(data.type), data end
    if data.shown and not data.item then return "fail", "the button is shown without an item", data end
    if data.itemId and data.item ~= ("item:" .. data.itemId) and not data.inCombat then
        return "fail", "the item attribute doesn't match the item shown", data
    end
    local summary = (data.shown and ("showing item " .. str(data.itemId)) or "hidden (no item to use right now)")
        .. ", key: " .. str(data.binding or "none")
    if not data.binding then
        return "warn", summary .. "; bind \"Quest Ladder: use the suggested quest item\" under Options > Keybindings > AddOns", data
    end
    return "ok", summary, data
end)

check("auctionator", "6. Auctionator API", function(ctx)
    local data = { loaded = addonLoaded("Auctionator"), global = type(Auctionator) == "table", ahStatus = ns.Gear.ahStatus }
    local api = data.global and type(Auctionator.API) == "table" and Auctionator.API.v1 or nil
    data.apiV1 = type(api) == "table"
    if data.apiV1 then
        data.functions = {}
        for _, n in ipairs({ "GetAuctionPriceByItemID", "GetAuctionPriceByItemLink", "MultiSearchExact", "MultiSearch" }) do
            data.functions[n] = type(api[n]) == "function"
        end
        data.linenClothPrice = value(api.GetAuctionPriceByItemID, "QuestLadder", 2589)
        data.addonSeesIt = ns.Prices.HasAuctionator()
    end
    if not data.global then return "skip", "Auctionator isn't loaded", data end
    if not (data.apiV1 and data.functions.GetAuctionPriceByItemID) then
        return "fail", "Auctionator.API.v1.GetAuctionPriceByItemID is missing", data
    end
    local price = type(data.linenClothPrice) == "number" and (data.linenClothPrice .. " copper") or "not scanned yet"
    return "ok", "API v1 present; Linen Cloth price: " .. price, data
end)

check("questie", "7. Questie IsDoable", function(ctx)
    local data = { loaded = addonLoaded("Questie"), api = type(Questie) == "table" and type(Questie.API) == "table" }
    if data.api then data.isReady = Questie.API.isReady end
    data.loader = type(QuestieLoader) == "table" and type(QuestieLoader.ImportModule) == "function"
    if data.loader then
        local okM, mod = try(QuestieLoader.ImportModule, QuestieLoader, "QuestieDB")
        data.isDoableFn = okM and type(mod) == "table" and type(mod.IsDoable) == "function"
    end
    data.samples = {}
    local point = ctx.player and ctx.player.point
    local near = point and ns.Data.StartersNear(point, 400) or {}
    for i = 1, math.min(3, #near) do
        local id = near[i].questId
        local q = ns.Data.Quest(id)
        local verdict = ns.Data.QuestieDoable(id)
        data.samples[#data.samples + 1] = { id = id, name = q and q.name, questie = (verdict == nil) and "unreachable" or verdict }
    end
    if not data.loaded then return "skip", "Questie isn't loaded (the add-on's own availability rules are used)", data end
    if data.isReady ~= true then return "warn", "Questie is loaded but not ready yet, run diag again in a minute", data end
    if not data.isDoableFn then return "fail", "QuestieDB.IsDoable isn't reachable through QuestieLoader", data end
    for _, s in ipairs(data.samples) do
        if s.questie == "unreachable" then return "fail", "calling IsDoable failed for a nearby quest", data end
    end
    return "ok", string.format("ready, IsDoable reachable (%d nearby quests sampled)", #data.samples), data
end)

check("bags", "8. Bag boxes (Blizzard / Bagnon / Baganator)", function(ctx)
    local HL = ns.Highlight
    local combined = _G.ContainerFrameCombinedBags
    local data = {
        combinedFrame = combined ~= nil, combinedShown = combined and value(combined.IsShown, combined) or false,
        enumerateFn = type(ContainerFrameUtil_EnumerateContainerFrames) == "function",
        combinedBagsCVar = cvar("combinedBags"), bagAddon = HL.UsingBagAddon(),
        bagAddonWindows = #HL.AddonBagRoots(), highlightsOn = ns.db.highlights,
    }
    local blizzOpen = data.combinedShown and true or false
    if not blizzOpen and data.enumerateFn then
        pcall(function()
            for _, f in ContainerFrameUtil_EnumerateContainerFrames() do
                if f:IsShown() then blizzOpen = true break end
            end
        end)
    end
    data.blizzardBagsOpen = blizzOpen
    local bagsOpen = blizzOpen or data.bagAddonWindows > 0
    data.bagsOpen = bagsOpen
    -- Probe with the Hearthstone, else the first item in the bags.
    local probe
    for _, s in ipairs((ctx.bags and ctx.bags.slots) or {}) do
        if s.itemId == ns.Travel.HEARTHSTONE then probe = s break end
        probe = probe or s
    end
    if probe then
        data.probe = { bag = probe.bag, slot = probe.slot, itemId = probe.itemId,
                       itemButton = frameName(HL.BagItemButton(probe.bag, probe.slot)),
                       bagBarButton = frameName(HL.BagBarButton(probe.bag)) }
    end
    data.activeBoxes = {}
    for key, box in pairs(HL.Active() or {}) do
        data.activeBoxes[key] = { target = frameName(box.target), label = box.label and value(box.label.GetText, box.label),
                                  itemId = box.itemId }
    end
    -- what the bag planner suggests for each item, and the item facts behind it
    data.suggestions = {}
    local okS, list = pcall(ns.Bags.Suggestions, ctx.bags, ns.Ladder.snapshot or {}, ns.Ladder.plan)
    for _, e in ipairs(okS and list or {}) do
        if #data.suggestions >= 40 then break end
        local info = ns.Gear.ItemInfo(e.link or e.itemId)
        data.suggestions[#data.suggestions + 1] = string.format("%s %s | class %s/%s q%s%s | %s: %s", tostring(e.itemId),
            tostring(e.name), tostring(info and info.classID), tostring(info and info.subClassID), tostring(info and info.quality),
            info and info.craftingReagent and " reagent" or "", tostring(e.action), tostring(e.reason))
    end
    if not ns.db.highlights then return "skip", "highlights are off (/ladder highlights)", data end
    if not probe then return "skip", "your bags are empty", data end
    local where = string.format("bag %d slot %d", probe.bag, probe.slot)
    if bagsOpen then
        if data.probe.itemButton then return "ok", "bags open: found the button for " .. where .. " (" .. data.probe.itemButton .. ")", data end
        return "fail", "bags are open but the button for " .. where .. " wasn't found", data
    end
    if data.probe.bagBarButton then
        return "ok", "bags closed: found the bag button " .. data.probe.bagBarButton .. " (open your bags and run diag again to test item boxes)", data
    end
    return "fail", "bags are closed and the bag-bar button for bag " .. probe.bag .. " wasn't found", data
end)

check("rewardwindow", "9. Reward box in the quest-complete window", function(ctx)
    local HL = ns.Highlight
    local rf, panel = _G.QuestInfoRewardsFrame, _G.QuestFrameRewardPanel
    local data = { rewardsFrame = rf ~= nil, rewardButtonsField = (rf ~= nil and type(rf.RewardButtons) == "table"),
                   rewardPanelShown = panel and value(panel.IsShown, panel) or false,
                   numChoices = value(GetNumQuestChoices), pick = HL.rewardIndex, buttons = {} }
    if data.rewardButtonsField then
        for i, b in ipairs(rf.RewardButtons) do
            if i > 10 then break end
            data.buttons[#data.buttons + 1] = { id = value(b.GetID, b), type = b.type, shown = value(b.IsShown, b), name = frameName(b) }
        end
    end
    if not data.rewardPanelShown then return "skip", "open a quest-complete window with a reward choice and run diag there", data end
    local n = type(data.numChoices) == "number" and data.numChoices or 0
    if n < 2 then return "skip", "this turn-in has no reward choice", data end
    local found = 0
    for i = 1, n do if HL.RewardButton(i) then found = found + 1 end end
    data.choiceButtonsFound = found
    if found < n then return "fail", string.format("found %d of %d reward choice buttons", found, n), data end
    local box = (HL.Active() or {}).reward
    data.pickBoxOn = box and frameName(box.target) or nil
    if data.pick and not box then return "fail", "a pick was chosen but no 'Pick this' box is showing", data end
    return "ok", string.format("found all %d choice buttons; pick: %s", n, str(data.pick or "none (no clear upgrade)")), data
end)

check("nameplates", "10. Nameplate markers", function(ctx)
    local WM = ns.WorldMarks
    local data = { worldMarks = ns.db.worldMarks, npcTargets = count(WM.npc), objectTargets = count(WM.object),
                   showFriendlyNPCs = cvar("nameplateShowFriendlyNPCs"), showEnemies = cvar("nameplateShowEnemies"), plates = {} }
    local okP, plates = try(C_NamePlate and C_NamePlate.GetNamePlates)
    if not okP then return "fail", "C_NamePlate.GetNamePlates failed", data end
    local total, forbidden, secretGuids, shouldMark, missed = 0, 0, 0, 0, 0
    for _, plate in ipairs(plates or {}) do
        total = total + 1
        if value(plate.IsForbidden, plate) then
            forbidden = forbidden + 1
        else
            local unit = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
            local mark = plate.QuestLadderMark
            local entry = { unit = unit, marked = mark and value(mark.IsShown, mark) or false }
            local okG, guid = try(UnitGUID, unit)
            if okG and ns.IsSecret(guid) then
                secretGuids = secretGuids + 1
                entry.guid = SECRET
            else
                local kind, id = WM.ParseGUID(guid)
                entry.kind, entry.npcId, entry.name = kind, id, value(UnitName, unit)
                entry.label = WM.LabelFor(guid)
                if entry.label then
                    shouldMark = shouldMark + 1
                    if not entry.marked then missed = missed + 1 end
                end
            end
            if #data.plates < 12 then data.plates[#data.plates + 1] = entry end
        end
    end
    data.total, data.forbidden, data.secretGuids, data.questNpcPlates, data.missed = total, forbidden, secretGuids, shouldMark, missed
    data.stepHasMobs = WM.StepHasMobs()
    if not ns.db.worldMarks then return "skip", "world marks are off (/ladder marks)", data end
    if data.stepHasMobs and data.showEnemies == "0" then
        return "warn", "enemy nameplates are off (press V), so this step's quest mobs can't be boxed", data
    end
    if total == 0 then return "skip", "no nameplates visible; stand near the step's mobs and run diag again", data end
    if forbidden == total then return "skip", "all nameplates are off-limits here (instance?)", data end
    if secretGuids > 0 and secretGuids == total - forbidden then
        return "fail", "every nameplate GUID is secret, so NPCs can't be matched", data
    end
    if missed > 0 then return "fail", string.format("%d of %d quest nameplates are missing their box", missed, shouldMark), data end
    if shouldMark == 0 then
        return "skip", string.format("%d nameplates, none for this step (%d NPC and %d object targets)",
            total, data.npcTargets, data.objectTargets), data
    end
    return "ok", string.format("%d of %d quest nameplates boxed (NPCs and objects)", shouldMark, shouldMark), data
end)

Diag.softEvents, Diag.lastSoft = 0, nil
ns.RegisterEvent("PLAYER_SOFT_INTERACT_CHANGED", function(_, _, newGuid)
    Diag.softEvents = Diag.softEvents + 1
    local kind, id = ns.WorldMarks.ParseGUID(newGuid)
    Diag.lastSoft = { kind = kind, id = id, at = value(GetTime) }
end)

check("softtarget", "11. Soft-target cue (facing an object)", function(ctx)
    local WM = ns.WorldMarks
    local data = { eventsSeen = Diag.softEvents, last = Diag.lastSoft, objectTargets = count(WM.object), softHit = WM.softHit,
                   eventValid = value(C_EventUtils and C_EventUtils.IsEventValid, "PLAYER_SOFT_INTERACT_CHANGED"),
                   softTargetInteract = cvar("SoftTargetInteract"), iconGameObject = cvar("SoftTargetIconGameObject"),
                   iconInteract = cvar("SoftTargetIconInteract") }
    local facing = "nothing"
    local okG, guid = try(UnitGUID, "softinteract")
    if okG and ns.IsSecret(guid) then
        data.current = SECRET
        facing = SECRET
    elseif okG and guid then
        local kind, id = WM.ParseGUID(guid)
        data.current = { kind = kind, id = id, name = value(UnitName, "softinteract") }
        facing = str(data.current.name or kind)
    end
    if data.eventValid == false then return "fail", "PLAYER_SOFT_INTERACT_CHANGED doesn't exist on this client", data end
    if Diag.softEvents == 0 then
        return "warn", "the event hasn't fired yet; face an object or NPC (try /ladder interacticons) and run diag again", data
    end
    return "ok", string.format("event fired %d times; facing: %s", Diag.softEvents, facing), data
end)

check("flights", "12. Flight paths and hearthstone", function(ctx)
    local T = ns.Travel
    local p = ctx.player
    local data = { learnedInns = ns.charDB.bindPoints, learnedFlightPaths = ns.charDB.flightPaths,
                   learnedFlightMasters = count(ns.charDB.knownTaxiNpc), hearthCooldownLearned = ns.charDB.hearthCooldown }
    if not (p and p.point) then return "skip", "position unknown", data end
    data.continentMap = T.ContinentMap(p.point.mapId)
    if not data.continentMap then return "fail", "couldn't find the continent map above map " .. str(p.point.mapId), data end
    local okN, nodes = try(C_TaxiMap and C_TaxiMap.GetTaxiNodesForMap, data.continentMap)
    if not okN then
        data.taxiError = nodes
        return "fail", "C_TaxiMap.GetTaxiNodesForMap failed", data
    end
    data.taxiNodes, data.undiscovered, data.sample = 0, 0, {}
    if not ns.IsSecret(nodes) and type(nodes) == "table" then
        for _, n in ipairs(nodes) do
            data.taxiNodes = data.taxiNodes + 1
            if plain(n.isUndiscovered) then data.undiscovered = data.undiscovered + 1 end
            if #data.sample < 4 then data.sample[#data.sample + 1] = n end
        end
    end
    local okNet, net = try(T.BuildNetwork, p)
    if okNet then
        local known = 0
        for _, node in ipairs(net.nodes) do if node.known then known = known + 1 end end
        data.network = { nodes = #net.nodes, known = known, speed = net.speed, mounted = net.mounted,
                         hasHearth = net.hasHearth, hearthReadyIn = net.hearthReadyIn, hearthCooldown = net.hearthCooldown,
                         bindName = net.bindName, innLearned = net.bind ~= nil,
                         zeppelinLinks = #(net.zeppelins or {}), zeppelinWhy = net.zeppelinWhy, towers = {} }
        for _, t in ipairs(net.towers or {}) do
            data.network.towers[#data.network.towers + 1] = string.format("%s | %d masters | cont %s", str(t.name),
                t.masters or 0, str(t.point and t.point.cont))
        end
    else
        data.networkError = net
    end
    -- Fly or walk to the current step, from where you stand (what the guide's travel line shows)
    local L = ns.Ladder
    local okL, live = try(L.LiveTravel, ctx.step, p.point)
    if okL and live then
        local function way(o)
            return o and { from = o.from and o.from.name, to = o.to and o.to.name, active = o.active, air = o.air, total = o.total } or nil
        end
        data.toCurrentStep = { pick = live.mode, walk = live.walk, walkable = live.walkable, step = ctx.step and ctx.step.index,
            fly = way(live.fly), zeppelin = way(live.zeppelin), text = (select(2, try(L.TravelText, ctx.step, live))) }
    end
    -- Zeppelin and boat masters QuestieDB knows (not planned with yet: this shows whether they could be)
    data.transportMasters = {}
    for _, e in ipairs(ns.Data.transportMasters or {}) do
        if #data.transportMasters >= 16 then break end
        local pt = e.point
        data.transportMasters[#data.transportMasters + 1] = string.format("%s <%s> | npc %s | map %s %.3f, %.3f | cont %s",
            str(e.name), str(e.subName), str(e.npcId), str(pt and pt.mapId), pt and pt.x or 0, pt and pt.y or 0, str(pt and pt.cont))
    end
    local inn = (data.network and data.network.innLearned) and "learned" or "not learned yet"
    local summary = string.format("%d flight nodes on map %s, you know %d of %d for your faction; hearth: %s, inn %s",
        data.taxiNodes, str(data.continentMap), data.network and data.network.known or 0,
        data.network and data.network.nodes or 0, str(data.network and data.network.bindName), inn)
    if data.network then
        summary = summary .. string.format("; %d zeppelin routes", data.network.zeppelinLinks or 0)
            .. (data.network.zeppelinWhy and (" (" .. data.network.zeppelinWhy .. ")") or "")
    end
    if data.toCurrentStep then
        local t = data.toCurrentStep
        summary = summary .. string.format("; to this step: %s (walk %ds%s%s)", t.pick, math.floor(t.walk or 0),
            t.fly and string.format(", fly %ds incl. %ds AFK", math.floor(t.fly.total or 0), math.floor(t.fly.air or 0)) or "",
            t.zeppelin and string.format(", zeppelin %ds incl. %ds AFK", math.floor(t.zeppelin.total or 0), math.floor(t.zeppelin.air or 0)) or "")
    end
    if not okNet then return "fail", "building the travel network failed: " .. str(net), data end
    if data.taxiNodes == 0 then
        return "warn", "the game lists no flight nodes here (QuestieDB flight masters are used instead); " .. summary, data
    end
    if count(ns.charDB.flightPaths) == 0 then
        return "warn", summary .. "; open the flight map at any flight master you know so your paths are learned", data
    end
    if not data.network.innLearned then return "warn", summary .. "; bind at an inn or hearth once", data end
    return "ok", summary, data
end)

check("mappins", "Minimap / world map boxes (HereBeDragons)", function(ctx)
    local data = { worldMarks = ns.db.worldMarks, pinsPlaced = ns.WorldMarks.PinCount() }
    local install = "install the HereBeDragons library from CurseForge (Questie's copy is private to Questie)"
    if not LibStub then return "fail", "LibStub is missing; " .. install, data end
    local okP, pins, minor = pcall(LibStub, "HereBeDragons-Pins-2.0", true)
    data.pinsLib, data.pinsMinor = okP and pins ~= nil, okP and minor or nil
    local okH, hbd, hbdMinor = pcall(LibStub, "HereBeDragons-2.0", true)
    data.hbdLib, data.hbdMinor = okH and hbd ~= nil, okH and hbdMinor or nil
    if not data.pinsLib then return "fail", "HereBeDragons-Pins-2.0 not found; " .. install, data end
    if not ns.db.worldMarks then return "skip", "world marks are off (/ladder marks)", data end
    return "ok", string.format("HereBeDragons-Pins %s; %d boxes placed for this step", str(data.pinsMinor), data.pinsPlaced), data
end)

check("hints", "Hint box", function(ctx)
    local H = ns.Hints
    local data = { enabled = ns.db.showHints, reminders = count(H.reminders), shown = {} }
    for i, h in ipairs(H.list or {}) do
        if i > 6 then break end
        data.shown[#data.shown + 1] = { kind = h.kind, text = h.text, itemId = h.itemId, priority = h.priority }
    end
    return "info", string.format("%d hints showing, %d reminders pending", #(H.list or {}), data.reminders), data
end)

check("errors", "Errors caught this session", function(ctx)
    local list = ns.recentErrors or {}
    if #list == 0 then return "ok", "no errors caught by Quest Ladder this session", { errors = list } end
    local total = 0
    for _, e in ipairs(list) do total = total + e.count end
    return "fail", string.format("%d distinct errors (%d total); first: %s", #list, total, list[1].msg), { errors = list }
end)

---------------------------------------------------------------------------
-- Running and storing
---------------------------------------------------------------------------
local VALID = { ok = true, warn = true, fail = true, skip = true, info = true, error = true }

local function buildContext()
    local QS, ctx = ns.QuestState, {}
    local okP, player = try(QS.Player)
    if okP then ctx.player = player end
    local okS, list, byId = try(QS.Snapshot)
    if okS then ctx.list, ctx.byId = list, byId end
    local okB, bags = try(QS.Bags)
    if okB then ctx.bags = bags end
    local okStep, step = try(ns.Ladder.CurrentStep)
    if okStep then ctx.step = step end
    return ctx
end

function Diag.Run(label)
    local run = {
        version = ns.VERSION,
        label = (type(label) == "string" and label ~= "") and label or nil,
        time = value(date, "%Y-%m-%d %H:%M:%S"),
        uptime = value(GetTime),
        counts = { ok = 0, warn = 0, fail = 0, skip = 0, info = 0, error = 0 },
        checks = {},
    }
    local okC, ctx = pcall(buildContext)
    if not okC then
        run.contextError = clean(ctx)
        ctx = {}
    end
    for _, c in ipairs(checks) do
        local ok, status, summary, data = pcall(c.fn, ctx)
        if not ok then status, summary, data = "error", "the check itself crashed: " .. str(status), nil end
        if not VALID[status] then status = "info" end
        local okClean, cleaned = pcall(clean, data)
        run.counts[status] = run.counts[status] + 1
        run.checks[#run.checks + 1] = {
            id = c.id, title = c.title, status = status, summary = clean(summary),
            data = okClean and cleaned or ("<unreadable: " .. str(cleaned) .. ">"),
        }
    end
    if type(QuestLadderDiag) ~= "table" then QuestLadderDiag = {} end
    if type(QuestLadderDiag.runs) ~= "table" then QuestLadderDiag.runs = {} end
    local runs = QuestLadderDiag.runs
    runs[#runs + 1] = run
    while #runs > Diag.MAX_RUNS do table.remove(runs, 1) end
    QuestLadderDiag.lastRun = run.time
    return run
end

local COLOR = { ok = "|cff00ff00", warn = "|cffffcc00", fail = "|cffff4444", error = "|cffff4444",
                skip = "|cff888888", info = "|cff66ccff" }

local function chatLine(text)
    if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage(text) else print(text) end
end

function Diag.Print(run)
    local c = run.counts
    ns.Print("diag%s: %d ok, %d warn, %d fail, %d skipped", run.label and (" [" .. run.label .. "]") or "",
        c.ok, c.warn, c.fail + c.error, c.skip)
    for _, e in ipairs(run.checks) do
        if e.status ~= "ok" and e.status ~= "info" then
            chatLine(string.format("  %s%s|r %s: %s", COLOR[e.status], e.status, e.title, tostring(e.summary)))
        end
    end
    ns.Print("%d run(s) stored. Type /reload to write them to SavedVariables\\QuestLadder.lua", #QuestLadderDiag.runs)
end

-- Right after /reload the add-on first plans your quest log alone, then again once the quest
-- index is built, with new quests in it. A diag taken in between saved the first plan: 0 new
-- quests, and replay data that can't show the real route (0.3.23 diag at Sun Rock Retreat). So
-- the diag waits until no plan is being worked out (up to WAIT_MAX seconds) before it looks.
Diag.WAIT_MAX = 30
Diag.WAIT_STEP = 0.5

--- Why the route isn't settled yet (nil = it is).
function Diag.Busy()
    local L, Data = ns.Ladder, ns.Data
    if Data and Data.lib and not Data.ready then return "the quest index is still being built" end
    if ns.IsJobRunning("QuestLadder.index") then return "the quest index is still being built" end
    if ns.IsJobRunning("QuestLadder.plan") then return "the route is still being planned" end
    if ns.IsPending and ns.IsPending("replan") then return "a replan is about to start" end
    if L and L.plan == nil and Data and Data.lib then return "no route planned yet" end
    return nil
end

local waiting = false
local function runWhenSettled(arg)
    local reason = Diag.Busy()
    if not reason or not (C_Timer and C_Timer.After) then
        Diag.Print(Diag.Run(arg))
        return
    end
    if waiting then ns.Print("diag: already waiting for the route to settle") return end
    waiting = true
    ns.Print("diag: waiting until %s finishes (up to %d s) - don't /reload until the results print", reason, Diag.WAIT_MAX)
    local waited = 0
    local function poll()
        waited = waited + Diag.WAIT_STEP
        local still = Diag.Busy()
        if still and waited < Diag.WAIT_MAX then
            C_Timer.After(Diag.WAIT_STEP, poll)
            return
        end
        waiting = false
        local run = Diag.Run(arg)
        run.waited = waited
        if still then run.gaveUpWaiting = still end
        Diag.Print(run)
    end
    C_Timer.After(Diag.WAIT_STEP, poll)
end

ns.On("RUN_DIAG", function(arg)
    arg = arg or ""
    if arg:lower() == "clear" then
        QuestLadderDiag = { runs = {} }
        ns.Print("diag history cleared")
        return
    end
    if arg:lower() == "now" then Diag.Print(Diag.Run("")) return end -- don't wait for the route
    runWhenSettled(arg)
end)
