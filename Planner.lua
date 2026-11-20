-- Quest Ladder: route planner (pure logic, no game API calls).
--
-- Every quest becomes tasks: pickup -> objective(s) -> turn-in, with precedence edges, plus
-- chain edges (turn-in of A -> pickup of its follow-up B). The planner orders the tasks to
-- minimise travel time (a travelling-salesman route with precedence constraints and a quest-log
-- capacity limit), then groups consecutive tasks that happen in the same place into "steps",
-- and simulates bag usage along the route.

local _, ns = ...
local Planner = {}
ns.Planner = Planner

local Geo = ns.Geo

Planner.UNKNOWN_LOC_PENALTY = 600 -- seconds: tasks we cannot place go last
Planner.GROUP_RADIUS = 90         -- yards: tasks this close form one step
Planner.MAX_TASKS_PER_STEP = 7
Planner.IMPROVE_PASSES = 4
Planner.IMPROVE_MAX_TASKS = 400


---------------------------------------------------------------------------
-- Work estimates: ETAs, and how long a finished quest would wait for its turn-in (see pullForward)
---------------------------------------------------------------------------
function Planner.EstimateObjective(o)
    local left = math.max((o.need or 1) - (o.have or 0), 1)
    if o.type == "monster" then return 20 * left end
    if o.type == "item" then return 28 * left end
    if o.type == "object" then return 12 * left end
    if o.type == "event" then return 15 end
    return 30
end

---------------------------------------------------------------------------
-- Mob levels: kill steps whose mobs are well above you wait until you've levelled
---------------------------------------------------------------------------
-- Mobs 2+ levels above you are slow to kill and dangerous. The other quests in the plan level
-- you up, so an objective like that waits until about enough of them are turned in for its
-- mobs to be at most LEVEL_SLACK above you. Turn-ins per level is a rough leveling estimate
-- (quest XP plus the kills on the way; it grows slowly with level). The wait is never more
-- than the plan can give before it (see BuildTasks), so nothing becomes impossible.
Planner.LEVEL_SLACK = 1
Planner.TALK_QUEST_XP = 0.4 -- a turn-in with no objectives counts this much of a full one
function Planner.TurninsPerLevel(level) return 4 + (level or 1) / 6 end

--- Turn-ins to do before an objective with mobs of mobLevel (0 = none).
function Planner.LevelGate(mobLevel, level, xpFrac)
    if not mobLevel or not level then return 0 end
    local behind = mobLevel - Planner.LEVEL_SLACK - (level + (xpFrac or 0))
    if behind <= 0 then return 0 end
    return math.ceil(behind * Planner.TurninsPerLevel(level))
end

local function gateOk(t, turnins, opts)
    return not t.minTurnins or t.minTurnins <= turnins or (opts and opts.ignoreGates) or false
end

---------------------------------------------------------------------------
-- Task graph
---------------------------------------------------------------------------
--- ctx.active:     quests in the log (see Ladder.lua for the shape)
--- ctx.candidates: quests not yet accepted
function Planner.BuildTasks(ctx)
    local tasks, byId = {}, {}
    local function add(t)
        t.deps = t.deps or {}
        tasks[#tasks + 1] = t
        byId[t.id] = t
        return t
    end

    local function addQuestBody(q, pickupId)
        local objIds = {}
        if not q.complete then
            for _, o in ipairs(q.objectives or {}) do
                if not o.finished then
                    local t = add({
                        id = "O" .. q.id .. ":" .. o.index,
                        kind = "objective",
                        questId = q.id,
                        quest = q,
                        obj = o,
                        loc = o.loc,
                        est = Planner.EstimateObjective(o),
                        collects = (o.type == "item" and o.itemId) or nil,
                        deps = pickupId and { pickupId } or {},
                        deferred = q.deferred,
                        mobLevel = o.mobLevel,
                    })
                    objIds[#objIds + 1] = t.id
                end
            end
        end
        local deps = objIds
        if #deps == 0 and pickupId then deps = { pickupId } end
        add({
            id = "T" .. q.id,
            kind = "turnin",
            questId = q.id,
            quest = q,
            loc = q.turnin,
            est = 8,
            deps = deps,
            frees = q.questItems,
            reward = q.hasItemReward and 1 or 0,
            deferred = q.deferred,
            -- "go talk to X" and delivery quests give much less XP than ones with objectives
            xpWeight = (#(q.objectives or {}) > 0) and 1 or Planner.TALK_QUEST_XP,
        })
    end

    for _, q in ipairs(ctx.active or {}) do
        addQuestBody(q, nil)
    end
    for _, c in ipairs(ctx.candidates or {}) do
        local deps = {}
        for _, prev in ipairs(c.after or {}) do deps[#deps + 1] = "T" .. prev end
        local p = add({
            id = "P" .. c.id,
            kind = "pickup",
            questId = c.id,
            quest = c,
            loc = c.pickup,
            est = 8,
            deps = deps,
            gives = (c.sourceItemId and c.sourceItemId ~= 0) and c.sourceItemId or nil,
            deferred = c.deferred,
        })
        addQuestBody(c, p.id)
    end

    -- Extra tasks (trainer or vendor visits) and extra precedence edges.
    for _, x in ipairs(ctx.extraTasks or {}) do add(x) end
    for taskId, extra in pairs(ctx.extraDeps or {}) do
        local t = byId[taskId]
        if t then
            for _, d in ipairs(extra) do t.deps[#t.deps + 1] = d end
        end
    end

    -- Drop dependencies on tasks that are not part of the plan, and quests whose pickup
    -- depends on something unplannable.
    local changed = true
    while changed do
        changed = false
        for i = #tasks, 1, -1 do
            local t = tasks[i]
            for _, d in ipairs(t.deps) do
                if not byId[d] then
                    if t.kind == "pickup" then
                        -- the chain parent is missing: drop the whole candidate
                        byId[t.id] = nil
                        table.remove(tasks, i)
                        changed = true
                    end
                    break
                end
            end
        end
        -- remove orphans of removed pickups
        for i = #tasks, 1, -1 do
            local t = tasks[i]
            for _, d in ipairs(t.deps) do
                if not byId[d] and t.kind ~= "pickup" then
                    byId[t.id] = nil
                    table.remove(tasks, i)
                    changed = true
                    break
                end
            end
        end
    end

    -- Deferred-ness propagates along dependencies (a follow-up of a skipped quest waits too).
    local function isDeferred(t, seen)
        if t.deferred then return true end
        seen = seen or {}
        if seen[t] then return false end
        seen[t] = true
        for _, d in ipairs(t.deps) do
            local dt = byId[d]
            if dt and isDeferred(dt, seen) then return true end
        end
        return false
    end
    for _, t in ipairs(tasks) do t.deferred = isDeferred(t) end

    -- dependents (reverse edges)
    for _, t in ipairs(tasks) do t.dependents = {} end
    for _, t in ipairs(tasks) do
        for _, d in ipairs(t.deps) do
            local dt = byId[d]
            if dt then dt.dependents[#dt.dependents + 1] = t.id end
        end
    end
    Planner.ApplyLevelGates(tasks, byId, ctx.level, ctx.xpFrac)
    return tasks, byId
end

--- Sets t.minTurnins on objectives whose mobs are too high for now. A wait can't ask for more
--- turn-ins than the plan has without any wait in the way (not deferred, not depending on a
--- waiting objective), so it can always be met. Needs t.dependents (BuildTasks sets them).
function Planner.ApplyLevelGates(tasks, byId, level, xpFrac)
    local waiting, blocked, stack = {}, {}, {}
    for _, t in ipairs(tasks) do
        local gate = t.kind == "objective" and Planner.LevelGate(t.mobLevel, level, xpFrac) or 0
        t.minTurnins = gate > 0 and gate or nil
        if t.minTurnins then waiting[#waiting + 1] = t; stack[#stack + 1] = t end
    end
    if #waiting == 0 then return end
    while #stack > 0 do
        local t = table.remove(stack)
        for _, id in ipairs(t.dependents or {}) do
            local dt = byId[id]
            if dt and not blocked[dt] then blocked[dt] = true; stack[#stack + 1] = dt end
        end
    end
    local free = 0
    for _, t in ipairs(tasks) do
        if t.kind == "turnin" and not t.deferred and not blocked[t] then free = free + (t.xpWeight or 1) end
    end
    for _, t in ipairs(waiting) do
        t.minTurnins = math.min(t.minTurnins, free)
        if t.minTurnins <= 0 then t.minTurnins = nil end
    end
end

---------------------------------------------------------------------------
-- Ordering
---------------------------------------------------------------------------
--- Travel cost function in use (Travel.NewCost when flights are known; plain walking otherwise).
Planner.travelFn = nil

local function legCost(a, b)
    return (Planner.travelFn or Geo.TravelSeconds)(a, b)
end
Planner.LegCost = legCost

local function travel(a, b)
    if not b then return Planner.UNKNOWN_LOC_PENALTY end
    if not a then return 0 end
    return legCost(a, b)
end

local function logDelta(t)
    if t.kind == "pickup" then return 1 end
    if t.kind == "turnin" then return -1 end
    return 0
end

--- Greedy nearest-feasible construction.
local function greedy(tasks, byId, start, opts)
    local done, order = {}, {}
    for id in pairs(opts.predone or {}) do done[id] = true end -- tasks already placed earlier
    local pos = start
    local logCount = opts.logCount or 0
    local logMax = opts.logMax or 20
    local turnins = opts.turninsBefore or 0
    local remaining = #tasks
    local function depsDone(t)
        for _, d in ipairs(t.deps) do
            if not done[d] then return false end
        end
        return true
    end
    while remaining > 0 do
        local best, bestCost
        local anyNormal = false
        for _, t in ipairs(tasks) do
            if not done[t.id] and not t.deferred and depsDone(t) then
                if t.kind ~= "pickup" or logCount < logMax then anyNormal = true break end
            end
        end
        -- First pass keeps the level waits; the second only runs when nothing else can happen
        -- (say the log is full), and then that objective's wait is lowered to what was reached.
        for pass = 1, 2 do
            for _, t in ipairs(tasks) do
                if not done[t.id] and depsDone(t) and (not anyNormal or not t.deferred)
                    and (pass == 2 or gateOk(t, turnins, opts)) then
                    if t.kind ~= "pickup" or logCount < logMax then
                        local c = travel(pos, t.loc)
                        -- Turn-ins free log slots and bag space: mild preference at equal distance.
                        if t.kind == "turnin" then c = c - 3 end
                        if opts.stickyId and t.id == opts.stickyId then c = c * 0.6 end
                        if not bestCost or c < bestCost then best, bestCost = t, c end
                    end
                end
            end
            if best then
                if pass == 2 and best.minTurnins then best.minTurnins = turnins end
                break
            end
        end
        if not best then break end -- only pickups left and the log is full
        done[best.id] = true
        order[#order + 1] = best
        remaining = remaining - 1
        if best.loc then pos = best.loc end
        logCount = logCount + logDelta(best)
        if best.kind == "turnin" then turnins = turnins + (best.xpWeight or 1) end
    end
    return order
end

--- Total travel seconds of a route (unknown-location penalty included).
function Planner.RouteCost(order, start)
    local cost, pos = 0, start
    for i = 1, #order do
        local t = order[i]
        if t.teleport then
            cost = cost + (t.teleportCost or 0) -- hearthstone: you arrive at t.loc without walking
        else
            cost = cost + travel(pos, t.loc)
        end
        if t.loc then pos = t.loc end
    end
    return cost
end

--- Checks precedence, deferred tiering, log capacity and level waits.
function Planner.IsValid(order, opts)
    local seen = {}
    for id in pairs(opts.predone or {}) do seen[id] = true end
    local logCount = opts.logCount or 0
    local logMax = opts.logMax or 20
    local turnins = opts.turninsBefore or 0
    local sawDeferred = false
    for i = 1, #order do
        local t = order[i]
        for _, d in ipairs(t.deps) do
            if not seen[d] then return false end
        end
        if t.deferred then sawDeferred = true elseif sawDeferred then return false end
        if not gateOk(t, turnins, opts) then return false end
        logCount = logCount + logDelta(t)
        if logCount > logMax then return false end
        if t.kind == "turnin" then turnins = turnins + (t.xpWeight or 1) end
        seen[t.id] = true
    end
    return true
end

--- Or-opt: move contiguous blocks of 1..MAX_SEGMENT tasks (e.g. "pickup + loot + turn-in" at
--- one NPC) to the best feasible position, using O(1) travel deltas and a precedence window.
--- Tasks without a location never change the travel cost, so they are skipped as segment ends.
--- 8 so a whole stop can move at once (a stop has up to MAX_TASKS_PER_STEP = 7 tasks). With 4,
--- busy stops like the Sepulcher (7 tasks) or Brill (5) could never move as a unit; on a real
--- Tirisfal/Silverpine plan that cost ~3.7 minutes (6%).
Planner.MAX_SEGMENT = 8

local function d(a, b)
    if not a or not b then return 0 end
    return legCost(a, b)
end

local function tryMoves(order, start, opts, segLen)
    local n = #order
    local improvedAny = false
    local i = 1
    while i <= n - segLen + 1 do
        -- segment and its located ends
        local seg, inSeg = {}, {}
        for k = 0, segLen - 1 do
            local t = order[i + k]
            seg[#seg + 1] = t
            inSeg[t.id] = true
        end
        local segFirst, segLast
        local segHasNormal, segHasDeferred = false, false
        for _, t in ipairs(seg) do
            if t.loc then segFirst = segFirst or t.loc; segLast = t.loc end
            if t.deferred then segHasDeferred = true else segHasNormal = true end
        end
        if segFirst then
            -- reduced route (segment removed)
            local rest = {}
            for k = 1, n do
                if k < i or k >= i + segLen then rest[#rest + 1] = order[k] end
            end
            local m = #rest
            -- last located before each slot j (inserting before rest[j]) and first located at/after j
            local prevLoc, nextLoc = {}, {}
            local last = start
            for j = 1, m + 1 do
                prevLoc[j] = last
                if rest[j] and rest[j].loc then last = rest[j].loc end
            end
            local nxt
            for j = m + 1, 1, -1 do
                if j <= m and rest[j].loc then nxt = rest[j].loc end
                nextLoc[j] = nxt
            end
            -- precedence window
            local pos = {}
            for k = 1, m do pos[rest[k].id] = k end
            local lo, hi = 1, m + 1
            for _, t in ipairs(seg) do
                for _, dep in ipairs(t.deps) do
                    if not inSeg[dep] and pos[dep] and pos[dep] + 1 > lo then lo = pos[dep] + 1 end
                end
                for _, dep in ipairs(t.dependents or {}) do
                    if not inSeg[dep] and pos[dep] and pos[dep] < hi then hi = pos[dep] end
                end
            end
            -- deferred tiering: normal tasks never after a deferred one, and vice versa
            for k = 1, m do
                if rest[k].deferred and segHasNormal and k < hi then hi = k end
                if not rest[k].deferred and segHasDeferred and k + 1 > lo then lo = k + 1 end
            end
            -- cost of the segment where it is now
            local A, B = prevLoc[i], nextLoc[i]
            local removalGain = d(A, segFirst) + d(segLast, B) - d(A, B)
            local bestJ, bestDelta
            for j = lo, hi do
                if j ~= i then
                    local C, D = prevLoc[j], nextLoc[j]
                    local added = d(C, segFirst) + d(segLast, D) - d(C, D)
                    local delta = added - removalGain
                    if delta < -0.5 and (not bestDelta or delta < bestDelta) then bestJ, bestDelta = j, delta end
                end
            end
            if bestJ then
                local candidate = {}
                for k = 1, bestJ - 1 do candidate[#candidate + 1] = rest[k] end
                for _, t in ipairs(seg) do candidate[#candidate + 1] = t end
                for k = bestJ, m do candidate[#candidate + 1] = rest[k] end
                if Planner.IsValid(candidate, opts) then
                    for k = 1, n do order[k] = candidate[k] end
                    improvedAny = true
                end
            end
        end
        i = i + 1
        if ns.MaybeYield then ns.MaybeYield(8) end
    end
    return improvedAny
end

--- 2-opt over stops: reverse a stretch of the route when that makes it shorter. This turns a
--- "fly south, walk north, walk back south" zigzag into one sweep, which Or-opt can't do: it
--- moves small blocks but never turns a stretch around. Tasks at the same stop stay in their
--- order (a turn-in before its follow-up pickup), only the stops are reversed. Walking is
--- symmetric and a flight costs about the same either way, so an O(1) estimate picks the
--- candidates and the exact route cost decides.
Planner.USE_REVERSALS = true
local STOP_YARDS = 30

local function reversedStops(order, i, k)
    -- consecutive tasks at (almost) the same place form one stop
    local stops, cur = {}, nil
    for q = i, k do
        local t = order[q]
        local same = cur and ((t.loc == nil and cur.loc == nil)
            or (t.loc and cur.loc and (Geo.Distance(t.loc, cur.loc) or math.huge) <= STOP_YARDS))
        if same then
            cur.tasks[#cur.tasks + 1] = t
        else
            cur = { loc = t.loc, tasks = { t } }
            stops[#stops + 1] = cur
        end
    end
    local out = {}
    for s = #stops, 1, -1 do
        for _, t in ipairs(stops[s].tasks) do out[#out + 1] = t end
    end
    return out, #stops
end

local function tryReversals(order, start, opts)
    local n = #order
    if n < 3 then return false end
    local improvedAny = false
    local base = Planner.RouteCost(order, start)
    local i = 1
    while i < n do
        local prevLoc = start
        for q = 1, i - 1 do if order[q].loc then prevLoc = order[q].loc end end
        local nextAfter, nxt = {}, nil
        for q = n, i, -1 do
            nextAfter[q] = nxt
            if order[q].loc then nxt = order[q].loc end
        end
        local first, last, accepted = nil, nil, false
        for k = i, n do
            local t = order[k]
            if t.loc then first = first or t.loc; last = t.loc end
            if k > i and first and last and last ~= first then
                local N = nextAfter[k]
                local est = d(prevLoc, last) + d(first, N) - d(prevLoc, first) - d(last, N)
                if est < -0.5 then
                    local middle, nStops = reversedStops(order, i, k)
                    if nStops > 1 then
                        local candidate = {}
                        for q = 1, i - 1 do candidate[#candidate + 1] = order[q] end
                        for _, m in ipairs(middle) do candidate[#candidate + 1] = m end
                        for q = k + 1, n do candidate[#candidate + 1] = order[q] end
                        if Planner.IsValid(candidate, opts) then
                            local c = Planner.RouteCost(candidate, start)
                            if c < base - 0.5 then
                                for q = 1, n do order[q] = candidate[q] end
                                base, improvedAny, accepted = c, true, true
                                break
                            end
                        end
                    end
                end
            end
            if ns.MaybeYield then ns.MaybeYield(60) end
        end
        if not accepted then i = i + 1 end
    end
    return improvedAny
end
Planner.TryReversals = tryReversals

local function improve(order, start, opts)
    local n = #order
    if n < 3 or n > Planner.IMPROVE_MAX_TASKS then return order end
    for _ = 1, Planner.IMPROVE_PASSES do
        local improved = false
        for segLen = 1, math.min(Planner.MAX_SEGMENT, n - 1) do
            if tryMoves(order, start, opts, segLen) then improved = true end
        end
        if Planner.USE_REVERSALS and tryReversals(order, start, opts) then improved = true end
        if not improved then break end
    end
    return order
end

---------------------------------------------------------------------------
-- "While you're here"
---------------------------------------------------------------------------
-- Travel time alone often prefers turning a finished quest in when the route passes the same NPC
-- again later (it saves a short walk now), and the improvement step pushes it back. For you,
-- later is worse: the reward, the XP and the free log slot come later, and plans change in
-- between. So a quest that is finished right now (its turn-in has nothing left to wait for)
-- moves to the earliest point in the route where the extra travel is small: PULL_FORWARD_SLACK
-- seconds plus TURNIN_WAIT_WEIGHT seconds per second you would otherwise carry it, capped at
-- TURNIN_MAX_EXTRA. Precedence, deferral and the log limit still hold. Turn-ins that only become
-- ready later in the route are left to the travel optimizer.
-- Only where you already are: the stop before the new slot must be within PULL_NEAR_YARDS of the
-- NPC. Otherwise cheap AFK flights let it "save time" with a bat ride back and out again (0.3.5:
-- Sepulcher -> Undercity -> Silverpine just to turn one quest in sooner).
Planner.PULL_FORWARD_SLACK = 10   -- seconds of extra travel accepted to do it now
Planner.TURNIN_WAIT_WEIGHT = 0.1  -- carrying a finished quest 10 minutes ~ worth 1 minute of walking
Planner.TURNIN_MAX_EXTRA = 120    -- never more than 2 extra minutes of travel per turn-in
Planner.PULL_NEAR_YARDS = 600     -- about the size of a capital city

local function readyNow(t)
    return t.kind == "turnin" and #t.deps == 0
end
Planner.ReadyNow = readyNow

local function pullForward(order, start, opts)
    for i = 2, #order do
        local t = order[i]
        if readyNow(t) and t.loc then
            local n = #order
            -- done[k]: time (travel + work) when order[k] is finished, in the current order
            local done, pos, clockTime = {}, start, 0
            for k = 1, n do
                local o = order[k]
                if o.teleport then clockTime = clockTime + (o.teleportCost or 0) else clockTime = clockTime + travel(pos, o.loc) end
                clockTime = clockTime + (o.est or 0)
                done[k] = clockTime
                if o.loc then pos = o.loc end
            end
            local rest = {}
            for k = 1, n do if k ~= i then rest[#rest + 1] = order[k] end end
            -- located neighbours of each slot j (inserting before rest[j])
            local prevLoc, nextLoc = {}, {}
            local last = start
            for j = 1, n do
                prevLoc[j] = last
                if rest[j] and rest[j].loc then last = rest[j].loc end
            end
            local nxt
            for j = n, 1, -1 do
                if rest[j] and rest[j].loc then nxt = rest[j].loc end
                nextLoc[j] = nxt
            end
            local removalGain = d(prevLoc[i], t.loc) + d(t.loc, nextLoc[i]) - d(prevLoc[i], nextLoc[i])
            -- earliest slot: after its dependencies, and never across a hearth
            local lo = 1
            for k = 1, i - 1 do
                local r = rest[k]
                if r.teleport and k + 1 > lo then lo = k + 1 end
                for _, dep in ipairs(t.deps) do
                    if r.id == dep and k + 1 > lo then lo = k + 1 end
                end
            end
            for j = lo, i - 1 do
                local away = prevLoc[j] and Geo.Distance(prevLoc[j], t.loc)
                local added = d(prevLoc[j], t.loc) + d(t.loc, nextLoc[j]) - d(prevLoc[j], nextLoc[j])
                local sooner = done[i - 1] - (j > 1 and done[j - 1] or 0) -- how much earlier it gets done
                local allowance = Planner.PULL_FORWARD_SLACK
                    + math.min(Planner.TURNIN_WAIT_WEIGHT * sooner, Planner.TURNIN_MAX_EXTRA)
                if away and away <= Planner.PULL_NEAR_YARDS and added - removalGain <= allowance then
                    local candidate = {}
                    for k = 1, j - 1 do candidate[#candidate + 1] = rest[k] end
                    candidate[#candidate + 1] = t
                    for k = j, n - 1 do candidate[#candidate + 1] = rest[k] end
                    if Planner.IsValid(candidate, opts) then
                        for k = 1, n do order[k] = candidate[k] end
                        break
                    end
                end
            end
        end
        if ns.MaybeYield then ns.MaybeYield(8) end
    end
    return order
end
Planner.PullForward = pullForward

Planner.Improve = improve -- exposed for tests

---------------------------------------------------------------------------
-- "Take it while you're standing there"
---------------------------------------------------------------------------
-- Travel time alone doesn't care when you accept a quest whose giver the route passes twice, so
-- it could leave one behind for the second visit. Then its mobs can't be killed together with
-- the other quests' mobs out in the field, and you go back out for them. So each pickup moves
-- to the first time the route has you standing next to its giver (within GRAB_YARDS), when its
-- prerequisites are done, the log has room and the route gets no longer (GRAB_SLACK covers
-- rounding in flight-aware travel). The improvement step then moves its objectives next to
-- the ones you're already doing.
Planner.GRAB_YARDS = 60
Planner.GRAB_SLACK = 5

local function grabPickups(order, start, opts)
    local moved = false
    for i = 2, #order do
        local t = order[i]
        if t.kind == "pickup" and t.loc then
            -- where you stand before slot j (after order[j-1]); never across a hearth, never
            -- before its prerequisites
            local lo, here = 1, start
            for k = 1, i - 1 do
                local r = order[k]
                if r.teleport then lo = k + 1 end
                for _, dep in ipairs(t.deps) do
                    if r.id == dep then lo = k + 1 end
                end
            end
            local baseCost
            for j = 1, i - 1 do
                if j > 1 and order[j - 1].loc then here = order[j - 1].loc end
                local dist = j >= lo and here and Geo.Distance(here, t.loc)
                if dist and dist <= Planner.GRAB_YARDS then
                    local candidate = {}
                    for k = 1, j - 1 do candidate[#candidate + 1] = order[k] end
                    candidate[#candidate + 1] = t
                    for k = j, #order do if k ~= i then candidate[#candidate + 1] = order[k] end end
                    if Planner.IsValid(candidate, opts) then
                        baseCost = baseCost or Planner.RouteCost(order, start)
                        if Planner.RouteCost(candidate, start) <= baseCost + Planner.GRAB_SLACK then
                            for k = 1, #order do order[k] = candidate[k] end
                            moved = true
                            break
                        end
                    end
                end
            end
        end
        if ns.MaybeYield then ns.MaybeYield(8) end
    end
    return moved
end
Planner.GrabPickups = grabPickups

---------------------------------------------------------------------------
-- Fitting the level waits into a good route
---------------------------------------------------------------------------
-- Planning with the waits from the start gave poor routes: the first guess wandered (a camp
-- was left half done to come back later) and the improvement step can't repair that, because
-- every move it tries must keep the waits. So: plan by travel alone first, then take out the
-- objectives that come too early (and what depends on them), and put each back at the
-- cheapest place where enough quests are turned in before it. The improvement step polishes
-- the result with the waits in force.
local function violations(order, opts)
    local turnins = opts.turninsBefore or 0
    for i, t in ipairs(order) do
        if not gateOk(t, turnins, opts) then return i end
        if t.kind == "turnin" then turnins = turnins + (t.xpWeight or 1) end
    end
    return nil
end

local function fitLevelWaits(order, start, opts)
    if not violations(order, opts) then return order end
    local index, routePos = {}, {}
    for k, t in ipairs(order) do index[t.id] = t; routePos[t] = k end
    -- 1) take out each objective that comes too early, with everything that depends on it
    local out = {}
    while true do
        local i = violations(order, opts)
        if not i then break end
        local drop, stack = { [order[i]] = true }, { order[i] }
        while #stack > 0 do
            local t = table.remove(stack)
            for _, id in ipairs(t.dependents or {}) do
                local dt = index[id]
                if dt and not drop[dt] then drop[dt] = true; stack[#stack + 1] = dt end
            end
        end
        local kept = {}
        for _, t in ipairs(order) do
            if drop[t] then out[#out + 1] = t else kept[#kept + 1] = t end
        end
        order = kept
    end
    -- they go back in their original route order, so prerequisites go in first
    table.sort(out, function(a, b) return routePos[a] < routePos[b] end)
    -- 2) put each back where it adds the least travel and the order stays valid
    for _, r in ipairs(out) do
        local n = #order
        local prevLoc, nextLoc, last = {}, {}, start
        for j = 1, n + 1 do
            prevLoc[j] = last
            if order[j] and order[j].loc then last = order[j].loc end
        end
        local nxt
        for j = n + 1, 1, -1 do
            if order[j] and order[j].loc then nxt = order[j].loc end
            nextLoc[j] = nxt
        end
        local slots = {}
        for j = 1, n + 1 do
            if not (order[j] and order[j].teleport) then
                local added = r.loc and (d(prevLoc[j], r.loc) + (nextLoc[j] and (d(r.loc, nextLoc[j]) - d(prevLoc[j], nextLoc[j])) or 0)) or 0
                slots[#slots + 1] = { j = j, added = added }
            end
        end
        table.sort(slots, function(a, b) if a.added ~= b.added then return a.added < b.added end return a.j < b.j end)
        local placed = false
        for _, s in ipairs(slots) do
            local candidate = {}
            for k = 1, s.j - 1 do candidate[#candidate + 1] = order[k] end
            candidate[#candidate + 1] = r
            for k = s.j, n do candidate[#candidate + 1] = order[k] end
            if Planner.IsValid(candidate, opts) then order = candidate; placed = true; break end
        end
        if not placed then
            r.minTurnins = nil -- can't be met (log full?): do it at the end rather than lose it
            order[#order + 1] = r
        end
        if ns.MaybeYield then ns.MaybeYield(4) end
    end
    return order
end
Planner.FitLevelWaits = fitLevelWaits

---------------------------------------------------------------------------
-- "Finish what's around you first"
---------------------------------------------------------------------------
-- Travel time alone sees no difference between finishing the camp you stand in now and
-- passing through it again later, so a route could send you away from mobs 100 yards off and
-- bring you back. For you that's ping-pong. So the work within HERE_YARDS of where you stand
-- (quests to accept, objectives, turn-ins: whatever can be done now, nearest first) goes to the
-- front, when that adds at most HERE_SLACK seconds of travel and keeps every rule (including
-- the level waits).
Planner.HERE_YARDS = 200
Planner.HERE_SLACK = 90

local function finishHere(order, start, opts)
    if not start or #order < 2 then return order end
    local done = {}
    for id in pairs(opts.predone or {}) do done[id] = true end
    local front, taken, pos = {}, {}, start
    local turnins = opts.turninsBefore or 0
    while true do
        local best, bestDist
        for _, t in ipairs(order) do
            if not taken[t] and t.loc and not t.teleport and gateOk(t, turnins, opts) then
                local dist = Geo.Distance(start, t.loc)
                local ready = dist and dist <= Planner.HERE_YARDS
                if ready then
                    for _, dep in ipairs(t.deps) do if not done[dep] then ready = false break end end
                end
                if ready then
                    local fromHere = Geo.Distance(pos, t.loc) or dist
                    if not bestDist or fromHere < bestDist then best, bestDist = t, fromHere end
                end
            end
        end
        if not best then break end
        taken[best], done[best.id] = true, true
        front[#front + 1] = best
        pos = best.loc
        if best.kind == "turnin" then turnins = turnins + (best.xpWeight or 1) end
    end
    if #front == 0 then return order end
    local candidate = {}
    for _, t in ipairs(front) do candidate[#candidate + 1] = t end
    for _, t in ipairs(order) do if not taken[t] then candidate[#candidate + 1] = t end end
    local same = true
    for k = 1, #order do if candidate[k] ~= order[k] then same = false break end end
    if same or not Planner.IsValid(candidate, opts) then return order end
    if Planner.RouteCost(candidate, start) > Planner.RouteCost(order, start) + Planner.HERE_SLACK then return order end
    return candidate
end
Planner.FinishHere = finishHere

--- Orders tasks. opts: logCount, logMax, stickyId, predone, turninsBefore.
function Planner.Solve(tasks, byId, start, opts)
    opts = opts or {}
    local hasWaits = false
    for _, t in ipairs(tasks) do if t.minTurnins then hasWaits = true break end end
    local order
    if hasWaits then
        local free = setmetatable({ ignoreGates = true }, { __index = opts })
        order = greedy(tasks, byId, start, free)
        order = improve(order, start, free)
        order = fitLevelWaits(order, start, opts)
        order = improve(order, start, opts)
    else
        order = greedy(tasks, byId, start, opts)
        order = improve(order, start, opts)
    end
    if grabPickups(order, start, opts) then order = improve(order, start, opts) end
    order = finishHere(order, start, opts)
    order = pullForward(order, start, opts)
    return order
end

---------------------------------------------------------------------------
-- Steps: consecutive tasks in the same place become one instruction
---------------------------------------------------------------------------
function Planner.GroupSteps(order, radius)
    radius = radius or Planner.GROUP_RADIUS
    local steps, cur = {}, nil
    for _, t in ipairs(order) do
        local join = false
        if cur and #cur.tasks < Planner.MAX_TASKS_PER_STEP and not t.solo and not cur.solo then
            if not t.loc then
                join = (cur.loc == nil) -- unknown with unknown
            elseif cur.loc then
                local d = Geo.Distance(cur.loc, t.loc)
                join = d ~= nil and d <= radius
            end
        end
        if join then
            cur.tasks[#cur.tasks + 1] = t
        else
            cur = { tasks = { t }, loc = t.loc, solo = t.solo }
            steps[#steps + 1] = cur
        end
    end
    for i, s in ipairs(steps) do
        s.index = i
        -- Keep solver order inside a step: it already respects precedence, and the solver's
        -- turn-in preference puts turn-ins before pickups at the same NPC.
        local est = 0
        for _, t in ipairs(s.tasks) do est = est + (t.est or 0) end
        s.est = est
    end
    return steps
end

---------------------------------------------------------------------------
-- Bag simulation
---------------------------------------------------------------------------
--- bags = { free = n, counts = { [itemId] = count } }; reserve = slots to keep free.
--- Returns { free, reserve, peak, overflowAt, needed, perStep = {used...} }.
function Planner.SimulateBags(steps, bags, reserve, lookahead)
    local free = bags.free or 0
    reserve = reserve or 0
    lookahead = math.min(lookahead or #steps, #steps)
    local held = {}
    for itemId, count in pairs(bags.counts or {}) do
        if count > 0 then held[itemId] = true end
    end
    local newItems = {}
    local used, peak, overflowAt = 0, 0, nil
    local perStep = {}
    for si = 1, lookahead do
        local step = steps[si]
        for _, t in ipairs(step.tasks) do
            if t.kind == "turnin" then
                for _, itemId in ipairs(t.frees or {}) do
                    if newItems[itemId] then
                        newItems[itemId] = nil
                        used = used - 1
                    elseif held[itemId] then
                        held[itemId] = nil
                        used = used - 1
                    end
                end
                used = used + (t.reward or 0)
            elseif t.kind == "pickup" and t.gives then
                if not held[t.gives] and not newItems[t.gives] then
                    newItems[t.gives] = true
                    used = used + 1
                end
            elseif t.kind == "visit" and type(t.frees) == "number" then
                used = used - t.frees
            elseif t.kind == "objective" and t.collects then
                if not held[t.collects] and not newItems[t.collects] then
                    newItems[t.collects] = true
                    used = used + 1
                end
            end
            if used > peak then peak = used end
        end
        perStep[si] = used
        if not overflowAt and (free - reserve - used) < 0 then overflowAt = si end
    end
    return {
        free = free,
        reserve = reserve,
        peak = peak,
        overflowAt = overflowAt,
        needed = math.max(0, peak - (free - reserve)),
        perStep = perStep,
    }
end

---------------------------------------------------------------------------
-- One call does everything
---------------------------------------------------------------------------
function Planner.Plan(ctx)
    Planner.travelFn = ctx.travel
    local tasks, byId = Planner.BuildTasks(ctx)
    local order = Planner.Solve(tasks, byId, ctx.start, {
        logCount = ctx.logCount,
        logMax = ctx.logMax,
        stickyId = ctx.stickyId,
    })
    local steps = Planner.GroupSteps(order, ctx.groupRadius)
    local bags = Planner.SimulateBags(steps, ctx.bags or { free = 99, counts = {} }, ctx.reserve, ctx.lookahead)
    return {
        tasks = tasks,
        byId = byId,
        order = order,
        steps = steps,
        bags = bags,
        cost = Planner.RouteCost(order, ctx.start),
        dropped = #tasks - #order,
    }
end
