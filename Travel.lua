-- Quest Ladder: travel network. Turns "walk everywhere" into the cheapest of
--   walking (or riding, once you have the riding skill),
--   flying between flight paths you know,
--   hearthing to your inn (once per cooldown, placed where it saves the most),
-- and suggests binding your hearthstone at a better inn and picking up flight paths
-- that are on the way.
--
-- The cost model and the hearth/bind/discovery decisions are pure functions (tested
-- offline); BuildNetwork() is the only part that reads the game.

local _, ns = ...
local Travel = {}
ns.Travel = Travel

local Geo, Data = ns.Geo, ns.Data

Travel.HEARTHSTONE = 6948
Travel.HEARTH_SPELL = 8690
Travel.FLY_SPEED = 32          -- yards/second on a flight path (Classic gryphon/wyvern, approx.)
Travel.FLY_PATH_FACTOR = 1.25  -- flight routes bend through hubs
Travel.FLY_OVERHEAD = 20       -- talk to the flight master, take off, land
Travel.AFK_WEIGHT = 0.35       -- a second on a flight path costs this much "real" effort: you can AFK
Travel.FLY_MAX_DETOUR = 1.15   -- a flight's total time may be at most 15% longer than walking
Travel.HEARTH_OVERHEAD = 25    -- 10 s cast + loading screen
Travel.MIN_HEARTH_SAVING = 90  -- per-leg screen used by the quick estimates
Travel.HEARTH_MIN_GAIN = 240   -- a recommended hearth must save at least 4 minutes...
Travel.HEARTH_MIN_FRACTION = 0.08 -- ...and at least 8% of the whole route
Travel.DEAD_END_SECONDS = 120  -- "area done": nothing left within 2 minutes of where you stand
Travel.COOLDOWN_CONTENT = 0.9  -- or: ~a full cooldown of steps follows the hearth
Travel.FAST_RETURN_SECONDS = 180  -- or (your rule): turn-ins more than 3 minutes away...
Travel.HEARTH_NEAR_SECONDS = 20   -- ...that the hearth drops you within ~20 s of...
Travel.FAST_RETURN_MIN_GAIN = 120 -- ...and the whole route still saves 2+ minutes
Travel.HEARTH_RULE_PREFERENCE = 30 -- a fast return must save this much more to beat "area done"/"cooldown"
Travel.MIN_FLY_SAVING = 30
Travel.BIND_MIN_GAIN = 180     -- a new inn must save 3+ minutes over the current one
Travel.DISCOVER_MAX_DETOUR = 60
Travel.RIDING_SKILL = 762
Travel.MOUNT_FACTOR = 1.6

---------------------------------------------------------------------------
-- Cost model
---------------------------------------------------------------------------
--- net = { speed, nodes = { {name, point, known} }, bind = point|nil, bindName,
---         hearthReadyIn = seconds, hearthCooldown = seconds, hasHearth = bool }
local function walk(net, a, b)
    if not a or not b then return 0 end
    if a.cont ~= b.cont then return Geo.CONTINENT_SECONDS end
    local dx, dy = a.wx - b.wx, a.wy - b.wy
    return math.sqrt(dx * dx + dy * dy) / (net.speed or Geo.RUN_SPEED)
end
Travel.Walk = walk

local function nearestKnown(net, p, k)
    -- cached per point: every leg from/to the same task reuses it
    local cache = net._nearest
    if not cache then cache = setmetatable({}, { __mode = "k" }); net._nearest = cache end
    local hit = cache[p]
    if hit then return hit end
    local list = {}
    for _, n in ipairs(net.nodes or {}) do
        if n.known and n.point and n.point.cont == p.cont then
            local dx, dy = n.point.wx - p.wx, n.point.wy - p.wy
            list[#list + 1] = { node = n, d = dx * dx + dy * dy }
        end
    end
    table.sort(list, function(x, y) return x.d < y.d end)
    local out = {}
    for i = 1, math.min(k, #list) do out[i] = list[i].node end
    cache[p] = out
    return out
end

--- Seconds in the air between two flight paths (rough: real routes are not exposed to add-ons).
local function airTime(f1, f2)
    local dx, dy = f1.point.wx - f2.point.wx, f1.point.wy - f2.point.wy
    return math.sqrt(dx * dx + dy * dy) * Travel.FLY_PATH_FACTOR / Travel.FLY_SPEED
end
Travel.AirTime = airTime

--- Walk or fly between two points: returns cost, mode ("walk"/"fly"), fromNode, toNode, airSeconds.
--- Time in the air is AFK time, so it is weighted down; but a flight is only taken when it is a
--- real shortcut: less active time than walking, and not much longer overall (no detours).
local function airLeg(net, a, b)
    if not a or not b then return 0, "walk" end
    local walking = walk(net, a, b)
    local best, mode, from, to, air = walking, "walk", nil, nil, nil
    if a.cont ~= b.cont then return best, mode end
    local starts, ends = nearestKnown(net, a, 3), nearestKnown(net, b, 3)
    for _, f1 in ipairs(starts) do
        for _, f2 in ipairs(ends) do
            if f1 ~= f2 then
                local active = walk(net, a, f1.point) + Travel.FLY_OVERHEAD + walk(net, f2.point, b)
                local inAir = airTime(f1, f2)
                if active < walking - Travel.MIN_FLY_SAVING and active + inAir <= walking * Travel.FLY_MAX_DETOUR then
                    local c = active + inAir * Travel.AFK_WEIGHT
                    if c < best then best, mode, from, to, air = c, "fly", f1, f2, inAir end
                end
            end
        end
    end
    return best, mode, from, to, air
end
Travel.AirLeg = airLeg

---------------------------------------------------------------------------
-- Zeppelins
---------------------------------------------------------------------------
-- The game gives add-ons no transport routes, but QuestieDB knows the zeppelin masters
-- ("<Zeppelin Master>"). Masters standing together form a tower, and each master serves one
-- route. When every tower has one master per other tower (Classic: Tirisfal, Durotar and
-- Grom'gol, two masters each), every pair of towers is linked. Any other layout can't be
-- paired from the data, so then nothing is linked (/ladder diag says so).
-- What players report (Warcraft Wiki's zeppelin guide, Forever launch threads): each zeppelin
-- docks for 60 s and leaves every 3-5 minutes (Undercity-Orgrimmar ~4:00, Undercity-Grom'gol
-- ~5:15). There's no timer in the game, so you wait anywhere from 0 to a full cycle, and at
-- Forever's launch some got lost for 10+ minutes. Guides use them only to change continents
-- (or to reach Grom'gol in the mid-30s), never as a shortcut inside a zone. So: between
-- continents a zeppelin is simply the way; on one continent only when it still beats walking
-- if you just missed it. Waiting is hands-on (you have to board), the ride is AFK.
Travel.ZEPPELIN_WAIT = 150         -- average wait: half a ~5-minute cycle
Travel.ZEPPELIN_WAIT_MAX = 330     -- you just missed it: a full cycle and boarding
Travel.ZEPPELIN_RIDE = 100         -- aboard, loading screen included (rough)
Travel.ZEPPELIN_TOWER_YARDS = 80   -- masters this close share a tower

local function zoneName(mapId)
    if not (mapId and C_Map and C_Map.GetMapInfo) then return nil end
    local ok, info = pcall(C_Map.GetMapInfo, mapId)
    if ok and type(info) == "table" and type(info.name) == "string" and not ns.IsSecret(info.name) then return info.name end
    return nil
end

--- masters = Data.transportMasters. Returns links { {a = tower, b = tower} }, towers, reason.
function Travel.ZeppelinLinks(masters)
    local towers = {}
    for _, m in ipairs(masters or {}) do
        if m.point and type(m.subName) == "string" and m.subName:lower():find("zeppelin", 1, true) then
            local home
            for _, t in ipairs(towers) do
                local dist = Geo.Distance(t.point, m.point)
                if dist and dist <= Travel.ZEPPELIN_TOWER_YARDS then home = t break end
            end
            if not home then
                home = { point = m.point, masters = 0, name = zoneName(m.point.mapId) or "zeppelin tower" }
                towers[#towers + 1] = home
            end
            home.masters = home.masters + 1
        end
    end
    if #towers < 2 then return {}, towers, "fewer than 2 zeppelin towers" end
    for _, t in ipairs(towers) do
        if t.masters ~= #towers - 1 then return {}, towers, "can't tell which tower goes where" end
    end
    local links = {}
    for i = 1, #towers do
        for j = i + 1, #towers do links[#links + 1] = { a = towers[i], b = towers[j] } end
    end
    return links, towers
end

--- Best zeppelin trip from a to b (to the tower and from the far one by walking or flying),
--- or nil. Returns { from = tower, to = tower, active, air, total, cost }.
function Travel.ZeppelinOption(net, a, b)
    local links = net.zeppelins
    if not (a and b and links and links[1]) then return nil end
    local AFK = Travel.AFK_WEIGHT
    local best
    for _, link in ipairs(links) do
        for dir = 1, 2 do
            local t1, t2 = link.a, link.b
            if dir == 2 then t1, t2 = link.b, link.a end
            if t1.point.cont == a.cont and t2.point.cont == b.cont then
                local c1, _, _, _, air1 = airLeg(net, a, t1.point)
                local c2, _, _, _, air2 = airLeg(net, t2.point, b)
                air1, air2 = air1 or 0, air2 or 0
                local active = (c1 - air1 * AFK) + Travel.ZEPPELIN_WAIT + (c2 - air2 * AFK)
                local inAir = air1 + Travel.ZEPPELIN_RIDE + air2
                local o = { from = t1, to = t2, active = active, air = inAir, total = active + inAir,
                            cost = active + inAir * AFK,
                            worst = active + inAir - Travel.ZEPPELIN_WAIT + Travel.ZEPPELIN_WAIT_MAX }
                if not best or o.cost < best.cost then best = o end
            end
        end
    end
    return best
end

--- Best leg between two points: walking, a flight, or a zeppelin. Between continents a zeppelin
--- is the way there. On one continent it's only taken when it beats walking even if you just
--- missed it (ZEPPELIN_WAIT_MAX), and beats the best walk or flight on average.
--- Returns cost, mode ("walk"/"fly"/"zeppelin"), from, to (nodes or towers), airSeconds.
function Travel.Leg(net, a, b)
    local best, mode, from, to, air = airLeg(net, a, b)
    if not (a and b and net.zeppelins and net.zeppelins[1]) then return best, mode, from, to, air end
    local sameCont = a.cont == b.cont
    -- a zeppelin can't beat a walk shorter than a missed departure and the ride
    if sameCont and best <= Travel.ZEPPELIN_WAIT_MAX + Travel.ZEPPELIN_RIDE then return best, mode, from, to, air end
    local z = Travel.ZeppelinOption(net, a, b)
    if not z then return best, mode, from, to, air end
    if not sameCont then return z.cost, "zeppelin", z.from, z.to, z.air end
    local walking = walk(net, a, b)
    if z.worst <= walking - Travel.MIN_FLY_SAVING and z.cost < best then
        return z.cost, "zeppelin", z.from, z.to, z.air
    end
    return best, mode, from, to, air
end

--- Every way from a to b, to show you the choice: walking, the fastest flight and the best
--- zeppelin (even ones the planner wouldn't take). Returns { pick = "walk"|"fly"|"zeppelin",
--- walk = seconds, walkable = same continent, fly = option or nil, zeppelin = option or nil },
--- option = { from, to, active, air, total }. `pick` and its option follow Leg's rules (in-air
--- time counts as AFK, no detours).
function Travel.Options(net, a, b)
    local out = { walk = walk(net, a, b), pick = "walk", walkable = a and b and a.cont == b.cont or false }
    if not a or not b then return out end
    local _, mode, from, to = Travel.Leg(net, a, b)
    out.zeppelin = Travel.ZeppelinOption(net, a, b)
    if mode == "zeppelin" then out.pick = "zeppelin" end
    if a.cont ~= b.cont then return out end
    local function option(f1, f2)
        local active = walk(net, a, f1.point) + Travel.FLY_OVERHEAD + walk(net, f2.point, b)
        local inAir = airTime(f1, f2)
        return { from = f1, to = f2, active = active, air = inAir, total = active + inAir }
    end
    if mode == "fly" then
        out.pick, out.fly = "fly", option(from, to)
        return out
    end
    for _, f1 in ipairs(nearestKnown(net, a, 3)) do
        for _, f2 in ipairs(nearestKnown(net, b, 3)) do
            if f1 ~= f2 then
                local o = option(f1, f2)
                if not out.fly or o.total < out.fly.total then out.fly = o end
            end
        end
    end
    return out
end

--- Memoized cost function for the planner.
function Travel.NewCost(net)
    local cache = setmetatable({}, { __mode = "k" })
    local hasFlights = (net.zeppelins ~= nil and net.zeppelins[1] ~= nil)
    for _, n in ipairs(net.nodes or {}) do if n.known then hasFlights = true break end end
    return function(a, b)
        if not a or not b then return 0 end
        if not hasFlights then return walk(net, a, b) end
        local row = cache[a]
        if not row then row = setmetatable({}, { __mode = "k" }); cache[a] = row end
        local c = row[b]
        if not c then
            c = Travel.Leg(net, a, b)
            row[b] = c
        end
        return c
    end
end

---------------------------------------------------------------------------
-- Hearthstone: where along the route to use it (weighted interval scheduling)
---------------------------------------------------------------------------
--- Returns { uses = { [stepIndex] = saving }, saving = total }.
--- `bindFrom` = first step index at which net.bind is valid (after a planned rebind);
--- legs before it hearth to `bindBefore` (the current inn), if any.
function Travel.PlanHearth(steps, start, net, cost, bindFrom, bindBefore)
    local result = { uses = {}, saving = 0 }
    if not net.hasHearth or not (net.bind or bindBefore) then return result end
    cost = cost or function(a, b) return walk(net, a, b) end
    bindFrom = bindFrom or 1
    local legs, t, pos = {}, 0, start
    for i, step in ipairs(steps) do
        if step.loc then
            local legCost = cost(pos, step.loc)
            local bindPoint = (i >= bindFrom) and net.bind or bindBefore
            if bindPoint then
                local hearthCost = Travel.HEARTH_OVERHEAD + cost(bindPoint, step.loc)
                local saving = legCost - hearthCost
                if saving >= Travel.MIN_HEARTH_SAVING and t >= (net.hearthReadyIn or 0) then
                    legs[#legs + 1] = { step = i, time = t, saving = saving }
                end
            end
            t = t + legCost
            pos = step.loc
        end
        t = t + (step.est or 0)
    end
    -- DP over legs sorted by time: best[i] = max(skip, take + best[last compatible])
    local cd = net.hearthCooldown or 3600
    local n = #legs
    local best, take = { [0] = 0 }, {}
    local prev = {}
    for i = 1, n do
        local p = 0
        for j = i - 1, 1, -1 do
            if legs[j].time <= legs[i].time - cd then p = j break end
        end
        prev[i] = p
        local with = legs[i].saving + best[p]
        if with > best[i - 1] then best[i], take[i] = with, true else best[i], take[i] = best[i - 1], false end
    end
    local i = n
    while i > 0 do
        if take[i] then
            result.uses[legs[i].step] = legs[i].saving
            i = prev[i]
        else
            i = i - 1
        end
    end
    result.saving = best[n] or 0
    return result
end

---------------------------------------------------------------------------
-- Hearth-aware route: split the route at the best point, hearth, and re-plan the rest
-- from the inn. Only recommended when it saves a lot AND either the area is finished
-- (dead end) or about a full cooldown of steps follows.
---------------------------------------------------------------------------
local function located(order, from)
    for j = from, #order do if order[j].loc then return order[j].loc end end
    return nil
end

local function sumEst(list, from, to)
    local e = 0
    for i = from or 1, to or #list do e = e + (list[i].est or 0) end
    return e
end

local function logDelta(t)
    if t.kind == "pickup" then return 1 elseif t.kind == "turnin" then return -1 end
    return 0
end

--- order: solved task list. opts: logCount, logMax, minK (earliest split), depth.
--- Returns { order, uses = { {task, gain, reason} }, saving } or nil, reason.
function Travel.HearthAware(order, start, net, cost, opts)
    opts = opts or {}
    local depth = opts.depth or 1
    local Planner = ns.Planner
    if depth > 2 or not net.hasHearth or not net.bind or #order < 3 then return nil, "no hearth" end
    local prevFn = Planner.travelFn
    Planner.travelFn = cost
    local baseline = Planner.RouteCost(order, start)

    -- timeline of the current route
    local times, t, pos = {}, 0, start
    for i, task in ipairs(order) do
        if task.loc then t = t + cost(pos, task.loc); pos = task.loc end
        t = t + (task.est or 0)
        times[i] = t
    end

    -- candidate split points: big immediate saving, or nothing left nearby (dead end)
    local cands = {}
    for k = math.max(opts.minK or 1, 1), #order - 1 do
        local here = order[k].loc
        if here and times[k] >= (net.hearthReadyIn or 0) then
            local nextLoc = located(order, k + 1)
            local quick = nextLoc and (cost(here, nextLoc) - (Travel.HEARTH_OVERHEAD + cost(net.bind, nextLoc))) or -math.huge
            local nearest = math.huge
            for j = k + 1, #order do
                local l = order[j].loc
                if l then
                    local c = cost(here, l)
                    if c < nearest then nearest = c end
                end
            end
            -- a quick trip home to turn in: the next stop has turn-ins right by your inn, and
            -- getting there any other way takes more than FAST_RETURN_SECONDS
            local fast = false
            if nextLoc and cost(here, nextLoc) > Travel.FAST_RETURN_SECONDS
                and cost(net.bind, nextLoc) <= Travel.HEARTH_NEAR_SECONDS then
                for j = k + 1, #order do
                    local l = order[j].loc
                    if l then
                        local dist = Geo.Distance(l, nextLoc)
                        if not dist or dist > Planner.GROUP_RADIUS then break end
                        if order[j].kind == "turnin" then fast = true break end
                    end
                end
            end
            cands[#cands + 1] = { k = k, quick = quick, deadEnd = nearest, fast = fast }
        end
    end
    local picked, seen = {}, {}
    local function take(list, n)
        for i = 1, math.min(n, #list) do
            if not seen[list[i].k] then seen[list[i].k] = true; picked[#picked + 1] = list[i] end
        end
    end
    table.sort(cands, function(x, y) return x.quick > y.quick end)
    take(cands, 4)
    table.sort(cands, function(x, y) return x.deadEnd > y.deadEnd end)
    take(cands, 3)
    local fastOnes = {}
    for _, c in ipairs(cands) do if c.fast then fastOnes[#fastOnes + 1] = c end end
    table.sort(fastOnes, function(x, y) return x.k < y.k end) -- the first trip home first
    take(fastOnes, 3)

    local function solveRest(k, passes)
        local predone, logCount, turnins = {}, opts.logCount or 0, 0
        for i = 1, k do
            predone[order[i].id] = true
            logCount = logCount + logDelta(order[i])
            if order[i].kind == "turnin" then turnins = turnins + (order[i].xpWeight or 1) end
        end
        local rest = {}
        for i = k + 1, #order do rest[#rest + 1] = order[i] end
        local saved = Planner.IMPROVE_PASSES
        Planner.IMPROVE_PASSES = passes
        local restOrder = Planner.Solve(rest, nil, net.bind, { logCount = logCount, logMax = opts.logMax or 20,
                                                              predone = predone, turninsBefore = turnins })
        Planner.IMPROVE_PASSES = saved
        return restOrder, #rest, logCount
    end

    local best, rejected
    local quick = opts.quick -- comparing inns: greedy-only candidates, no polish, no second hearth
    for _, c in ipairs(picked) do
        local restOrder, n = solveRest(c.k, quick and 0 or 1)
        if #restOrder == n then
            local prefixCost = 0
            local p = start
            for i = 1, c.k do
                local task = order[i]
                if task.teleport then prefixCost = prefixCost + (task.teleportCost or 0)
                elseif task.loc then prefixCost = prefixCost + cost(p, task.loc) end
                if task.loc then p = task.loc end
            end
            local restCost = Planner.RouteCost(restOrder, net.bind)
            local gain = baseline - (prefixCost + Travel.HEARTH_OVERHEAD + restCost)
            -- Your rules, per candidate: a big saving AND (area finished OR ~an hour of steps after),
            -- or a quick trip home to turn-ins right by the inn that still saves 2+ minutes.
            local large = gain >= math.max(Travel.HEARTH_MIN_GAIN, Travel.HEARTH_MIN_FRACTION * baseline)
            local dead = c.deadEnd >= Travel.DEAD_END_SECONDS
            local covered = (restCost + sumEst(restOrder)) >= (net.hearthCooldown or 3600) * Travel.COOLDOWN_CONTENT
            local fastReturn = c.fast and gain >= Travel.FAST_RETURN_MIN_GAIN
            if (large and (dead or covered)) or fastReturn then
                local reason = (large and dead and "area done") or (large and covered and "cooldown") or "fast return"
                -- near-ties go to the hearth that leaves a finished area (it uses the cooldown better)
                local score = gain + ((reason ~= "fast return") and Travel.HEARTH_RULE_PREFERENCE or 0)
                if not best or score > best.score then
                    best = { k = c.k, gain = gain, score = score, deadEnd = c.deadEnd, prefixCost = prefixCost,
                             restOrder = restOrder, reason = reason }
                end
            elseif not rejected or gain > rejected.gain then
                rejected = { gain = gain, why = (not large) and "saving too small" or "would waste the cooldown" }
            end
        end
        if ns.MaybeYield then ns.MaybeYield(1) end
    end
    if not best then
        Planner.travelFn = prevFn
        return nil, rejected and rejected.why or "no split"
    end

    -- polish the chosen split with the full improver
    local restOrder, logAfter
    if quick then
        restOrder = best.restOrder
        logAfter = opts.logCount or 0
    else
        restOrder, _, logAfter = solveRest(best.k, Planner.IMPROVE_PASSES)
    end
    local restCost = Planner.RouteCost(restOrder, net.bind)
    best.gain = baseline - (best.prefixCost + Travel.HEARTH_OVERHEAD + restCost)
    local restTime = restCost + sumEst(restOrder)
    Planner.travelFn = prevFn
    local reason = best.reason
    local hearthTask = {
        id = "V:hearth" .. depth, kind = "visit", visit = "hearth", loc = net.bind,
        teleport = true, teleportCost = Travel.HEARTH_OVERHEAD, est = Travel.HEARTH_OVERHEAD,
        deps = {}, solo = true, saving = best.gain, reason = reason, bindName = net.bindName,
        label = "Use your Hearthstone",
    }
    local uses = { { task = hearthTask, gain = best.gain, reason = reason } }
    local tail = restOrder
    -- a second hearth later in a long plan, once the cooldown is back
    local laterNet = setmetatable({ hearthReadyIn = (net.hearthCooldown or 3600) - Travel.HEARTH_OVERHEAD }, { __index = net })
    local second = (not quick) and Travel.HearthAware(restOrder, net.bind, laterNet, cost,
        { logCount = logAfter, logMax = opts.logMax, depth = depth + 1 }) or nil
    if second then
        tail = second.order
        for _, u in ipairs(second.uses) do uses[#uses + 1] = u end
    end
    local out = {}
    for i = 1, best.k do out[#out + 1] = order[i] end
    out[#out + 1] = hearthTask
    for _, task in ipairs(tail) do out[#out + 1] = task end
    local saving = 0
    for _, u in ipairs(uses) do saving = saving + u.gain end
    return { order = out, uses = uses, saving = saving, restTime = restTime }
end

---------------------------------------------------------------------------
-- Insertion helpers (for stops that are not quests: inns, flight masters)
---------------------------------------------------------------------------
--- Cheapest position to insert a stop at `point` into the step list.
--- Returns index (insert before steps[index]; #steps+1 = append), detour seconds.
--- Detour (seconds) of inserting a stop at `point` before steps[k], for every k.
local function insertionDetours(steps, start, point, cost, maxK)
    local out = {}
    local prev = start
    for k = 1, math.min(#steps + 1, maxK or (#steps + 1)) do
        local nextLoc
        for j = k, #steps do
            if steps[j].loc then nextLoc = steps[j].loc break end
        end
        out[k] = cost(prev, point) + (nextLoc and (cost(point, nextLoc) - cost(prev, nextLoc)) or 0)
        if steps[k] and steps[k].loc then prev = steps[k].loc end
    end
    return out
end

Travel.InsertionDetours = insertionDetours

function Travel.CheapestInsertion(steps, start, point, cost)
    local bestK, bestDetour
    for k, detour in ipairs(insertionDetours(steps, start, point, cost)) do
        if not bestDetour or detour < bestDetour then bestK, bestDetour = k, detour end
    end
    return bestK or 1, bestDetour or 0
end

local function withInserted(steps, k, stop)
    local out = {}
    for i = 1, k - 1 do out[#out + 1] = steps[i] end
    out[#out + 1] = stop
    for i = k, #steps do out[#out + 1] = steps[i] end
    return out
end
Travel.WithInserted = withInserted

--- Should the player bind at one of `inns` ({ {name, npcName, point} })? Returns the best
--- { inn, index, detour, gain, saving } or nil. Compares against the current bind.
function Travel.SuggestBind(steps, start, net, cost, inns)
    if not net.hasHearth or not inns or #inns == 0 then return nil end
    local base = Travel.PlanHearth(steps, start, net, cost).saving
    local best
    for _, inn in ipairs(inns) do
        local isCurrent = net.bind ~= nil and (Geo.Distance(net.bind, inn.point) or math.huge) <= 60
        if not isCurrent then
            -- Binding early leaves more legs to hearth on; binding where it's cheap may leave none.
            -- Try every position in the first 30 steps and keep the best net gain.
            local trialNet = setmetatable({ bind = inn.point }, { __index = net })
            for k, detour in ipairs(insertionDetours(steps, start, inn.point, cost, 31)) do
                local trial = withInserted(steps, k, { loc = inn.point, est = 20, isStop = true })
                -- legs before the stop still hearth to the current inn (one cooldown-aware plan)
                local saving = Travel.PlanHearth(trial, start, trialNet, cost, k + 1, net.bind).saving
                local gain = saving - detour - base
                if gain >= Travel.BIND_MIN_GAIN and (not best or gain > best.gain) then
                    best = { inn = inn, index = k, detour = detour, gain = gain, saving = saving }
                end
            end
        end
    end
    return best
end

--- Unknown flight paths that cost at most `maxDetour` seconds to grab on the way.
function Travel.SuggestDiscoveries(steps, start, net, cost, maxDetour, exclude)
    local out = {}
    for _, node in ipairs(net.nodes or {}) do
        if not node.known and not (exclude and exclude[node]) and node.point and start and node.point.cont == start.cont then
            local k, detour = Travel.CheapestInsertion(steps, start, node.point, cost)
            if detour <= (maxDetour or Travel.DISCOVER_MAX_DETOUR) then
                out[#out + 1] = { node = node, index = k, detour = detour }
            end
        end
    end
    table.sort(out, function(a, b) return a.detour < b.detour end)
    return out
end

--- Fills step.travel = { mode = "fly"|"hearth", ... } for each step.
function Travel.AnnotateSteps(steps, start, net)
    local pos = start
    for _, step in ipairs(steps) do
        step.travel = nil
        local first = step.tasks and step.tasks[1]
        if first and first.visit == "hearth" then
            step.travel = { mode = "hearth", saving = first.saving, reason = first.reason, bindName = first.bindName }
        elseif step.loc and pos then
            local _, mode, from, to, air = Travel.Leg(net, pos, step.loc)
            if mode == "fly" or mode == "zeppelin" then
                step.travel = { mode = mode, from = from, to = to, air = air }
            end
        end
        if step.loc then pos = step.loc end
    end
end

---------------------------------------------------------------------------
-- Reading the game
---------------------------------------------------------------------------
--- The continent UiMap containing mapId (Kalimdor / Eastern Kingdoms on Forever).
function Travel.ContinentMap(mapId)
    if not (C_Map and C_Map.GetMapInfo) then return nil end
    local continentType = (Enum and Enum.UIMapType and Enum.UIMapType.Continent) or 2
    local guard = 0
    while mapId and guard < 8 do
        local info = C_Map.GetMapInfo(mapId)
        if not info then return nil end
        if info.mapType == continentType then return mapId end
        mapId = info.parentMapID
        guard = guard + 1
    end
    return nil
end

local function factionOk(nodeFaction, playerFaction)
    local E = Enum and Enum.FlightPathFaction
    if not E or nodeFaction == nil then return true end
    if nodeFaction == E.Neutral then return true end
    return nodeFaction == E[playerFaction or ""]
end

local function hearthState()
    local has = (C_Item and C_Item.GetItemCount and (C_Item.GetItemCount(Travel.HEARTHSTONE) or 0) > 0) or false
    local readyIn, duration = 0, nil
    local cdFn = (C_Container and C_Container.GetItemCooldown) or (C_Item and C_Item.GetItemCooldown)
    if cdFn then
        local ok, start, dur = pcall(cdFn, Travel.HEARTHSTONE)
        if ok and type(start) == "number" and type(dur) == "number" and dur > 1.5 and start > 0 then
            readyIn = math.max(0, start + dur - (GetTime and GetTime() or 0))
            duration = dur
        end
    end
    return has, readyIn, duration
end
Travel.HearthState = hearthState

function Travel.BuildNetwork(player)
    local net = { nodes = {}, speed = Geo.RUN_SPEED }
    if player.skills and player.skills[Travel.RIDING_SKILL] then
        net.speed = Geo.RUN_SPEED * Travel.MOUNT_FACTOR
        net.mounted = true
    end
    -- Flight paths: the game's own list (known and undiscovered) for this continent.
    local contMap = player.point and Travel.ContinentMap(player.point.mapId)
    if contMap and C_TaxiMap and C_TaxiMap.GetTaxiNodesForMap then
        local ok, list = pcall(C_TaxiMap.GetTaxiNodesForMap, contMap)
        if ok and type(list) == "table" then
            for _, info in ipairs(list) do
                local pos = info.position
                local x, y = pos and (pos.x or (pos.GetXY and select(1, pos:GetXY()))), pos and (pos.y or (pos.GetXY and select(2, pos:GetXY())))
                if x and y and factionOk(info.faction, player.faction) then
                    local point = Geo.Point(contMap, x, y)
                    if point then
                        -- Forever reports isUndiscovered = false for every node (even the other
                        -- faction's), so only paths seen as reachable on a flight map count as known.
                        local learned = ns.charDB.flightPaths
                        local known = (learned ~= nil and info.name ~= nil and learned[info.name] == true)
                        net.nodes[#net.nodes + 1] = { name = info.name, point = point, known = known, nodeID = info.nodeID }
                    end
                end
            end
        end
    end
    -- Fallback: QuestieDB flight masters + nodes seen at a flight master this session.
    if #net.nodes == 0 and Data.flightMasters then
        for _, fm in ipairs(Data.flightMasters) do
            local known = ns.charDB.knownTaxiNpc and ns.charDB.knownTaxiNpc[fm.npcId] or false
            net.nodes[#net.nodes + 1] = { name = fm.name, point = fm.point, known = known, npcId = fm.npcId }
        end
    end
    -- Zeppelins (from QuestieDB's zeppelin masters; nothing when the layout can't be paired)
    net.zeppelins, net.towers, net.zeppelinWhy = Travel.ZeppelinLinks(Data.transportMasters)
    -- Hearthstone
    net.hasHearth, net.hearthReadyIn, net.hearthCooldown = hearthState()
    net.hearthCooldown = net.hearthCooldown or ns.charDB.hearthCooldown or 3600
    net.bindName = GetBindLocation and GetBindLocation() or nil
    local binds = ns.charDB.bindPoints or {}
    local saved = net.bindName and binds[net.bindName]
    if saved and saved.mapId then net.bind = Geo.Point(saved.mapId, saved.x, saved.y) end
    return net
end

---------------------------------------------------------------------------
-- Learning bind points, known flight paths and the hearth cooldown
---------------------------------------------------------------------------
local function rememberBindHere()
    local name = GetBindLocation and GetBindLocation()
    local here = Geo.PlayerPoint()
    if not name or not here then return end
    ns.charDB.bindPoints = ns.charDB.bindPoints or {}
    ns.charDB.bindPoints[name] = { mapId = here.mapId, x = here.x, y = here.y }
end
Travel.RememberBindHere = rememberBindHere

local lastBind
ns.RegisterEvent("PLAYER_ENTERING_WORLD", function() lastBind = GetBindLocation and GetBindLocation() end)
ns.RegisterEvent("CHAT_MSG_SYSTEM", function()
    local now = GetBindLocation and GetBindLocation()
    if now and lastBind and now ~= lastBind then
        rememberBindHere() -- you are standing at the innkeeper you just bound to
        ns.Fire("REQUEST_REPLAN", "bind changed")
    end
    lastBind = now
end)

ns.RegisterEvent("UNIT_SPELLCAST_SUCCEEDED", function(_, unit, _, spellId)
    if unit ~= "player" or spellId ~= Travel.HEARTH_SPELL then return end
    local plan = ns.Ladder and ns.Ladder.plan
    if plan then
        for _, t in ipairs(plan.order or {}) do
            if t.visit == "hearth" and not t.done then t.done = true break end
        end
    end
    -- After the loading screen we are at the inn: learn it if unknown, and the cooldown.
    local function learn()
        local name = GetBindLocation and GetBindLocation()
        local binds = ns.charDB.bindPoints or {}
        if name and not binds[name] then rememberBindHere() end
        local _, _, duration = hearthState()
        if duration then ns.charDB.hearthCooldown = duration end
        ns.Fire("REQUEST_REPLAN", "hearthed")
    end
    if C_Timer and C_Timer.After then C_Timer.After(4, learn) else learn() end
end)

--- Flight paths you can fly to from the open flight map, plus the one you're standing at.
--- The map also lists paths you haven't discovered, so only "CURRENT"/"REACHABLE" nodes count.
local KNOWN_TAXI_TYPE = { CURRENT = true, REACHABLE = true }

function Travel.ReadOpenTaxiMap()
    local known = {}
    if NumTaxiNodes and TaxiNodeName and TaxiNodeGetType then
        local okN, n = pcall(NumTaxiNodes)
        if okN and not ns.IsSecret(n) and type(n) == "number" then
            for i = 1, n do
                local okName, name = pcall(TaxiNodeName, i)
                local okType, kind = pcall(TaxiNodeGetType, i)
                if okName and okType and not ns.AnySecret(name, kind) and name and KNOWN_TAXI_TYPE[kind] then
                    known[name] = true
                end
            end
        end
    end
    -- Mainline-style fallback: node states on the open taxi map.
    local S = Enum and Enum.FlightPathState
    if next(known) == nil and S and C_TaxiMap and C_TaxiMap.GetAllTaxiNodes and GetTaxiMapID then
        local okMap, mapId = pcall(GetTaxiMapID)
        if okMap and not ns.IsSecret(mapId) and mapId then
            local okList, list = pcall(C_TaxiMap.GetAllTaxiNodes, mapId)
            if okList and not ns.IsSecret(list) and type(list) == "table" then
                for _, node in ipairs(list) do
                    local state, name = node.state, node.name
                    if not ns.AnySecret(state, name) and name and (state == S.Current or state == S.Reachable) then
                        known[name] = true
                    end
                end
            end
        end
    end
    return known
end

ns.RegisterEvent("TAXIMAP_OPENED", function()
    -- Learned paths only ever get added: a path you know can't be forgotten.
    -- (The older `knownTaxi` table listed every node on the map, so it is no longer read.)
    local known = Travel.ReadOpenTaxiMap()
    if next(known) then
        ns.charDB.flightPaths = ns.charDB.flightPaths or {}
        for name in pairs(known) do ns.charDB.flightPaths[name] = true end
    end
    local okG, npc = pcall(UnitGUID, "npc")
    if okG and not ns.IsSecret(npc) and type(npc) == "string" then
        -- select() returns every field from the 6th on; the extra parentheses keep only the
        -- NPC ID, so tonumber doesn't take the spawn UID as its number base.
        local npcId = tonumber((select(6, strsplit("-", npc))))
        if npcId then
            ns.charDB.knownTaxiNpc = ns.charDB.knownTaxiNpc or {}
            ns.charDB.knownTaxiNpc[npcId] = true
        end
    end
    ns.Fire("TAXI_LEARNED")
end)
