package.path = "./?.lua;" .. package.path
local M = require("mock")
M.installGlobals()
M.player = { level = 10, classFile = "WARRIOR", money = 0, mapId = 1429, x = 0.5, y = 0.5 }
local ns = M.loadAddon("..", { "Core.lua", "Geo.lua", "Data.lua", "QuestState.lua", "Planner.lua" })
ns.Geo.SetTransform(1429, { cont = 0, ox = 0, oy = 0, ax = 3000, ay = 0, bx = 0, by = 2000 })
local P, Geo = ns.Planner, ns.Geo
math.randomseed(3)
local function rp() return Geo.Point(1429, math.random(), math.random()) end
local active, cands = {}, {}
for i = 1, 20 do
  local objs = {}
  for k = 1, 2 do objs[k] = { index = k, type = "monster", need = 5, have = 0, loc = rp() } end
  active[i] = { id = i, objectives = objs, turnin = rp() }
end
for i = 1, 12 do
  local objs = {}
  for k = 1, 2 do objs[k] = { index = k, type = "item", itemId = 9000 + i * 10 + k, need = 3, have = 0, loc = rp() } end
  cands[i] = { id = 100 + i, pickup = rp(), objectives = objs, turnin = rp(), candidate = true }
end
local tasks, byId = P.BuildTasks({ active = active, candidates = cands })
local t0 = os.clock()
P.IMPROVE_PASSES = 0
local start0 = rp()
local g = P.Solve(tasks, byId, start0, { logCount = 20, logMax = 40 })
local t1 = os.clock()
local tasks2, byId2 = P.BuildTasks({ active = active, candidates = cands })
P.IMPROVE_PASSES = 4
local start = start0
local g2 = P.Solve(tasks2, byId2, start, { logCount = 20, logMax = 40 })
local t2 = os.clock()
print(string.format("tasks=%d greedy=%.3fs full=%.3fs", #tasks, t1 - t0, t2 - t1))
print(string.format("greedy cost=%.0fs improved cost=%.0fs (%.0f%% less walking)", P.RouteCost(g, start), P.RouteCost(g2, start), (1 - P.RouteCost(g2, start) / P.RouteCost(g, start)) * 100))
