-- Replay a saved Quest Ladder plan offline with the add-on's own planner and cost model.
-- Usage: cd tests && lua5.1 replay.lua <path to WTF\Account\<account>\SavedVariables\QuestLadder.lua> [runIndex]
-- Needs a /ladder diag run from 0.3.8 or later (it saves the route as replay data).
package.path = "./?.lua;" .. package.path
local M = require("mock")
M.installGlobals()
M.player = { level = 14, classFile = "PALADIN", className = "Paladin", money = 0, mapId = 1, x = 0, y = 0 }
M.log, M.completed, M.rewards, M.bag, M.equipped, M.items = {}, {}, {}, {}, {}, {}
local ns = M.loadAddon("..", { "Core.lua", "Geo.lua", "Data.lua", "QuestState.lua", "Planner.lua", "Travel.lua" })
local P, T = ns.Planner, ns.Travel

-- load the SavedVariables file as data
local chunk = assert(loadfile(arg[1]))
local env = {}
setfenv(chunk, env)
chunk()
local runs = env.QuestLadderDiag.runs
local run = runs[tonumber(arg[2] or #runs)]
local replay
for _, c in ipairs(run.checks) do if c.id == "plan" then replay = c.data.replay end end
assert(replay, "no replay data in that run")

local function split(s, sep)
    local out = {}
    for part in (s .. sep):gmatch("(.-)" .. sep:gsub("%p", "%%%0")) do out[#out + 1] = part end
    return out
end
local function point(cont, x, y)
    if cont == "-" then return nil end
    return { cont = tonumber(cont), wx = tonumber(x), wy = tonumber(y) }
end
local s = split(replay.start, "|")
local start = point(s[1], s[2], s[3])

local tasks, byId = {}, {}
for _, line in ipairs(replay.tasks) do
    local f = split(line, "|")
    local t = { id = f[1], kind = f[2], deps = {}, loc = point(f[4], f[5], f[6]), est = tonumber(f[7]) or 0 }
    if f[3] ~= "" then for _, d in ipairs(split(f[3], ",")) do t.deps[#t.deps + 1] = d end end
    local flags = f[8] or ""
    t.deferred = flags:find("d", 1, true) == 1 or nil
    t.teleport = flags:find("t", 1, true) and true or nil
    t.mobLevel = tonumber(f[9] or "")    -- 0.3.15+
    t.xpWeight = tonumber(f[10] or "")
    tasks[#tasks + 1] = t
    byId[t.id] = t
end
for _, t in ipairs(tasks) do t.dependents = {} end
for _, t in ipairs(tasks) do
    for _, d in ipairs(t.deps) do if byId[d] then byId[d].dependents[#byId[d].dependents + 1] = t.id end end
end
P.ApplyLevelGates(tasks, byId, replay.level, replay.xpFrac)
local net = { speed = replay.speed or 7, nodes = {} }
for _, line in ipairs(replay.nodes) do
    local f = split(line, "|")
    net.nodes[#net.nodes + 1] = { name = f[1], point = point(f[2], f[3], f[4]), known = f[5] == "known" }
end
local opts = { logCount = replay.logCount or 0, logMax = replay.logMax or 40 }

local function costFn(afk)
    local saved = T.AFK_WEIGHT
    T.AFK_WEIGHT = afk
    local fn = T.NewCost(net)
    return function(a, b) T.AFK_WEIGHT = afk; local c = fn(a, b); T.AFK_WEIGHT = saved; return c end
end
local planCost = costFn(T.AFK_WEIGHT)       -- what the planner optimizes (flights at AFK weight)
local realCost = costFn(1.0)                -- wall-clock: a minute in the air is a minute

local function route(order, fn)
    P.travelFn = fn
    return P.RouteCost(order, start)
end
local function ids(order)
    local out = {}
    for _, t in ipairs(order) do out[#out + 1] = t.id end
    return table.concat(out, " ")
end
local function report(label, order)
    print(string.format("%-34s valid=%-5s plan-cost=%6.0f s  real-time=%6.0f s",
        label, tostring(P.IsValid(order, opts)), route(order, planCost), route(order, realCost)))
end

-- 1) the order the add-on planned in game
local planned = {}
for i, t in ipairs(tasks) do planned[i] = t end
report("as planned in game", planned)

-- 2) the leg-by-leg picture of the first 26 tasks
P.travelFn = planCost
local pos = start
print("\nleg                         yd      cost  mode")
for i = 1, math.min(26, #planned) do
    local t = planned[i]
    if t.loc then
        local c, mode = T.Leg(net, pos, t.loc)
        local yd = ns.Geo.Distance(pos, t.loc) or 0
        print(string.format("%2d %-22s %6.0f %8.1f  %s", i, t.id, yd, c, mode))
        pos = t.loc
    end
end

-- 3) hand-made alternative: Dalaran Crate + Podrig after the north-Silverpine sweep
local function moveAfter(order, idsToMove, afterId)
    local moving, rest = {}, {}
    local set = {}
    for _, id in ipairs(idsToMove) do set[id] = true end
    for _, t in ipairs(order) do if set[t.id] then moving[#moving + 1] = t else rest[#rest + 1] = t end end
    local out = {}
    for _, t in ipairs(rest) do
        out[#out + 1] = t
        if t.id == afterId then for _, m in ipairs(moving) do out[#out + 1] = m end end
    end
    return out
end
print("")
report("crate+Podrig after O447:2", moveAfter(planned, { "T477", "P478", "T6324" }, "O447:2"))

-- 4) re-solve from scratch with the current planner
P.travelFn = planCost
local fresh = {}
for i, t in ipairs(tasks) do fresh[i] = t end
local solved = P.Solve(fresh, byId, start, opts)
report("re-solved (plan cost)", solved)
print("  " .. ids(solved))
-- 5) and if flights counted at full time
P.travelFn = realCost
local fresh2 = {}
for i, t in ipairs(tasks) do fresh2[i] = t end
local solvedReal = P.Solve(fresh2, byId, start, opts)
report("re-solved (flights at full time)", solvedReal)
print("  " .. ids(solvedReal))

-- 6) does a wider search find the better order? (improvement passes, Or-opt block size)
print("\nsearch settings                plan-cost  real-time  solve time")
local savedPasses, savedSeg = P.IMPROVE_PASSES, P.MAX_SEGMENT
for _, cfg in ipairs({ { 4, 4 }, { 10, 4 }, { 10, 6 }, { 20, 8 } }) do
    P.IMPROVE_PASSES, P.MAX_SEGMENT = cfg[1], cfg[2]
    P.travelFn = planCost
    local list = {}
    for i, t in ipairs(tasks) do list[i] = t end
    local t0 = os.clock()
    local o = P.Solve(list, byId, start, opts)
    local dt = os.clock() - t0
    print(string.format("passes=%2d max block=%d      %6.0f s   %6.0f s   %.2f s", cfg[1], cfg[2],
        route(o, planCost), route(o, realCost), dt))
end
P.IMPROVE_PASSES, P.MAX_SEGMENT = savedPasses, savedSeg

-- 7) the route the current planner settings produce, stop by stop (yards from you, mode)
print("\ncurrent settings: route by leg")
P.travelFn = planCost
local list = {}
for i, t in ipairs(tasks) do list[i] = t end
local o = P.Solve(list, byId, start, opts)
local here, prev = start, start
for i, t in ipairs(o) do
    if t.loc then
        local _, mode = T.Leg(net, prev, t.loc)
        print(string.format("%2d %-10s %5.0f yd from you  %s", i, t.id, ns.Geo.Distance(here, t.loc) or -1, mode == "fly" and "FLY" or ""))
        prev = t.loc
    end
end
