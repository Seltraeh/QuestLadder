-- Quest Ladder: controller. Gathers live state + QuestieDB facts into a planning context,
-- runs the planner, tracks progress through the steps, and drives the waypoint.

local _, ns = ...
local Ladder = {}
ns.Ladder = Ladder

local Geo, Data, QS, Planner = ns.Geo, ns.Data, ns.QuestState, ns.Planner

Ladder.plan = nil          -- last plan from Planner.Plan
Ladder.current = 1         -- index of the current step
Ladder.snapshot = nil      -- byId of quests in log at last refresh
Ladder.status = "Starting..."

---------------------------------------------------------------------------
-- Objective location matching (live objective -> QuestieDB objective)
---------------------------------------------------------------------------
local function containsName(text, name)
    if not text or not name or name == "" then return false end
    return text:lower():find(name:lower(), 1, true) ~= nil
end

local GROUP_FOR_TYPE = { monster = 1, object = 2, item = 3 }

--- Returns points, inInstance, itemId, sourceName for one live objective.
local function objectivePoints(o, db, counters)
    if not db then return nil end
    local groupIndex = GROUP_FOR_TYPE[o.type]
    if o.type == "event" or (not groupIndex and db.triggerEnd) then
        local trig = db.triggerEnd
        if type(trig) == "table" and type(trig[2]) == "table" then
            local pts, inst = Geo.PointsFromSpawns(trig[2], 40)
            return pts, inst, nil, trig[1], nil, nil
        end
        return nil
    end
    if not groupIndex then return nil end

    local rows = db.objectives[groupIndex]
    local killCredits = (o.type == "monster") and db.objectives[5] or nil
    local nameOf = (groupIndex == 1 and Data.NpcName) or (groupIndex == 2 and Data.ObjectName) or Data.ItemName

    -- 1) name match against the live text ("Kobold Vermin slain: 3/10")
    local chosen
    if type(rows) == "table" then
        for _, row in ipairs(rows) do
            local name = row[2] or nameOf(row[1])
            if containsName(o.text, name) or containsName(o.text, nameOf(row[1])) then chosen = row break end
        end
    end
    -- kill credit rows: { {npcIds...}, rewardNpcId, text }
    if not chosen and type(killCredits) == "table" then
        for _, kc in ipairs(killCredits) do
            local label = kc[3] or Data.NpcName(kc[2])
            if containsName(o.text, label) then
                local pts, inst = {}, false
                for _, npcId in ipairs(kc[1] or {}) do
                    local p, i2 = Data.NpcPoints(npcId)
                    if i2 then inst = true end
                    for k = 1, #p do pts[#pts + 1] = p[k] end
                end
                return pts, inst, nil, label, nil, { npc = kc[1] or {} }
            end
        end
    end
    -- 2) positional fallback within the objective type
    if not chosen and type(rows) == "table" then
        counters[groupIndex] = (counters[groupIndex] or 0) + 1
        chosen = rows[counters[groupIndex]]
    end
    if not chosen then return nil end

    local id = chosen[1]
    if groupIndex == 1 then
        local pts, inst = Data.NpcPoints(id)
        return pts, inst, nil, Data.NpcName(id), nil, { npc = { id } }
    elseif groupIndex == 2 then
        local pts, inst = Data.ObjectPoints(id)
        return pts, inst, nil, Data.ObjectName(id), nil, { object = { id } }
    else
        local pts, inst, kind, sources = Data.ItemSourcePoints(id)
        local sourceName
        if sources and sources[1] then
            sourceName = (kind == "object") and Data.ObjectName(sources[1]) or Data.NpcName(sources[1])
        end
        local targets = (kind == "object") and { object = sources } or { npc = sources }
        return pts, inst, id, sourceName, kind, targets
    end
end
Ladder.ObjectivePoints = objectivePoints

local function questItemList(db, objectives)
    local items, seen = {}, {}
    local function push(id)
        if id and id ~= 0 and not seen[id] then seen[id] = true; items[#items + 1] = id end
    end
    for _, o in ipairs(objectives) do push(o.itemId) end
    if db then
        push(db.sourceItemId)
        for _, id in ipairs(db.requiredSourceItems or {}) do push(id) end
        if type(db.objectives[3]) == "table" then
            for _, row in ipairs(db.objectives[3]) do push(row[1]) end
        end
    end
    return items
end

local function centroid(objectives)
    local sx, sy, n, cont, any = 0, 0, 0, nil, nil
    for _, o in ipairs(objectives) do
        if o.loc then
            any = any or o.loc
            if not cont then cont = o.loc.cont end
            if o.loc.cont == cont then
                sx, sy, n = sx + o.loc.wx, sy + o.loc.wy, n + 1
            end
        end
    end
    if n == 0 then return nil end
    return { cont = cont, wx = sx / n, wy = sy / n, mapId = any.mapId, x = any.x, y = any.y }
end

--- Level of the easiest mob that counts for an objective (kills, or drops from mobs), from
--- QuestieDB's NPC data; nil when no mob is involved.
local function mobLevelOf(o)
    if o.type ~= "monster" and o.type ~= "item" then return nil end
    local best
    for _, id in ipairs((o.targets and o.targets.npc) or {}) do
        local lv = tonumber(Data.Npc(id, "minLevel"))
        if lv and lv > 0 and (not best or lv < best) then best = lv end
    end
    return best
end
Ladder.MobLevelOf = mobLevelOf

local function isEscort(db)
    for _, line in ipairs((db and db.objectivesText) or {}) do
        local l = line:lower()
        if l:find("escort", 1, true) or l:find("protect", 1, true) then return true end
    end
    return false
end

---------------------------------------------------------------------------
-- Context building
---------------------------------------------------------------------------
local function enrichActive(sq, player, pois)
    local db = Data.Quest(sq.id)
    local q = {
        id = sq.id, title = sq.title, level = sq.level, complete = sq.complete,
        live = sq, db = db, objectives = {},
        deferred = ns.charDB.deferred[sq.id] and true or nil,
        hasItemReward = sq.rewards and sq.rewards.hasItems,
        escort = isEscort(db),
    }
    local counters = {}
    local gameLoc = pois[sq.id] or sq.waypoint
    local anyInstanceOnly = false
    for _, o in ipairs(sq.objectives) do
        local e = { index = o.index, text = o.text, type = o.type, finished = o.finished, have = o.have, need = o.need }
        local pts, inst, itemId, sourceName, sourceKind, targets = objectivePoints(o, db, counters)
        e.itemId, e.sourceName, e.sourceKind, e.targets = itemId, sourceName, sourceKind, targets
        e.mobLevel = mobLevelOf(e)
        if pts and #pts > 0 then
            e.loc = Geo.BestCluster(pts, player.point, 90)
        elseif inst then
            e.dungeon = true
            anyInstanceOnly = anyInstanceOnly or not o.finished
        end
        -- New Forever quests are often missing from QuestieDB: use the game's own POI.
        if not e.loc and not e.dungeon then e.loc = gameLoc end
        q.objectives[#q.objectives + 1] = e
    end
    if db then
        local pts, names = Data.GiverPoints(db.finishedBy)
        local near = centroid(q.objectives) or player.point
        q.turnin = Geo.Nearest(pts, near)
        q.turninName = (q.turnin and q.turnin.giverName) or names[1]
    end
    if not q.turnin and sq.complete then q.turnin = gameLoc end
    q.questItems = questItemList(db, q.objectives)
    -- No tracked objectives but a usable required item ("use the Symbol of Life to resurrect
    -- Deathguard Falgan"): using it IS the objective, so the turn-in line says so.
    if db and #sq.objectives == 0 and ns.Hints then
        for _, itemId in ipairs(db.requiredSourceItems or {}) do
            if ns.Hints.ItemIsUsable(itemId) then q.useFirst = itemId break end
        end
        if not q.useFirst and db.sourceItemId ~= 0 and ns.Hints.ItemIsUsable(db.sourceItemId) then
            q.useFirst = db.sourceItemId
        end
    end
    local tag = sq.tag
    q.dungeon = anyInstanceOnly or (tag and (tag.tagID == 81 or tag.tagID == 62)) or false
    q.group = (sq.suggestedGroup or 0) > 1 or (tag and tag.tagID == 1) or false
    return q
end

local function dbObjectives(db, ref)
    local out = {}
    local objs = db.objectives or {}
    local idx = 0
    local instanceOnly = false
    local function push(kind, text, pts, inst, itemId, sourceName, sourceKind, targets)
        idx = idx + 1
        local e = { index = idx, type = kind, text = text, finished = false, have = 0, need = 1,
                    itemId = itemId, sourceName = sourceName, sourceKind = sourceKind, targets = targets }
        e.mobLevel = mobLevelOf(e)
        if pts and #pts > 0 then e.loc = Geo.BestCluster(pts, ref, 90)
        elseif inst then e.dungeon = true; instanceOnly = true end
        out[#out + 1] = e
    end
    for _, row in ipairs(objs[1] or {}) do
        local name = Data.NpcName(row[1])
        local pts, inst = Data.NpcPoints(row[1])
        push("monster", "Kill " .. (row[2] or name or "?"), pts, inst, nil, nil, nil, { npc = { row[1] } })
    end
    for _, row in ipairs(objs[2] or {}) do
        local name = Data.ObjectName(row[1])
        local pts, inst = Data.ObjectPoints(row[1])
        push("object", "Use " .. (row[2] or name or "?"), pts, inst, nil, nil, nil, { object = { row[1] } })
    end
    for _, row in ipairs(objs[3] or {}) do
        local name = Data.ItemName(row[1])
        local pts, inst, kind, sources = Data.ItemSourcePoints(row[1])
        local sourceName
        if sources and sources[1] then
            sourceName = (kind == "object") and Data.ObjectName(sources[1]) or Data.NpcName(sources[1])
        end
        push("item", "Loot " .. (row[2] or name or "?"), pts, inst, row[1], sourceName, kind,
            (kind == "object") and { object = sources } or { npc = sources })
    end
    for _, kc in ipairs(objs[5] or {}) do
        local pts, inst = {}, false
        for _, npcId in ipairs(kc[1] or {}) do
            local p, i2 = Data.NpcPoints(npcId)
            if i2 then inst = true end
            for k = 1, #p do pts[#pts + 1] = p[k] end
        end
        push("monster", kc[3] or ("Kill " .. (Data.NpcName(kc[2]) or "?")), pts, inst, nil, nil, nil, { npc = kc[1] or {} })
    end
    if type(db.triggerEnd) == "table" and type(db.triggerEnd[2]) == "table" then
        local pts, inst = Geo.PointsFromSpawns(db.triggerEnd[2], 40)
        push("event", db.triggerEnd[1] or "Explore", pts, inst)
    end
    return out, instanceOnly
end

local function enrichCandidate(qid, pickupPoint, player)
    local db = Data.Quest(qid)
    if not db then return nil end
    local objectives, instanceOnly = dbObjectives(db, pickupPoint)
    local c = {
        id = qid, title = db.name, level = db.level, db = db, objectives = objectives,
        pickup = pickupPoint, pickupName = pickupPoint and pickupPoint.giverName,
        sourceItemId = db.sourceItemId,
        hasItemReward = Data.rewardItems[qid] ~= nil,
        dungeon = instanceOnly, escort = isEscort(db),
        candidate = true,
        deferred = ns.charDB.deferred[qid] and true or nil,
    }
    local pts, names = Data.GiverPoints(db.finishedBy)
    c.turnin = Geo.Nearest(pts, centroid(objectives) or pickupPoint)
    c.turninName = (c.turnin and c.turnin.giverName) or names[1]
    c.questItems = questItemList(db, objectives)
    return c
end

local function levelOk(db, player, green, above)
    if (db.reqLevel or 0) > player.level then return false end
    local ql = (db.level and db.level > 0) and db.level or player.level
    return ql >= player.level - green and ql <= player.level + above
end

--- Where to look for quests you haven't picked up: around you, and around the places your
--- quests already send you (unfinished objectives and turn-ins). Otherwise, standing in
--- Undercity, nothing at The Sepulcher can be bundled into the trip you're making anyway.
--- Only on your continent: another continent's quests are planned when you get there, and
--- shouldn't take the limited new-quest slots (a turn-in in the Crossroads filled them with
--- Barrens quests while you were still in Tirisfal).
Ladder.ANCHOR_MERGE_YARDS = 300
Ladder.MAX_ANCHORS = 12

function Ladder.SearchAnchors(player, activeList)
    local anchors = {}
    local cont = player.point and player.point.cont
    local function add(p)
        if not p or #anchors >= Ladder.MAX_ANCHORS then return end
        if cont ~= nil and p.cont ~= cont then return end
        for _, a in ipairs(anchors) do
            local dist = Geo.Distance(a, p)
            if dist and dist <= Ladder.ANCHOR_MERGE_YARDS then return end
        end
        anchors[#anchors + 1] = p
    end
    add(player.point)
    for _, q in ipairs(activeList) do
        if q.complete or not q.objectives then
            add(q.turnin)
        else
            for _, o in ipairs(q.objectives) do
                if not o.finished then add(o.loc) end
            end
            add(q.turnin)
        end
    end
    return anchors
end

--- Quest givers within `radius` of any anchor, nearest-to-an-anchor first, one entry per quest.
function Ladder.StartersAround(anchors, radius)
    local best = {}
    for _, a in ipairs(anchors) do
        for _, e in ipairs(Data.StartersNear(a, radius)) do
            local prev = best[e.questId]
            if not prev or e.dist < prev.dist then best[e.questId] = e end
        end
    end
    local out = {}
    for _, e in pairs(best) do out[#out + 1] = e end
    table.sort(out, function(a, b)
        if a.dist ~= b.dist then return a.dist < b.dist end
        return a.questId < b.questId
    end)
    return out
end

local function buildCandidates(player, activeList, state)
    local opts = ns.db
    local out, planned = {}, {}
    for _, q in ipairs(activeList) do planned[q.id] = true end
    if not opts.includeUnstarted or not Data.ready or not player.point then return out end

    local capacity = (player.logMax or 20) - #activeList
    local maxC = math.max(0, math.min(opts.maxCandidates, capacity))
    local green = QS.GreenRange(player.level)
    local near = Ladder.StartersAround(Ladder.SearchAnchors(player, activeList), opts.pickupRadius)
    local checked = 0
    for _, e in ipairs(near) do
        if #out >= maxC or checked > 250 then break end
        local qid = e.questId
        if not planned[qid] and not ns.charDB.ignored[qid] then
            checked = checked + 1
            local db = Data.Quest(qid)
            if db and levelOk(db, player, green, opts.levelsAbove) and Data.IsAvailableNow(qid, state) then
                local c = enrichCandidate(qid, e.point, player)
                if c and not (opts.skipDungeonQuests and c.dungeon)
                    and not (opts.skipEscortsAndElites and c.escort) then
                    out[#out + 1] = c
                    planned[qid] = true
                end
            end
        end
        ns.MaybeYield(10)
    end

    -- Chain follow-ups: the next quest in a series, picked up right after the turn-in.
    local frontier = {}
    for _, q in ipairs(activeList) do frontier[#frontier + 1] = q end
    for _, c in ipairs(out) do frontier[#frontier + 1] = c end
    for _ = 1, opts.chainDepth do
        local nextFrontier = {}
        for _, parent in ipairs(frontier) do
            for _, fq in ipairs(Data.followUps[parent.id] or {}) do
                if not planned[fq] and not ns.charDB.ignored[fq] then
                    local assume = {}
                    for id in pairs(planned) do assume[id] = true end
                    local chainState = setmetatable({ assumeDone = assume }, { __index = state })
                    local db = Data.Quest(fq)
                    if db and levelOk(db, player, green, opts.levelsAbove + 1) and Data.IsAvailable(fq, chainState) then
                        local from = parent.turnin or parent.pickup or player.point
                        local pts = Data.GiverPoints(db.startedBy)
                        local start = Geo.Nearest(pts, from)
                        local d = start and Geo.Distance(from, start)
                        if start and d and d <= opts.pickupRadius * 1.5 then
                            local c = enrichCandidate(fq, start, player)
                            if c and not (opts.skipDungeonQuests and c.dungeon) then
                                -- depend on every planned prerequisite, not just the parent
                                c.after = {}
                                for _, pre in ipairs(db.preSingle or db.preGroup or {}) do
                                    if planned[pre] and not state.isComplete(pre) then c.after[#c.after + 1] = pre end
                                end
                                if #c.after == 0 then c.after = { parent.id } end
                                c.chainedFrom = parent.id
                                out[#out + 1] = c
                                planned[fq] = true
                                nextFrontier[#nextFrontier + 1] = c
                            end
                        end
                    end
                end
            end
        end
        frontier = nextFrontier
        ns.MaybeYield(5)
    end
    return out
end

---------------------------------------------------------------------------
-- Planning
---------------------------------------------------------------------------
local function availabilityState(player, byId)
    local raceMask, classMask = Data.PlayerMasks(player)
    return {
        level = player.level,
        raceMask = raceMask,
        classMask = classMask,
        skills = player.skills,
        isComplete = QS.IsComplete,
        isActive = function(id) return byId[id] ~= nil end,
    }
end

local function trainerTask(player)
    local due = ns.charDB.trainerDue
    if not due or due > player.level or not Data.ready then return nil end
    local trainer = Data.NearestClassTrainer(player.point, player.className)
    if not trainer then return nil end
    local d = Geo.Distance(player.point, trainer.point)
    if not d or d > 2500 then return nil end
    return {
        id = "V:trainer", kind = "visit", visit = "trainer",
        loc = trainer.point, est = 30, deps = {},
        label = "Train new spells: " .. (trainer.name or "class trainer"),
        npcName = trainer.name,
    }
end

--- Where to sell before the bags overflow at step `overflowAt`: the vendor nearest you and the
--- ones nearest each step before the overflow are compared by how much travel the stop adds
--- there. Within ~10 s of the cheapest, the earliest stop wins (then the one nearest you), so you
--- sell where you are instead of carrying junk across a flight.
Ladder.VENDOR_TIE_SECONDS = 10

function Ladder.PickVendor(steps, start, overflowAt, cost)
    if not start then return nil end
    local candidates, seen = {}, {}
    local function consider(point)
        local v = point and Data.NearestVendor(point)
        if v and not seen[v] then
            seen[v] = true
            candidates[#candidates + 1] = v
        end
    end
    consider(start)
    for i = 1, math.min((overflowAt or 1) - 1, 6) do consider(steps[i] and steps[i].loc) end
    -- every (vendor, insert-before-step-k) option, k = 1 .. overflowAt
    local options, cheapest = {}, nil
    for _, v in ipairs(candidates) do
        local fromYou = Geo.Distance(start, v.point) or math.huge
        for k, detour in ipairs(ns.Travel.InsertionDetours(steps, start, v.point, cost, overflowAt or 1)) do
            options[#options + 1] = { vendor = v, k = k, detour = detour, fromYou = fromYou }
            if not cheapest or detour < cheapest then cheapest = detour end
        end
    end
    local best
    for _, e in ipairs(options) do
        if e.detour <= cheapest + Ladder.VENDOR_TIE_SECONDS then
            if not best or e.k < best.k or (e.k == best.k and e.fromYou < best.fromYou) then best = e end
        end
    end
    return best and best.vendor or nil, best
end

function Ladder.Rebuild(reason)
    if not Data.lib and not Data.Init() then
        Ladder.status = Data.reason or "QuestieDB unavailable"
        ns.Fire("PLAN_UPDATED")
        return
    end
    ns.Debug("replan: %s", tostring(reason))
    ns.Async("QuestLadder.plan", function()
        local player = QS.Player()
        if not player.point then
            Ladder.status = "Position unavailable (inside an instance?)"
            return
        end
        local snapshotList, byId = QS.Snapshot()
        Ladder.snapshot = byId
        local pois = QS.MapPOIs(player.point.mapId)
        local active = {}
        for _, sq in ipairs(snapshotList) do
            -- A failed quest (an escort you walked away from, a timer that ran out) can't be
            -- finished: route nothing for it. The hint box says to abandon it; once you do, it
            -- becomes an ordinary pickup again on the next replan.
            if not sq.failed then
                local q = enrichActive(sq, player, pois)
                local skip = q.dungeon and ns.db.skipDungeonQuests and not q.complete
                if not skip then active[#active + 1] = q end
            end
            ns.MaybeYield(4)
        end
        local state = availabilityState(player, byId)
        local candidates = buildCandidates(player, active, state)
        local bags = QS.Bags()

        local extra = {}
        local trainer = trainerTask(player)
        if trainer then extra[#extra + 1] = trainer end

        local prevSticky
        if Ladder.plan and Ladder.plan.steps[Ladder.current] then
            local s = Ladder.plan.steps[Ladder.current]
            prevSticky = s.tasks[1] and s.tasks[1].id
        end

        local net = ns.Travel.BuildNetwork(player)
        local walkOnly = function(a, b) return ns.Travel.Walk(net, a, b) end
        local cost = ns.db.useFlights and ns.Travel.NewCost(net) or walkOnly

        local ctx = {
            travel = cost,
            start = player.point,
            level = player.level,       -- with xpFrac: the mob-level rule (Planner.LevelGate)
            xpFrac = player.xpFrac,
            active = active,
            candidates = candidates,
            logCount = #snapshotList,
            logMax = player.logMax,
            bags = bags,
            reserve = ns.db.reserveSlots,
            lookahead = ns.db.lookahead,
            stickyId = prevSticky,
            extraTasks = extra,
        }
        local plan = Planner.Plan(ctx)

        -- Bags will overflow: add a vendor stop before the overflowing step when selling helps.
        if plan.bags.overflowAt and ns.Bags and Data.ready then
            local sellable = ns.Bags.SellableSlots(bags)
            local vendor = Ladder.PickVendor(plan.steps, player.point, plan.bags.overflowAt, cost)
            if vendor and sellable > 0 then
                local vtask = {
                    id = "V:vendor", kind = "visit", visit = "vendor", loc = vendor.point,
                    est = 30, deps = {}, label = "Sell junk to " .. (vendor.name or "a vendor"),
                    npcName = vendor.name, frees = sellable,
                }
                local overflowStep = plan.steps[plan.bags.overflowAt]
                local extraDeps = {}
                for _, t in ipairs(overflowStep.tasks) do extraDeps[t.id] = { vtask.id } end
                ctx.extraTasks = { vtask, trainer }
                ctx.extraDeps = extraDeps
                local replanned = Planner.Plan(ctx)
                -- simulate the freed space at the vendor stop
                if replanned.dropped == plan.dropped then
                    replanned.vendorStop = vtask
                    plan = replanned
                end
            end
        end

        Ladder.AddTravelStops(plan, player, net, cost, bags, ctx.logCount, ctx.logMax)

        plan.player = player
        plan.logCount, plan.logMax = ctx.logCount, ctx.logMax
        plan.candidates = candidates
        plan.active = active
        plan.builtAt = GetTime and GetTime() or 0
        Ladder.plan = plan
        Ladder.current = 1
        Ladder.status = nil
        Ladder.RefreshProgress(true)
    end, function()
        ns.Fire("PLAN_UPDATED", Ladder.plan)
    end)
end

---------------------------------------------------------------------------
-- Travel stops: flight paths on the way, a better inn, where to hearth
---------------------------------------------------------------------------
local function stopStep(task)
    return { tasks = { task }, loc = task.loc, est = task.est or 20, isStop = true }
end

local function rebuildIndex(plan)
    plan.order = {}
    for i, s in ipairs(plan.steps) do
        s.index = i
        for _, t in ipairs(s.tasks) do
            plan.order[#plan.order + 1] = t
            plan.byId[t.id] = t
        end
    end
end

function Ladder.AddTravelStops(plan, player, net, cost, bags, logCount, logMax)
    local Travel = ns.Travel
    local start = player.point
    if not start then return end
    plan.net = net
    local order = plan.order

    -- 1) Hearth-aware route with your current inn (only kept when it really pays off).
    local hearth, why
    if ns.db.useHearth then
        hearth, why = Travel.HearthAware(order, start, net, cost, { logCount = logCount, logMax = logMax })
    end
    plan.hearthWhy = why

    -- 2) Would binding at another inn on the way unlock a much better hearth?
    if ns.db.suggestBind and ns.db.useHearth and Data.ready and net.hasHearth then
        local pts = { start }
        for i = 1, math.min(#order, 40) do if order[i].loc then pts[#pts + 1] = order[i].loc end end
        local current = hearth and hearth.saving or 0
        local best
        for _, inn in ipairs(Data.InnkeepersNear(pts, 500, 4)) do
            local isCurrent = net.bind ~= nil and (Geo.Distance(net.bind, inn.point) or math.huge) <= 60
            if not isCurrent then
                local pseudo = {}
                for i, t in ipairs(order) do pseudo[i] = { loc = t.loc } end
                local detours = Travel.InsertionDetours(pseudo, start, inn.point, cost, math.floor(#order * 0.6) + 1)
                local k, detour
                for i, d in ipairs(detours) do if not detour or d < detour then k, detour = i, d end end
                if k then
                    local bindTask = { id = "V:bind", kind = "visit", visit = "bind", loc = inn.point, est = 20, deps = {},
                                       npcName = inn.name, npcId = inn.npcId }
                    local trial = Travel.WithInserted(order, k, bindTask)
                    local innNet = setmetatable({ bind = inn.point, bindName = inn.name }, { __index = net })
                    local r = Travel.HearthAware(trial, start, innNet, cost,
                        { logCount = logCount, logMax = logMax, minK = k, quick = true })
                    if r then
                        local gain = r.saving - detour - current
                        if gain >= Travel.BIND_MIN_GAIN and (not best or gain > best.gain) then
                            best = { inn = inn, k = k, gain = gain, task = bindTask, trial = trial, innNet = innNet }
                        end
                    end
                end
            end
        end
        if best then
            local r = Travel.HearthAware(best.trial, start, best.innNet, cost,
                { logCount = logCount, logMax = logMax, minK = best.k })
            if r then
                best.task.saving = best.gain
                best.task.label = string.format("Set your hearthstone at %s (saves ~%d min later)",
                    best.inn.name or "the innkeeper", math.floor(best.gain / 60 + 0.5))
                hearth = r
                plan.bindSuggestion = best
            end
        end
    end
    if hearth then plan.order = hearth.order end
    plan.hearth = hearth
    plan.steps = ns.Planner.GroupSteps(plan.order)

    -- 3) Flight paths within a short detour: talking to the flight master is enough.
    if ns.db.discoverFlights then
        local added, taken = 0, {}
        for _ = 1, 2 do
            local list = Travel.SuggestDiscoveries(plan.steps, start, net, cost, Travel.DISCOVER_MAX_DETOUR, taken)
            local pick = list[1]
            if not pick then break end
            taken[pick.node] = true
            local task = { id = "V:fp:" .. (pick.node.name or added), kind = "visit", visit = "flight",
                           loc = pick.node.point, est = 15, deps = {}, nodeName = pick.node.name,
                           npcId = pick.node.npcId,
                           label = "Discover flight path: " .. (pick.node.name or "flight master") }
            plan.steps = Travel.WithInserted(plan.steps, pick.index, stopStep(task))
            added = added + 1
        end
    end

    -- 4) Which legs to fly, and the hearth steps' notes.
    Travel.AnnotateSteps(plan.steps, start, ns.db.useFlights and net or { nodes = {}, speed = net.speed })

    rebuildIndex(plan)
    plan.bags = ns.Planner.SimulateBags(plan.steps, bags, ns.db.reserveSlots, ns.db.lookahead)
    ns.Planner.travelFn = cost
    plan.cost = ns.Planner.RouteCost(plan.order, start)
end

--- The way to a step from where you stand now. Re-checked every second, so both ways work:
--- walk off instead of taking the flight and the guide switches to walking once that's
--- quicker from there; take a flight it didn't suggest and it carries on from where you land.
--- Returns { mode = "fly"|"walk", walk = seconds, fly = option or nil } (Travel.Options), the
--- planned hearth step as is, or nil (no location, or you're on a flight right now).
function Ladder.LiveTravel(step, here)
    if not step then return nil end
    if step.travel and step.travel.mode == "hearth" then return step.travel end
    local plan = Ladder.plan
    if not (here and step.loc and plan and plan.net) then return nil end
    if UnitOnTaxi then
        local ok, onTaxi = pcall(UnitOnTaxi, "player")
        if ok and not ns.IsSecret(onTaxi) and onTaxi then return nil end
    end
    local net = ns.db.useFlights and plan.net or { nodes = {}, speed = plan.net.speed }
    local o = ns.Travel.Options(net, here, step.loc)
    local out = { mode = o.pick, walk = o.walk, walkable = o.walkable, fly = o.fly, zeppelin = o.zeppelin }
    if o.zeppelin then
        local d = Geo.Distance(here, o.zeppelin.from.point)
        out.atTower = d ~= nil and d <= ns.Travel.ZEPPELIN_TOWER_YARDS
    end
    return out
end

local function clock(seconds)
    seconds = math.max(0, math.floor((seconds or 0) + 0.5))
    return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end
Ladder.Clock = clock

--- A flight worth mentioning next to "walk": not more than twice the walk, or 5 minutes more.
Ladder.ALT_FLIGHT_MAX_RATIO, Ladder.ALT_FLIGHT_MAX_EXTRA = 2, 300

--- "Undercity, Tirisfal" -> "Undercity"
local function placeName(node, fallback)
    local name = node and node.name
    if type(name) ~= "string" then return fallback end
    return name:match("^([^,]+)") or name
end

local function worthMentioning(o, than)
    return o and o.total <= than * Ladder.ALT_FLIGHT_MAX_RATIO and o.total <= than + Ladder.ALT_FLIGHT_MAX_EXTRA
end

local function zeppelinWay(z)
    return string.format("zeppelin %s -> %s: about %s, up to %s if you just miss it", placeName(z.from, "tower"),
        placeName(z.to, "?"), clock(z.total), clock(z.worst or z.total))
end

function Ladder.TravelText(step, live)
    local tr = live or (step and step.travel)
    if not tr then return nil end
    if tr.mode == "fly" and tr.fly then
        local f = tr.fly
        local quicker = tr.walk - f.total
        local others = { quicker >= 0 and string.format("walking takes %s", clock(tr.walk))
            or string.format("walking is %s quicker, all hands-on", clock(-quicker)) }
        if worthMentioning(tr.zeppelin, f.total) then others[#others + 1] = zeppelinWay(tr.zeppelin) end
        return string.format("|cff66ccffFly:|r %s -> %s - %s total, %s of it AFK in the air |cff888888(%s)|r",
            placeName(f.from, "flight master"), placeName(f.to, "?"), clock(f.total), clock(f.air), table.concat(others, "; "))
    elseif tr.mode == "zeppelin" and tr.zeppelin then
        local z = tr.zeppelin
        local others = {}
        if tr.walkable then others[#others + 1] = string.format("walking takes %s", clock(tr.walk)) end
        if worthMentioning(tr.fly, z.total) then
            others[#others + 1] = string.format("flying %s -> %s: %s", placeName(tr.fly.from, "flight master"),
                placeName(tr.fly.to, "?"), clock(tr.fly.total))
        end
        local where = tr.atTower and " Each side of the tower flies somewhere else: the zeppelin master on each platform says where." or ""
        return string.format("|cff66ccffZeppelin:|r %s -> %s - about %s, up to %s if you just miss it (no departure timer in the game; %s aboard is AFK)%s%s",
            placeName(z.from, "tower"), placeName(z.to, "?"), clock(z.total), clock(z.worst or z.total),
            clock(ns.Travel.ZEPPELIN_RIDE), #others > 0 and (" |cff888888(" .. table.concat(others, "; ") .. ")|r") or "", where)
    elseif tr.mode == "walk" and (tr.fly or tr.zeppelin) then
        local others = {}
        if worthMentioning(tr.fly, tr.walk) then
            local f = tr.fly
            others[#others + 1] = string.format("flying %s -> %s: %s, %s AFK", placeName(f.from, "flight master"),
                placeName(f.to, "?"), clock(f.total), clock(f.air))
        end
        if worthMentioning(tr.zeppelin, tr.walk) then others[#others + 1] = zeppelinWay(tr.zeppelin) end
        if #others == 0 then return nil end
        return string.format("|cff66ccffWalk:|r %s |cff888888(%s)|r", clock(tr.walk), table.concat(others, "; "))
    elseif tr.mode == "zeppelin" then
        return string.format("|cff66ccffZeppelin:|r %s -> %s", placeName(tr.from, "tower"), placeName(tr.to, "?"))
    elseif tr.mode == "fly" then
        return string.format("|cff66ccffFly:|r %s -> %s (AFK flight)", tr.from and tr.from.name or "flight master",
            tr.to and tr.to.name or "?")
    elseif tr.mode == "hearth" then
        local why = (tr.reason == "area done") and "nothing left out here"
            or (tr.reason == "fast return") and "your turn-ins are right by the inn"
            or "plenty of steps before you need it again"
        return string.format("|cff66ccffHearth|r to %s - saves ~%d min, %s", tr.bindName or "your inn",
            math.max(1, math.floor((tr.saving or 0) / 60 + 0.5)), why)
    end
    return nil
end

---------------------------------------------------------------------------
-- Progress through steps (cheap; no replanning)
---------------------------------------------------------------------------
local function taskDone(t, byId)
    if t.kind == "pickup" then
        return byId[t.questId] ~= nil or QS.IsComplete(t.questId)
    elseif t.kind == "turnin" then
        return QS.IsComplete(t.questId) or (byId[t.questId] == nil and not t.quest.candidate and true) or false
    elseif t.kind == "objective" then
        local live = byId[t.questId]
        if not live then return t.quest.candidate ~= true end -- abandoned or turned in
        if live.complete then return true end
        local o = live.objectives[t.obj.index]
        if o then
            t.obj.have, t.obj.need, t.obj.text = o.have, o.need, o.text
            return o.finished
        end
        return false
    elseif t.kind == "visit" then
        if t.done then return true end
        if t.visit == "flight" then
            local known = ns.charDB.flightPaths and t.nodeName and ns.charDB.flightPaths[t.nodeName]
            local knownNpc = ns.charDB.knownTaxiNpc and t.npcId and ns.charDB.knownTaxiNpc[t.npcId]
            return (known or knownNpc) and true or false
        end
        return false
    end
    return false
end
Ladder.TaskDone = taskDone

function Ladder.RefreshProgress(silent)
    local plan = Ladder.plan
    if not plan then return end
    local _, byId = QS.Snapshot()
    Ladder.snapshot = byId
    local newlyDone = false
    for _, step in ipairs(plan.steps) do
        local allDone = true
        for _, t in ipairs(step.tasks) do
            local wasDone = t.isDone
            t.isDone = taskDone(t, byId)
            if t.isDone and not wasDone then newlyDone = true end
            if not t.isDone then allDone = false end
        end
        step.isDone = allDone
    end
    -- Travel stops (hearth, flight path, inn, vendor, trainer) are optional: once you've moved
    -- on to a later step, the ones you skipped stop blocking the guide.
    local lastProgress = 0
    for i, step in ipairs(plan.steps) do
        for _, t in ipairs(step.tasks) do
            if t.isDone and t.kind ~= "visit" then lastProgress = i end
        end
    end
    for i = 1, lastProgress - 1 do
        local step = plan.steps[i]
        if not step.isDone then
            local onlyVisits = true
            for _, t in ipairs(step.tasks) do if t.kind ~= "visit" then onlyVisits = false end end
            if onlyVisits then
                for _, t in ipairs(step.tasks) do t.isDone = true; t.skipped = true end
                step.isDone = true
            end
        end
    end
    local cur = 1
    while plan.steps[cur] and plan.steps[cur].isDone do cur = cur + 1 end
    local changed = cur ~= Ladder.current
    Ladder.current = cur
    if changed then Ladder.UpdateWaypoint() end
    if not silent then ns.Fire("PROGRESS_UPDATED") end
    return newlyDone
end

function Ladder.CurrentStep()
    return Ladder.plan and Ladder.plan.steps[Ladder.current]
end

---------------------------------------------------------------------------
-- Waypoint (Blizzard user waypoint, or TomTom when installed)
---------------------------------------------------------------------------
local lastWaypointKey, tomtomUid

--- Where the arrow should point now: the flight master first when flying is the way from
--- where you stand (Ladder.LiveTravel), else the step itself.
function Ladder.WaypointTarget(step, here)
    if not step then return nil end
    if step.travel and step.travel.mode == "hearth" then return nil end -- no walking: keep the arrow where it is
    local live = Ladder.LiveTravel(step, here)
    -- zeppelin: to the tower first (by flight master when that's the way to the tower)
    local z = live and live.mode == "zeppelin" and live.zeppelin
    if z and here then
        local atTower = Geo.Distance(here, z.from.point)
        if atTower and atTower > ns.Travel.ZEPPELIN_TOWER_YARDS then
            local _, mode, f1 = ns.Travel.AirLeg(Ladder.plan.net, here, z.from.point)
            if mode == "fly" and f1 then return f1.point, "Flight master: " .. (f1.name or "") end
            return z.from.point, "Zeppelin: " .. (z.from.name or "")
        end
        return step.loc
    end
    local f = live and live.mode == "fly" and live.fly
    if f and here and step.loc then
        local toStep = Geo.Distance(here, step.loc)
        local landed = Geo.Distance(f.to.point, step.loc)
        if toStep and landed and toStep > landed + 150 then
            return f.from.point, "Flight master: " .. (f.from.name or "")
        end
    end
    return step.loc
end

function Ladder.UpdateWaypoint()
    if not ns.db.waypoints then return end
    local step = Ladder.CurrentStep()
    local loc = Ladder.WaypointTarget(step, Geo.PlayerPoint())
    if not loc or not loc.mapId then return end
    local key = loc.mapId .. ":" .. math.floor(loc.x * 1000) .. ":" .. math.floor(loc.y * 1000)
    if key == lastWaypointKey then return end
    lastWaypointKey = key
    local title = Ladder.StepTitle(step)
    if TomTom and TomTom.AddWaypoint then
        if tomtomUid and TomTom.RemoveWaypoint then pcall(TomTom.RemoveWaypoint, TomTom, tomtomUid) end
        local ok, uid = pcall(TomTom.AddWaypoint, TomTom, loc.mapId, loc.x, loc.y,
            { title = "Quest Ladder: " .. title, persistent = false, minimap = true, world = true, crazy = true })
        if ok then tomtomUid = uid end
        return
    end
    if C_Map and C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates then
        if C_Map.CanSetUserWaypointOnMap and not C_Map.CanSetUserWaypointOnMap(loc.mapId) then return end
        pcall(C_Map.SetUserWaypoint, UiMapPoint.CreateFromCoordinates(loc.mapId, loc.x, loc.y))
        if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
            pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, true)
        end
    end
end

---------------------------------------------------------------------------
-- Text for the UI
---------------------------------------------------------------------------
local VERB = { monster = "Kill", item = "Loot", object = "Use", event = "Go to", reputation = "Reputation" }

function Ladder.TaskText(t)
    local q = t.quest
    local title = q and (q.title or ("Quest " .. t.questId)) or ""
    if t.kind == "pickup" then
        return string.format("Accept |cffffd100%s|r%s", title, q.pickupName and (" from " .. q.pickupName) or "")
    elseif t.kind == "turnin" then
        local pick = t.rewardPick and (" - pick |cff00ff00" .. t.rewardPick .. "|r") or ""
        if q.useFirst and ns.Hints and ns.Hints.ItemCount(q.useFirst) > 0 then
            return string.format("Use |cff66ccff[%s]|r%s, then turn in |cffffd100%s|r%s", ns.Hints.ItemName(q.useFirst),
                q.turninName and (" on " .. q.turninName) or "", title, pick)
        end
        return string.format("Turn in |cffffd100%s|r%s%s", title, q.turninName and (" to " .. q.turninName) or "", pick)
    elseif t.kind == "objective" then
        local o = t.obj
        local text = o.text
        if not text or text == "" then text = (VERB[o.type] or "Do") .. " objective" end
        if o.need and o.need > 1 and not text:find("%d+/%d+") then
            text = string.format("%s %d/%d", text, o.have or 0, o.need)
        end
        local where = ""
        if o.type == "item" and o.sourceName then
            where = (o.sourceKind == "object") and (" (from " .. o.sourceName .. ")") or (" (drops from " .. o.sourceName .. ")")
        end
        if o.mobLevel then
            local lvl = Ladder.plan and Ladder.plan.player and Ladder.plan.player.level
            local color = (lvl and o.mobLevel >= lvl + 2) and "|cffff8800" or "|cff888888"
            where = where .. string.format(" %s(lvl %d)|r", color, o.mobLevel)
        end
        if not t.loc then where = where .. " |cffff8800(location unknown)|r" end
        return text .. where .. "  |cff888888" .. title .. "|r"
    elseif t.kind == "visit" then
        return t.label
    end
    return "?"
end

function Ladder.StepTitle(step)
    if not step then return "" end
    local kinds, names = {}, {}
    for _, t in ipairs(step.tasks) do
        kinds[t.kind] = true
        local n = (t.kind == "pickup" and t.quest.pickupName) or (t.kind == "turnin" and t.quest.turninName) or t.npcName
        if n then names[n] = true end
    end
    local list = {}
    for n in pairs(names) do list[#list + 1] = n end
    table.sort(list)
    local npc
    if #list == 1 then npc = list[1]
    elseif #list == 2 then npc = list[1] .. " and " .. list[2]
    elseif #list > 2 then npc = list[1] .. ", " .. list[2] .. " and others" end
    if kinds.objective and not kinds.pickup and not kinds.turnin then
        local zone
        if step.loc and C_Map and C_Map.GetMapInfo then
            local info = C_Map.GetMapInfo(step.loc.mapId)
            zone = info and info.name
        end
        return "Clear area" .. (zone and (" in " .. zone) or "")
    end
    if npc then return "Talk to " .. npc end
    if kinds.visit then return step.tasks[1].label end
    return "Next step"
end

---------------------------------------------------------------------------
-- Skip / ignore
---------------------------------------------------------------------------
ns.On("SKIP_STEP", function()
    local step = Ladder.CurrentStep()
    if not step then return end
    for _, t in ipairs(step.tasks) do
        if t.kind == "pickup" then
            ns.charDB.ignored[t.questId] = true
        elseif t.kind == "visit" then
            if t.visit == "trainer" then ns.charDB.trainerDue = nil end
            t.done = true
        elseif t.questId then
            ns.charDB.deferred[t.questId] = true
        end
    end
    ns.Print("skipped: %s", Ladder.StepTitle(step))
    Ladder.Rebuild("skip")
end)

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local function requestReplan(reason, delay)
    ns.Debounce("replan", delay or 1.0, function() Ladder.Rebuild(reason) end)
end
ns.On("REQUEST_REPLAN", function(reason) requestReplan(reason, 0.1) end)

local function onLogUpdate()
    ns.Debounce("progress", 0.3, function()
        if not Ladder.plan then return end
        local newlyDone = Ladder.RefreshProgress()
        if newlyDone then requestReplan("progress", 1.5) end
    end)
end

ns.On("LOGIN", function()
    if not Data.Init() then
        Ladder.status = Data.reason
        ns.Print("|cffff4444%s|r", Data.reason or "QuestieDB unavailable")
        ns.Fire("PLAN_UPDATED")
        return
    end
    Ladder.status = "Indexing quests..."
    ns.Fire("PLAN_UPDATED")
    -- Let the world finish loading first.
    local function start()
        -- Plan the quest log first (fast); unstarted quests join once the index is built.
        Ladder.Rebuild("login")
        Data.BuildIndexes(QS.Player(), function() Ladder.Rebuild("indexes ready") end)
    end
    if C_Timer and C_Timer.After then C_Timer.After(3, start) else start() end
end)

ns.RegisterEvent("QUEST_LOG_UPDATE", onLogUpdate)
ns.RegisterEvent("QUEST_ACCEPTED", function() requestReplan("accepted", 1.0) end)
ns.RegisterEvent("QUEST_TURNED_IN", function() requestReplan("turned in", 1.0) end)
ns.RegisterEvent("QUEST_REMOVED", function() requestReplan("removed", 1.0) end)
ns.RegisterEvent("ZONE_CHANGED_NEW_AREA", function() requestReplan("zone", 2.0) end)
ns.RegisterEvent("PLAYER_LEVEL_UP", function(_, level)
    -- Classic-style trainers teach new ranks on even levels.
    if level and level % 2 == 0 then ns.charDB.trainerDue = level end
    requestReplan("level", 2.0)
end)
ns.RegisterEvent("TRAINER_SHOW", function()
    ns.charDB.trainerDue = nil
    if Ladder.plan and Ladder.plan.byId["V:trainer"] then Ladder.plan.byId["V:trainer"].done = true end
    onLogUpdate()
end)
ns.RegisterEvent("MERCHANT_SHOW", function()
    if Ladder.plan and Ladder.plan.byId["V:vendor"] then Ladder.plan.byId["V:vendor"].done = true end
    onLogUpdate()
end)
ns.On("TAXI_LEARNED", onLogUpdate)
ns.On("REQUEST_REPLAN", function(reason)
    if reason == "bind changed" and Ladder.plan and Ladder.plan.byId["V:bind"] then
        Ladder.plan.byId["V:bind"].done = true
    end
end)
ns.RegisterEvent("BAG_UPDATE_DELAYED", function() ns.Debounce("bags", 1.0, function() ns.Fire("BAGS_CHANGED") end) end)
