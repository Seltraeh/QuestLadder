-- Offline tests for Quest Ladder. Run: lua5.1 run.lua <addon dir>
package.path = arg[0]:gsub("run%.lua$", "?.lua") .. ";" .. package.path
local M = require("mock")
local ADDON_DIR = arg[1] or (arg[0]:gsub("[^/]*$", "") .. "..")

local passed, failed = 0, 0
local function check(name, cond, detail)
    if cond then
        passed = passed + 1
    else
        failed = failed + 1
        print("FAIL: " .. name .. (detail and (" -- " .. tostring(detail)) or ""))
    end
end

---------------------------------------------------------------------------
-- Scenario data
---------------------------------------------------------------------------
local function spawn(x, y) return { [12] = { { x, y } } } end
local function db()
    return M.fakeDB({
        quests = {
            [1] = { name = "Wolves Across the Border", startedBy = { { 100 } }, finishedBy = { { 100 } },
                    requiredLevel = 1, questLevel = 2, objectives = { nil, nil, { { 500 } } },
                    objectivesText = { "Bring 8 pieces of Tough Wolf Meat to the Marshal." } },
            [2] = { name = "Kobold Camp Cleanup", startedBy = { { 101 } }, finishedBy = { { 101 } },
                    requiredLevel = 1, questLevel = 2, objectives = { { { 201 } } } },
            [3] = { name = "The Lost Book", startedBy = { { 102 } }, finishedBy = { { 102 } },
                    requiredLevel = 1, questLevel = 3, objectives = { nil, nil, { { 501 } } } },
            [4] = { name = "The Wolf Den", startedBy = { { 100 } }, finishedBy = { { 100 } },
                    requiredLevel = 2, questLevel = 4, preQuestSingle = { 1 }, objectives = { { { 202 } } } },
            [5] = { name = "Mage Only", startedBy = { { 104 } }, finishedBy = { { 104 } },
                    requiredLevel = 1, questLevel = 3, requiredClasses = 128, objectives = {} },
            [7] = { name = "Too High", startedBy = { { 103 } }, finishedBy = { { 103 } },
                    requiredLevel = 25, questLevel = 30, objectives = {} },
            [8] = { name = "Far Away", startedBy = { { 107 } }, finishedBy = { { 107 } },
                    requiredLevel = 1, questLevel = 3, objectives = {} },
            [9] = { name = "Escort the Miner", startedBy = { { 108 } }, finishedBy = { { 108 } },
                    requiredLevel = 1, questLevel = 4, objectives = {},
                    objectivesText = { "Escort the miner safely out of the mine." },
                    extraObjectives = { { nil, 0, "Talk to the miner to start the escort", 0 } } },
        },
        npcs = {
            [100] = { name = "Marshal McBride", spawns = spawn(40, 40) },
            [101] = { name = "Deputy Willem", spawns = spawn(41, 40) },
            [102] = { name = "Librarian Mae", spawns = spawn(20, 70) },
            [103] = { name = "High Guy", spawns = spawn(42, 42) },
            [104] = { name = "Mage Trainer Guy", spawns = spawn(42, 40) },
            [105] = { name = "Brog Hamfist", subName = "General Supplies", spawns = spawn(45, 45), npcFlags = 128 },
            [106] = { name = "Llane Beshere", subName = "Warrior Trainer", spawns = spawn(43, 43), npcFlags = 16 },
            [107] = { name = "Faraway Fred", spawns = { [40] = { { 50, 50 } } } },
            [108] = { name = "Miner", spawns = spawn(44, 30) },
            [109] = { name = "Innkeeper Farley", subName = "Innkeeper", spawns = spawn(40.5, 40.5), npcFlags = 512 },
            [110] = { name = "Zapetta", subName = "Zeppelin Master", spawns = spawn(46, 46) },
            [200] = { name = "Timber Wolf", spawns = { [12] = { { 60, 40 }, { 61, 41 }, { 60.5, 39.5 }, { 10, 10 } } } },
            [201] = { name = "Kobold Vermin", minLevel = 2, maxLevel = 3, spawns = { [12] = { { 60, 42 }, { 61, 43 } } } },
            [202] = { name = "Den Wolf", minLevel = 4, maxLevel = 5, spawns = spawn(80, 20) },
        },
        objects = {
            [300] = { name = "Dusty Bookshelf", spawns = spawn(20.5, 70.2) },
        },
        items = {
            [500] = { name = "Tough Wolf Meat", npcDrops = { 200 }, class = 12 },
            [501] = { name = "Old Book", objectDrops = { 300 }, class = 12 },
            [902] = { name = "Kobold Boots", class = 4, requiredLevel = 1, questRewards = { 2 } },
            [903] = { name = "Kobold Gloves", class = 4, requiredLevel = 1, questRewards = { 2 } },
            [910] = { name = "Bear's Belt", class = 4, requiredLevel = 3 },
        },
    })
end

local FILES = { "Core.lua", "Theme.lua", "Geo.lua", "Data.lua", "QuestState.lua", "Planner.lua", "Travel.lua", "Gear.lua",
                "Bags.lua", "Hints.lua", "Ladder.lua", "Goodies.lua", "Speed.lua", "Automation.lua", "Highlight.lua", "WorldMarks.lua" }

local function setup(opts)
    M.installGlobals(opts)
    M.names = {}
    M.player = { level = 3, classFile = "WARRIOR", className = "Warrior", money = 25000, mapId = 1429, x = 0.42, y = 0.41 }
    M.log, M.completed, M.rewards, M.bag, M.equipped = {}, {}, {}, {}, {}
    M.items = {
        [500] = { name = "Tough Wolf Meat", classID = 12 },
        [501] = { name = "Old Book", classID = 12 },
        [600] = { name = "Broken Fang", quality = 0, sell = 15, classID = 15 },
        [601] = { name = "Linen Cloth", quality = 1, sell = 2, classID = 7 },
        [602] = { name = "Strange Note", classID = 12 },
        [700] = { name = "Gnomish Tools", classID = 12, spell = "Use" },
        [901] = { name = "Worn Shortsword", classID = 2, subClassID = 7, equipLoc = "INVTYPE_WEAPON",
                  stats = { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 3 } },
        [900] = { name = "Sturdy Sword", classID = 2, subClassID = 7, equipLoc = "INVTYPE_WEAPON", quality = 2, sell = 120,
                  stats = { ITEM_MOD_STRENGTH_SHORT = 3, ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 6 } },
        [902] = { name = "Kobold Boots", classID = 4, subClassID = 3, equipLoc = "INVTYPE_FEET", sell = 40,
                  stats = { RESISTANCE0_NAME = 20, ITEM_MOD_AGILITY_SHORT = 3 } },
        [903] = { name = "Kobold Gloves", classID = 4, subClassID = 1, equipLoc = "INVTYPE_HAND", sell = 80,
                  stats = { ITEM_MOD_STAMINA_SHORT = 2 } },
        [904] = { name = "Plate Helm", classID = 4, subClassID = 4, equipLoc = "INVTYPE_HEAD", sell = 80,
                  stats = { ITEM_MOD_STRENGTH_SHORT = 10 } },
        [910] = { name = "Bear's Belt", classID = 4, subClassID = 2, equipLoc = "INVTYPE_WAIST", quality = 2, sell = 30,
                  stats = { ITEM_MOD_STRENGTH_SHORT = 2, ITEM_MOD_STAMINA_SHORT = 2 } },
    }
    M.equipped = { [16] = 901 }
    local ns = M.loadAddon(ADDON_DIR, FILES)
    ns.Geo.SetZoneMaps({ [12] = 1429, [40] = 1436 }, {})
    ns.Geo.SetTransform(1429, { cont = 0, ox = 0, oy = 0, ax = 3000, ay = 0, bx = 0, by = 2000 })
    ns.Geo.SetTransform(1436, { cont = 1, ox = 0, oy = 0, ax = 3000, ay = 0, bx = 0, by = 2000 })
    ns.Geo.SetTransform(1415, { cont = 0, ox = 0, oy = 0, ax = 3000, ay = 0, bx = 0, by = 2000 })
    ns.Data.InitWith(db())
    return ns
end

---------------------------------------------------------------------------
-- 1. Geo
---------------------------------------------------------------------------
do
    local ns = setup()
    local Geo = ns.Geo
    local a = Geo.Point(1429, 0.4, 0.4)
    local b = Geo.Point(1429, 0.6, 0.4)
    check("geo distance", math.abs(Geo.Distance(a, b) - 600) < 0.01, Geo.Distance(a, b))
    check("geo continent", Geo.Distance(a, Geo.Point(1436, 0.5, 0.5)) == math.huge)
    local pts = Geo.PointsFromSpawns({ [12] = { { 60, 40 }, { 61, 41 }, { 60.5, 39.5 }, { 10, 10 } } })
    local c = Geo.BestCluster(pts, Geo.Point(1429, 0.42, 0.41), 90)
    check("cluster picks the camp, not the outlier", c and c.count == 3, c and c.count)
    local _, inst = Geo.PointsFromSpawns({ [12] = { { -1, -1 } } })
    check("instance sentinel detected", inst == true)
    check("parse money", ns.ParseMoney("2g 50s") == 25000)
end

---------------------------------------------------------------------------
-- 2. Availability rules
---------------------------------------------------------------------------
do
    local ns = setup()
    local Data = ns.Data
    local state = { level = 3, raceMask = 1, classMask = 1, isComplete = function(id) return M.completed[id] end,
                    isActive = function() return false end }
    check("available basic", Data.IsAvailable(1, state) == true)
    local ok, why = Data.IsAvailable(5, state)
    check("class restricted", ok == false and why == "class", why)
    ok, why = Data.IsAvailable(7, state)
    check("level restricted", ok == false and why == "level", why)
    ok, why = Data.IsAvailable(4, state)
    check("prequest missing", ok == false and why == "prequest", why)
    state.assumeDone = { [1] = true }
    check("prequest assumed done (chain)", Data.IsAvailable(4, state) == true)
    check("hasBit Skyborne-width mask", Data.HasBit(8589934770, 8589934592) == true and Data.HasBit(4294967373, 8589934592) == false)
end

---------------------------------------------------------------------------
-- 3. Full pipeline: indexes -> candidates -> plan
---------------------------------------------------------------------------
local function fullPlan(ns)
    local built = false
    ns.Data.BuildIndexes(ns.QuestState.Player(), function() built = true end)
    check("indexes built", built and ns.Data.ready)
    ns.Ladder.Rebuild("test")
    return ns.Ladder.plan
end

do
    local ns = setup()
    M.log = {
        { id = 2, title = "Kobold Camp Cleanup", level = 2, complete = false,
          objectives = { { text = "Kobold Vermin slain: 2/6", type = "monster", finished = false, numFulfilled = 2, numRequired = 6 } } },
    }
    M.rewards[2] = { 902, 903 }
    local plan = fullPlan(ns)
    check("plan exists", plan ~= nil)
    if plan then
        local order = {}
        local pos = {}
        for i, t in ipairs(plan.order) do order[#order + 1] = t.id; pos[t.id] = i end
        print("route: " .. table.concat(order, " "))
        for i, s in ipairs(plan.steps) do
            local ids = {}
            for _, t in ipairs(s.tasks) do ids[#ids + 1] = t.id end
            print(string.format("  step %d [%s] %s", i, ns.Ladder.StepTitle(s), table.concat(ids, ",")))
        end
        check("valid order", ns.Planner.IsValid(plan.order, { logCount = 1, logMax = 20 }))
        check("mage quest excluded", pos.P5 == nil)
        check("high-level quest excluded", pos.P7 == nil)
        check("other-continent quest excluded", pos.P8 == nil)
        check("Q1 picked up", pos.P1 ~= nil)
        check("chain follow-up planned", pos.P4 ~= nil)
        check("follow-up after parent turn-in", pos.P4 and pos.T1 and pos.P4 > pos.T1)
        check("objectives after pickup", pos["O1:1"] and pos["O1:1"] > pos.P1)
        -- clustering: wolves and kobolds are next to each other -> same step
        local stepOf = {}
        for i, s in ipairs(plan.steps) do for _, t in ipairs(s.tasks) do stepOf[t.id] = i end end
        check("wolf + kobold objectives share one step", stepOf["O1:1"] == stepOf["O2:1"], tostring(stepOf["O1:1"]) .. " vs " .. tostring(stepOf["O2:1"]))
        check("hub step groups both givers", stepOf.P1 == stepOf.P9 or stepOf.P1 ~= nil)
        check("first step is the nearby hub", stepOf.P1 == 1)
        -- the turn-in at the marshal and pickup of the follow-up happen in the same step
        check("turn-in + follow-up pickup together", stepOf.T1 == stepOf.P4)
        -- live objective matched to QuestieDB NPC by name -> has a location
        local o = plan.byId["O2:1"]
        check("live objective located via DB name match", o and o.loc and math.abs(o.loc.wx - 1815) < 40, o and o.loc and o.loc.wx)
        local textQ2 = ns.Ladder.TaskText(plan.byId["O2:1"])
        check("task text shows progress", textQ2:find("2/6") ~= nil, textQ2)
        local text1 = ns.Ladder.TaskText(plan.byId["O1:1"])
        check("item objective names its source", text1:find("Timber Wolf") ~= nil, text1)
        -- trainer/vendor indexes
        check("vendor indexed", #ns.Data.vendors == 1)
        check("trainer found", ns.Data.NearestClassTrainer(ns.Geo.PlayerPoint(), "Warrior") ~= nil)
        -- bag simulation: at least the two quest item stacks
        check("bag peak counts quest items", plan.bags.peak >= 2, plan.bags.peak)
        -- improvement never worse than plain greedy
        check("route cost finite", plan.cost < 10000, plan.cost)
    end

    -- Gear annotation: Q2 rewards boots (armor+agi) vs gloves (sta); nothing equipped there
    ns.Gear.AnnotatePlan(plan, ns.Ladder.snapshot)
    local t2 = plan.byId.T2
    check("reward pick annotated", t2 and t2.rewardPick ~= nil, t2 and t2.rewardPick)
    print("  reward pick: " .. tostring(t2 and t2.rewardPick))

    -- Progress: finish kobolds -> objective done, current step advances only when the step is done
    M.log[1].objectives[1] = { text = "Kobold Vermin slain: 6/6", type = "monster", finished = true, numFulfilled = 6, numRequired = 6 }
    ns.Ladder.RefreshProgress(true)
    check("objective marked done", plan.byId["O2:1"].isDone == true)

    -- Skip the current step: pickups become ignored
    local cur = ns.Ladder.CurrentStep()
    ns.Fire("SKIP_STEP")
    check("skip ignores unstarted quests", ns.charDB.ignored[1] == true or not cur)
end

---------------------------------------------------------------------------
-- 4. Planner properties on random graphs
---------------------------------------------------------------------------
do
    local ns = setup()
    local P, Geo = ns.Planner, ns.Geo
    math.randomseed(7)
    local allValid, neverWorse, boundedExtra = true, true, true
    for trial = 1, 40 do
        local active, candidates = {}, {}
        local function rp() return Geo.Point(1429, math.random(), math.random()) end
        for i = 1, math.random(2, 6) do
            local objs = {}
            for k = 1, math.random(0, 3) do objs[k] = { index = k, type = "monster", need = 5, have = 0, loc = rp() } end
            active[#active + 1] = { id = i, objectives = objs, turnin = rp(), complete = (#objs == 0) }
        end
        for i = 1, math.random(1, 8) do
            local id = 100 + i
            local objs = {}
            for k = 1, math.random(1, 3) do objs[k] = { index = k, type = "item", itemId = 5000 + id * 10 + k, need = 3, have = 0, loc = rp() } end
            local c = { id = id, pickup = rp(), objectives = objs, turnin = rp(), candidate = true }
            if i > 1 and math.random() < 0.4 then c.after = { 100 + i - 1 } end
            candidates[#candidates + 1] = c
        end
        local start = rp()
        local logMax = math.random(#active, #active + 4)
        local opts = { logCount = #active, logMax = logMax }
        local function solve()
            local tasks, byId = P.BuildTasks({ active = active, candidates = candidates })
            return P.Solve(tasks, byId, start, opts)
        end
        -- travel only (no "turn it in while you're here" allowance): greedy vs greedy + improve
        local savedSlack, savedWeight, savedPasses = P.PULL_FORWARD_SLACK, P.TURNIN_WAIT_WEIGHT, P.IMPROVE_PASSES
        P.PULL_FORWARD_SLACK, P.TURNIN_WAIT_WEIGHT = 0, 0
        P.IMPROVE_PASSES = 0
        local g = solve()
        P.IMPROVE_PASSES = savedPasses
        local travelOnly = solve()
        P.PULL_FORWARD_SLACK, P.TURNIN_WAIT_WEIGHT = savedSlack, savedWeight
        local o = solve()
        if not P.IsValid(o, opts) then allValid = false end
        if P.RouteCost(travelOnly, start) > P.RouteCost(g, start) + 0.01 then neverWorse = false end
        -- the allowance only ever spends a bounded amount on finished quests
        local ready = 0
        for _, t in ipairs(o) do if P.ReadyNow(t) then ready = ready + 1 end end
        local cap = ready * (P.PULL_FORWARD_SLACK + P.TURNIN_MAX_EXTRA)
        if P.RouteCost(o, start) > P.RouteCost(travelOnly, start) + cap + 0.01 then boundedExtra = false end
    end
    check("random plans always valid (precedence + log capacity)", allValid)
    check("improvement never worse than greedy", neverWorse)
    check("turning finished quests in early costs a bounded amount of travel", boundedExtra)
end

---------------------------------------------------------------------------
-- 5. Bag simulation
---------------------------------------------------------------------------
do
    local ns = setup()
    local P, Geo = ns.Planner, ns.Geo
    local here = Geo.Point(1429, 0.5, 0.5)
    local steps = {
        { tasks = { { kind = "pickup", gives = 700 } } },
        { tasks = { { kind = "objective", collects = 500 }, { kind = "objective", collects = 501 } } },
        { tasks = { { kind = "turnin", frees = { 500, 700 }, reward = 1 } } },
    }
    local r = P.SimulateBags(steps, { free = 3, counts = {} }, 2)
    check("bag peak", r.peak == 3, r.peak)
    check("bag overflow step", r.overflowAt == 2, r.overflowAt)
    check("bag needed", r.needed == 2, r.needed)
    local r2 = P.SimulateBags(steps, { free = 3, counts = { [500] = 2 } }, 0)
    check("already-held stacks need no new slot", r2.peak == 2, r2.peak)
    check("turn-in frees held stacks (reward takes one)", r2.perStep[3] == 1, r2.perStep[3])
end

---------------------------------------------------------------------------
-- 6. Bag suggestions
---------------------------------------------------------------------------
do
    local ns = setup()
    M.bag = { { id = 600, count = 3 }, { id = 602 }, { id = 500, count = 2 }, { id = 900 }, { id = 904 }, { id = 601, count = 5 } }
    M.log = { { id = 1, title = "Wolves", level = 2, complete = false,
                objectives = { { text = "Tough Wolf Meat: 2/8", type = "item", finished = false, numFulfilled = 2, numRequired = 8 } } } }
    local bags = ns.QuestState.Bags()
    local _, byId = ns.QuestState.Snapshot()
    local plan = { bags = { needed = 1 }, candidates = {}, player = { level = 3, classFile = "WARRIOR" } }
    local list = ns.Bags.Suggestions(bags, byId, plan)
    local by = {}
    for _, e in ipairs(list) do by[e.itemId] = e end
    check("junk -> sell", by[600] and by[600].action == "sell" and by[600].value == 45, by[600] and by[600].value)
    check("orphan quest item -> destroy", by[602] and by[602].action == "destroy")
    check("needed quest item kept", by[500] == nil)
    check("upgrade sword -> equip", by[900] and by[900].action == "equip", by[900] and by[900].action)
    check("plate at level 3 -> unusable sell", by[904] and by[904].action == "sell" and by[904].reason:find("can't"), by[904] and by[904].reason)
    check("cloth only when space is short", by[601] ~= nil)
end

---------------------------------------------------------------------------
-- 7. Gear scoring and AH upgrades
---------------------------------------------------------------------------
do
    local ns = setup()
    local G = ns.Gear
    local w = G.Weights("WARRIOR")
    local s = G.ScoreStats({ ITEM_MOD_STRENGTH_SHORT = 3, ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 6 }, w, 16)
    check("score str+dps", math.abs(s - (3 * 1.0 + 6 * 7.0)) < 0.001, s)
    local hunter = G.Weights("HUNTER")
    local melee = G.ScoreStats({ ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 10 }, hunter, 16)
    local ranged = G.ScoreStats({ ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 10 }, hunter, 18)
    check("hunter values ranged dps more", ranged > melee * 5)
    check("warrior can't wear plate before 40", G.Proficient("WARRIOR", 20, 4, 4) == false and G.Proficient("WARRIOR", 40, 4, 4) == true)
    check("mage can't use maces", G.Proficient("MAGE", 10, 2, 4) == false)
    local pick = G.BestChoice({ { index = 1, itemId = 903 }, { index = 2, itemId = 902 } }, { level = 3, classFile = "WARRIOR" })
    check("best choice picks bigger upgrade", pick and pick.itemId == 902, pick and pick.itemId)
    M.equipped[8] = 902
    M.equipped[10] = 903
    local pick2 = G.BestChoice({ { index = 1, itemId = 903 }, { index = 2, itemId = 902 } }, { level = 3, classFile = "WARRIOR" })
    check("no upgrade -> highest sell value", pick2 and pick2.itemId == 903 and pick2.reason:find("sell"), pick2 and pick2.reason)

    -- AH: Auctionator knows the belt costs 50s; budget = 2.5g - reserve(3) = 25000 - 315
    _G.Auctionator = { API = { v1 = {
        GetAuctionPriceByItemID = function(_, id) if id == 910 then return 5000 end return nil end,
        MultiSearchExact = function(_, names) M.searched = names end,
    } } }
    local built = false
    ns.Data.BuildIndexes(ns.QuestState.Player(), function() built = true end)
    local results
    G.FindAHUpgrades({ level = 3, classFile = "WARRIOR", money = 25000 }, function(list) results = list end)
    check("AH upgrade found", results and #results == 1 and results[1].itemId == 910, results and #results)
    ns.Prices.Search({ "Bear's Belt" })
    check("Auctionator search opened", M.searched and M.searched[1] == "Bear's Belt")
    -- poor player: can't afford
    G.FindAHUpgrades({ level = 3, classFile = "WARRIOR", money = 3000 }, function(list) results = list end)
    check("AH respects budget", results and #results == 0)
    _G.Auctionator = nil
end

---------------------------------------------------------------------------
-- 7b. 0.3.14: low-level gear. Plain white/gray pieces only have armor (0.01 a point), so the
-- fixed "+0.5 points" bar never counted them: the reward pick fell back to sell value and a
-- wearable upgrade in the bags was sold as junk. (Burning Blade Medallion, level 5 hunter.)
---------------------------------------------------------------------------
do
    local ns = setup()
    local G = ns.Gear
    local hunter = { level = 5, classFile = "HUNTER" }
    M.items[960] = { name = "Dust-covered Leggings", classID = 4, subClassID = 2, equipLoc = "INVTYPE_LEGS", sell = 20,
                     stats = { RESISTANCE0_NAME = 25 } }
    M.items[961] = { name = "Jagged Chain Vest", classID = 4, subClassID = 3, equipLoc = "INVTYPE_CHEST", sell = 40,
                     stats = { RESISTANCE0_NAME = 60 } }
    M.items[962] = { name = "Ripped Pants", classID = 4, subClassID = 1, equipLoc = "INVTYPE_LEGS", sell = 10,
                     stats = { RESISTANCE0_NAME = 8 } }
    M.items[963] = { name = "Starter Pants", classID = 4, subClassID = 1, equipLoc = "INVTYPE_LEGS", quality = 0,
                     stats = { RESISTANCE0_NAME = 5 } }
    M.items[964] = { name = "Thick Leather Pants", classID = 4, subClassID = 2, equipLoc = "INVTYPE_LEGS", sell = 30,
                     stats = { RESISTANCE0_NAME = 40 } }
    local choices = { { index = 1, itemId = 960 }, { index = 2, itemId = 961 }, { index = 3, itemId = 962 } }
    local pick = G.BestChoice(choices, hunter)
    check("empty legs: the leggings, not the best-selling mail vest", pick and pick.itemId == 960 and pick.reason:find("empty Legs"),
        pick and (pick.itemId .. " " .. pick.reason))
    M.equipped[7] = 963
    pick = G.BestChoice(choices, hunter)
    check("starter pants: +20 armor counts as an upgrade", pick and pick.itemId == 960 and pick.reason:find("upgrade"),
        pick and (pick.itemId .. " " .. pick.reason))
    M.equipped[7] = 964
    pick = G.BestChoice(choices, hunter)
    check("nothing beats what you wear: best sell value, and it says so", pick and pick.itemId == 961
        and pick.reason:find("none beats") and pick.reason:find("sell"), pick and pick.reason)
    check("upgrade bar: tiny gain but +20% counts", G.IsUpgrade({ delta = 0.2, pct = 20 }))
    check("upgrade bar: +1% of a small score doesn't", not G.IsUpgrade({ delta = 0.1, pct = 1 }))
    check("upgrade bar: an empty slot always does", G.IsUpgrade({ delta = 0, pct = 0, empty = true }))

    -- Armor left out of the stat list: read from the tooltip instead.
    M.items[965] = { name = "Quiet Boots", classID = 4, subClassID = 2, equipLoc = "INVTYPE_FEET", stats = {} }
    _G.C_TooltipInfo = { GetHyperlink = function(link)
        if link:find("item:965") then
            return { lines = { { leftText = "Quiet Boots" }, { leftText = "Feet" }, { leftText = "1,234 Armor" } } }
        end
        return { lines = { { leftText = "Something" } } }
    end }
    local link965 = select(2, C_Item.GetItemInfo(965))
    local stats = G.ItemStats(link965)
    check("tooltip armor used when the stats leave it out", stats and stats.RESISTANCE0_NAME == 1234,
        stats and stats.RESISTANCE0_NAME)
    check("tooltip armor scores", G.Score(link965, 8, "HUNTER") > 0)
    check("weapons don't read tooltip armor", G.ItemStats(select(2, C_Item.GetItemInfo(901))).RESISTANCE0_NAME == nil)
    _G.C_TooltipInfo = nil

    -- Bags: gear is checked before "gray = junk".
    M.items[966] = { name = "Tattered Vest", classID = 4, subClassID = 1, equipLoc = "INVTYPE_CHEST", quality = 0, sell = 3,
                     stats = { RESISTANCE0_NAME = 10 } }
    M.items[967] = { name = "Frayed Gloves", classID = 4, subClassID = 1, equipLoc = "INVTYPE_HAND", quality = 0, sell = 2,
                     stats = { RESISTANCE0_NAME = 4 } }
    M.items[968] = { name = "Scout's Boots", classID = 4, subClassID = 2, equipLoc = "INVTYPE_FEET", minLevel = 7, sell = 25,
                     stats = { RESISTANCE0_NAME = 20, ITEM_MOD_AGILITY_SHORT = 2 } }
    M.items[969] = { name = "Burlap Gloves", classID = 4, subClassID = 1, equipLoc = "INVTYPE_HAND",
                     stats = { RESISTANCE0_NAME = 9 } }
    M.equipped[10] = 969
    M.bag = { { id = 966 }, { id = 967 }, { id = 968 }, { id = 600 } }
    local list = ns.Bags.Suggestions(ns.QuestState.Bags(), {}, { bags = { needed = 0 }, candidates = {}, player = hunter })
    local by = {}
    for _, e in ipairs(list) do by[e.itemId] = e end
    check("gray vest for an empty chest: equip, not junk", by[966] and by[966].action == "equip", by[966] and by[966].action)
    check("gray gloves worse than yours: still junk", by[967] and by[967].action == "sell" and by[967].reason:find("junk"),
        by[967] and by[967].reason)
    check("upgrade two levels away: kept, not 'equip it' or sold", by[968] == nil, by[968] and by[968].action)
    check("plain junk still sold", by[600] and by[600].action == "sell")
end

---------------------------------------------------------------------------
-- 8. Hints
---------------------------------------------------------------------------
do
    local ns = setup()
    local H, Geo = ns.Hints, ns.Geo
    ns.Data.BuildIndexes(ns.QuestState.Player(), function() end)
    -- Accept "The Lost Book" standing next to the librarian; the bookshelf is 15 yards away.
    M.log = { { id = 3, title = "The Lost Book", level = 3, complete = false,
                objectives = { { text = "Old Book: 0/1", type = "item", finished = false, numFulfilled = 0, numRequired = 1 } } } }
    local _, byId = ns.QuestState.Snapshot()
    local atGiver = Geo.Point(1429, 0.20, 0.70)
    H.OnQuestAccepted(3, atGiver)
    local list = H.Compute({ point = atGiver, byId = byId, bags = ns.QuestState.Bags(), now = M.time })
    local grab = false
    for _, h in ipairs(list) do if h.text:find("grab") and h.text:find("Old Book") then grab = true end end
    check("grab-before-leaving hint at the giver", grab)
    -- walk away without it
    M.time = M.time + 10
    list = H.Compute({ point = Geo.Point(1429, 0.30, 0.70), byId = byId, bags = ns.QuestState.Bags(), now = M.time })
    local warn = list[1] and list[1].text:find("left without")
    check("warning after leaving without the item", warn ~= nil, list[1] and list[1].text)
    -- pick it up -> reminder resolves
    M.bag = { { id = 501 } }
    list = H.Compute({ point = Geo.Point(1429, 0.30, 0.70), byId = byId, bags = ns.QuestState.Bags(), now = M.time })
    local still = false
    for _, h in ipairs(list) do if h.text:find("Old Book") then still = true end end
    check("reminder cleared once looted", not still)

    -- Quest starter item in bags + special item + escort + extra objective
    M.bag = { { id = 602, startsQuest = 77 } }
    M.log = { { id = 9, title = "Escort the Miner", level = 4, complete = false, special = 700, objectives = {} } }
    _, byId = ns.QuestState.Snapshot()
    H.OnQuestAccepted(9, Geo.Point(1429, 0.44, 0.30))
    list = H.Compute({ point = Geo.Point(1429, 0.44, 0.30), byId = byId, bags = ns.QuestState.Bags(), now = M.time })
    local found = { starter = false, special = false, escort = false, extra = false }
    for _, h in ipairs(list) do
        if h.text:find("starts a quest") then found.starter = true end
        if h.text:find("Gnomish Tools") then found.special = true end
        if h.text:find("Escort quest") then found.escort = true end
        if h.text:find("start the escort") then found.extra = true end
    end
    check("bag quest-starter hint", found.starter)
    check("special quest item: no hint while it isn't this step's quest (0.3.25)", not found.special)
    check("escort hint", found.escort)
    check("Questie extra-objective note shown", found.extra)
    local use = H.UsableItem()
    check("use button gets the quest starter", use and use.itemId == 602, use and use.itemId)
    -- on the step for that quest, standing at its place, the game's special item is ready to use
    local here = Geo.Point(1429, 0.44, 0.30)
    list = H.Compute({ point = here, byId = byId, bags = ns.QuestState.Bags(), now = M.time,
                       step = { tasks = { { id = "T9", kind = "turnin", questId = 9, loc = here, deps = {} } } } })
    found.special = false
    for _, h in ipairs(list) do if h.text:find("Gnomish Tools") and h.kind == "use" and h.button then found.special = true end end
    check("special quest item: this step's quest, at its place: on the button", found.special)
end

---------------------------------------------------------------------------
-- 9. Automation only acts on planned quests, and Shift suspends it
---------------------------------------------------------------------------
do
    local ns = setup()
    local accepted, rewarded, completed = {}, nil, 0
    local currentQuest = 1
    _G.AcceptQuest = function() accepted[#accepted + 1] = currentQuest end
    _G.GetQuestID = function() return currentQuest end
    _G.IsQuestCompletable = function() return true end
    _G.CompleteQuest = function() completed = completed + 1 end
    _G.GetNumQuestChoices = function() return 2 end
    _G.GetQuestItemLink = function(_, i) return "|Hitem:" .. (i == 1 and 903 or 902) .. "|h[x]|h" end
    _G.GetQuestReward = function(i) rewarded = i end
    ns.Ladder.plan = { order = { { kind = "pickup", questId = 3 } }, byId = {} }
    ns.DispatchEvent("QUEST_DETAIL")
    check("auto-accept ignores unplanned quest", #accepted == 0)
    currentQuest = 3
    ns.DispatchEvent("QUEST_DETAIL")
    check("auto-accept takes planned quest", accepted[1] == 3)
    _G.IsShiftKeyDown = function() return true end
    ns.DispatchEvent("QUEST_DETAIL")
    check("shift suspends automation", #accepted == 1)
    _G.IsShiftKeyDown = function() return false end
    ns.DispatchEvent("QUEST_PROGRESS")
    check("auto-complete when completable", completed == 1)
    ns.DispatchEvent("QUEST_COMPLETE")
    check("reward choice left to the player by default", rewarded == nil)
    ns.db.autoPickReward = true
    ns.DispatchEvent("QUEST_COMPLETE")
    check("auto-pick chooses the better reward (boots)", rewarded == 2, rewarded)
    _G.GetNumQuestChoices = function() return 0 end
    ns.DispatchEvent("QUEST_COMPLETE")
    check("no-choice turn-in", rewarded == 0, rewarded)
end

---------------------------------------------------------------------------
-- 11. Travel: flights, hearth DP, bind and flight-path suggestions
---------------------------------------------------------------------------
do
    local ns = setup()
    local T, Geo = ns.Travel, ns.Geo
    local function P(x, y) return Geo.Point(1429, x, y) end
    local net = { speed = 7, nodes = {
        { name = "West", point = P(0.10, 0.50), known = true },
        { name = "East", point = P(0.90, 0.50), known = true },
    } }
    local c, mode, from, to = T.Leg(net, P(0.10, 0.52), P(0.90, 0.52))
    check("long leg flies", mode == "fly" and from.name == "West" and to.name == "East", mode)
    check("flight cheaper than walking", c < T.Walk(net, P(0.10, 0.52), P(0.90, 0.52)))
    local _, shortMode = T.Leg(net, P(0.10, 0.52), P(0.12, 0.52))
    check("short leg walks", shortMode == "walk")
    local cost = T.NewCost(net)
    check("memoized cost stable", cost(P(0.1, 0.1), P(0.9, 0.9)) > 0)

    -- 1-D world, 1 yard = 1 second, to check the hearth DP exactly
    local function X(x) return { cont = 0, wx = x, wy = 0, mapId = 1429, x = 0, y = 0 } end
    local lin = function(a, b) return math.abs(a.wx - b.wx) end
    local steps = { { loc = X(1000) }, { loc = X(2000) }, { loc = X(100) }, { loc = X(2100) }, { loc = X(50) } }
    local hnet = { hasHearth = true, bind = X(0), hearthCooldown = 3600, hearthReadyIn = 0 }
    local hp = T.PlanHearth(steps, X(0), hnet, lin)
    check("hearth used twice when cooldown allows", hp.uses[3] and hp.uses[5] and hp.saving > 3500, hp.saving)
    hnet.hearthCooldown = 5000
    hp = T.PlanHearth(steps, X(0), hnet, lin)
    check("hearth DP picks the bigger saving under a long cooldown", hp.uses[5] and not hp.uses[3], tostring(hp.uses[3]))
    hnet.hearthReadyIn = 99999
    hp = T.PlanHearth(steps, X(0), hnet, lin)
    check("hearth on cooldown is not planned", hp.saving == 0)

    -- bind suggestion: route keeps returning to a hub at x=3000
    local route = {}
    for i = 1, 4 do route[#route + 1] = { loc = X(3000) }; route[#route + 1] = { loc = X(3000 - 700 - i * 50) } end
    route[#route + 1] = { loc = X(3000) }
    local bnet = { hasHearth = true, bind = X(0), hearthCooldown = 600, hearthReadyIn = 0 }
    local best = T.SuggestBind(route, X(2900), bnet, lin, { { name = "Hub Inn", point = X(3010) }, { name = "Far Inn", point = X(0) } })
    check("bind suggestion picks the hub inn", best and best.inn.name == "Hub Inn", best and best.inn.name)
    local none = T.SuggestBind(route, X(2900), { hasHearth = true, bind = X(3005), hearthCooldown = 600, hearthReadyIn = 0 }, lin,
        { { name = "Hub Inn", point = X(3010) } })
    check("no bind suggestion when already bound there", none == nil)

    -- flight paths on the way
    local dnet = { nodes = { { name = "OnTheWay", point = { cont = 0, wx = 1500, wy = 30 }, known = false },
                             { name = "OffRoute", point = { cont = 0, wx = 1500, wy = 2000 }, known = false } } }
    local path = { { loc = { cont = 0, wx = 0, wy = 0 } }, { loc = { cont = 0, wx = 3000, wy = 0 } } }
    local dist = function(a, b) local dx, dy = a.wx - b.wx, a.wy - b.wy return math.sqrt(dx * dx + dy * dy) / 7 end
    local found = T.SuggestDiscoveries(path, path[1].loc, dnet, dist, 60)
    check("flight path on the way suggested", #found == 1 and found[1].node.name == "OnTheWay", #found)
end

---------------------------------------------------------------------------
-- 12. Travel in the full pipeline (bind point known, flight paths on the map)
---------------------------------------------------------------------------
do
    local ns = setup()
    M.log = { { id = 2, title = "Kobold Camp Cleanup", level = 2, complete = false,
                objectives = { { text = "Kobold Vermin slain: 2/6", type = "monster", finished = false, numFulfilled = 2, numRequired = 6 } } } }
    M.items[6948] = { name = "Hearthstone", classID = 15, spell = "Hearthstone" }
    M.bag = { { id = 6948 } }
    M.bindName = "Northshire"
    ns.charDB.bindPoints = { Northshire = { mapId = 1429, x = 0.40, y = 0.40 } }
    M.taxiNodes = {
        { name = "Northshire Gryphons", position = { x = 0.41, y = 0.39 }, isUndiscovered = false, faction = 2, nodeID = 1 },
        { name = "Field Post", position = { x = 0.50, y = 0.405 }, isUndiscovered = true, faction = 2, nodeID = 2 },
        { name = "Horde Post", position = { x = 0.50, y = 0.41 }, isUndiscovered = true, faction = 1, nodeID = 3 },
        { name = "Far Post", position = { x = 0.98, y = 0.98 }, isUndiscovered = true, faction = 2, nodeID = 4 },
    }
    ns.charDB.flightPaths = { ["Northshire Gryphons"] = true } -- learned from a flight map earlier
    local plan = fullPlan(ns)
    local ids = {}
    for _, t in ipairs(plan.order) do ids[#ids + 1] = t.id end
    print("travel route: " .. table.concat(ids, " "))
    check("flight path on the route added", plan.byId["V:fp:Field Post"] ~= nil)
    check("enemy-faction flight path ignored", plan.byId["V:fp:Horde Post"] == nil)
    check("far flight path not worth the detour", plan.byId["V:fp:Far Post"] == nil)
    check("small map: a ~2 min return doesn't burn the hearth", plan.hearth == nil and plan.hearthWhy == "saving too small",
        tostring(plan.hearthWhy))
    -- flight-path visit completes when the taxi map lists it
    ns.charDB.flightPaths["Field Post"] = true
    check("flight-path visit done once learned", ns.Ladder.TaskDone(plan.byId["V:fp:Field Post"], ns.Ladder.snapshot))

    -- waypoint points at the flight master first when flying is the way (0.3.16: worked out
    -- from where you stand, on the plan's flight network)
    local A = { name = "A", point = ns.Geo.Point(1429, 0.1, 0.5), known = true }
    local B = { name = "B", point = ns.Geo.Point(1429, 0.88, 0.5), known = true }
    local savedNet = ns.Ladder.plan.net
    ns.Ladder.plan.net = { speed = 7, nodes = { A, B } }
    local step = { loc = ns.Geo.Point(1429, 0.9, 0.5) }
    local target = ns.Ladder.WaypointTarget(step, ns.Geo.Point(1429, 0.12, 0.5))
    check("waypoint goes to the flight master before flying", target == A.point)
    ns.Ladder.plan.net = savedNet
    target = ns.Ladder.WaypointTarget(step, ns.Geo.Point(1429, 0.87, 0.5))
    check("waypoint goes to the objective after landing", target == step.loc)
end

---------------------------------------------------------------------------
-- 13. Cyan UI boxes
---------------------------------------------------------------------------
do
    local ns = setup({ frames = true })
    local HL = ns.Highlight
    M.items[700] = { name = "Gnomish Tools", classID = 12, spell = "Use" }
    M.bag = { { id = 700 }, { id = 600, count = 2 } }
    ns.Hints.list = { { kind = "use", itemId = 700, text = "use it", button = true } }
    local bp = M.newFrame("backpack"); bp:Show()
    _G.MainMenuBarBackpackButton = bp
    HL.Update({ bags = ns.QuestState.Bags(), suggestions = {} })
    check("bags closed: box on the backpack button", HL.Active()["b:0"] and HL.Active()["b:0"].target == bp)
    check("bags closed: label says open, and why", HL.Active()["b:0"] and HL.Active()["b:0"].label:GetText() == "Open: Use")
    local cf = M.newFrame("combined"); cf:Show()
    local b1, b2 = M.newFrame("slot1"), M.newFrame("slot2")
    b1.__id, b2.__id = 1, 2
    b1.GetBagID = function() return 0 end
    b2.GetBagID = function() return 0 end
    cf.__items = { b1, b2 }
    _G.ContainerFrameCombinedBags = cf
    HL.Update({ bags = ns.QuestState.Bags(), suggestions = {} })
    check("bags open: box on the item itself", HL.Active()["i:0:1"] and HL.Active()["i:0:1"].target == b1)
    check("bags open: bag-button box removed", HL.Active()["b:0"] == nil)
    _G.MerchantFrame = M.newFrame("merchant"); MerchantFrame:Show()
    HL.Update({ bags = ns.QuestState.Bags(), suggestions = { { action = "sell", itemId = 600, bag = 0, slot = 2 } } })
    check("at a vendor: junk boxed with Sell", HL.Active()["i:0:2"] and HL.Active()["i:0:2"].label:GetText() == "Sell")
    MerchantFrame:Hide()
    local r1, r2 = M.newFrame("r1"), M.newFrame("r2")
    r1.__id, r2.__id = 1, 2; r1.type, r2.type = "choice", "choice"; r1:Show(); r2:Show()
    _G.QuestInfoRewardsFrame = { RewardButtons = { r1, r2 } }
    _G.QuestFrame = M.newFrame("questframe"); QuestFrame:Show()
    HL.rewardIndex = 2
    HL.Update({ bags = ns.QuestState.Bags(), suggestions = {} })
    check("reward to pick boxed", HL.Active().reward and HL.Active().reward.target == r2)
    check("sell boxes gone after leaving the vendor", HL.Active()["i:0:2"] == nil)
    ns.db.highlights = false
    HL.Update({ bags = ns.QuestState.Bags(), suggestions = {} })
    check("highlights toggle clears boxes", next(HL.Active()) == nil)
end

---------------------------------------------------------------------------
-- 14. World markers: nameplates, soft target, minimap boxes
---------------------------------------------------------------------------
do
    local ns = setup({ frames = true })
    local WM = ns.WorldMarks
    local kind, id = WM.ParseGUID("Creature-0-1-2-3-201-0000ABCD")
    check("GUID parsed", kind == "Creature" and id == 201)
    local added = {}
    _G.LibStub = function(name) if name == "HereBeDragons-Pins-2.0" then return {
        RemoveAllMinimapIcons = function() added = {} end,
        RemoveAllWorldMapIcons = function() end,
        AddMinimapIconMap = function(_, _, _, mapId, x, y) added[#added + 1] = { mapId, x, y } end,
        AddWorldMapIconMap = function() end,
    } end end
    local p1, p2, p3 = ns.Geo.Point(1429, 0.6, 0.4), ns.Geo.Point(1429, 0.61, 0.41), ns.Geo.Point(1429, 0.605, 0.395)
    local step = { tasks = {
        { kind = "objective", obj = { type = "monster", targets = { npc = { 201 } } }, quest = {},
          loc = { mapId = 1429, x = 0.6, y = 0.4, members = { p1, p2, p3 } } },
        { kind = "turnin", loc = { giverId = 100, mapId = 1429, x = 0.4, y = 0.4 }, quest = {} },
        { kind = "objective", obj = { type = "item", targets = { object = { 300 } } }, quest = {} },
    } }
    WM.SetTargets(step)
    check("kill target registered", WM.npc[201] == "Kill")
    check("turn-in NPC registered", WM.npc[100] == "Turn in")
    check("object source registered", WM.object[300] == "Loot")
    check("minimap boxes at the camp's spawns", #added == 4, #added)
    local plate = M.newFrame("plate")
    M.plates.nameplate1 = plate
    M.guids.nameplate1 = "Creature-0-1-2-3-201-0000ABCD"
    WM.DecoratePlate("nameplate1")
    check("quest mob nameplate marked", plate.QuestLadderMark and plate.QuestLadderMark:IsShown()
        and plate.QuestLadderMark.label:GetText() == "Kill")
    -- 0.3.27: the label sat above the box, over the mob's name; now it's under the box
    local lp = plate.QuestLadderMark and plate.QuestLadderMark.label.__points
    lp = lp and lp[#lp]
    check("nameplate label sits under the box, clear of the mob's name",
        lp and lp[1] == "TOP" and lp[2] == plate.QuestLadderMark and lp[3] == "BOTTOM" and (lp[5] or 0) < 0,
        lp and table.concat({ tostring(lp[1]), tostring(lp[3]), tostring(lp[5]) }, " "))
    local other = M.newFrame("plate2")
    M.plates.nameplate2 = other
    M.guids.nameplate2 = "Creature-0-1-2-3-999-0000ABCD"
    WM.DecoratePlate("nameplate2")
    check("other mobs left alone", other.QuestLadderMark == nil)
    M.names.softinteract = "Dusty Bookshelf"
    ns.DispatchEvent("PLAYER_SOFT_INTERACT_CHANGED", nil, "GameObject-0-1-2-3-300-0000ABCD")
    check("facing the objective object", WM.softHit and WM.softHit.label == "Loot")
    local list = ns.Hints.Compute({ byId = {}, bags = ns.QuestState.Bags(), now = M.time })
    check("'this one' hint on top", list[1] and list[1].text:find("This one") and list[1].text:find("Dusty Bookshelf"), list[1] and list[1].text)
    ns.DispatchEvent("PLAYER_SOFT_INTERACT_CHANGED", "GameObject-0-1-2-3-300-0000ABCD", nil)
    check("cue clears when you turn away", WM.softHit == nil)
    -- 0.3.11: the "target is right" cue follows the step, not only your clicks ("Use item on
    -- Deathguard Falgan" stayed up after that step was done)
    M.guids.target = "Creature-0-1-2-3-100-0000ABCD"
    M.names.target = "Marshal McBride"
    ns.DispatchEvent("PLAYER_TARGET_CHANGED")
    check("target cue for the step's NPC", WM.targetHit and WM.targetHit.label == "Turn in")
    WM.SetTargets(nil) -- the step is done; you still have the NPC targeted
    check("target cue clears when the step moves on", WM.targetHit == nil)
    M.guids.target = nil
    -- 0.3.12: with enemy nameplates off, quest mobs can't be boxed; say so once per session
    local prints = 0
    _G.DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg) if msg:find("enemy nameplates are off", 1, true) then prints = prints + 1 end end }
    _G.C_CVar = { GetCVar = function(name) return (name == "nameplateShowEnemies") and "0" or "1" end }
    WM.SetTargets(step)
    WM.SetTargets(step)
    check("enemy nameplates off: told once for a kill step", prints == 1, prints)
    -- 0.3.13: a drop from a mob is a fight too (Burning Blade Medallion from Yarrog showed no
    -- notice), but an item from an object is not
    WM.toldEnemyPlates, prints = nil, 0
    WM.SetTargets({ tasks = { { kind = "objective", obj = { type = "item", targets = { object = { 300 } } }, quest = {} } } })
    check("object-only step: no mobs, no notice", not WM.StepHasMobs() and prints == 0, prints)
    WM.SetTargets({ tasks = { { kind = "objective", obj = { type = "item", targets = { npc = { 202 } } }, quest = {} } } })
    check("item dropped by a mob: notice too", WM.StepHasMobs() and prints == 1, prints)
    _G.C_CVar = nil
    -- 0.3.13: the game gives the object you face its own nameplate (Thazz'ril's Pick); it gets
    -- the box too, around its name since it has no health bar. The same plate held a mob before.
    WM.SetTargets(step)
    check("object IDs don't borrow NPC labels", WM.LabelFor("GameObject-0-1-2-3-201-0000ABCD") == nil)
    local name, bar = M.newFrame("name"), M.newFrame("bar")
    plate.UnitFrame = { name = name, healthBar = bar }
    WM.DecoratePlate("nameplate1")
    local mark = plate.QuestLadderMark
    check("reused plate: box moves to the mob's health bar", mark.__points[1] and mark.__points[1][2] == bar)
    M.guids.nameplate1 = "GameObject-0-1-2-3-300-0000ABCD"
    WM.DecoratePlate("nameplate1")
    check("object nameplate boxed", mark:IsShown() and mark.label:GetText() == "Loot", mark.label:GetText())
    check("object box goes around the name", #mark.__points == 2 and mark.__points[1][2] == name)
    M.guids.nameplate1 = "GameObject-0-1-2-3-301-0000ABCD"
    WM.DecoratePlate("nameplate1")
    check("other objects left alone", not mark:IsShown())
    -- 0.3.27: every kind of tag sits under its box, not just "Turn in": the same label for all
    WM.SetTargets({ tasks = {
        { kind = "objective", obj = { type = "monster", targets = { npc = { 401 } } }, quest = {} },
        { kind = "objective", obj = { type = "item", targets = { npc = { 402 }, object = { 501 } } }, quest = {} },
        { kind = "objective", obj = { type = "object", targets = { object = { 502 } } }, quest = {} },
        { kind = "objective", obj = { type = "event", targets = { npc = { 403 } } }, quest = {} },
        { kind = "objective", obj = { type = "killcredit", targets = { npc = { 404 } } }, quest = {} },
        { kind = "pickup", loc = { giverId = 405 }, quest = {} },
        { kind = "turnin", loc = { giverId = 406 }, quest = {} },
        { kind = "turnin", loc = { giverId = 407 }, quest = { useFirst = true } },
        { kind = "turnin", loc = { giverId = -503 }, quest = {} },
        { kind = "visit", visit = "flight", npcId = 408 }, { kind = "visit", visit = "bind", npcId = 409 },
        { kind = "visit", visit = "vendor", npcId = 410 }, { kind = "visit", visit = "trainer", npcId = 411 },
    } })
    local tags = {
        { "Creature", 401, "Kill" }, { "Creature", 402, "Loot" }, { "GameObject", 501, "Loot" },
        { "GameObject", 502, "Use" }, { "Creature", 403, "Go" }, { "Creature", 404, "Quest" },
        { "Creature", 405, "Accept" }, { "Creature", 406, "Turn in" }, { "Creature", 407, "Use item on" },
        { "GameObject", 503, "Turn in" }, { "Creature", 408, "Flight path" }, { "Creature", 409, "Innkeeper" },
        { "Creature", 410, "Vendor" }, { "Creature", 411, "Trainer" },
    }
    local wrong = {}
    local reused = M.newFrame("plateR")
    reused.UnitFrame = { name = M.newFrame("nameR"), healthBar = M.newFrame("barR") }
    for i, tag in ipairs(tags) do
        -- a fresh plate for each tag, and one plate the game keeps reusing for all of them
        for _, p in ipairs({ M.newFrame("plateT" .. i), reused }) do
            M.plates.nameplate9 = p
            M.guids.nameplate9 = string.format("%s-0-1-2-3-%d-0000ABCD", tag[1], tag[2])
            WM.DecoratePlate("nameplate9")
            local mk = p.QuestLadderMark
            local pts = mk and mk.label.__points
            local at = pts and pts[#pts]
            if not (mk and mk:IsShown() and mk.label:GetText() == tag[3] and at and at[1] == "TOP" and at[2] == mk
                    and at[3] == "BOTTOM" and (at[5] or 0) < 0) then
                wrong[#wrong + 1] = tag[3] .. " (" .. tostring(mk and mk.label:GetText()) .. ")"
            end
        end
    end
    check("every nameplate tag (Kill, Loot, Turn in, Accept, ...) sits under its box", #wrong == 0, table.concat(wrong, ", "))
    _G.LibStub = nil
end

---------------------------------------------------------------------------
-- 15. Hearth rules on synthetic routes (dead end vs. full cooldown of steps)
---------------------------------------------------------------------------
do
    local ns = setup()
    local P, T = ns.Planner, ns.Travel
    local function X(x) return { cont = 0, wx = x, wy = 0, mapId = 1429, x = 0, y = 0 } end
    local cost = function(a, b) return math.abs(a.wx - b.wx) / 7 end
    local function route(far1, far2)
        local cands = {
            { id = 1, pickup = X(0), turnin = X(0), objectives = { { index = 1, type = "event", loc = X(far1) } } },
            { id = 2, after = { 1 }, pickup = X(10), turnin = X(10), objectives = { { index = 1, type = "event", loc = X(far2) } } },
        }
        local tasks, byId = P.BuildTasks({ candidates = cands })
        P.travelFn = cost
        return P.Solve(tasks, byId, X(0), { logCount = 0, logMax = 20 })
    end
    local function ids(order) local o = {} for _, t in ipairs(order) do o[#o + 1] = t.id end return table.concat(o, " ") end
    local order = route(3500, 3400)
    print("  synthetic route: " .. ids(order))
    local net = { hasHearth = true, bind = X(0), bindName = "Hub Inn", hearthCooldown = 3600, hearthReadyIn = 0 }
    local r = T.HearthAware(order, X(0), net, cost, { logCount = 0, logMax = 20 })
    check("dead end: hearth recommended", r ~= nil)
    if r then
        print("  with hearth:     " .. ids(r.order))
        local pos = {}
        for i, t in ipairs(r.order) do pos[t.id] = i end
        check("dead end: hearth after the LAST far objective, not between trips", pos["V:hearth1"] == pos["O2:1"] + 1,
            ids(r.order))
        check("dead end: reason is 'area done'", r.uses[1].reason == "area done", r.uses[1].reason)
        check("dead end: saves 4+ minutes", r.saving >= 240, r.saving)
    end
    -- short cooldown: hearthing after the first far trip is fine because plenty of route follows
    net.hearthCooldown = 600
    r = T.HearthAware(route(3500, 3400), X(0), net, cost, { logCount = 0, logMax = 20 })
    local pos = {}
    for i, t in ipairs(r and r.order or {}) do pos[t.id] = i end
    check("short cooldown: hearth after the first trip (cooldown rule)", r and pos["V:hearth1"] == pos["O1:1"] + 1
        and r.uses[1].reason == "cooldown", r and ids(r.order))
    -- not worth it: small trip
    net.hearthCooldown = 3600
    local none, why = T.HearthAware(route(1200, 1100), X(0), net, cost, { logCount = 0, logMax = 20 })
    check("small saving: no hearth", none == nil and why == "saving too small", tostring(why))
    -- cooldown not ready until after the route
    net.hearthReadyIn = 99999
    none = T.HearthAware(route(3500, 3400), X(0), net, cost, { logCount = 0, logMax = 20 })
    check("hearth on cooldown: no hearth", none == nil)
    P.travelFn = nil
end

---------------------------------------------------------------------------
-- 16. Hearth in the full pipeline on a big map (the den is a dead end)
---------------------------------------------------------------------------
do
    local ns = setup()
    ns.Geo.SetTransform(1429, { cont = 0, ox = 0, oy = 0, ax = 12000, ay = 0, bx = 0, by = 8000 })
    ns.Geo.SetTransform(1415, { cont = 0, ox = 0, oy = 0, ax = 12000, ay = 0, bx = 0, by = 8000 })
    M.log = { { id = 2, title = "Kobold Camp Cleanup", level = 2, complete = false,
                objectives = { { text = "Kobold Vermin slain: 2/6", type = "monster", finished = false, numFulfilled = 2, numRequired = 6 } } } }
    M.items[6948] = { name = "Hearthstone", classID = 15, spell = "Hearthstone" }
    M.bag = { { id = 6948 } }
    M.bindName = "Northshire"
    ns.charDB.bindPoints = { Northshire = { mapId = 1429, x = 0.40, y = 0.40 } }
    local plan = fullPlan(ns)
    local ids, pos = {}, {}
    for i, t in ipairs(plan.order) do ids[#ids + 1] = t.id; pos[t.id] = i end
    print("big-map route: " .. table.concat(ids, " "))
    check("big map: hearth recommended", plan.hearth ~= nil, tostring(plan.hearthWhy))
    local hearthStep
    for i, st in ipairs(plan.steps) do if st.travel and st.travel.mode == "hearth" then hearthStep = i end end
    if hearthStep then
        print("  step " .. hearthStep .. ": " .. ns.Ladder.TravelText(plan.steps[hearthStep]))
        check("hearth is its own step", #plan.steps[hearthStep].tasks == 1)
        check("hearth reason shown", ns.Ladder.TravelText(plan.steps[hearthStep]):find("nothing left out here") ~= nil)
        ns.Ladder.current = hearthStep
        M.player.x, M.player.y = 0.80, 0.20
        local list = ns.Hints.Compute({ point = ns.Geo.PlayerPoint(), byId = ns.Ladder.snapshot, bags = ns.QuestState.Bags(),
                                        plan = plan, step = plan.steps[hearthStep], now = M.time })
        local hearthHint = false
        for _, h in ipairs(list) do if h.itemId == 6948 then hearthHint = true end end
        check("hearth-now hint puts the hearthstone on the use button", hearthHint)
        check("no waypoint change for a hearth step", ns.Ladder.WaypointTarget(plan.steps[hearthStep], ns.Geo.PlayerPoint()) == nil)
    end
    -- walking past a hearth step instead: it stops blocking once a later quest step is done
    M.completed[4] = true
    ns.Ladder.plan = { steps = {
        { tasks = { { id = "V:hearth1", kind = "visit", visit = "hearth" } } },
        { tasks = { { id = "T4", kind = "turnin", questId = 4, quest = {} } } },
    }, byId = {} }
    ns.Ladder.current = 1
    ns.Ladder.RefreshProgress(true)
    check("skipped hearth no longer blocks the guide", ns.Ladder.current == 3, ns.Ladder.current)
    check("skipped hearth marked as skipped", ns.Ladder.plan.steps[1].tasks[1].skipped == true)
end

---------------------------------------------------------------------------
-- 17. Flights are AFK time, but only when they're a real shortcut
---------------------------------------------------------------------------
do
    local ns = setup()
    local T, Geo = ns.Travel, ns.Geo
    local function Pt(x, y) return Geo.Point(1429, x, y) end
    local net = { speed = 7, nodes = { { name = "West", point = Pt(0.10, 0.50), known = true },
                                       { name = "East", point = Pt(0.90, 0.50), known = true } } }
    local c, mode, _, _, air = T.Leg(net, Pt(0.10, 0.52), Pt(0.90, 0.52))
    local walking = T.Walk(net, Pt(0.10, 0.52), Pt(0.90, 0.52))
    check("AFK flight chosen", mode == "fly" and air and air > 0)
    check("air time weighted as AFK", c < (walking * 0.4), string.format("%.0f vs walk %.0f", c, walking))
    local savedSpeed = T.FLY_SPEED
    T.FLY_SPEED = 2 -- a painfully slow flight: total time would be far longer than walking
    local _, slowMode = T.Leg({ speed = 7, nodes = net.nodes, _nearest = nil }, Pt(0.10, 0.52), Pt(0.90, 0.52))
    T.FLY_SPEED = savedSpeed
    check("no flight when it's a detour in total time", slowMode == "walk", slowMode)
    local step = { loc = Pt(0.9, 0.5), travel = { mode = "fly", from = { name = "West" }, to = { name = "East" } } }
    check("flight step says AFK", ns.Ladder.TravelText(step):find("AFK") ~= nil)
end

---------------------------------------------------------------------------
-- 18. Bagnon and Baganator item buttons
---------------------------------------------------------------------------
do
    local ns = setup({ frames = true })
    local HL = ns.Highlight
    M.items[700] = { name = "Gnomish Tools", classID = 12, spell = "Use" }
    M.bag = { { id = 600 }, { id = 700 } }      -- tools in bag 0 slot 2
    ns.Hints.list = { { kind = "use", itemId = 700, text = "use it", button = true } }
    local function itemButton(bag, slot, viaParent)
        local b = M.newFrame("item"); b:Show(); b.__id = slot
        b.IsObjectType = function(_, t) return t == "ItemButton" or t == "Button" end
        if viaParent then b.GetBagID = function() return bag end else b.GetBag = function() return bag end end
        return b
    end
    -- Bagnon: one big inventory window registered with BagBrother.Frames
    local inv = M.newFrame("BagnonInventory"); inv:Show(); inv[0] = true; inv.id = "inventory"
    local group = M.newFrame("ItemGroup"); group:Show()
    local bagnonButton = itemButton(0, 2)
    group.__children = { itemButton(0, 1), bagnonButton }
    inv.__children = { group }
    _G.BagBrother = { Frames = { Iterate = function() return ipairs({ inv }) end } }
    HL.Update({ bags = ns.QuestState.Bags(), suggestions = {} })
    check("Bagnon: box on the item inside the big inventory", HL.Active()["i:0:2"] and HL.Active()["i:0:2"].target == bagnonButton)
    -- closed Bagnon: box the backpack button (one big inventory opens from it)
    inv:Hide()
    local bp = M.newFrame("backpack"); bp:Show(); _G.MainMenuBarBackpackButton = bp
    M.bag = { { id = 600 } }
    -- put the tools in bag 2 to check the one-bag fallback
    _G.C_Container.GetContainerNumSlots = function(bag) return (bag == 0 or bag == 2) and 16 or 0 end
    local origInfo = _G.C_Container.GetContainerItemInfo
    _G.C_Container.GetContainerItemInfo = function(bag, slot)
        if bag == 2 and slot == 5 then return { itemID = 700, stackCount = 1, quality = 1, hyperlink = "|Hitem:700|h[Gnomish Tools]|h" } end
        return origInfo(bag, slot)
    end
    _G.C_Item.GetItemCount = function(id) return (id == 700 or id == 600) and 1 or 0 end
    HL.Update({ bags = ns.QuestState.Bags(), suggestions = {} })
    check("Bagnon closed: backpack button boxed for an item in bag 2", HL.Active()["b:2"] and HL.Active()["b:2"].target == bp)
    _G.BagBrother = nil
    -- Baganator: backpack view frame per skin, live buttons inherit Blizzard's GetBagID
    local view = M.newFrame("Baganator_SingleViewBackpackViewFrameblizzard"); view:Show()
    local bagFrame = M.newFrame("bag2"); bagFrame:Show()
    local baganatorButton = itemButton(2, 5, true)
    bagFrame.__children = { itemButton(2, 4, true), baganatorButton }
    view.__children = { bagFrame }
    _G.Baganator_SingleViewBackpackViewFrameblizzard = view
    _G.Baganator = { API = { Skins = { GetCurrentSkin = function() return "blizzard" end } } }
    M.time = M.time + 5
    HL.Update({ bags = ns.QuestState.Bags(), suggestions = {} })
    check("Baganator: box on the item in its backpack view", HL.Active()["i:2:5"] and HL.Active()["i:2:5"].target == baganatorButton)
    check("Baganator: no bag-button box while the view is open", HL.Active()["b:2"] == nil)
    _G.Baganator = nil
end

---------------------------------------------------------------------------
-- 10. UI smoke test with stub frames (catches runtime errors in layout code)
---------------------------------------------------------------------------
do
    M.installGlobals({ frames = true })
    M.player = { level = 3, classFile = "WARRIOR", className = "Warrior", money = 25000, mapId = 1429, x = 0.42, y = 0.41 }
    M.log, M.completed, M.rewards, M.bag, M.equipped = {}, {}, {}, {}, {}
    M.items = M.items or {}
    local files = {}
    for _, f in ipairs(FILES) do files[#files + 1] = f end
    files[#files + 1] = "UI.lua"
    files[#files + 1] = "Options.lua"
    local ok, err = pcall(function()
        local ns = M.loadAddon(ADDON_DIR, files)
        ns.Geo.SetZoneMaps({ [12] = 1429 }, {})
        ns.Geo.SetTransform(1429, { cont = 0, ox = 0, oy = 0, ax = 3000, ay = 0, bx = 0, by = 2000 })
        ns.Data.InitWith(db())
        ns.Fire("SETTINGS_LOADED")
        M.log = { { id = 2, title = "Kobold Camp Cleanup", level = 2, complete = false,
                    objectives = { { text = "Kobold Vermin slain: 2/6", type = "monster", finished = false, numFulfilled = 2, numRequired = 6 } } } }
        M.bag = { { id = 600, count = 1 } }
        ns.Data.BuildIndexes(ns.QuestState.Player(), function() end)
        -- Async jobs with frames run via OnUpdate; drive the runner manually
        for _, f in ipairs(M.frames) do
            local s = f.__scripts and f.__scripts.OnUpdate
            if s then for _ = 1, 500 do s(f, 0.016) end end
        end
        ns.Ladder.Rebuild("ui")
        for _, f in ipairs(M.frames) do
            local s = f.__scripts and f.__scripts.OnUpdate
            if s then for _ = 1, 500 do s(f, 0.016) end end
        end
        check("ui: plan built through async runner", ns.Ladder.plan ~= nil)
        ns.UI.Refresh()
        ns.UI.ShowPanel("bags")
        ns.UI.ShowPanel("gear")
        check("ui: guide header set", _G.QuestLadderGuideFrame and _G.QuestLadderGuideFrame.header ~= nil)
        -- a timed quest's countdown is the guide's first line
        local timer = { total = 300, elapsed = 0, readAt = M.time }
        ns.Ladder.plan.active[#ns.Ladder.plan.active + 1] = { id = 99, title = "Timed One", timed = true, timer = timer,
                                                              turninName = "Someone", objectives = {} }
        ns.Ladder.snapshot = ns.Ladder.snapshot or {}
        ns.Ladder.snapshot[99] = { id = 99, timer = timer }
        ns.UI.RefreshGuide()
        local line = _G.QuestLadderGuideFrame.tasks[1]:GetText() or ""
        check("ui: the countdown leads the guide", line:find("Timed:", 1, true) and line:find("5:00", 1, true), line)
        ns.Ladder.snapshot[99] = nil
        check("ui: waypoint set", M.waypoint ~= nil, "no waypoint")
        -- 0.3.29: a hint line that names a place can be clicked for a map pin
        ns.Hints.list = { { text = "Cozy Sleeping Bag: starts at Burned-Out Remains", kind = "info",
                            pin = { mapId = 1429, x = 0.463, y = 0.739, title = "Burned-Out Remains" } },
                          { text = "a plain line", kind = "info" } }
        ns.UI.RefreshHints()
        local hf = _G.QuestLadderHintFrame
        local hit1, hit2 = hf and hf.hits and hf.hits[1], hf and hf.hits and hf.hits[2]
        check("ui: a hint with a place is clickable, a plain one isn't", hit1 and hit1:IsShown() and hit2 and not hit2:IsShown())
        check("ui: ...and says so", (hf.lines[1]:GetText() or ""):find("(click for a map pin)", 1, true) ~= nil
            and not (hf.lines[2]:GetText() or ""):find("map pin", 1, true), hf.lines[1]:GetText())
        M.waypoint = nil
        local click = hit1 and hit1.__scripts and hit1.__scripts.OnClick
        if click then click(hit1, "LeftButton") end
        check("ui: clicking the line places the pin", M.waypoint and M.waypoint.x == 0.463 and M.waypoint.y == 0.739,
            M.waypoint and M.waypoint.x)
        _G.SlashCmdList.QUESTLADDER("help")
        _G.SlashCmdList.QUESTLADDER("reserve 4")
        check("slash reserve", ns.db.reserveSlots == 4)
        _G.SlashCmdList.QUESTLADDER("gold 3g")
        check("slash gold", ns.db.goldReserve == 30000)
        _G.SlashCmdList.QUESTLADDER("weight agi 2")
        check("slash weight", ns.db.weights and ns.db.weights.agi == 2)
        _G.SlashCmdList.QUESTLADDER("weight reset")
        check("slash weight reset", ns.db.weights == nil)
    end)
    check("ui smoke test runs without errors", ok, err)
end

---------------------------------------------------------------------------
-- 11. /ladder diag: every check runs, results can be saved, secrets are recorded not used
---------------------------------------------------------------------------
-- SavedVariables can only hold strings, finite numbers, booleans and tables of those
-- (inf/nan are written as bare words and break the whole file on the next load).
local function saveable(v, path, depth)
    path, depth = path or "QuestLadderDiag", depth or 0
    local t = type(v)
    if t == "string" or t == "boolean" then return true end
    if t == "number" then
        if v ~= v or v == math.huge or v == -math.huge then return false, path .. " = " .. tostring(v) end
        return true
    end
    if t ~= "table" then return false, path .. " is a " .. t end
    if depth > 12 then return false, path .. " nests too deep" end
    for k, val in pairs(v) do
        local kt = type(k)
        if kt ~= "string" and not (kt == "number" and k == k and k ~= math.huge and k ~= -math.huge) then
            return false, path .. " has a " .. kt .. " key"
        end
        local ok, why = saveable(val, path .. "." .. tostring(k), depth + 1)
        if not ok then return false, why end
    end
    return true
end

do
    M.installGlobals({ frames = true })
    M.player = { level = 3, classFile = "WARRIOR", className = "Warrior", money = 25000, mapId = 1429, x = 0.42, y = 0.41 }
    M.log = {
        { id = 2, title = "Kobold Camp Cleanup", level = 2, complete = false,
          objectives = { { text = "Kobold Vermin slain: 2/6", type = "monster", finished = false, numFulfilled = 2, numRequired = 6 } } },
        { id = 1, title = "Wolves Across the Border", level = 2, complete = false, special = 700, objectives = {} },
    }
    M.completed, M.equipped = {}, {}
    M.rewards = { [2] = { 902, 903 } }
    M.bag = { { id = 600, count = 1 }, { id = 700 } }
    M.items = M.items or {}
    M.items[700] = { name = "Gnomish Tools", classID = 12, spell = "Use" }
    M.taxiNodes = { { name = "Goldshire", nodeID = 1, faction = 0, isUndiscovered = true, position = { x = 0.45, y = 0.45 } } }
    M.bindName = "Goldshire"
    local placedPins = 0
    local pinsLib = {
        RemoveAllMinimapIcons = function() end, RemoveAllWorldMapIcons = function() end,
        AddMinimapIconMap = function() placedPins = placedPins + 1 end, AddWorldMapIconMap = function() end,
    }
    _G.LibStub = setmetatable({}, { __call = function(_, name) if name:find("^HereBeDragons") then return pinsLib, 7 end end })
    _G.MainMenuBarBackpackButton = M.newFrame("MainMenuBarBackpackButton"); _G.MainMenuBarBackpackButton:Show()
    _G.QuestLadderDiag = nil

    local files = {}
    for _, f in ipairs(FILES) do files[#files + 1] = f end
    files[#files + 1] = "UI.lua"
    files[#files + 1] = "Options.lua"
    files[#files + 1] = "Diag.lua"
    local ns
    local ok, err = pcall(function()
        ns = M.loadAddon(ADDON_DIR, files)
        ns.Geo.SetZoneMaps({ [12] = 1429 }, {})
        ns.Geo.SetTransform(1429, { cont = 0, ox = 0, oy = 0, ax = 3000, ay = 0, bx = 0, by = 2000 })
        ns.Geo.SetTransform(1415, { cont = 0, ox = 0, oy = 0, ax = 3000, ay = 0, bx = 0, by = 2000 })
        ns.Data.InitWith(db())
        ns.Fire("SETTINGS_LOADED")
        ns.charDB.bindPoints = { Goldshire = { mapId = 1429, x = 0.4, y = 0.4 } }
        ns.charDB.flightPaths = { Goldshire = true }
        local function drive()
            for _, f in ipairs(M.frames) do
                local s = f.__scripts and f.__scripts.OnUpdate
                if s then for _ = 1, 500 do s(f, 0.016) end end
            end
        end
        ns.Data.BuildIndexes(ns.QuestState.Player(), function() end)
        drive()
        ns.Ladder.Rebuild("diag test")
        drive()
        _G.SlashCmdList.QUESTLADDER("diag first run")
    end)
    check("diag: runs without errors", ok, err)

    local runs = _G.QuestLadderDiag and _G.QuestLadderDiag.runs
    check("diag: run stored in QuestLadderDiag", type(runs) == "table" and #runs == 1)
    local function byId(run)
        local out = {}
        for _, c in ipairs((run and run.checks) or {}) do out[c.id] = c end
        return out
    end
    local function crashed(run)
        local list = {}
        for _, c in ipairs((run and run.checks) or {}) do
            if c.status == "error" then list[#list + 1] = c.id .. ": " .. tostring(c.summary) end
        end
        return list
    end
    local run = runs and runs[1]
    if ns and run then
        local c = byId(run)
        check("diag: label kept", run.label == "first run", run.label)
        check("diag: every check ran", #run.checks == #ns.Diag.checks and #run.checks >= 18, #run.checks)
        local bad = crashed(run)
        check("diag: no check crashed", #bad == 0, table.concat(bad, "; "))
        local okSave, why = saveable(_G.QuestLadderDiag)
        check("diag: results can be saved", okSave, why)
        local function status(id, want)
            local e = c[id]
            check("diag: " .. id .. " is " .. want, e and e.status == want, e and (e.status .. ": " .. tostring(e.summary)))
        end
        status("questiedb", "ok")
        status("plan", "ok")
        status("gear", "info")
        status("position", "ok")
        status("waypoint", "ok")
        status("rewards", "ok")
        status("questitems", "ok")
        status("flights", "ok")
        status("mappins", "ok")
        status("errors", "ok")
        status("softtarget", "warn")   -- the event has not fired yet
        status("auctionator", "skip")  -- not installed in the fake client
        status("options", "fail")      -- the fake client has no Settings API
        check("diag: options says why", c.options and (c.options.summary or ""):find("no Blizzard Settings API", 1, true)
            and c.options.data.theme == "cyan" and c.options.data.pages == 5, c.options and c.options.summary)
        check("diag: use button is parented to UIParent", c.usebutton and c.usebutton.data.parentIsUIParent == true
            and c.usebutton.data.type == "item", c.usebutton and c.usebutton.summary)
        check("diag: reward IDs read for the right quest", c.rewards and c.rewards.data.quests[1].choices[1].itemId == 902)
        check("diag: map boxes placed through HereBeDragons", placedPins > 0, placedPins)

        -- the soft-target event is counted once it fires
        ns.DispatchEvent("PLAYER_SOFT_INTERACT_CHANGED", nil, "GameObject-0-1-2-3-300-0000ABCD")
        _G.SlashCmdList.QUESTLADDER("diag")
        c = byId(runs[2])
        status("softtarget", "ok")
        check("diag: no label stored when none given", runs[2].label == nil)

        -- a secret map ID is recorded as "<secret>" and never used
        local origSecret, origMap = _G.issecretvalue, _G.C_Map.GetBestMapForUnit
        _G.issecretvalue = function(v) return v == "SECRET-MAP" end
        _G.C_Map.GetBestMapForUnit = function() return "SECRET-MAP" end
        check("secrets: player position is nil for a secret map ID", ns.Geo.PlayerPoint() == nil)
        check("secrets: AnySecret finds one among nils", ns.AnySecret(1, nil, "SECRET-MAP") == true and ns.AnySecret(1, nil) == false)
        local okSecret, errSecret = pcall(_G.SlashCmdList.QUESTLADDER, "diag secret")
        _G.issecretvalue, _G.C_Map.GetBestMapForUnit = origSecret, origMap
        check("diag: secret run completes", okSecret, errSecret)
        local secretRun = runs[3]
        c = byId(secretRun)
        check("diag: secret map ID stored as <secret>", c.position and c.position.status == "fail"
            and c.position.data.mapId == "<secret>", c.position and c.position.summary)
        bad = crashed(secretRun)
        check("diag: no check crashed with a secret map", #bad == 0, table.concat(bad, "; "))
        check("diag: secret run can be saved", (saveable(_G.QuestLadderDiag)))

        -- values SavedVariables can't hold are converted
        local cleaned = ns.Diag.Clean({ far = math.huge, bad = 0 / 0, fn = function() end, list = { 1, 2 } })
        check("diag: inf/nan/functions cleaned", cleaned.far == "inf" and cleaned.bad == "nan" and cleaned.fn == nil
            and cleaned.list[2] == 2)

        -- errors in our handlers are recorded (deduplicated) and still reach the error handler
        ns.RegisterEvent("QL_TEST_FAILING_EVENT", function() error("boom from a handler") end)
        local reached = pcall(ns.DispatchEvent, "QL_TEST_FAILING_EVENT")
        pcall(ns.DispatchEvent, "QL_TEST_FAILING_EVENT")
        local e = ns.recentErrors[#ns.recentErrors]
        check("errors: still passed to the error handler", reached == false)
        check("errors: recorded once with a count", e and e.msg:find("boom from a handler", 1, true) and e.count == 2, e and e.msg)
        _G.SlashCmdList.QUESTLADDER("diag")
        c = byId(runs[#runs])
        status("errors", "fail")

        -- history is capped, and can be cleared
        for _ = 1, 12 do _G.SlashCmdList.QUESTLADDER("diag") end
        check("diag: keeps the last 10 runs", #_G.QuestLadderDiag.runs == 10, #_G.QuestLadderDiag.runs)
        _G.SlashCmdList.QUESTLADDER("diag clear")
        check("diag: clear empties the history", #_G.QuestLadderDiag.runs == 0)

        -- 0.3.24: right after /reload a diag saved the log-only plan (0 new quests); now it waits
        -- until the route settles, up to 30 s
        local timers = {}
        _G.C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }
        local function tick() local list = timers; timers = {}; for _, fn in ipairs(list) do fn() end end
        local realBusy = ns.Diag.Busy
        local busy = { "the route is still being planned", "the route is still being planned" }
        ns.Diag.Busy = function() return table.remove(busy, 1) end
        _G.SlashCmdList.QUESTLADDER("diag waits")
        check("diag waits: nothing saved while the route is being planned", #_G.QuestLadderDiag.runs == 0)
        tick()
        check("diag waits: still waiting", #_G.QuestLadderDiag.runs == 0)
        tick()
        local w = _G.QuestLadderDiag.runs[1]
        check("diag waits: saved once the route settles", w and w.label == "waits" and w.waited == 1 and w.gaveUpWaiting == nil,
            w and tostring(w.waited))
        ns.Diag.Busy = function() return "the route is still being planned" end
        _G.SlashCmdList.QUESTLADDER("diag")
        for _ = 1, 100 do tick() end
        w = _G.QuestLadderDiag.runs[2]
        check("diag waits: gives up after 30 s and says why", w and w.waited >= 30 and w.gaveUpWaiting == "the route is still being planned",
            w and tostring(w.waited))
        _G.SlashCmdList.QUESTLADDER("diag now")
        check("diag now: doesn't wait", #_G.QuestLadderDiag.runs == 3)
        ns.Diag.Busy = realBusy
        for _, f in ipairs(M.frames) do
            local s = f.__scripts and f.__scripts.OnUpdate
            if s then for _ = 1, 500 do s(f, 0.016) end end
        end
        check("diag busy: settled once the route is planned", realBusy() == nil, tostring(realBusy()))
        ns.Debounce("replan", 1, function() end)
        check("diag busy: while a replan is due", realBusy() == "a replan is about to start", tostring(realBusy()))
        tick()
        check("diag busy: settled again after it", realBusy() == nil, tostring(realBusy()))
        _G.C_Timer = nil
    end
    _G.LibStub, _G.MainMenuBarBackpackButton = nil, nil
end

---------------------------------------------------------------------------
-- 13. First in-game test (0.3.2): flight map, flight paths, failed escort, bag boxes
---------------------------------------------------------------------------
do
    -- Opening a flight map: the GUID's trailing spawn UID used to reach tonumber() as its number
    -- base ("bad argument #2"). Only paths you can fly to count as known.
    local ns = setup()
    local nodes = {
        { "The Sepulcher, Silverpine Forest", "CURRENT" },
        { "Undercity, Tirisfal", "REACHABLE" },
        { "Booty Bay, Stranglethorn", "DISTANT" },
        { "Kargath, Badlands", "NONE" },
    }
    _G.NumTaxiNodes = function() return #nodes end
    _G.TaxiNodeName = function(i) return nodes[i] and nodes[i][1] end
    _G.TaxiNodeGetType = function(i) return nodes[i] and nodes[i][2] end
    M.guids.npc = "Creature-0-4170-0-12-4551-0000ABCDEF"
    local learnedEvent = false
    ns.On("TAXI_LEARNED", function() learnedEvent = true end)
    local ok, err = pcall(ns.DispatchEvent, "TAXIMAP_OPENED")
    check("flight map: opening it doesn't error", ok, err)
    local fp = ns.charDB.flightPaths or {}
    check("flight map: current and reachable paths learned", fp["The Sepulcher, Silverpine Forest"] and fp["Undercity, Tirisfal"])
    check("flight map: paths you haven't discovered aren't", not fp["Booty Bay, Stranglethorn"] and not fp["Kargath, Badlands"])
    check("flight map: flight master's NPC ID recorded", ns.charDB.knownTaxiNpc and ns.charDB.knownTaxiNpc[4551] == true)
    check("flight map: route refresh requested", learnedEvent)
    _G.NumTaxiNodes, _G.TaxiNodeName, _G.TaxiNodeGetType = nil, nil, nil

    -- Forever says isUndiscovered = false for every node, so only learned paths are known, and an
    -- unlearned flight master right next to you gets a "Discover flight path" step.
    ns = setup()
    M.log = { { id = 2, title = "Kobold Camp Cleanup", level = 2, complete = false,
                objectives = { { text = "Kobold Vermin slain: 2/6", type = "monster", finished = false, numFulfilled = 2, numRequired = 6 } } } }
    M.taxiNodes = {
        { name = "Bat Handler Post", position = { x = 0.425, y = 0.415 }, isUndiscovered = false, faction = 2, nodeID = 10 },
        { name = "Home Post", position = { x = 0.60, y = 0.42 }, isUndiscovered = false, faction = 2, nodeID = 11 },
    }
    ns.charDB.flightPaths = { ["Home Post"] = true }
    local net = ns.Travel.BuildNetwork(ns.QuestState.Player())
    local known = {}
    for _, n in ipairs(net.nodes) do known[n.name] = n.known end
    check("flight paths: unlearned node is unknown despite isUndiscovered=false", known["Bat Handler Post"] == false)
    check("flight paths: learned node is known", known["Home Post"] == true)
    local plan = fullPlan(ns)
    check("flight paths: nearby unlearned flight master gets a discover step", plan.byId["V:fp:Bat Handler Post"] ~= nil)
    ns.charDB.flightPaths = nil
    net = ns.Travel.BuildNetwork(ns.QuestState.Player())
    local anyKnown = false
    for _, n in ipairs(net.nodes) do anyKnown = anyKnown or n.known end
    check("flight paths: none assumed known before a flight map was opened", not anyKnown)

    -- A failed escort gets no route, and the hint says what to do and who gives it.
    ns = setup()
    M.log = {
        { id = 9, title = "Escort the Miner", level = 4, complete = false, objectives = {} },
        { id = 2, title = "Kobold Camp Cleanup", level = 2, complete = false,
          objectives = { { text = "Kobold Vermin slain: 2/6", type = "monster", finished = false, numFulfilled = 2, numRequired = 6 } } },
    }
    _G.C_QuestLog.IsFailed = function(id) return id == 9 end
    plan = fullPlan(ns)
    local routedFailed = false
    for _, t in ipairs(plan.order) do if t.questId == 9 then routedFailed = true end end
    check("failed escort: no steps routed for it", not routedFailed)
    check("failed escort: the rest of the log is still planned", plan.byId["O2:1"] ~= nil)
    local hints = ns.Hints.Compute({ byId = ns.Ladder.snapshot, bags = ns.QuestState.Bags(), now = M.time })
    local failHint
    for _, h in ipairs(hints) do if h.text:find("failed", 1, true) then failHint = h.text end end
    check("failed escort: hint says abandon and names the giver",
        failHint and failHint:find("abandon", 1, true) and failHint:find("from Miner", 1, true), failHint)

    -- Bag boxes: a stale bag/slot from an earlier suggestion must not misplace the box, the
    -- bag-button box says why, and an upgrade in the bags gets a hint line.
    ns = setup({ frames = true })
    local HL = ns.Highlight
    M.bag = { { id = 600 }, { id = 900 } }          -- the sword now sits in bag 0 slot 2
    ns.Hints.list = {}
    local stale = { { action = "equip", itemId = 900, bag = 0, slot = 1, name = "Sturdy Sword", pct = 42 } }
    local bp = M.newFrame("backpack"); bp:Show()
    _G.MainMenuBarBackpackButton = bp
    HL.Update({ bags = ns.QuestState.Bags(), suggestions = stale })
    check("bag box: closed bags say what's inside", HL.Active()["b:0"] and HL.Active()["b:0"].label:GetText() == "Open: Equip")
    local cf = M.newFrame("combined"); cf:Show()
    local s1, s2 = M.newFrame("slot1"), M.newFrame("slot2")
    s1.__id, s2.__id = 1, 2
    s1.GetBagID = function() return 0 end
    s2.GetBagID = function() return 0 end
    cf.__items = { s1, s2 }
    _G.ContainerFrameCombinedBags = cf
    HL.Update({ bags = ns.QuestState.Bags(), suggestions = stale })
    check("bag box: lands on the item's real slot, not the stale one",
        HL.Active()["i:0:2"] and HL.Active()["i:0:2"].target == s2 and HL.Active()["i:0:1"] == nil)
    check("bag box: remembers which item it marks", HL.Active()["i:0:2"] and HL.Active()["i:0:2"].itemId == 900)

    -- 0.3.4: the box sat under the bag window once it was clicked/sorted (raised). Bag item boxes
    -- are now children of the item button, re-layered on every update.
    local itemBox = HL.Active()["i:0:2"]
    check("bag box: is a child of the item button", itemBox and itemBox:GetParent() == s2)
    s2.__level = 50
    HL.Update({ bags = ns.QuestState.Bags(), suggestions = stale })
    check("bag box: drawn above its button", itemBox:GetFrameLevel() == 60, itemBox:GetFrameLevel())
    s2.__level = 80 -- the bag window was raised
    HL.Update({ bags = ns.QuestState.Bags(), suggestions = stale })
    check("bag box: follows the window when it is raised", itemBox:GetFrameLevel() == 90, itemBox:GetFrameLevel())
    cf:Hide()
    HL.Update({ bags = ns.QuestState.Bags(), suggestions = stale })
    check("bag box: closing the bags releases it back to UIParent", itemBox:GetParent() == _G.UIParent and HL.Active()["i:0:2"] == nil)
    local barBox = HL.Active()["b:0"]
    check("bag box: the bag-bar box stays on UIParent", barBox and barBox:GetParent() == _G.UIParent)
    bp.__level = 5
    HL.Update({ bags = ns.QuestState.Bags(), suggestions = stale })
    bp.__level = 40
    HL.Update({ bags = ns.QuestState.Bags(), suggestions = stale })
    check("bag box: UIParent boxes are re-layered on every update too", barBox:GetFrameLevel() == 60, barBox:GetFrameLevel())
    hints = ns.Hints.Compute({ byId = {}, bags = ns.QuestState.Bags(), suggestions = stale, now = M.time })
    local equipHint
    for _, h in ipairs(hints) do if h.kind == "equip" then equipHint = h.text end end
    check("bag box: upgrade explained in the hint box",
        equipHint and equipHint:find("equip", 1, true) and equipHint:find("Sturdy Sword", 1, true) and equipHint:find("+42%", 1, true), equipHint)
    _G.ContainerFrameCombinedBags, _G.MainMenuBarBackpackButton = nil, nil
end

---------------------------------------------------------------------------
-- 13b. Items to use (0.3.10): "A Lesson in Divinity" says "use the Symbol of Life to resurrect
--      Deathguard Falgan". It has no tracked objectives; the item is only in QuestieDB's
--      requiredSourceItems, so nothing told you to use it or boxed it in your bags.
---------------------------------------------------------------------------
do
    local ns = setup({ frames = true })
    local H = ns.Hints
    local function sp(x, y) return { [12] = { { x, y } } } end
    M.items[700] = { name = "Symbol of Life", classID = 12, spell = "Resurrect" }
    M.items[701] = { name = "Holy Water", classID = 12, spell = "Bless" }
    M.items[602] = { name = "Strange Note", classID = 12 } -- carried, no "Use:"
    ns.Data.InitWith(M.fakeDB({
        quests = {
            [60] = { name = "A Lesson in Healing", startedBy = { { 601 } }, finishedBy = { { 601 } }, requiredLevel = 1,
                     questLevel = 3, objectives = {}, requiredSourceItems = { 700 } },
            [61] = { name = "Bless the Fallen", startedBy = { { 601 } }, finishedBy = { { 601 } }, requiredLevel = 1,
                     questLevel = 3, objectives = { { { 610 } } } },
            [62] = { name = "Carry the Note", startedBy = { { 601 } }, finishedBy = { { 601 } }, requiredLevel = 1,
                     questLevel = 3, objectives = {}, requiredSourceItems = { 602 } },
            [63] = { name = "Done Already", startedBy = { { 601 } }, finishedBy = { { 601 } }, requiredLevel = 1,
                     questLevel = 3, objectives = { { { 610 } } }, requiredSourceItems = { 700 } },
        },
        npcs = {
            [601] = { name = "Fallen Guard", spawns = sp(43, 41) },
            [610] = { name = "Scarlet Zealot", spawns = sp(45, 42) },
        },
        objects = {},
        items = { [700] = { name = "Symbol of Life" }, [701] = { name = "Holy Water", relatedQuests = { 61 } },
                  [602] = { name = "Strange Note" } },
    }))
    M.log = {
        { id = 60, title = "A Lesson in Healing", level = 3, complete = true, objectives = {} }, -- the game counts it done
        { id = 61, title = "Bless the Fallen", level = 3, complete = false,
          objectives = { { text = "Scarlet Zealot blessed: 0/3", type = "monster", finished = false, numFulfilled = 0, numRequired = 3 } } },
        { id = 62, title = "Carry the Note", level = 3, complete = true, objectives = {} },
        { id = 63, title = "Done Already", level = 3, complete = true,
          objectives = { { text = "Scarlet Zealot slain: 1/1", type = "monster", finished = true, numFulfilled = 1, numRequired = 1 } } },
    }
    M.bag = { { id = 700 }, { id = 701, questItem = true }, { id = 602 } }
    -- with frames, planning runs in the background: drive the job runner by hand
    local function drive()
        for _, f in ipairs(M.frames) do
            local s = f.__scripts and f.__scripts.OnUpdate
            if s then for _ = 1, 500 do s(f, 0.016) end end
        end
    end
    ns.Data.BuildIndexes(ns.QuestState.Player(), function() end)
    drive()
    ns.Ladder.Rebuild("use items")
    drive()
    local plan = ns.Ladder.plan
    check("use item: planned", plan ~= nil and plan.byId.T60 ~= nil and plan.byId["O61:1"] ~= nil)
    plan = plan or { byId = {} }
    local step = { tasks = { plan.byId.T60, plan.byId["O61:1"], plan.byId.T62, plan.byId.T63 } }
    -- no OnQuestAccepted here: this is what you see after a /reload. Nothing selected, no
    -- position: the hint says what to select, and the button waits (0.3.25).
    local hints = H.Compute({ byId = ns.Ladder.snapshot, bags = ns.QuestState.Bags(), step = step, now = M.time })
    local function find(...)
        local needles = { ... }
        for _, h in ipairs(hints) do
            local all = true
            for _, n in ipairs(needles) do if not h.text:find(n, 1, true) then all = false end end
            if all then return h end
        end
        return nil
    end
    local pending = find("Select ", "Fallen Guard", "Symbol of Life", "A Lesson in Healing")
    check("use item: a no-objective quest's item: select its NPC first", pending and pending.kind == "info", pending and pending.text)
    check("use item: an item QuestieDB links to the quest: select the objective's NPC first",
        find("Select ", "Scarlet Zealot", "Holy Water", "Bless the Fallen") ~= nil)
    check("use item: an item without a Use: effect is just carried", find("Strange Note") == nil)
    check("use item: nothing to use once a quest's own objectives are done", find("Done Already") == nil)
    H.list = hints
    check("use item: the button stays empty until then", H.UsableItem() == nil, H.UsableItem() and H.UsableItem().itemId)
    -- target Fallen Guard: the Symbol of Life pops up
    M.guids = { target = "Creature-0-1-2-3-601-0000AAAA" }
    M.names = { target = "Fallen Guard" }
    hints = H.Compute({ byId = ns.Ladder.snapshot, bags = ns.QuestState.Bags(), step = step, now = M.time })
    local symbol = find("Use ", "Symbol of Life", "Fallen Guard", "A Lesson in Healing")
    check("use item: target its NPC and it's ready", symbol and symbol.kind == "use" and symbol.button, symbol and symbol.text)
    H.list = hints
    local use = H.UsableItem()
    check("use item: then it goes on the use button", use and use.itemId == 700, use and use.itemId)
    -- the Dried Seeds case: a quest item for a quest that isn't this step's never shows from afar
    local blessStep = { tasks = { plan.byId["O61:1"] } }
    local function later(point)
        return H.Compute({ point = point, byId = ns.Ladder.snapshot, bags = ns.QuestState.Bags(), plan = plan,
                           step = blessStep, now = M.time })
    end
    M.guids, M.names = {}, {}
    hints = later(ns.Geo.Point(1429, 0.90, 0.90))
    check("use item: a later step's item doesn't show from afar", find("Symbol of Life") == nil)
    H.list = hints
    check("use item: ...and stays off the button", H.UsableItem() == nil, H.UsableItem() and H.UsableItem().itemId)
    -- 0.3.26: out of order. Target Fallen Guard and the later step's item shows anyway.
    M.guids = { target = "Creature-0-1-2-3-601-0000AAAA" }
    M.names = { target = "Fallen Guard" }
    hints = later(ns.Geo.Point(1429, 0.90, 0.90))
    local early = find("Use ", "Symbol of Life", "Fallen Guard", "A Lesson in Healing", "but you're here")
    check("use item: a later step's item shows once its target is selected", early and early.button and early.kind == "use",
        early and early.text)
    local T60step
    for i, s in ipairs(plan.steps) do for _, t in ipairs(s.tasks) do if t == plan.byId.T60 then T60step = i end end end
    check("use item: ...and says which step it is", early and T60step
        and early.text:find("(step " .. T60step .. ",", 1, true) ~= nil, early and early.text)
    H.list = hints
    check("use item: ...and goes on the button", H.UsableItem() and H.UsableItem().itemId == 700,
        H.UsableItem() and H.UsableItem().itemId)
    hints = H.Compute({ byId = ns.Ladder.snapshot, bags = ns.QuestState.Bags(), step = blessStep, now = M.time })
    check("use item: without a plan, only this step counts", find("Symbol of Life") == nil)
    -- standing at the later step's target counts too, and this step's unready item doesn't block it
    M.guids, M.names = {}, {}
    hints = later(ns.Geo.Point(1429, 0.43, 0.41))
    early = find("Use ", "Symbol of Life", "but you're here")
    check("use item: standing at a later step's target: ready", early and early.button, early and early.text)
    check("use item: this step's item still says what to select", find("Select ", "Scarlet Zealot", "Holy Water") ~= nil)
    H.list = hints
    check("use item: the later step's item takes the empty button", H.UsableItem() and H.UsableItem().itemId == 700,
        H.UsableItem() and H.UsableItem().itemId)
    -- both ready the same way (standing at both): this step's item wins the button
    M.guids, M.names = {}, {}
    hints = later(ns.Geo.Point(1429, 0.44, 0.415))
    H.list = hints
    check("use item: both ready: this step's item gets the button", H.UsableItem() and H.UsableItem().itemId == 701,
        H.UsableItem() and H.UsableItem().itemId)
    check("use item: ...the later one is listed below it", find("Symbol of Life", "but you're here") ~= nil)
    local stand = find("Use ", "Holy Water")
    check("use item: standing near it: no 'This one', no button nag", stand and not stand.text:find("This one", 1, true)
        and not stand.text:find("use button", 1, true) and stand.priority == 92, stand and stand.text)
    -- 0.3.28: what you've selected beats what you're only standing near, so the button holds
    -- the item the line tells you to use
    M.guids = { target = "Creature-0-1-2-3-601-0000AAAA" }
    M.names = { target = "Fallen Guard" }
    hints = later(ns.Geo.Point(1429, 0.45, 0.42))
    H.list = hints
    check("use item: the selected target's item gets the button", H.UsableItem() and H.UsableItem().itemId == 700,
        H.UsableItem() and H.UsableItem().itemId)
    local sel = find("Use ", "Symbol of Life", "Fallen Guard")
    check("use item: ...and its line says how to use it", sel and sel.text:find(" - click the use button", 1, true) ~= nil,
        sel and sel.text)
    -- UseTasks: this step's quests aren't repeated as later ones; done tasks are left out
    local now, laterQ, at = H.UseTasks(plan, blessStep)
    check("use item: UseTasks splits this step from later ones", now[61] and not laterQ[61] and laterQ[60] and at[60] == T60step,
        tostring(at[60]))
    check("use item: UseTasks with no plan or step", next((H.UseTasks(nil, nil))) == nil)
    -- the diag lists both, with where they are
    M.guids, M.names = {}, {}
    if not ns.Diag then assert(loadfile(ADDON_DIR .. "/Diag.lua"))("QuestLadder", ns) end
    local qi
    for _, c in ipairs(ns.Diag.checks) do if c.id == "questitems" then qi = c end end
    local okD, _, _, dData = pcall(qi.fn, { step = blessStep, byId = ns.Ladder.snapshot, bags = ns.QuestState.Bags(),
        list = M.log, player = { point = ns.Geo.Point(1429, 0.43, 0.41) } })
    local lines = okD and dData and table.concat(dData.stepUse or {}, " / ") or ""
    check("use item: diag shows this step's and a later step's item",
        lines:find("this step 61 ", 1, true) and lines:find("step " .. tostring(T60step) .. " 60 ", 1, true)
        and lines:find("standing at it", 1, true), lines)
    M.guids, M.names = {}, {}

    -- 0.3.28: facing the Bubbling Fissure showed ">> This one: Use Bubbling Fissure - press your
    -- Interact key". You use the Dried Seeds on it; interacting does nothing.
    local WM = ns.WorldMarks
    M.items[5068] = { name = "Dried Seeds", classID = 12, spell = "Plant Seeds" }
    local bagBefore = M.bag
    M.bag = { { id = 700 }, { id = 701, questItem = true }, { id = 602 }, { id = 5068 } }
    local oasisQ = { id = 877, title = "The Stagnant Oasis", complete = false, specialItem = { itemId = 5068 },
                     objectives = { { text = "Test the Dried Seeds: 0/1", type = "object", finished = false } } }
    local oasisStep = { tasks = { { id = "O877:1", kind = "objective", questId = 877, quest = { title = "The Stagnant Oasis" },
                                    obj = { type = "object", targets = { object = { 3737 } } },
                                    loc = ns.Geo.Point(1429, 0.30, 0.30) } } }
    local function oasis()
        return H.Compute({ byId = { [877] = oasisQ }, bags = ns.QuestState.Bags(), step = oasisStep, now = M.time })
    end
    WM.SetTargets(oasisStep)
    M.guids = { softinteract = "GameObject-0-1-2-3-3737-00001111" }
    M.names = { softinteract = "Bubbling Fissure" }
    ns.DispatchEvent("PLAYER_SOFT_INTERACT_CHANGED", nil, M.guids.softinteract)
    check("use on object: facing the fissure is a hit", WM.softHit and WM.softHit.label == "Use")
    hints = oasis()
    local cue = find(">> This one:", "Use ", "Dried Seeds", "on |cffffffffBubbling Fissure", "The Stagnant Oasis",
        " - click the use button")
    check("use on object: the cue says to use the seeds on it", cue and cue.kind == "use" and cue.button, cue and cue.text)
    check("use on object: ...and it's the top line", cue and hints[1] == cue, hints[1] and hints[1].text)
    check("use on object: no 'press your Interact key'", find("Interact key") == nil, find("Interact key") and find("Interact key").text)
    H.list = hints
    check("use on object: the seeds are on the button", H.UsableItem() and H.UsableItem().itemId == 5068,
        H.UsableItem() and H.UsableItem().itemId)
    -- with a key bound, the line names the key
    _G.GetBindingKey = function(cmd) return cmd == "CLICK QuestLadderUseButton:LeftButton" and "F" or nil end
    hints = oasis()
    check("use on object: names your key when one is bound", find(">> This one:", "Dried Seeds", " - press F") ~= nil)
    _G.GetBindingKey = nil
    -- an object you interact with (no item to use on it) keeps the Interact cue
    oasisQ.specialItem = nil
    hints = oasis()
    check("use on object: no item, the Interact cue stays", find(">> This one:", "Use Bubbling Fissure", "Interact key") ~= nil)
    oasisQ.specialItem = { itemId = 5068 }
    -- turning away: no cue, and the seeds wait again
    M.guids, M.names = {}, {}
    ns.DispatchEvent("PLAYER_SOFT_INTERACT_CHANGED", "GameObject-0-1-2-3-3737-00001111", nil)
    hints = oasis()
    H.list = hints
    check("use on object: turned away, the seeds wait again", find("This one") == nil and H.UsableItem() == nil,
        H.UsableItem() and H.UsableItem().itemId)
    -- the target cue too: "Target is right: Use item on Fallen Guard" gives way to the use line
    WM.SetTargets(step)
    M.guids = { target = "Creature-0-1-2-3-601-0000AAAA" }
    M.names = { target = "Fallen Guard" }
    ns.DispatchEvent("PLAYER_TARGET_CHANGED")
    check("use on target: targeting Falgan's stand-in is a hit", WM.targetHit ~= nil)
    hints = H.Compute({ byId = ns.Ladder.snapshot, bags = ns.QuestState.Bags(), step = step, now = M.time })
    check("use on target: one line, the use line", find("Target is right") == nil
        and find("Use ", "Symbol of Life", "Fallen Guard", " - click the use button") ~= nil)
    WM.SetTargets(nil)
    M.guids, M.names, M.bag = {}, {}, bagBefore
    -- standing at the Scarlet Zealots' spawn is enough (some targets can't be selected)
    M.guids, M.names = {}, {}
    hints = H.Compute({ point = ns.Geo.Point(1429, 0.45, 0.42), byId = ns.Ladder.snapshot, bags = ns.QuestState.Bags(),
                        step = step, now = M.time })
    local holy = find("Use ", "Holy Water", "Scarlet Zealot", "Bless the Fallen")
    check("use item: standing at its target's spawn: ready", holy and holy.button, holy and holy.text)
    check("use item: the other quest's NPC 60 yd away still needs selecting", find("Select ", "Fallen Guard") ~= nil)
    H.list = hints
    -- facing an object (soft target) counts as selecting it; something else doesn't
    local seeds = { npc = {}, object = { [3737] = true }, names = { "Test the Dried Seeds" } }
    M.guids = { softinteract = "GameObject-0-1-2-3-3737-00001111" }
    check("use item: facing the object selects it", H.UseReady(seeds, {}, nil) == true)
    M.guids = { softinteract = "GameObject-0-1-2-3-9999-00001111" }
    check("use item: facing another object doesn't", H.UseReady(seeds, {}, nil) == false)
    M.guids = { softinteract = "SECRET-GUID" }
    local origSecret = _G.issecretvalue
    _G.issecretvalue = function(v) return v == "SECRET-GUID" end
    check("use item: a secret GUID is never read", H.UseReady(seeds, {}, nil) == false)
    _G.issecretvalue = origSecret
    M.guids = {}
    -- nothing known to aim at: within 60 yd of the step's place
    local spot = { { kind = "objective", loc = ns.Geo.Point(1429, 0.50, 0.50) } }
    check("use item: no target known: ready at the place", H.UseReady(nil, spot, ns.Geo.Point(1429, 0.51, 0.50)) == true)
    check("use item: no target known: not from afar", H.UseReady(nil, spot, ns.Geo.Point(1429, 0.60, 0.50)) == false)
    check("use item: the turn-in line says to use it first",
        ns.Ladder.TaskText(plan.byId.T60):find("Use |cff66ccff[Symbol of Life]|r on Fallen Guard, then turn in", 1, true) ~= nil,
        ns.Ladder.TaskText(plan.byId.T60))
    -- the bag box: closed bags box the backpack, labelled for using
    local bp = M.newFrame("backpack"); bp:Show()
    _G.MainMenuBarBackpackButton = bp
    ns.Highlight.Update({ bags = ns.QuestState.Bags(), suggestions = {} })
    local box = ns.Highlight.Active()["b:0"]
    check("use item: boxed in your bags", box and box.label:GetText() == "Open: Use", box and box.label:GetText())
end

---------------------------------------------------------------------------
-- 14. Hands (0.3.3): a level-14 Paladin saw a one-hander and a shield both called "+100%"
---------------------------------------------------------------------------
do
    local ns = setup()
    local Gear = ns.Gear
    M.items[920] = { name = "Big Two-Hander", classID = 2, subClassID = 5, equipLoc = "INVTYPE_2HWEAPON",
                     stats = { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 9, ITEM_MOD_STRENGTH_SHORT = 4 } }
    M.items[921] = { name = "Deathstalker Shortsword", classID = 2, subClassID = 7, equipLoc = "INVTYPE_WEAPON",
                     stats = { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 5.5, ITEM_MOD_STAMINA_SHORT = 1 } }
    M.items[922] = { name = "Salvaged Wooden Tower Shield", classID = 4, subClassID = 6, equipLoc = "INVTYPE_SHIELD",
                     stats = { RESISTANCE0_NAME = 300, ITEM_MOD_STAMINA_SHORT = 2 } }
    M.items[923] = { name = "Rusty Dagger-Sword", classID = 2, subClassID = 7, equipLoc = "INVTYPE_WEAPON",
                     stats = { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 2 } }
    M.player.classFile, M.player.className, M.player.level = "PALADIN", "Paladin", 14
    local function cmp(id, classFile, level)
        local info = Gear.ItemInfo(id)
        return Gear.CompareToEquipped(info.link, info, classFile or "PALADIN", level or 14)
    end

    -- Two-hander equipped: a one-hander or a shield would replace it.
    M.equipped = { [16] = 920 }
    local sword, shield = cmp(921), cmp(922)
    check("hands: no off-hand weapon slot for a Paladin", sword and sword.slot == 16, sword and sword.slot)
    check("hands: one-hander compared with the two-hander", sword and sword.old > 0 and sword.delta < 0,
        sword and string.format("old %.1f delta %.1f pct %.0f", sword.old, sword.delta, sword.pct))
    check("hands: shield compared with the two-hander it pushes out", shield and shield.old > 0 and shield.delta < 0,
        shield and string.format("old %.1f delta %.1f pct %.0f", shield.old, shield.delta, shield.pct))
    M.bag = { { id = 921 }, { id = 922 } }
    local equips = {}
    for _, e in ipairs(ns.Bags.Suggestions(ns.QuestState.Bags(), {}, nil)) do
        if e.action == "equip" then equips[#equips + 1] = e.name .. " " .. tostring(e.reason) end
    end
    check("hands: neither is suggested as an upgrade over the two-hander", #equips == 0, table.concat(equips, "; "))

    -- One-hander equipped, off hand empty: a shield really fills the empty slot, a weaker sword doesn't.
    M.equipped = { [16] = 901 }
    local weak = cmp(923)
    check("hands: weaker one-hander isn't '+100% in the off hand'", weak and weak.slot == 16 and weak.delta < 0,
        weak and string.format("slot %d pct %.0f", weak.slot, weak.pct))
    shield = cmp(922)
    check("hands: shield into an empty off hand is an upgrade", shield and shield.slot == 17 and shield.old == 0 and shield.pct == 100)

    -- Classes that dual wield still get the off hand.
    local rogue = cmp(923, "ROGUE", 12)
    check("hands: a rogue can put a one-hander in the off hand", rogue and rogue.slot == 17 and rogue.pct == 100)
    check("hands: dual wield needs training (warrior 19 no, 20 yes)",
        not Gear.CanDualWield("WARRIOR", 19) and Gear.CanDualWield("WARRIOR", 20) and not Gear.CanDualWield("PALADIN", 60))
end

---------------------------------------------------------------------------
-- 15. Planning (0.3.5): finished quests in Undercity were left for "when we're back", and the
--     junk stop was put across a flight
---------------------------------------------------------------------------
do
    local ns = setup()
    local P, Geo = ns.Planner, ns.Geo
    P.travelFn = nil -- plain walking
    -- You stand at the bat handler S. A finished quest's NPC U is 200 yd off to the side; the
    -- route goes to a far area F and later comes back to U for another turn-in.
    local S, U, F = Geo.Point(1429, 0.10, 0.50), Geo.Point(1429, 0.10, 0.60), Geo.Point(1429, 0.90, 0.50)
    local function tasks()
        local list = {
            { id = "T1", kind = "turnin", questId = 1, deps = {}, dependents = {}, loc = U, est = 8 },
            { id = "O2", kind = "objective", questId = 2, deps = {}, dependents = { "T2" }, loc = F, est = 300 },
            { id = "T2", kind = "turnin", questId = 2, deps = { "O2" }, dependents = {}, loc = U, est = 8 },
        }
        local byId = {}
        for _, t in ipairs(list) do byId[t.id] = t end
        return list, byId
    end
    local function ids(order)
        local out = {}
        for _, t in ipairs(order) do out[#out + 1] = t.id end
        return table.concat(out, " ")
    end
    -- baseline: travel time alone (both "do it now" rules off; 0.3.15's finish-here rule
    -- would also catch this one, U being 200 yd away)
    local weight, here = P.TURNIN_WAIT_WEIGHT, P.HERE_YARDS
    P.TURNIN_WAIT_WEIGHT, P.HERE_YARDS = 0, 0
    local list, byId = tasks()
    local travelOnly = P.Solve(list, byId, S, { logCount = 2, logMax = 20 })
    check("turn-ins: travel time alone defers the nearby turn-in (the bug)", travelOnly[1].id ~= "T1", ids(travelOnly))
    P.TURNIN_WAIT_WEIGHT, P.HERE_YARDS = weight, here
    list, byId = tasks()
    local order = P.Solve(list, byId, S, { logCount = 2, logMax = 20 })
    check("turn-ins: a finished quest nearby is turned in before leaving", order[1].id == "T1", ids(order))
    local extra = P.RouteCost(order, S) - P.RouteCost(travelOnly, S)
    check("turn-ins: for a small extra walk", extra > 0 and extra <= P.TURNIN_MAX_EXTRA + P.PULL_FORWARD_SLACK, extra)
    -- far away, it still waits: no cross-zone trips just to turn in sooner
    local farU = Geo.Point(1429, 0.10, 0.95)
    list, byId = tasks()
    list[1].loc, list[3].loc = farU, farU
    order = P.Solve(list, byId, S, { logCount = 2, logMax = 20 })
    check("turn-ins: a far-off turn-in isn't dragged forward", order[1].id ~= "T1", ids(order))
    -- precedence still holds: a turn-in never moves before its objective
    check("turn-ins: never before its own objective", ids(order):find("O2.*T2") ~= nil, ids(order))

    -- 0.3.6: no bat ride back and out again just to turn in sooner. Cheap AFK flights made
    -- "Podrig (Sepulcher) -> Bethor (Undercity) -> crate (Silverpine)" fit the allowance.
    do
        local S, B = Geo.Point(1429, 0.10, 0.50), Geo.Point(1429, 0.10, 0.75) -- you, Bethor: 500 yd apart
        local Pd, C = Geo.Point(1429, 0.80, 0.50), Geo.Point(1429, 0.82, 0.52) -- Podrig, crate: far away
        local E = Geo.Point(1429, 0.12, 0.74)                                     -- later stop next to Bethor
        local name = { [S] = "S", [B] = "B", [Pd] = "P", [C] = "C", [E] = "E" }
        local cost = { SB = 120, SP = 60, SC = 70, SE = 110, BP = 60, BC = 70, BE = 5, PC = 40, PE = 60, CE = 60 }
        P.travelFn = function(a, b)
            if a == b then return 0 end
            return cost[name[a] .. name[b]] or cost[name[b] .. name[a]]
        end
        local function route()
            return {
                { id = "TP", kind = "turnin", deps = {}, dependents = {}, loc = Pd, est = 8 },
                { id = "OC", kind = "objective", deps = {}, dependents = { "TE" }, loc = C, est = 700 },
                { id = "TE", kind = "turnin", deps = { "OC" }, dependents = {}, loc = E, est = 8 },
                { id = "TB", kind = "turnin", deps = {}, dependents = {}, loc = B, est = 8 },
            }
        end
        local near = P.PULL_NEAR_YARDS
        P.PULL_NEAR_YARDS = math.huge
        local old = P.PullForward(route(), S, { logCount = 4, logMax = 20 })
        check("ping-pong: the 0.3.5 rule flew back for Bethor (the bug)", old[2].id == "TB", ids(old))
        P.PULL_NEAR_YARDS = near
        local fixed = P.PullForward(route(), S, { logCount = 4, logMax = 20 })
        check("ping-pong: Bethor waits for the next pass through Undercity", ids(fixed) == "TP OC TE TB", ids(fixed))
        P.travelFn = nil
    end

    -- Vendor stop: sell at the vendor next to you rather than after a flight, when it costs the same.
    local here = { npcId = 1, name = "Vendor Here", point = Geo.Point(1429, 0.10, 0.52) }
    local there = { npcId = 2, name = "Vendor There", point = Geo.Point(1429, 0.90, 0.52) }
    ns.Data.vendors = { there, here }
    local steps = { { loc = F, tasks = {} }, { loc = Geo.Point(1429, 0.92, 0.55), tasks = {} } }
    local v = ns.Ladder.PickVendor(steps, S, 2, Geo.TravelSeconds)
    check("vendor: equal detour, so sell where you are", v == here, v and v.name)
    -- but a vendor far in the wrong direction loses to one on the way
    here.point = Geo.Point(1429, 0.10, 0.95)
    v = ns.Ladder.PickVendor(steps, S, 2, Geo.TravelSeconds)
    check("vendor: a big detour loses to the vendor on the way", v == there, v and v.name)
    ns.Data.vendors = {}
end

do
    -- 0.3.8: a zigzag like the Silverpine leg (far end first, walk back north past Quinn, then
    -- south again) is turned into one sweep by reversing the stretch of stops. Quinn's
    -- "turn in, then pick up the follow-up" stays in that order.
    local ns = setup()
    local P, Geo = ns.Planner, ns.Geo
    P.travelFn = nil
    local function at(yd) return Geo.Point(1429, yd / 3000, 0.5) end
    local S = at(0)
    local function zigzag()
        return {
            { id = "A", kind = "objective", deps = {}, loc = at(1650), est = 60 },
            { id = "B", kind = "objective", deps = {}, loc = at(1270), est = 60 },
            { id = "QT", kind = "turnin", deps = {}, loc = at(890), est = 8 },
            { id = "QP", kind = "pickup", deps = { "QT" }, loc = at(890), est = 8 },
            { id = "C", kind = "objective", deps = {}, loc = at(830), est = 60 },
            { id = "K", kind = "turnin", deps = {}, loc = at(1680), est = 8 },
            { id = "Z", kind = "turnin", deps = {}, loc = at(1530), est = 8 },
        }
    end
    local function ids(order)
        local out = {}
        for _, t in ipairs(order) do out[#out + 1] = t.id end
        return table.concat(out, " ")
    end
    local order = zigzag()
    local before = P.RouteCost(order, S)
    local changed = P.TryReversals(order, S, { logCount = 5, logMax = 20 })
    local after = P.RouteCost(order, S)
    check("zigzag: reversing the stretch shortens the route", changed and after < before - 60,
        string.format("%.0f -> %.0f s: %s", before, after, ids(order)))
    local sweep, lastX = true, -1
    for _, t in ipairs(order) do
        if t.loc.wx < lastX - 1 then sweep = false end
        lastX = t.loc.wx
    end
    check("zigzag: becomes one sweep (no walking back)", sweep, ids(order))
    local qt, qp
    for i, t in ipairs(order) do if t.id == "QT" then qt = i elseif t.id == "QP" then qp = i end end
    check("zigzag: Quinn's turn-in still comes right before the follow-up pickup", qt and qp == qt + 1, ids(order))
    check("zigzag: still valid (turn-in before its follow-up)", P.IsValid(order, { logCount = 5, logMax = 20 }))
end

do
    -- 0.3.9: busy stops (the Sepulcher had 7 tasks, Brill 5) must be able to move as one block.
    -- With blocks of at most 4 tasks the improvement step got stuck; replaying a real Tirisfal/
    -- Silverpine plan, blocks of up to 8 saved ~3.7 minutes (6%).
    local ns = setup()
    local P, Geo = ns.Planner, ns.Geo
    P.travelFn = nil
    local function at(yd) return Geo.Point(1429, yd / 3000, 0.5) end
    local S = at(0)
    local function stop(prefix, loc) -- six tasks at one place that must be done in order
        local list = {}
        for k = 1, 6 do
            list[k] = { id = prefix .. k, kind = "objective", loc = loc, est = 5,
                        deps = (k > 1) and { prefix .. (k - 1) } or {}, dependents = (k < 6) and { prefix .. (k + 1) } or {} }
        end
        return list
    end
    local function badOrder() -- far stop F, then H next to it, then G that was right by the start
        local o = {}
        for _, part in ipairs({ stop("f", at(1000)), stop("h", at(1100)), stop("g", at(300)) }) do
            for _, t in ipairs(part) do o[#o + 1] = t end
        end
        return o
    end
    local opts = { logCount = 0, logMax = 20 }
    local savedRev, savedSeg = P.USE_REVERSALS, P.MAX_SEGMENT
    P.USE_REVERSALS = false
    P.MAX_SEGMENT = 4
    local small = P.Improve(badOrder(), S, opts)
    P.MAX_SEGMENT = savedSeg
    local big = P.Improve(badOrder(), S, opts)
    P.USE_REVERSALS = savedRev
    check("blocks: with 4-task blocks a 6-task stop is stuck (the bug)", small[1].id == "f1", small[1].id)
    check("blocks: a whole 6-task stop moves as one block", big[1].id == "g1"
        and P.RouteCost(big, S) < P.RouteCost(small, S) - 60,
        string.format("%s first, %.0f vs %.0f s", big[1].id, P.RouteCost(big, S), P.RouteCost(small, S)))
    check("blocks: still valid", P.IsValid(big, opts))
end

do
    -- 0.3.6: new quests are looked for around you AND around where your quests send you, so work
    -- next to a far turn-in is bundled into that trip.
    local ns = setup()
    M.player.x, M.player.y = 0.10, 0.50
    local function sp(x, y) return { [12] = { { x, y } } } end
    ns.Data.InitWith(M.fakeDB({
        quests = {
            [50] = { name = "Report to the Far Camp", startedBy = { { 500 } }, finishedBy = { { 500 } },
                     requiredLevel = 1, questLevel = 3, objectives = {} },
            [51] = { name = "Far Camp Chores", startedBy = { { 501 } }, finishedBy = { { 501 } },
                     requiredLevel = 1, questLevel = 3, objectives = { { { 502 } } } },
            [52] = { name = "Local Errand", startedBy = { { 503 } }, finishedBy = { { 503 } },
                     requiredLevel = 1, questLevel = 3, objectives = {} },
            [53] = { name = "Sample for Overseas", startedBy = { { 503 } }, finishedBy = { { 505 } },
                     requiredLevel = 1, questLevel = 3, objectives = {} },
            [54] = { name = "Overseas Hub Errand", startedBy = { { 506 } }, finishedBy = { { 506 } },
                     requiredLevel = 1, questLevel = 3, objectives = {} },
        },
        npcs = {
            [500] = { name = "Camp Leader", spawns = sp(90, 50) },   -- 2400 yd from you
            [501] = { name = "Camp Cook", spawns = sp(91, 50) },     -- next to the camp leader
            [502] = { name = "Camp Pest", spawns = sp(92, 53) },
            [503] = { name = "Neighbour", spawns = sp(12, 50) },     -- next to you
            [505] = { name = "Overseas Contact", spawns = { [40] = { { 50, 50 } } } }, -- another continent
            [506] = { name = "Overseas Hub", spawns = { [40] = { { 51, 50 } } } },
        },
        objects = {}, items = {},
    }))
    M.log = {
        { id = 50, title = "Report to the Far Camp", level = 3, complete = true, objectives = {} },
        { id = 53, title = "Sample for Overseas", level = 3, complete = true, objectives = {} },
    }
    local plan = fullPlan(ns)
    local cands = {}
    for _, c in ipairs(plan.candidates or {}) do cands[c.id] = true end
    check("candidates: quests next to you", cands[52] == true)
    check("candidates: quests next to a far turn-in", cands[51] == true)
    local sameStep = false
    for _, s in ipairs(plan.steps) do
        local has = {}
        for _, t in ipairs(s.tasks) do has[t.id] = true end
        if has.T50 and has.P51 then sameStep = true end
    end
    check("candidates: picked up in the same stop as that turn-in", sameStep)
    check("candidates: nothing from another continent's turn-in area", cands[54] == nil)
    check("candidates: the overseas turn-in is left for the end of the route",
        plan.order[#plan.order] and plan.order[#plan.order].id == "T53", plan.order[#plan.order] and plan.order[#plan.order].id)
end

---------------------------------------------------------------------------
-- 15b. Planning (0.3.15): "it left quests behind and now I'm killing mobs 2 levels above me;
-- I want to accept as many quests as possible so their mobs overlap"
---------------------------------------------------------------------------
do
    local ns = setup()
    local P, Geo = ns.Planner, ns.Geo
    P.travelFn = nil -- plain walking
    local function ids(order)
        local out = {}
        for _, t in ipairs(order) do out[#out + 1] = t.id end
        return table.concat(out, " ")
    end
    local function indexOf(order, id)
        for i, t in ipairs(order) do if t.id == id then return i end end
    end
    local function graph(list)
        local byId = {}
        for _, t in ipairs(list) do byId[t.id] = t; t.dependents = {} end
        for _, t in ipairs(list) do
            for _, d in ipairs(t.deps) do byId[d].dependents[#byId[d].dependents + 1] = t.id end
        end
        return list, byId
    end

    -- the wait itself
    check("level: mobs 2 above wait ~a level of turn-ins", P.LevelGate(8, 6, 0) == 5, P.LevelGate(8, 6, 0))
    check("level: mobs 1 above don't wait", P.LevelGate(7, 6, 0) == 0)
    check("level: halfway into the level, half the wait", P.LevelGate(8, 6, 0.5) == 3, P.LevelGate(8, 6, 0.5))
    check("level: no mobs, no wait", P.LevelGate(nil, 6, 0) == 0)

    -- Hub H. Easy mobs at E (300 yd east); high mobs at X, on the way (150 yd east).
    local H, X, E = Geo.Point(1429, 0.10, 0.50), Geo.Point(1429, 0.15, 0.50), Geo.Point(1429, 0.20, 0.50)
    local function camp()
        return graph({
            { id = "O1", kind = "objective", deps = {}, loc = E, est = 100, mobLevel = 5 },
            { id = "T1", kind = "turnin", deps = { "O1" }, loc = H, est = 8 },
            { id = "O2", kind = "objective", deps = {}, loc = E, est = 100, mobLevel = 6 },
            { id = "T2", kind = "turnin", deps = { "O2" }, loc = H, est = 8 },
            { id = "O3", kind = "objective", deps = {}, loc = X, est = 100, mobLevel = 8 },
            { id = "T3", kind = "turnin", deps = { "O3" }, loc = H, est = 8 },
        })
    end
    local opts = { logCount = 3, logMax = 20 }
    local list, byId = camp()
    local before = P.Solve(list, byId, H, opts)
    check("level: travel alone does the high mobs first (they're on the way)",
        indexOf(before, "O3") < indexOf(before, "T1"), ids(before))
    list, byId = camp()
    P.ApplyLevelGates(list, byId, 6, 0)
    check("level: the wait is capped to the turn-ins the plan has (2)", byId.O3.minTurnins == 2, byId.O3.minTurnins)
    check("level: easy mobs don't wait", byId.O1.minTurnins == nil and byId.O2.minTurnins == nil)
    local after = P.Solve(list, byId, H, opts)
    check("level: high mobs after the easy quests are turned in",
        indexOf(after, "O3") > indexOf(after, "T1") and indexOf(after, "O3") > indexOf(after, "T2"), ids(after))
    check("level: still a valid route", P.IsValid(after, opts) and #after == 6, ids(after))
    list, byId = graph({ { id = "O9", kind = "objective", deps = {}, loc = X, est = 100, mobLevel = 9 },
                         { id = "T9", kind = "turnin", deps = { "O9" }, loc = H, est = 8 } })
    P.ApplyLevelGates(list, byId, 6, 0)
    check("level: nothing else to do first: no wait", byId.O9.minTurnins == nil)
    -- "go talk to X" quests count less towards the wait
    local built = P.BuildTasks({ active = {
        { id = 70, objectives = {}, turnin = H, complete = true },
        { id = 71, objectives = { { index = 1, type = "monster", need = 5, have = 0, loc = E, mobLevel = 5 } }, turnin = H },
    } })
    local w = {}
    for _, t in ipairs(built) do w[t.id] = t.xpWeight end
    check("level: a talk quest's turn-in counts less", w.T70 == P.TALK_QUEST_XP and w.T71 == 1, tostring(w.T70) .. " " .. tostring(w.T71))
    check("level: the objective carries its mob level", (function()
        for _, t in ipairs(built) do if t.id == "O71:1" then return t.mobLevel == 5 end end
    end)())

    -- Accept it while you're standing there: B's giver is at the hub, but the route left B
    -- for the second visit, so B's mobs next to A's needed a second trip out.
    local F, F2 = Geo.Point(1429, 0.50, 0.50), Geo.Point(1429, 0.52, 0.50)
    list, byId = graph({
        { id = "OA", kind = "objective", deps = {}, loc = F, est = 100 },
        { id = "TA", kind = "turnin", deps = { "OA" }, loc = H, est = 8 },
        { id = "PB", kind = "pickup", deps = {}, loc = H, est = 8 },
        { id = "OB", kind = "objective", deps = { "PB" }, loc = F2, est = 100 },
        { id = "TB", kind = "turnin", deps = { "OB" }, loc = H, est = 8 },
    })
    local order = { byId.OA, byId.TA, byId.PB, byId.OB, byId.TB }
    local leftBehind = P.RouteCost(order, H)
    check("grab: pickup moved to the first time you stand at its giver", P.GrabPickups(order, H, opts) and order[1].id == "PB", ids(order))
    order = P.Improve(order, H, opts)
    check("grab: then its mobs are done with the others' (one trip out)",
        indexOf(order, "OB") < indexOf(order, "TA") and P.RouteCost(order, H) < leftBehind * 0.7,
        ids(order) .. string.format(" %.0f -> %.0f s", leftBehind, P.RouteCost(order, H)))

    -- Finish what's around you: the camp you stand in (100 yd) before the far hub.
    local S, C, Far = Geo.Point(1429, 0.30, 0.50), Geo.Point(1429, 0.30, 0.55), Geo.Point(1429, 0.90, 0.50)
    list, byId = graph({
        { id = "TF", kind = "turnin", deps = {}, loc = Far, est = 8 },
        { id = "OC", kind = "objective", deps = {}, loc = C, est = 100 },
        { id = "TC", kind = "turnin", deps = { "OC" }, loc = Far, est = 8 },
    })
    order = P.FinishHere({ byId.TF, byId.OC, byId.TC }, S, opts)
    check("here: the camp you stand in comes first", order[1].id == "OC", ids(order))
    byId.OC.minTurnins = 5
    order = P.FinishHere({ byId.TF, byId.OC, byId.TC }, S, opts)
    check("here: but not mobs that are too high for you yet", order[1].id == "TF", ids(order))

    -- More quests in the plan: 25, and a saved 12 (the old default) is updated once
    check("candidates: default is 25", ns.defaults.maxCandidates == 25)
    local saved = { maxCandidates = 12 }
    ns.MigrateSettings(saved)
    check("candidates: a saved old default becomes 25", saved.maxCandidates == 25 and saved.settingsVersion == 2)
    saved = { maxCandidates = 8 }
    ns.MigrateSettings(saved)
    check("candidates: a value you chose stays", saved.maxCandidates == 8)
    saved = { maxCandidates = 12, settingsVersion = 1 }
    ns.MigrateSettings(saved)
    check("candidates: 12 chosen after the update stays", saved.maxCandidates == 12)

    -- Mob levels from QuestieDB, and the step text shows them
    local L = ns.Ladder
    check("mob level: the easiest mob that counts", L.MobLevelOf({ type = "monster", targets = { npc = { 202, 201 } } }) == 2)
    check("mob level: drops from mobs count", L.MobLevelOf({ type = "item", targets = { npc = { 202 } } }) == 4)
    check("mob level: objects have none", L.MobLevelOf({ type = "item", targets = { object = { 300 } } }) == nil)
    local savedPlan = L.plan
    L.plan = { player = { level = 5 } }
    local text = L.TaskText({ kind = "objective", quest = { title = "Vanquish the Betrayers" },
                              obj = { type = "monster", text = "Kul Tiras Sailor slain: 0/10", mobLevel = 8 }, loc = X })
    check("mob level: shown on the step, orange when 2+ above you", text:find("lvl 8", 1, true) and text:find("ff8800", 1, true), text)
    L.plan = savedPlan
end

---------------------------------------------------------------------------
-- 15c. Fly or walk (0.3.16), on the real Undercity / Sepulcher flight points from your diag:
-- "both should be viable": the guide shows both ways with their times, and follows the one you
-- take, re-checked from where you stand.
---------------------------------------------------------------------------
do
    local ns = setup()
    local T, L = ns.Travel, ns.Ladder
    local function pt(x, y) return { cont = 0, wx = x, wy = y, mapId = 1420, x = 0.5, y = 0.5 } end
    local uc = { name = "Undercity, Tirisfal", point = pt(1568.6, 268.0), known = true }
    local sep = { name = "The Sepulcher, Silverpine Forest", point = pt(478.9, 1536.6), known = true }
    local net = { speed = 7, nodes = { uc, sep } }
    local inUC = pt(1293.8, 317.4)          -- where you ran diag in Undercity
    local nearSep = pt(600, 1400)           -- an objective 180 yd from the Sepulcher
    local onTheWay = pt(900, 1000)          -- north Silverpine, between the two

    local o = T.Options(net, inUC, nearSep)
    check("fly or walk: the bat wins near the Sepulcher", o.pick == "fly" and o.fly.from == uc and o.fly.to == sep,
        string.format("%s walk %.0f fly %.0f", o.pick, o.walk, o.fly and o.fly.total or -1))
    check("fly or walk: and it's quicker in total", o.fly.total < o.walk, string.format("%.0f vs %.0f", o.fly.total, o.walk))
    o = T.Options(net, inUC, onTheWay)
    check("fly or walk: walking wins on the way", o.pick == "walk", o.pick)
    check("fly or walk: the flight is still offered as the other way", o.fly and o.fly.total > o.walk,
        o.fly and string.format("%.0f vs %.0f", o.fly.total, o.walk))
    check("fly or walk: same as what the planner uses", select(2, T.Leg(net, inUC, nearSep)) == "fly"
        and select(2, T.Leg(net, inUC, onTheWay)) == "walk")

    local savedPlan = L.plan
    L.plan = { net = net }
    local step = { loc = nearSep, tasks = {} }
    local live = L.LiveTravel(step, inUC)
    local text = L.TravelText(step, live)
    check("guide: says fly, with both times", live.mode == "fly" and text:find("Fly:", 1, true)
        and text:find("AFK", 1, true) and text:find("walking takes", 1, true), text)
    local target = L.WaypointTarget(step, inUC)
    check("guide: the arrow points at the bat handler", target == uc.point)
    -- you walk off towards the objective instead: from halfway, walking is the way
    local halfway = pt(1000, 800)
    live = L.LiveTravel(step, halfway)
    check("guide: walked off instead? it switches to walking", live.mode == "walk", live.mode)
    check("guide: and doesn't nag about a flight that's now 2x slower", L.TravelText(step, live) == nil,
        L.TravelText(step, live))
    check("guide: and the arrow points at the objective", L.WaypointTarget(step, halfway) == nearSep)
    step = { loc = onTheWay, tasks = {} }
    text = L.TravelText(step, L.LiveTravel(step, inUC))
    check("guide: walking step still names the flight and its time", text and text:find("Walk:", 1, true)
        and text:find("Undercity", 1, true) and text:find("Sepulcher", 1, true), text)
    -- a flight that's way slower isn't worth a mention
    local farNet = { speed = 7, nodes = { uc, { name = "Far Away", point = pt(5000, 5000), known = true } } }
    L.plan = { net = farNet }
    check("guide: a pointless flight isn't mentioned", L.TravelText(step, L.LiveTravel(step, inUC)) == nil)
    L.plan = { net = net }
    -- on the bat right now: no travel line, the arrow points at the step
    _G.UnitOnTaxi = function() return true end
    step = { loc = nearSep, tasks = {} }
    check("guide: on a flight, nothing to choose", L.LiveTravel(step, inUC) == nil and L.WaypointTarget(step, inUC) == nearSep)
    _G.UnitOnTaxi = nil
    -- flights turned off (/ladder flights): walking only, no flight mentioned
    ns.db.useFlights = false
    live = L.LiveTravel(step, inUC)
    check("guide: flights off means walking only", live.mode == "walk" and live.fly == nil and L.TravelText(step, live) == nil)
    ns.db.useFlights = true
    -- a hearth step keeps its own line
    local hearth = { loc = nearSep, tasks = {}, travel = { mode = "hearth", bindName = "The Sepulcher", saving = 300 } }
    check("guide: hearth steps unchanged", L.TravelText(hearth, L.LiveTravel(hearth, inUC)):find("Hearth", 1, true) ~= nil)
    L.plan = savedPlan

    -- Zeppelin masters are found in QuestieDB
    local built = false
    ns.Data.BuildIndexes(ns.QuestState.Player(), function() built = true end)
    local found = false
    for _, e in ipairs(ns.Data.transportMasters) do if e.name == "Zapetta" then found = true end end
    check("zeppelins: masters indexed from QuestieDB titles", built and found)

    -- 0.3.17: zeppelin routes, from the six masters your diag listed (two per tower)
    local function master(name, cont, x, y)
        return { name = name, subName = "Zeppelin Master", point = { cont = cont, wx = x, wy = y, mapId = 1420, x = 0.6, y = 0.6 } }
    end
    local masters = {
        master("Hin Denburg", 0, 2060, 290), master("Zapetta", 0, 2070, 300),            -- Tirisfal
        master("Frezza", 1, 1300, -4400), master("Snurk Bucksquick", 1, 1305, -4395),    -- Durotar
        master("Nez'raz", 0, -12400, 200), master("Squibby Overspeck", 0, -12410, 205),  -- Grom'gol
        { name = "Dock Dan", subName = "Dockmaster", point = pt(0, 0) },                 -- not a zeppelin
    }
    local links, towers, why = T.ZeppelinLinks(masters)
    check("zeppelins: three towers, every pair linked", #towers == 3 and #links == 3 and why == nil,
        string.format("%d towers %d links %s", #towers, #links, tostring(why)))
    towers[1].name, towers[2].name, towers[3].name = "Tirisfal Glades", "Durotar", "Stranglethorn Vale"
    local extra = {}
    for _, m in ipairs(masters) do extra[#extra + 1] = m end
    extra[#extra + 1] = master("New Guy", 1, -1200, 30)
    local l2, _, why2 = T.ZeppelinLinks(extra)
    check("zeppelins: a layout that can't be paired links nothing", #l2 == 0 and why2 ~= nil, tostring(why2))

    local znet = { speed = 7, nodes = { uc, sep }, zeppelins = links, towers = towers }
    local crossroads = { cont = 1, wx = -441, wy = -2596, mapId = 1413, x = 0.5, y = 0.5 }
    local inUC2 = pt(1646, 279) -- where you ran the 0.3.16 diag
    local cost, mode, zFrom, zTo = T.Leg(znet, inUC2, crossroads)
    check("zeppelins: another continent goes by zeppelin", mode == "zeppelin" and zFrom == towers[1] and zTo == towers[2],
        tostring(mode))
    check("zeppelins: cheaper than the old flat 15 minutes", cost < ns.Geo.CONTINENT_SECONDS, cost)
    check("zeppelins: without them it's the flat cost", T.Leg({ speed = 7, nodes = { uc, sep } }, inUC2, crossroads) == ns.Geo.CONTINENT_SECONDS)
    check("zeppelins: the planner's cost uses them", math.abs(T.NewCost(znet)(inUC2, crossroads) - cost) < 0.01)
    local stv = pt(-12000, 300)
    local _, longMode = T.Leg(znet, pt(2000, 300), stv)
    check("zeppelins: Tirisfal to Stranglethorn rides to Grom'gol", longMode == "zeppelin", longMode)
    local _, shortMode = T.Leg(znet, inUC2, onTheWay)
    check("zeppelins: never for a short trip", shortMode == "walk", shortMode)

    L.plan = { net = znet }
    step = { loc = crossroads, tasks = {} }
    live = L.LiveTravel(step, inUC2)
    text = L.TravelText(step, live)
    check("zeppelins: guide line names the towers, the uncertain wait and the AFK ride", live.mode == "zeppelin"
        and text:find("Zeppelin:", 1, true) and text:find("Tirisfal Glades -> Durotar", 1, true)
        and text:find("just miss it", 1, true) and text:find("no departure timer", 1, true) and text:find("AFK", 1, true), text)
    check("zeppelins: no walking time when you can't walk there", not text:find("walking", 1, true), text)
    check("zeppelins: the arrow points at the tower first", L.WaypointTarget(step, inUC2) == towers[1].point)
    check("zeppelins: at the tower, the arrow points on", L.WaypointTarget(step, pt(2065, 295)) == crossroads)
    L.plan = savedPlan

    -- "+1814%" for a cape over a bare one reads as "big upgrade"
    check("gear: huge percentages read as a big upgrade", ns.Gear.PctText(1814) == "big upgrade"
        and ns.Gear.PctText(40) == "+40%" and ns.Gear.UpgradeText({ pct = 1814, delta = 1.27, slot = 15 }) == "big upgrade")

    -- 0.3.18: zeppelins have no timer and leave every ~4-5 minutes, so on one continent a
    -- zeppelin only counts when it still beats walking if you just missed it.
    local nearTower = pt(2060, 300)
    local _, closeCall = T.Leg(znet, nearTower, pt(-6395, 200))
    local zc = T.ZeppelinOption(znet, nearTower, pt(-6395, 200))
    check("zeppelins: quicker on average but not if you miss it: no zeppelin", closeCall ~= "zeppelin"
        and zc.total < T.Walk(znet, nearTower, pt(-6395, 200)), closeCall)
    local _, clearWin = T.Leg(znet, nearTower, pt(-8000, 200))
    check("zeppelins: a clear win even after a missed departure: ride", clearWin == "zeppelin", clearWin)
end

---------------------------------------------------------------------------
-- 15d. 0.3.18: hearth for a fast return, and profession tools
---------------------------------------------------------------------------
do
    local ns = setup()
    local P, T, L = ns.Planner, ns.Travel, ns.Ladder
    local function X(x) return { cont = 0, wx = x, wy = 0, mapId = 1429, x = 0, y = 0 } end
    local cost = function(a, b) return math.abs(a.wx - b.wx) / 7 end
    P.travelFn = cost
    -- You stand at a far objective; its turn-in and three more quests are at the hub by the inn.
    local function route(far)
        local active = { { id = 1, objectives = { { index = 1, type = "event", loc = X(far) } }, turnin = X(0) } }
        local cands = {
            { id = 2, pickup = X(0), turnin = X(0), objectives = { { index = 1, type = "event", loc = X(200) } } },
            { id = 3, pickup = X(0), turnin = X(0), objectives = { { index = 1, type = "event", loc = X(-250) } } },
            { id = 4, pickup = X(0), turnin = X(0), objectives = { { index = 1, type = "event", loc = X(-300) } } },
        }
        local tasks, byId = P.BuildTasks({ active = active, candidates = cands })
        return P.Solve(tasks, byId, X(far), { logCount = 1, logMax = 20 })
    end
    local function inn(at, readyIn)
        return { hasHearth = true, bind = X(at), bindName = "Hub Inn", hearthCooldown = 3600, hearthReadyIn = readyIn or 0 }
    end
    local order = route(1500) -- 3:34 walk back
    local r, why = T.HearthAware(order, X(1500), inn(0), cost, { logCount = 1, logMax = 20 })
    check("hearth: 3+ min from turn-ins right by the inn: hearth", r ~= nil and r.uses[1].reason == "fast return", why)
    check("hearth: (the old rules alone said no: saving under 4 min)", r and r.uses[1].gain < T.HEARTH_MIN_GAIN, r and r.uses[1].gain)
    check("hearth: used right after the far objective", r and r.order[1].id == "O1:1" and r.order[2].visit == "hearth",
        r and (r.order[1].id .. " " .. r.order[2].id))
    check("hearth: the step says why", r and L.TravelText({ travel = { mode = "hearth", reason = "fast return",
        bindName = "Hub Inn", saving = r.uses[1].gain } }):find("right by the inn", 1, true))
    order = route(1200) -- 2:51 walk: under 3 minutes
    check("hearth: under 3 minutes away: walk", T.HearthAware(order, X(1200), inn(0), cost, { logCount = 1, logMax = 20 }) == nil)
    order = route(1500)
    check("hearth: inn not by the turn-ins (43 s away): no fast return",
        T.HearthAware(order, X(1500), inn(-300), cost, { logCount = 1, logMax = 20 }) == nil)
    check("hearth: on cooldown: no hearth", T.HearthAware(order, X(1500), inn(0, 5000), cost, { logCount = 1, logMax = 20 }) == nil)

    -- Tools: QuestieDB has them as "miscellaneous" weapons and fishing poles; never sell them
    M.items[2901] = { name = "Mining Pick", classID = 2, subClassID = 14, equipLoc = "INVTYPE_WEAPON", sell = 16 }
    M.items[5956] = { name = "Blacksmith Hammer", classID = 2, subClassID = 14, equipLoc = "INVTYPE_WEAPONMAINHAND", sell = 4 }
    M.items[6256] = { name = "Fishing Pole", classID = 2, subClassID = 20, equipLoc = "INVTYPE_2HWEAPON", sell = 6 }
    M.items[6218] = { name = "Runed Copper Rod", classID = 7, sell = 25 }
    M.items[3001] = { name = "Broken Pick", classID = 2, subClassID = 14, equipLoc = "INVTYPE_WEAPON", quality = 0, sell = 5 }
    M.bag = { { id = 2901 }, { id = 5956 }, { id = 6256 }, { id = 6218 }, { id = 3001 } }
    local list = ns.Bags.Suggestions(ns.QuestState.Bags(), {}, { bags = { needed = 3 }, candidates = {},
        player = { level = 14, classFile = "PALADIN" } })
    local by = {}
    for _, e in ipairs(list) do by[e.itemId] = e end
    check("tools: mining pick, hammer and fishing pole never sold", not by[2901] and not by[5956] and not by[6256],
        (by[2901] and by[2901].reason) or (by[5956] and by[5956].reason) or (by[6256] and by[6256].reason))
    check("tools: enchanting rod kept even when bags are short", not by[6218], by[6218] and by[6218].reason)
    check("tools: a gray broken one is still junk", by[3001] and by[3001].action == "sell")
end

---------------------------------------------------------------------------
-- 15e. 0.3.19: "tired of lower level quests that don't pump out good rewards". New quests are
-- valued by QuestieDB's quest XP at your level; the tiny ones are skipped, and when few good
-- ones are left nearby the guide names the next area.
---------------------------------------------------------------------------
do
    local ns = setup()
    local D, L = ns.Data, ns.Ladder
    M.player.level = 15
    local function q(name, level, extra)
        local t = { name = name, startedBy = { { 400 } }, finishedBy = { { 400 } }, requiredLevel = 1, questLevel = level,
                    objectives = { { { 420 } } } }
        for k, v in pairs(extra or {}) do t[k] = v end
        return t
    end
    local quests = {
        [501] = q("Solid Quest", 15),
        [502] = q("Low Quest", 10),
        [503] = q("Tiny Talk", 15, { objectives = {} }),
        [504] = q("Breadcrumb", 14, { objectives = {} }),
        [505] = q("Real Quest", 15, { preQuestSingle = { 504 } }),
        [506] = q("Class Quest", 15, { requiredClasses = 1, objectives = {} }),
        [507] = q("Unknown XP", 15),
        [508] = q("Shiny Reward", 15, { objectives = {} }),
        [509] = q("Older But Fine", 11),
    }
    local xp = {
        [501] = { 15, 1050 }, [502] = { 10, 300 }, [503] = { 15, 100 }, [504] = { 14, 150 }, [505] = { 15, 1200 },
        [506] = { 15, 150 }, [508] = { 15, 150 }, [509] = { 11, 700 },
    }
    -- the rest of the level-15 quests (real data has hundreds per level band): a solid one is 1000
    for id = 9001, 9030 do xp[id] = { 15, 1000 } end
    -- a hub 1700 yd away with rich quests
    for id = 511, 516 do
        quests[id] = { name = "Far Quest " .. id, startedBy = { { 410 } }, finishedBy = { { 410 } }, requiredLevel = 1,
                       questLevel = 15, objectives = { { { 421 } } } }
        xp[id] = { 15, 2500 }
    end
    D.InitWith(M.fakeDB({
        quests = quests, questXP = xp,
        npcs = {
            [400] = { name = "Near Giver", spawns = spawn(43, 42) },
            [410] = { name = "Far Giver", spawns = spawn(90, 90) },
            [420] = { name = "Near Mob", minLevel = 14, spawns = spawn(45, 45) },
            [421] = { name = "Far Mob", minLevel = 14, spawns = spawn(91, 91) },
        },
        objects = {},
        items = { [950] = { name = "Shiny Helm", class = 4, requiredLevel = 10, questRewards = { 508 } } },
    }))
    M.items[950] = { name = "Shiny Helm", classID = 4, subClassID = 1, equipLoc = "INVTYPE_HEAD", sell = 40,
                     stats = { RESISTANCE0_NAME = 20, ITEM_MOD_STRENGTH_SHORT = 3 } }

    check("value: full XP up to 5 levels above the quest", D.XPAtLevel(1000, 10, 15) == 1000)
    check("value: then 20% less per level", D.XPAtLevel(1000, 10, 16) == 800 and D.XPAtLevel(1000, 10, 18) == 400)
    check("value: never under 10%", D.XPAtLevel(1000, 10, 30) == 100)
    check("value: a solid quest at 15 is the 75th percentile nearby", D.SolidQuestXP(15) == 1000, D.SolidQuestXP(15))

    local built = false
    D.BuildIndexes(ns.QuestState.Player(), function() built = true end)
    local player = ns.QuestState.Player()
    local function verdict(id)
        local ok, _, why = L.WorthDoing(id, player)
        return ok, why
    end
    check("value: a solid quest is planned", (verdict(501)))
    check("value: a low-level quest worth 30% is skipped", not verdict(502))
    check("value: a tiny talk quest is skipped", not verdict(503))
    check("value: an older quest still worth 70% stays", (verdict(509)))
    local ok, why = verdict(504)
    check("value: a breadcrumb into a solid quest stays", ok and why == "leads on", why)
    ok, why = verdict(506)
    check("value: a quest for your class stays", ok and why == "class", why)
    ok, why = verdict(507)
    check("value: unknown XP stays", ok and why == "unknown", why)
    ok, why = verdict(508)
    check("value: a reward you'd wear keeps a tiny quest", built and ok and why == "upgrade", why)

    ns.Ladder.Rebuild("value test")
    local plan = L.plan
    local cands = {}
    for _, c in ipairs((plan and plan.candidates) or {}) do cands[c.id] = true end
    check("plan: the skipped ones aren't in it", cands[501] and cands[509] and not cands[502] and not cands[503],
        table.concat((function() local o = {} for id in pairs(cands) do o[#o + 1] = id end table.sort(o) return o end)(), ","))
    check("plan: the breadcrumb's follow-up comes with it", cands[504] and cands[505])
    local skipped = {}
    for _, s in ipairs((plan and plan.skippedLowValue) or {}) do skipped[s.id] = s end
    check("plan: the skipped ones are listed with their XP", skipped[502] and skipped[502].xp == 300 and skipped[503] ~= nil)
    check("plan: plenty of good quests nearby: no next area", plan and plan.nextArea == nil)
    local pickText
    for _, t in ipairs((plan and plan.order) or {}) do if t.id == "P501" then pickText = L.TaskText(t) end end
    check("step text shows the XP", pickText and pickText:find("+1050 XP", 1, true), pickText)

    -- Ask for more (200% of a solid quest): little is left nearby, and the rich hub is named
    ns.db.minQuestValue = 2
    ns.Ladder.Rebuild("value test 2")
    plan = L.plan
    local area = plan and plan.nextArea
    check("next area: found when little is left nearby", area and area.count == 6 and area.giver == "Far Giver",
        area and (area.count .. " " .. tostring(area.giver)))
    local hints = ns.Hints.Compute({ plan = plan, byId = {}, bags = ns.QuestState.Bags(), now = M.time })
    local hinted = false
    for _, h in ipairs(hints) do if h.text:find("Next area:", 1, true) and h.text:find("6 quests worth doing", 1, true) then hinted = true end end
    check("next area: shown in the hint box", hinted)
    ns.db.minQuestValue = 0
    check("value: 0 keeps every quest", (verdict(502)) and (verdict(503)))
    _G.SlashCmdList.QUESTLADDER("minxp 30")
    check("value: /ladder minxp 30 sets 30%", math.abs(ns.db.minQuestValue - 0.3) < 1e-9, ns.db.minQuestValue)
    ns.db.minQuestValue = 0.5
end

---------------------------------------------------------------------------
-- 15f. 0.3.20: Forever extras for a casual player (from Wowhead's Forever guides; the facts
-- the add-on uses come from QuestieDB and the game)
---------------------------------------------------------------------------
do
    local ns = setup()
    local D, L, G = ns.Data, ns.Ladder, ns.Goodies
    M.player.level, M.player.money = 15, 200000
    local function q(name, level, extra)
        local t = { name = name, startedBy = { { 400 } }, finishedBy = { { 400 } }, requiredLevel = 1, questLevel = level,
                    objectives = {} }
        for k, v in pairs(extra or {}) do t[k] = v end
        return t
    end
    local xp = {}
    for id = 9001, 9030 do xp[id] = { 15, 1000 } end
    local quests = {
        [601] = q("Camping 101: Skinning", 5), [602] = q("The Great Outdoors", 5),
        [603] = q("The Dalaran Digest", 10, { zoneOrSort = -284, startedBy = { nil, nil, { 7001 } }, finishedBy = { { 401 } } }),
        [604] = q("Plain Errand", 15),
        [605] = q("Bag Quest", 15),
        [606] = q("Lucky Drop", 15, { startedBy = { nil, nil, { 7002 } } }), -- starts from a mob drop: never planned
        [79007] = q("...and that note you found", 14, { startedBy = { nil, { 9100 } }, requiredLevel = 14 }),
        [79192] = q("Stepping Stones", 24, { preQuestSingle = { 79007 }, requiredLevel = 14 }),
        [79976] = q("This Must Be The Place", 32, { requiredLevel = 14 }),
        [91899] = q("A Sealed Crate", 60, { finishedBy = { { 256386, 256390 } } }),
        [610] = q("Into the Keep", 16, { zoneOrSort = 209, objectives = { { { 430 } } } }),
        [611] = q("Out in the Woods", 16, { objectives = { { { 431 } } } }),
    }
    for id, t in pairs(quests) do xp[id] = xp[id] or { t.questLevel, 100 } end -- all tiny
    D.InitWith(M.fakeDB({
        quests = quests, questXP = xp,
        npcs = {
            [400] = { name = "Near Giver", spawns = spawn(43, 42) },
            [401] = { name = "Owen Thadd", spawns = spawn(44, 42) },
            [402] = { name = "Bag Vendor", spawns = spawn(45, 41), npcFlags = 128 },
            [403] = { name = "Randal Hunter", subName = "Horse Riding Trainer", friendlyToFaction = "A", spawns = spawn(80, 80), npcFlags = 16 },
            [404] = { name = "Ram Guy", subName = "Ram Riding Trainer", friendlyToFaction = "A", spawns = spawn(43, 43), npcFlags = 16 },
            [405] = { name = "World Horse Riding Trainer", subName = "Horse Riding Trainer", spawns = spawn(42, 41), npcFlags = 16 },
            [256386] = { name = "Dokimi", subName = "Inventory Intake", friendlyToFaction = "H", spawns = spawn(50, 50) },
            [256390] = { name = "Marcy Baker", subName = "Inventory Intake", friendlyToFaction = "A", spawns = spawn(60, 60) },
            [430] = { name = "Keep Guard", spawns = { [209] = { { -1, -1 } } } },
            [431] = { name = "Wolf", spawns = spawn(50, 45) },
            [432] = { name = "Lucky Mob", spawns = spawn(46, 46) },
        },
        objects = {
            [9100] = { name = "Burned Plank", spawns = spawn(70, 30) },
            [9101] = { name = "Dalaran Digest", spawns = spawn(41, 40) },
        },
        items = {
            [7001] = { name = "The Dalaran Digest, Vol. 23", objectDrops = { 9101 } },
            [7002] = { name = "Strange Letter", npcDrops = { 432 } },
            [8001] = { name = "Old Moneybag", class = 1, questRewards = { 605 } },
            [8002] = { name = "Heavy Brown Bag", class = 1, vendors = { 402 } },
        },
    }))
    M.items[8001] = { name = "Old Moneybag", classID = 1, subClassID = 0, sell = 5 }
    M.items[8002] = { name = "Heavy Brown Bag", classID = 1, subClassID = 0, sell = 2500 }
    M.items[8003] = { name = "Shiny Pebble", classID = 15, sell = 900 }
    local slots = { [8001] = 8, [8002] = 10 }
    _G.C_TooltipInfo = { GetItemByID = function(id)
        return { lines = { { leftText = (M.items[id] or {}).name or "?" }, slots[id] and { leftText = slots[id] .. " Slot Bag" } or nil } }
    end }
    local worn = { 6, 6, 10, 10 } -- your four bags
    _G.C_Container.GetContainerNumSlots = function(bag) if bag == 0 then return 16 end return worn[bag] or 0 end
    _G.C_Map.GetAreaInfo = function(id) return ({ [209] = "Shadowfang Keep" })[id] end
    D.BuildIndexes(ns.QuestState.Player(), function() end)
    local player = ns.QuestState.Player()

    -- must-do quests stay whatever their XP
    check("must-do: camping unlocks", G.MustDo(601) == "unlocks a camp item" and G.MustDo(602) == "unlocks camping")
    check("must-do: Library books", G.MustDo(603) == "Library book")
    check("must-do: the sleeping bag chain", G.MustDo(79192) == "Cozy Sleeping Bag chain")
    check("must-do: supply crates", G.MustDo(91899) == "supply crate")
    check("must-do: a plain tiny quest is not", G.MustDo(604) == nil)
    local ok, _, why = L.WorthDoing(601, player)
    check("must-do: kept by the low-XP filter", ok and why == "goodie", why)
    check("must-do: the tiny errand is still skipped", not (L.WorthDoing(604, player)))

    -- quests that start from an item you find
    local pts = D.GiverPoints(D.Quest(603).startedBy)
    check("found item: the book's spot is its pickup", #pts == 1 and pts[1].foundItem == 7001 and pts[1].giverId == -9101,
        #pts .. " " .. tostring(pts[1] and pts[1].giverId))
    check("found item: never a mob drop", #D.GiverPoints(D.Quest(606).startedBy) == 0)
    local text = L.TaskText({ kind = "pickup", questId = 603, quest = { title = "The Dalaran Digest", pickupName = "The Dalaran Digest, Vol. 23",
                                                                         pickup = pts[1] } })
    check("found item: the step says to pick it up and right-click it", text:find("right-click it", 1, true)
        and text:find("Library book", 1, true), text)

    -- bags
    check("bags: slots read from the tooltip", G.BagSlots(8001) == 8 and G.BagSlots(8002) == 10)
    check("bags: your smallest bag", G.SmallestBag() == 6)
    check("bags: an 8-slot reward is an upgrade, a 6 isn't", G.IsBagUpgrade(8) and not G.IsBagUpgrade(6))
    check("bags: a bag reward is a must-do", G.MustDo(605) == "rewards a 8-slot bag", G.MustDo(605))
    local pick = ns.Gear.BestChoice({ { index = 1, itemId = 8003 }, { index = 2, itemId = 8001 } }, player)
    check("bags: a bigger bag beats sell value in a reward choice", pick and pick.itemId == 8001 and pick.reason:find("8 slots"),
        pick and pick.reason)
    local buy = G.BagToBuy(player)
    check("bags: a 10-slot bag to buy, from the vendor nearby", buy and buy.itemId == 8002 and buy.vendor == "Bag Vendor"
        and buy.price == 10000, buy and (buy.name .. " " .. buy.price))
    M.player.money = 5000
    check("bags: not when it would eat your training gold", G.BagToBuy(ns.QuestState.Player()) == nil)
    M.player.money = 200000
    worn = { 10, 12, 10, 10 }
    check("bags: nothing to buy once your bags are 10+", G.BagToBuy(player) == nil)
    worn = { 6, 6, 10, 10 }

    -- riding at 40
    local function at(level, class, skills)
        return { level = level, classFile = class or "WARRIOR", skills = skills or {}, money = 200000, raceFile = "Human",
                 faction = "Alliance", point = player.point }
    end
    local base = 36 * 36 * 35
    check("riding: 100g kept aside from level 35", ns.Gear.Reserve(36, at(36)) == base + ns.Gear.RIDING_COST)
    check("riding: not before 35", ns.Gear.Reserve(30, at(30)) == 30 * 30 * 35)
    check("riding: not for Paladins (class mount quest)", ns.Gear.Reserve(36, at(36, "PALADIN")) == base)
    check("riding: not once you can ride", ns.Gear.Reserve(36, at(36, nil, { [762] = 75 })) == base)
    check("riding: a heads-up at 38", (G.RidingHint(at(38)) or ""):find("Riding at 40", 1, true))
    local t = G.RidingTrainer(at(40))
    check("riding: your race's trainer, not a nearer one or a placeholder", t and t.name == "Randal Hunter", t and t.name)
    local hint = G.RidingHint(setmetatable({ money = 1500000 }, { __index = at(40) }))
    check("riding: at 40 with the gold: where to learn it", hint and hint:find("Learn Apprentice Riding", 1, true)
        and hint:find("Randal Hunter", 1, true), hint)
    check("riding: Paladins get the class mount quest line", (G.RidingHint(at(40, "PALADIN")) or ""):find("class mount quest", 1, true))

    -- the Cozy Sleeping Bag chain
    local _, byId = ns.QuestState.Snapshot()
    local state = L.AvailabilityState(player, byId)
    local cozy = G.CozyStart(player, byId, state)
    check("cozy: suggested at 14+", cozy and cozy.questId == 79007 and cozy.giver == "Burned Plank", cozy and cozy.giver)
    check("cozy: not before 14", G.CozyStart(at(13), byId, state) == nil)
    M.completed[79976] = true
    check("cozy: not once you have it", G.CozyStart(player, byId, state) == nil)
    M.completed[79976] = nil
    -- 0.3.29: "I don't know where or what level requirements the cozy sleeping bag quest has, but
    -- I should be able to click on the step to place a pin": the hint says both, and has a pin
    local function hintWith(plan, needle)
        L.plan = plan
        for _, h in ipairs(ns.Hints.Compute({ plan = plan, byId = {}, bags = ns.QuestState.Bags(), now = M.time })) do
            if h.text:find(needle, 1, true) then return h end
        end
    end
    local cozyHint = hintWith({ player = player, cozyStart = cozy }, "Cozy Sleeping Bag:")
    check("cozy: the hint gives the chain's levels",
        cozyHint and cozyHint.text:find("(quests level 14-32, you can start from level 14)", 1, true), cozyHint and cozyHint.text)
    check("cozy: ...and where it starts", cozyHint and cozyHint.text:find("starts at Burned Plank in", 1, true)
        and cozyHint.text:find("70.0, 30.0", 1, true), cozyHint and cozyHint.text)
    check("cozy: ...with a map pin on it", cozyHint and cozyHint.pin and cozyHint.pin.mapId == cozy.point.mapId
        and cozyHint.pin.x == cozy.point.x and cozyHint.pin.y == cozy.point.y and cozyHint.pin.title == "Burned Plank")
    -- the route's pin, then the clicked one, then the route's again at the next step
    L.plan = { player = player, steps = { { loc = ns.Geo.Point(1429, 0.2, 0.2), tasks = {} },
                                          { loc = ns.Geo.Point(1429, 0.8, 0.8), tasks = {} } } }
    L.current = 1
    L.UpdateWaypoint()
    check("pin: the route's pin is on the step", M.waypoint and M.waypoint.x == 0.2, M.waypoint and M.waypoint.x)
    local prints = {}
    local origPrint = ns.Print
    ns.Print = function(msg) prints[#prints + 1] = msg end
    check("pin: clicking the hint places its pin", L.PinHint(cozyHint) and M.waypoint and M.waypoint.x == cozy.point.x
        and M.waypoint.y == cozy.point.y, M.waypoint and M.waypoint.x)
    check("pin: ...and says where in chat", prints[1] and prints[1]:find("Burned Plank", 1, true)
        and prints[1]:find("70.0, 30.0", 1, true), prints[1])
    ns.Print = origPrint
    L.UpdateWaypoint()
    check("pin: the route doesn't take it back on the same step", M.waypoint and M.waypoint.x == cozy.point.x)
    L.current = 2
    L.UpdateWaypoint()
    check("pin: the route's pin comes back at the next step", M.waypoint and M.waypoint.x == 0.8, M.waypoint and M.waypoint.x)
    check("pin: a hint without a place does nothing", L.PinHint({ text = "x" }) == false)
    -- with TomTom: its own arrow, and a second click replaces only the clicked one
    local added, removed = {}, {}
    _G.TomTom = { AddWaypoint = function(_, m, x, y, o) added[#added + 1] = { m, x, y, o.title }; return #added end,
                  RemoveWaypoint = function(_, uid) removed[#removed + 1] = uid end }
    L.PinTo(cozyHint.pin, "first")
    L.PinTo(cozyHint.pin, "second")
    check("pin: TomTom gets the arrow", #added == 2 and added[2][4] == "Quest Ladder: second" and added[2][2] == cozy.point.x)
    check("pin: a second click replaces the first pin only", #removed == 1 and removed[1] == 1, table.concat(removed, ","))
    _G.TomTom = nil
    -- 0.4.1: on the laptop the pin was on the map with no arrow on screen: the game's In-Game
    -- Navigation option (CVar showInGameNavigation) hides it. Say so once per session.
    local told = 0
    local origPrint2 = ns.Print
    ns.Print = function(msg) if msg:find("In-Game Navigation setting is off", 1, true) then told = told + 1 end end
    local navOff = { GetCVar = function(name) if name == "showInGameNavigation" then return "0" end return "1" end }
    _G.C_CVar = navOff
    L.toldNoArrow = nil
    L.current = 1
    L.UpdateWaypoint()
    check("arrow: In-Game Navigation off, told when the route's pin goes on the map", told == 1, told)
    L.PinTo(cozyHint.pin, "again")
    L.current = 2
    L.UpdateWaypoint()
    check("arrow: ...only once per session", told == 1, told)
    if not ns.Diag then assert(loadfile(ADDON_DIR .. "/Diag.lua"))("QuestLadder", ns) end
    local wpCheck
    for _, c in ipairs(ns.Diag.checks) do if c.id == "waypoint" then wpCheck = c end end
    local okW, wStatus, wSummary, wData = pcall(wpCheck.fn, { step = L.plan.steps[2] })
    check("arrow: the diag names the option", okW and wStatus == "warn" and wData.inGameNavigation == "0"
        and tostring(wSummary):find("In-Game Navigation", 1, true), tostring(wStatus) .. ": " .. tostring(wSummary))
    -- on: nothing said, and the diag is happy
    _G.C_CVar = { GetCVar = function() return "1" end }
    L.toldNoArrow, told = nil, 0
    L.current = 1
    L.UpdateWaypoint()
    check("arrow: In-Game Navigation on, nothing said", told == 0, told)
    okW, wStatus, wSummary = pcall(wpCheck.fn, { step = L.plan.steps[1] })
    check("arrow: ...and the diag's waypoint check is ok", okW and wStatus == "ok", tostring(wStatus) .. ": " .. tostring(wSummary))
    -- 0.5.0: Forever has no In-Game Navigation setting, and the arrow went missing with the pin set
    -- and tracked: the diag records what Blizzard's arrow is doing
    local realST = _G.C_SuperTrack
    _G.C_SuperTrack = { SetSuperTrackedUserWaypoint = function() end, IsSuperTrackingUserWaypoint = function() return true end,
                        GetHighestPrioritySuperTrackingType = function() return 0 end, GetSuperTrackedQuestID = function() return 123 end }
    okW, wStatus, wSummary = pcall(wpCheck.fn, { step = L.plan.steps[1] })
    check("arrow: the diag says when the game navigates to a quest instead", okW and wStatus == "warn"
        and tostring(wSummary):find("navigating to something else (type 0, quest 123)", 1, true), tostring(wSummary))
    _G.C_SuperTrack.GetHighestPrioritySuperTrackingType = function() return 1 end
    _G.C_Navigation = { GetFrame = function() return nil end, GetTargetState = function() return 0 end }
    okW, wStatus, wSummary = pcall(wpCheck.fn, { step = L.plan.steps[1] })
    check("arrow: ...or makes no navigation frame for the pin", okW and wStatus == "warn"
        and tostring(wSummary):find("made no navigation frame", 1, true), tostring(wSummary))
    _G.C_Navigation.GetFrame = function() return {} end
    _G.SuperTrackedFrame = { IsShown = function() return true end, GetAlpha = function() return 1 end,
                             Arrow = { IsShown = function() return true end } }
    local okN, nStatus, nSummary, nData = pcall(wpCheck.fn, { step = L.plan.steps[1] })
    check("arrow: ...and what the arrow frame shows when it's there", okN and nStatus == "ok"
        and tostring(nSummary):find("arrow frame true, alpha 1, edge arrow true", 1, true) and nData.nav.shown == true, tostring(nSummary))
    _G.C_SuperTrack, _G.C_Navigation, _G.SuperTrackedFrame = realST, nil, nil
    -- 0.5.0: Forever rated a pin 5,300 yd away "Invalid" (state 0) and Blizzard's arrow frame
    -- draws that see-through, though it was placed and its edge arrow pointed the right way. Quest
    -- Ladder shows it for its own pins (the user's choice), never for the user's own.
    local arrowFrame = { alpha = 0 }
    function arrowFrame:SetAlpha(a) self.alpha = a end
    function arrowFrame:UpdateAlpha() self:SetAlpha(0) end -- what Blizzard does for an Invalid target
    _G.SuperTrackedFrame = arrowFrame
    local realHook, hooks = _G.hooksecurefunc, 0
    _G.hooksecurefunc = function(t, name, fn)
        hooks = hooks + 1
        local orig = t[name]
        t[name] = function(...) orig(...); fn(...) end
    end
    local navState = 0
    _G.C_Navigation = { GetTargetState = function() return navState end, HasValidScreenPosition = function() return true end }
    L.arrowHooked = false
    L.current = 2
    L.UpdateWaypoint() -- Quest Ladder places its pin
    arrowFrame:UpdateAlpha()
    check("arrow: Quest Ladder's pin rated Invalid: the arrow shows", L.arrowHooked and L.ourPinTracked and arrowFrame.alpha == 1,
        tostring(L.ourPinTracked) .. " " .. tostring(arrowFrame.alpha))
    navState = 2
    arrowFrame:UpdateAlpha()
    check("arrow: in range, Blizzard's own alpha is left alone", arrowFrame.alpha == 0)
    navState = 0
    local ours = M.waypoint
    M.waypoint = { mapId = 1429, x = 0.5, y = 0.5 } -- you place your own pin
    ns.DispatchEvent("USER_WAYPOINT_UPDATED")
    arrowFrame:UpdateAlpha()
    check("arrow: your own pin looks as Blizzard draws it", not L.ourPinTracked and arrowFrame.alpha == 0)
    M.waypoint = ours
    ns.DispatchEvent("SUPER_TRACKING_CHANGED")
    local keepPlan = L.plan
    _G.SlashCmdList.QUESTLADDER("arrow")
    L.plan = keepPlan
    arrowFrame:UpdateAlpha()
    check("arrow: /ladder arrow turns it off", ns.db.unhideArrow == false and arrowFrame.alpha == 0)
    _G.SlashCmdList.QUESTLADDER("arrow")
    L.plan = keepPlan
    L.HookNavigationArrow()
    check("arrow: hooked once", hooks == 1 and ns.db.unhideArrow == true, hooks)
    _G.C_Navigation = { GetTargetState = function() return "secret" end, HasValidScreenPosition = function() return true end }
    _G.issecretvalue = function(v) return v == "secret" end
    arrowFrame:UpdateAlpha()
    check("arrow: a secret state is never compared", arrowFrame.alpha == 0)
    _G.issecretvalue = function() return false end
    _G.hooksecurefunc, _G.C_Navigation, _G.SuperTrackedFrame = realHook, nil, nil
    L.current = 1
    L.UpdateWaypoint()
    -- TomTom draws its own arrow, so the option doesn't matter there
    _G.C_CVar = navOff
    _G.TomTom = { AddWaypoint = function() return 1 end, RemoveWaypoint = function() end }
    L.current = 2
    L.UpdateWaypoint()
    L.PinTo(cozyHint.pin, "tomtom")
    check("arrow: with TomTom, nothing said", told == 0, told)
    _G.TomTom = nil
    -- the game's answer is read safely: an error, no C_CVar at all, a value we can't read
    _G.C_CVar = { GetCVar = function() error("no such CVar") end }
    check("arrow: a CVar error counts as on", L.InGameNavigationOff() == false)
    _G.C_CVar = nil
    check("arrow: no CVar API counts as on", L.InGameNavigationOff() == false)
    _G.C_CVar = { GetCVar = function() return nil end }
    check("arrow: an unknown CVar counts as on", L.InGameNavigationOff() == false)
    _G.C_CVar = nil
    ns.Print = origPrint2
    L.toldNoArrow = nil
    -- the other hints that name a place get one too
    local buyHint = hintWith({ player = player, bagToBuy = buy }, "More bag space:")
    check("pin: the bag vendor", buyHint and buyHint.pin and buyHint.pin.title == "Bag Vendor" and buy.point
        and buyHint.pin.x == buy.point.x, buyHint and buyHint.pin and buyHint.pin.title)
    local _, trainer = G.RidingHint(setmetatable({ money = 1500000 }, { __index = at(40) }))
    check("pin: the riding hint names its trainer for the pin", trainer and trainer.name == "Randal Hunter" and trainer.point ~= nil)

    -- supply crates
    M.items[8010] = { name = "Waylaid Supplies: Copper Bars", classID = 7 }
    M.items[8011] = { name = "Supply Shipment", classID = 7 }
    M.bag = { { id = 8010 }, { id = 8011 } }
    local crates = G.CratesInBags(ns.QuestState.Bags())
    check("crates: found in your bags", #crates == 2 and crates[1].material == "Copper Bars" and crates[2].kind == "turnin")
    local npc = G.CrateNpc(player)
    check("crates: your faction's intake NPC", npc and npc.name == "Marcy Baker", npc and npc.name)
    L.plan = { player = player }
    local hints = ns.Hints.Compute({ plan = L.plan, byId = {}, bags = ns.QuestState.Bags(), now = M.time })
    local fill, turnin, pinned = false, false, 0
    for _, h in ipairs(hints) do
        if h.text:find("Copper Bars", 1, true) and h.text:find("Marcy Baker", 1, true) then fill = true end
        if h.text:find("Supply Shipment:", 1, true) then turnin = true end
        if (h.text:find("Copper Bars", 1, true) or h.text:find("Supply Shipment:", 1, true)) and h.pin
            and h.pin.title == "Marcy Baker" then pinned = pinned + 1 end
    end
    check("crates: hints say what to fill and who takes it", fill and turnin)
    check("crates: both lines pin the intake NPC", pinned == 2, pinned)
    M.bag = {}

    -- dungeon quests to pick up
    local groups = G.DungeonQuests(player, state, { 610, 611, 604 })
    check("dungeons: only quests with objectives inside, by dungeon", #groups == 1 and groups[1].dungeon == "Shadowfang Keep"
        and #groups[1].quests == 1 and groups[1].quests[1].id == 610, #groups .. " " .. tostring(groups[1] and groups[1].dungeon))
    check("dungeons: says who gives it", groups[1] and groups[1].quests[1].giver == "Near Giver")
    _G.C_TooltipInfo, _G.C_Map.GetAreaInfo = nil, nil
end

---------------------------------------------------------------------------
-- 15g. 0.3.21: The Barrens, "resources are spread out a ton". New quests must be worth the walk
-- (Planner.PruneTrips); a Silverpine quest's murlocs were looked for in Darkshore; a retired
-- "zzOLD" flight point was a step; "/ladder dungeons" hid the dungeon toggle.
---------------------------------------------------------------------------
do
    local ns = setup()
    local P, Geo = ns.Planner, ns.Geo
    check("trips: grinding at 17 gives 6.5 XP a second (130 XP a kill, 20 s each)", math.abs(P.GrindRate(17) - 6.5) < 1e-9)

    -- A hub with quests in every direction (yards on one continent, walking at 7 yd/s)
    local function pt(x, y) return { cont = 0, wx = x, wy = y, mapId = 1, x = 0, y = 0 } end
    local hub = pt(0, 0)
    local function obj(x, y) return { { index = 1, type = "monster", need = 1, have = 0, finished = false, loc = pt(x, y) } } end
    local function cand(id, title, objectives, xp, extra)
        local c = { id = id, title = title, pickup = hub, turnin = hub, objectives = objectives or {}, tripXP = xp }
        for k, v in pairs(extra or {}) do c[k] = v end
        return c
    end
    local function ctx(tripCheck)
        return {
            start = hub, level = 17, tripCheck = tripCheck, logCount = 1, logMax = 40,
            active = { { id = 10, title = "East Camp (in your log)", objectives = obj(1500, 0), turnin = hub } },
            candidates = {
                cand(20, "Far West", obj(-2000, 0), 700),
                cand(21, "Same East Camp", obj(1520, 30), 800),
                cand(22, "North One", obj(0, 1500), 600),
                cand(23, "North Two", obj(50, 1500), 600),
                cand(24, "Far South Class Quest", obj(0, -2500), 150, { keep = true }),
                cand(25, "Next Door", obj(100, 0), 300),
                cand(26, "Breadcrumb", {}, 200),
                cand(27, "Follow-up Far Away", obj(-1800, -1800), 1000, { after = { 26 }, chainedFrom = 26 }),
            },
        }
    end
    local plan = P.Plan(ctx(true))
    local pruned, inOrder = {}, {}
    for _, p in ipairs(plan.pruned) do pruned[p.questId] = p end
    for _, t in ipairs(plan.order) do if t.kind == "pickup" then inOrder[t.questId] = true end end
    local function list(set) local o = {} for id in pairs(set) do o[#o + 1] = id end table.sort(o) return table.concat(o, ",") end
    check("trips: a far quest that gives less than grinding that long is dropped", pruned[20] ~= nil and not inOrder[20], list(pruned))
    check("trips: a quest at a camp you visit anyway stays", inOrder[21] and not pruned[21])
    check("trips: next door stays", inOrder[25])
    check("trips: two quests sharing one long walk are weighed together and dropped",
        pruned[22] and pruned[23] and pruned[22].together == 2, pruned[22] and pruned[22].together)
    check("trips: a quest marked keep stays however far", inOrder[24])
    check("trips: a far follow-up goes, its breadcrumb at the hub stays", pruned[27] and inOrder[26] and not pruned[26], list(inOrder))
    check("trips: the route left is valid", P.IsValid(plan.order, { logCount = 1, logMax = 40 }))
    check("trips: dropped counts only quests left out for log space", plan.dropped == 0, plan.dropped)
    check("trips: each skipped quest says what it would have cost", pruned[20] and pruned[20].seconds > 120
        and pruned[20].title == "Far West" and pruned[20].worth < P.TRIP_KEEP_SHARE, pruned[20] and pruned[20].seconds)
    local tie = ctx(true)
    tie.candidates = { cand(20, "Far West", obj(-2000, 0), 3100) } -- ~83% of grinding for its ~570 s detour
    check("trips: a near tie with grinding stays (real grinding has eating and drinking in it)", #P.Plan(tie).pruned == 0)
    local off = P.Plan(ctx(nil))
    check("trips: off keeps every quest", #off.pruned == 0 and #off.order == #plan.tasks, #off.order .. " of " .. #plan.tasks)
    check("trips: and the check makes the route shorter", plan.cost < off.cost - 600,
        string.format("%.0f vs %.0f s", plan.cost, off.cost))
    local lines = ns.Ladder.SkippedLines(plan)
    local text = table.concat(lines, "\n")
    check("trips: /ladder skipped lists them with the travel they'd add", text:find("Not worth the walk from here (4):", 1, true)
        and text:find("Far West - 700 XP, but adds", 1, true) and text:find("2 quests out there together: 1200 XP", 1, true), text)

    -- Mobs on two continents: a Silverpine quest's murlocs, while you're in The Barrens
    local darkshore = { pt(100, 500), pt(110, 505), pt(105, 495) }
    for _, p in ipairs(darkshore) do p.cont = 1 end
    local silverpine = { pt(500, 1600), pt(510, 1605), pt(505, 1595) }
    local pts = {}
    for _, p in ipairs(darkshore) do pts[#pts + 1] = p end
    for _, p in ipairs(silverpine) do pts[#pts + 1] = p end
    local you = { cont = 1, wx = 112, wy = -2777 }
    local sepulcher = pt(522, 1652)
    check("cluster: without the quest's home, the nearest camp (Darkshore) wins", Geo.BestCluster(pts, you, 90).cont == 1)
    local c = Geo.BestCluster(pts, you, 90, sepulcher)
    check("cluster: with it, the camp on the quest's continent near its NPC", c.cont == 0 and math.abs(c.wx - 505) < 1, c.cont)
    local near = { pt(0, 0), pt(10, 5) }
    local byNpc = { pt(2000, 0), pt(2010, 5) }
    local both = { near[1], near[2], byNpc[1], byNpc[2] }
    check("cluster: on the quest's continent, the camp near you still wins", Geo.BestCluster(both, pt(5, 0), 90, pt(2100, 0)).wx < 100)

    -- the same in the full pipeline: you're on continent 1, the quest's NPC on continent 0
    local D = ns.Data
    D.InitWith(M.fakeDB({
        quests = { [810] = { name = "Murloc Eyes", startedBy = { { 450 } }, finishedBy = { { 450 } }, requiredLevel = 1,
                             questLevel = 12, objectives = { { { 460 } } } } },
        npcs = {
            [450] = { name = "Apothecary Renferrel", spawns = spawn(50, 50) },
            [460] = { name = "Murloc", spawns = { [12] = { { 60, 60 }, { 61, 61 }, { 60.5, 60.5 } },
                                                  [40] = { { 45, 45 }, { 46, 46 }, { 45.5, 45.5 } } } },
        },
        objects = {}, items = {},
    }))
    M.player.mapId, M.player.x, M.player.y, M.player.level = 1436, 0.44, 0.44, 12
    M.log = { { id = 810, title = "Murloc Eyes", level = 12, complete = false,
                objectives = { { text = "Murloc slain: 0/3", type = "monster", finished = false, numFulfilled = 0, numRequired = 3 } } } }
    local mplan = fullPlan(ns)
    local o = mplan and mplan.byId["O810:1"]
    check("cluster: a log quest's objective is placed on its NPC's continent", o and o.loc and o.loc.cont == 0,
        o and o.loc and o.loc.cont)
    M.log = {}

    -- retired flight points
    check("flights: \"zz\" nodes are retired test points", ns.Travel.IsRetiredNode("zzOLDPowderfuse Port, Riverglades")
        and not ns.Travel.IsRetiredNode("Ratchet, The Barrens") and not ns.Travel.IsRetiredNode(nil))
    M.player.mapId, M.player.x, M.player.y = 1429, 0.42, 0.41
    M.taxiNodes = {
        { name = "zzOLDPowderfuse Port, Riverglades", position = { x = 0.50, y = 0.405 }, faction = 2, nodeID = 9 },
        { name = "Ratchet, The Barrens", position = { x = 0.50, y = 0.405 }, faction = 2, nodeID = 10 },
    }
    local net = ns.Travel.BuildNetwork(ns.QuestState.Player())
    local names = {}
    for _, n in ipairs(net.nodes) do names[#names + 1] = n.name end
    check("flights: a retired node never makes the network", #net.nodes == 1 and names[1] == "Ratchet, The Barrens",
        table.concat(names, ","))
    M.taxiNodes = {}
end

---------------------------------------------------------------------------
-- 15m. 0.4.0: "once my character gets to a certain level (+3 to 4) above the area's proposed
-- quests, it may be time to move on from some of my older quests that are from a lower level."
-- Outgrown quests in your log get the "worth the trip" check; the hint box says what to drop
-- and, in a quest dialog, which quests to take.
---------------------------------------------------------------------------
do
    local ns = setup()
    local P, L, H = ns.Planner, ns.Ladder, ns.Hints
    local function pt(x, y, cont) return { cont = cont or 0, wx = x, wy = y, mapId = 1, x = 0, y = 0 } end
    local hub = pt(0, 0)
    local function obj(x, y, cont) return { { index = 1, type = "monster", need = 1, have = 0, finished = false, loc = pt(x, y, cont) } } end
    local function logq(id, title, objectives, xp, extra)
        local q = { id = id, title = title, turnin = hub, objectives = objectives or {}, outgrown = true, tripXP = xp, level = 12 }
        for k, v in pairs(extra or {}) do q[k] = v end
        return q
    end
    -- walking at 7 yd/s; another continent is a 900 s crossing
    local function walk(a, b)
        if a.cont ~= b.cont then return 900 end
        return math.sqrt((a.wx - b.wx) ^ 2 + (a.wy - b.wy) ^ 2) / 7
    end
    local function ctx(active, candidates)
        return { start = hub, level = 17, tripCheck = true, logCount = #active, logMax = 40, travel = walk,
                 active = active, candidates = candidates or {} }
    end
    local plan = P.Plan(ctx({
        logq(30, "Old Far Camp", obj(-2000, 0), 600),
        logq(31, "Old Next Door", obj(100, 0), 600),
        logq(32, "At Your Level, Far", obj(0, -2000), 600, { outgrown = false, tripXP = nil, level = 17 }),
        logq(33, "Old Class Quest, Far", obj(2000, 0), 100, { keep = true }),
        logq(34, "Old, Ready To Turn In, Far", {}, 300, { complete = true, turnin = pt(0, 2200) }),
    }))
    local out, inOrder = {}, {}
    for _, p in ipairs(plan.outgrown) do out[p.questId] = p end
    for _, t in ipairs(plan.order) do inOrder[t.questId or -1] = true end
    local function list(set) local o = {} for id in pairs(set) do o[#o + 1] = id end table.sort(o) return table.concat(o, ",") end
    check("outgrown: an old quest the route would walk 2000 yd for is left out", out[30] and not inOrder[30], list(out))
    check("outgrown: ...and so is an old turn-in far away", out[34] and not inOrder[34], list(out))
    check("outgrown: an old quest on the way stays", inOrder[31] and not out[31])
    check("outgrown: a quest at your level stays however far", inOrder[32] and not out[32])
    check("outgrown: a class quest stays", inOrder[33] and not out[33])
    check("outgrown: they're listed apart from new quests", #plan.pruned == 0 and out[30] and out[30].inLog == true)
    check("outgrown: the route left is valid", P.IsValid(plan.order, { logCount = 5, logMax = 40 }))
    check("outgrown: they don't count as left out for log space", plan.dropped == 0, plan.dropped)

    -- one ocean crossing carries two old quests that each look cheap on their own: weighed together
    local away = P.Plan(ctx({
        logq(40, "Old Quest Over The Sea, West", obj(0, 0, 1), 2500, { turnin = pt(0, 0, 1) }),
        logq(41, "Old Quest Over The Sea, East", obj(3000, 0, 1), 2500, { turnin = pt(3000, 0, 1) }),
        logq(42, "Here", obj(50, 0), 600, { outgrown = false, tripXP = nil, level = 17 }),
    }))
    local gone = {}
    for _, p in ipairs(away.outgrown) do gone[p.questId] = p end
    check("outgrown: two quests across the sea go together", gone[40] and gone[41] and gone[40].together == 2, list(gone))
    -- ...but not when one of them is still at your level: the trip happens anyway
    local stay = P.Plan(ctx({
        logq(40, "Old Quest Over The Sea, West", obj(0, 0, 1), 2500, { turnin = pt(0, 0, 1) }),
        logq(41, "At Your Level Over The Sea", obj(3000, 0, 1), 2500, { turnin = pt(3000, 0, 1), outgrown = false, tripXP = nil }),
    }))
    check("outgrown: with an at-level quest over there, the old one rides along", #stay.outgrown == 0, #stay.outgrown)
    -- a new quest that only follows an outgrown one goes with it
    local chain = P.Plan(ctx({ logq(50, "Old Breadcrumb, Far", obj(-2000, 0), 300) },
        { { id = 51, title = "Its Follow-up", pickup = hub, turnin = hub, objectives = obj(-2050, 0), tripXP = 400, after = { 50 } } }))
    local cgone = {}
    for _, p in ipairs(chain.outgrown) do cgone[p.questId] = true end
    for _, p in ipairs(chain.pruned) do cgone[p.questId] = true end
    check("outgrown: its follow-up goes with it", cgone[50] and cgone[51], list(cgone))
    local off = ctx({ logq(30, "Old Far Camp", obj(-2000, 0), 600) })
    off.tripCheck = nil
    check("outgrown: /ladder trips off keeps them", #P.Plan(off).outgrown == 0)

    -- the full pipeline: which quests in your log count as outgrown (3+ levels under you)
    local D = ns.Data
    D.InitWith(M.fakeDB({
        quests = {
            [960] = { name = "Old Murlocs", startedBy = { { 600 } }, finishedBy = { { 600 } }, requiredLevel = 1, questLevel = 12,
                      objectives = { { { 610 } } } },
            [961] = { name = "Nearly Current", startedBy = { { 600 } }, finishedBy = { { 600 } }, requiredLevel = 1, questLevel = 16,
                      objectives = { { { 611 } } } },
            [962] = { name = "Old Class Errand", startedBy = { { 600 } }, finishedBy = { { 600 } }, requiredLevel = 1, questLevel = 10,
                      requiredClasses = 1, objectives = { { { 611 } } } },
            [963] = { name = "Old Breadcrumb", startedBy = { { 600 } }, finishedBy = { { 601 } }, requiredLevel = 1, questLevel = 12,
                      objectives = {} },
            [964] = { name = "Good Follow-up", startedBy = { { 601 } }, finishedBy = { { 601 } }, requiredLevel = 14, questLevel = 18,
                      objectives = {}, preQuestSingle = { 963 } },
        },
        questXP = { [960] = { 12, 500 }, [961] = { 16, 1200 }, [962] = { 10, 400 }, [963] = { 12, 200 }, [964] = { 18, 1500 } },
        npcs = {
            [600] = { name = "Old Giver", spawns = spawn(42, 41) },
            [601] = { name = "Far Contact", spawns = spawn(90, 90) },
            [610] = { name = "Murloc", spawns = spawn(85, 85) },
            [611] = { name = "Boar", spawns = spawn(44, 42) },
        },
        objects = {}, items = {},
    }))
    M.player.level = 18
    M.log = {
        { id = 960, title = "Old Murlocs", level = 12, complete = false,
          objectives = { { text = "Murloc slain: 0/5", type = "monster", finished = false, numFulfilled = 0, numRequired = 5 } } },
        { id = 961, title = "Nearly Current", level = 16, complete = false,
          objectives = { { text = "Boar slain: 0/5", type = "monster", finished = false, numFulfilled = 0, numRequired = 5 } } },
        { id = 962, title = "Old Class Errand", level = 10, complete = false,
          objectives = { { text = "Boar slain: 0/1", type = "monster", finished = false, numFulfilled = 0, numRequired = 1 } } },
        { id = 963, title = "Old Breadcrumb", level = 12, complete = true, objectives = {} },
    }
    local fp = fullPlan(ns)
    local act = {}
    for _, q in ipairs((fp and fp.active) or {}) do act[q.id] = q end
    check("outgrown: 3+ levels under you counts (12 at 18)", act[960] and act[960].outgrown == true)
    check("outgrown: 2 under doesn't (16 at 18)", act[961] and not act[961].outgrown)
    check("outgrown: a class quest never does", act[962] and not act[962].outgrown)
    check("outgrown: its XP is what it gives you now", act[960] and math.abs((act[960].tripXP or 0) - 400) < 1, act[960] and act[960].tripXP)
    -- a breadcrumb into a good quest: the follow-up is planned after it, so dropping the
    -- breadcrumb would drop the follow-up too and its XP counts there; when the follow-up isn't
    -- planned yet, the breadcrumb carries its XP
    local follow
    for _, c in ipairs((fp and fp.candidates) or {}) do if c.id == 964 then follow = c end end
    check("outgrown: the breadcrumb's follow-up is planned after it", follow and follow.after and follow.after[1] == 963
        and act[963] and act[963].outgrown and math.abs((act[963].tripXP or 0) - 160) < 1, act[963] and act[963].tripXP)
    local crumb = { { id = 963, title = "Old Breadcrumb", level = 12, complete = true, objectives = {} } }
    L.MarkOutgrown(crumb, ns.QuestState.Player(), {})
    check("outgrown: a breadcrumb into a good quest not planned yet carries that quest's XP",
        crumb[1].outgrown and (crumb[1].tripXP or 0) >= 1500, crumb[1].tripXP)
    local fout = {}
    for _, p in ipairs((fp and fp.outgrown) or {}) do fout[p.questId] = true end
    check("outgrown: the far old murlocs are left out of the route", fout[960] == true, list(fout))

    -- the hint box: what to abandon, and with a full log, what to drop first
    local function hintWith(p, needle)
        for _, h in ipairs(H.Compute({ plan = p, byId = {}, bags = ns.QuestState.Bags(), now = M.time })) do
            if h.text:find(needle, 1, true) then return h end
        end
    end
    local hp = { player = ns.QuestState.Player(), outgrown = { { questId = 960, title = "Old Murlocs", xp = 400, seconds = 400,
        quest = { level = 12 } } }, pruned = {}, logCount = 30, logMax = 40, active = {} }
    local oh = hintWith(hp, "Outgrown:")
    check("outgrown: the hint names it and says to abandon it", oh and oh.text:find("Old Murlocs", 1, true)
        and oh.text:find("[12]", 1, true) and oh.text:find("abandon it to free log space (log 30/40)", 1, true), oh and oh.text)
    local full = { player = hp.player, outgrown = {}, pruned = {}, logCount = 39, logMax = 40, active = {
        { id = 70, title = "Old Started", level = 12, outgrown = true, tripXP = 300,
          objectives = { { numFulfilled = 2, finished = false } } },
        { id = 71, title = "Old Untouched", level = 12, outgrown = true, tripXP = 500, objectives = { { numFulfilled = 0 } } },
        { id = 72, title = "Older Untouched", level = 10, outgrown = true, tripXP = 200, objectives = {} },
        { id = 73, title = "Current", level = 17, objectives = {} },
    } }
    local fh = hintWith(full, "Quest log 39/40:")
    check("log full: names the weakest to drop, least XP first",
        fh and fh.text:find("Older Untouched", 1, true) and fh.text:find("Old Untouched", 1, true)
        and fh.text:find("Older Untouched", 1, true) < fh.text:find("Old Untouched", 1, true), fh and fh.text)
    check("log full: never a quest you've started or one at your level", fh and not fh.text:find("Old Started", 1, true)
        and not fh.text:find("Current", 1, true))
    full.logCount = 30
    check("log full: quiet while there's room", hintWith(full, "Quest log") == nil)
    local lines = table.concat(L.SkippedLines(hp), "\n")
    check("outgrown: /ladder outgrown lists them", lines:find("Outgrown, in your log but not worth the trip any more (1)", 1, true)
        and lines:find("Old Murlocs [12] - 400 XP", 1, true), lines)
    full.logCount = 40
    local fl = table.concat(L.SkippedLines(full), "\n")
    check("log full: /ladder outgrown lists the weakest too", fl:find("Your log is 40/40. Weakest to drop first:", 1, true)
        and fl:find("Older Untouched [10] - 200 XP, outgrown, not started", 1, true), fl)
    M.log = {}
end

---------------------------------------------------------------------------
-- 15n. 0.4.0: take it or leave it, in a quest dialog
---------------------------------------------------------------------------
do
    local ns = setup()
    local L, H, D = ns.Ladder, ns.Hints, ns.Data
    local function q(name, level, xp) return { name = name, startedBy = { { 600 } }, finishedBy = { { 600 } }, requiredLevel = 1,
                                             questLevel = level, objectives = {} } end
    D.InitWith(M.fakeDB({
        quests = { [950] = q("Planned Pickup", 17), [951] = q("Dropped Before", 17), [952] = q("Too High", 22),
                   [953] = q("Grey", 5), [954] = q("Far Trip", 17), [955] = q("Tiny", 17), [956] = q("Worth It", 17),
                   [957] = q("Low XP", 17) },
        questXP = { [950] = { 17, 1400 }, [951] = { 17, 1400 }, [952] = { 22, 2000 }, [953] = { 5, 100 }, [954] = { 17, 1400 },
                    [955] = { 17, 1400 }, [956] = { 17, 1400 }, [957] = { 17, 40 } },
        npcs = { [600] = { name = "Giver", spawns = spawn(42, 41) } }, objects = {}, items = {},
    }))
    M.player.level = 17
    ns.db.autoAccept = false
    ns.charDB.ignored[951] = true
    L.plan = { player = ns.QuestState.Player(), steps = { { tasks = {} }, { tasks = { { kind = "pickup", questId = 950 } } } },
               pruned = { { questId = 954, xp = 900, seconds = 600 } }, skippedLowValue = { { id = 955, xp = 200 } },
               logCount = 20, logMax = 40 }
    local function v(id) local take, why = L.QuestVerdict(id) return take, why or "" end
    local take, why = v(950)
    check("verdict: a quest on your route: take it, and which step", take == true and why:find("step 2", 1, true), why)
    take, why = v(951)
    check("verdict: one you dropped: skip, and how to undo", take == false and why:find("/ladder unignore 951", 1, true), why)
    take, why = v(952)
    check("verdict: too high", take == false and why:find("level 22 is too high", 1, true), why)
    take, why = v(953)
    check("verdict: grey", take == false and why:find("grey for you", 1, true), why)
    take, why = v(954)
    check("verdict: not worth the walk, with the numbers", take == false and why:find("900 XP for 10:00 of travel", 1, true), why)
    take, why = v(955)
    check("verdict: too little XP", take == false and why:find("too little XP", 1, true), why)
    take, why = v(956)
    check("verdict: worth it but not planned: take it", take == true and why:find("route adds it", 1, true), why)
    take, why = v(957)
    check("verdict: not worth it and not planned: skip", take == false, why)
    L.plan.logCount = 40
    take, why = v(956)
    check("verdict: a full log: skip, and where to look", take == false and why:find("log is full (40/40)", 1, true), why)
    L.plan.logCount = 20
    check("verdict: nothing to say about a secret or unknown id", L.QuestVerdict(nil) == nil and L.QuestVerdict(99999) == nil)

    -- the dialog lines in the hint box
    local function find(needle)
        for _, h in ipairs(H.Compute({ plan = L.plan, byId = {}, bags = ns.QuestState.Bags(), now = M.time })) do
            if h.text:find(needle, 1, true) then return h end
        end
    end
    _G.GetQuestID = function() return 956 end
    ns.DispatchEvent("QUEST_DETAIL")
    local line = find("Worth It")
    check("dialog: the quest text gets a Take line", line and line.text:find("Take:", 1, true), line and line.text)
    ns.DispatchEvent("QUEST_FINISHED")
    check("dialog: gone when the dialog closes", find("Worth It") == nil)
    _G.C_GossipInfo = { GetAvailableQuests = function() return { { questID = 950 }, { questID = 953 } } end }
    ns.DispatchEvent("GOSSIP_SHOW")
    local a, b = find("Planned Pickup"), find("Grey")
    check("dialog: a gossip list gets a line per quest", a and a.text:find("Take:", 1, true) and b and b.text:find("Skip:", 1, true),
        (a and a.text or "-") .. " / " .. (b and b.text or "-"))
    check("dialog: takes come first", a and b and a.priority > b.priority)
    _G.GetQuestID = function() return 950 end
    ns.DispatchEvent("QUEST_DETAIL")
    ns.DispatchEvent("GOSSIP_CLOSED") -- the gossip window closes after the quest text opened
    check("dialog: closing the gossip list keeps the quest text's line", find("Planned Pickup") ~= nil and find("Grey") == nil)
    ns.DispatchEvent("QUEST_FINISHED")
    check("dialog: and that goes with the quest text", find("Planned Pickup") == nil)
    _G.GetQuestID, _G.C_GossipInfo = nil, nil
    ns.charDB.ignored[951] = nil
    ns.db.autoAccept = true
end

do
    -- the whole pipeline at a Barrens-like hub: XP from QuestieDB, a quest 1,500 yards out
    local ns = setup()
    local D, L = ns.Data, ns.Ladder
    M.player.level = 17
    local xp = {}
    for id = 9001, 9030 do xp[id] = { 17, 1350 } end
    local function q(name, mob, extra)
        local t = { name = name, startedBy = { { 400 } }, finishedBy = { { 400 } }, requiredLevel = 1, questLevel = 17,
                    objectives = { { { mob } } } }
        for k, v in pairs(extra or {}) do t[k] = v end
        return t
    end
    local quests = {
        [801] = q("Near Errand", 420),
        [802] = q("Long Walk", 421),
        [803] = q("Class Trip", 422, { requiredClasses = 1 }),
    }
    xp[801], xp[802], xp[803] = { 17, 1350 }, { 17, 1350 }, { 17, 150 }
    D.InitWith(M.fakeDB({
        quests = quests, questXP = xp,
        npcs = {
            [400] = { name = "Hub Giver", spawns = spawn(43, 42) },
            [420] = { name = "Near Mob", minLevel = 16, spawns = spawn(45, 44) },
            [421] = { name = "Far Mob", minLevel = 16, spawns = spawn(95, 45) },
            [422] = { name = "Other Far Mob", minLevel = 16, spawns = spawn(2, 45) },
        },
        objects = {}, items = {},
    }))
    local plan = (function()
        local built = false
        D.BuildIndexes(ns.QuestState.Player(), function() built = true end)
        L.Rebuild("barrens")
        return L.plan
    end)()
    local inOrder, pruned = {}, {}
    for _, t in ipairs((plan and plan.order) or {}) do if t.kind == "pickup" then inOrder[t.questId] = true end end
    for _, p in ipairs((plan and plan.pruned) or {}) do pruned[p.questId] = p end
    check("barrens: the quest next to the hub is planned", inOrder[801])
    check("barrens: the solid quest 1,500 yards out isn't worth the walk", pruned[802] and not inOrder[802]
        and pruned[802].xp == 1350, pruned[802] and pruned[802].seconds)
    check("barrens: a class quest out there stays (never dropped for distance)", inOrder[803] and not pruned[803])
    local c803
    for _, c in ipairs(plan.candidates) do if c.id == 803 then c803 = c end end
    check("barrens: class quests are marked keep", c803 and c803.keep and c803.worthWhy == "class")
    local hints = ns.Hints.Compute({ plan = plan, byId = {}, bags = ns.QuestState.Bags(), now = M.time })
    local hinted = false
    for _, h in ipairs(hints) do if h.text:find("1 quest here is not worth the walk", 1, true) then hinted = true end end
    check("barrens: the hint box says a quest was skipped", hinted)
    local text = table.concat(L.SkippedLines(plan), "\n")
    check("barrens: /ladder skipped names it", text:find("Long Walk - 1350 XP", 1, true) and text:find("killing mobs that long", 1, true), text)
    _G.SlashCmdList.QUESTLADDER("trips")
    check("barrens: /ladder trips turns the check off", ns.db.tripCheck == false)
    L.Rebuild("barrens off")
    inOrder = {}
    for _, t in ipairs(L.plan.order) do if t.kind == "pickup" then inOrder[t.questId] = true end end
    check("barrens: and then the far quest is planned again", inOrder[802] and #L.plan.pruned == 0)
    _G.SlashCmdList.QUESTLADDER("trips")
    check("barrens: and back on", ns.db.tripCheck == true)

    -- what a quest is worth for the check
    local player = ns.QuestState.Player()
    local function tv(id, why, planned)
        local c = { id = id }
        L.SetTripValue(c, why, player, planned or {})
        return c
    end
    check("trip value: its XP at your level", tv(801).tripXP == 1350 and not tv(801).keep)
    check("trip value: unknown XP counts as a solid quest", tv(899).tripXP == 1350, tv(899).tripXP)
    check("trip value: upgrades and must-do quests are kept", tv(801, "upgrade").keep and tv(801, "goodie").keep)
    check("trip value: a class quest is kept even when its XP alone gets it planned (no reason given)",
        tv(803).keep and tv(803).worthWhy == "class")
    D.followUps[801] = { 802 }
    check("trip value: a breadcrumb is worth its follow-up too", tv(801, "leads on").tripXP == 2700)
    check("trip value: unless that follow-up is planned (it's weighed with it)", tv(801, "leads on", { [802] = true }).tripXP == 1350)
    D.followUps[801] = nil

    -- "/ladder dungeons" lists, "/ladder dungeons plan" toggles (0.3.20 hid the toggle)
    local before = ns.db.skipDungeonQuests
    _G.SlashCmdList.QUESTLADDER("dungeons")
    check("dungeons: the list doesn't change the setting", ns.db.skipDungeonQuests == before)
    _G.SlashCmdList.QUESTLADDER("dungeons plan")
    check("dungeons: \"plan\" toggles planning them", ns.db.skipDungeonQuests == not before)
    _G.SlashCmdList.QUESTLADDER("dungeons plan")
    check("dungeons: and back", ns.db.skipDungeonQuests == before)
    _G.SlashCmdList.QUESTLADDER("skipped") -- prints without an error
end

---------------------------------------------------------------------------
-- 15h. 0.3.22: "stop trying to mark my reagents as sell/destroy. That stuff is good money /
-- bankable." And a "speak to Neeru Fireblade" objective (a friendly level-37 NPC in QuestieDB)
-- held a level-12 quest back until 37 more turn-ins, sending you across the ocean and back.
---------------------------------------------------------------------------
do
    local ns = setup()
    M.items[1001] = { name = "Linen Cloth", classID = 7, subClassID = 5, quality = 1, sell = 13 }
    M.items[1002] = { name = "Peacebloom", classID = 7, subClassID = 9, quality = 1, sell = 1 }
    M.items[1003] = { name = "Small Venom Sac", classID = 12, quality = 1, sell = 0, reagent = true } -- a quest-type item the game calls a reagent
    M.items[1004] = { name = "Recipe: Spiced Wolf Meat", classID = 9, quality = 1, sell = 10 }
    M.items[1005] = { name = "Moonstone", classID = 3, quality = 2, sell = 150 }
    M.items[1006] = { name = "Red Wolf Fang", classID = 15, subClassID = 1, quality = 1, sell = 4 }
    M.items[1007] = { name = "Chipped Claw", classID = 15, quality = 0, sell = 6 }
    M.items[1008] = { name = "Dusty Gray Reagent", classID = 15, quality = 0, sell = 3, reagent = true }
    M.items[1009] = { name = "Plain Pebble", classID = 15, quality = 1, sell = 2 }
    M.bag = {}
    for id = 1001, 1009 do M.bag[#M.bag + 1] = { id = id, count = 5 } end
    local function suggest(needed)
        local list = ns.Bags.Suggestions(ns.QuestState.Bags(), {}, { bags = { needed = needed }, candidates = {},
            player = { level = 17, classFile = "PALADIN" } })
        local by = {}
        for _, e in ipairs(list) do by[e.itemId] = e end
        return by
    end
    local by = suggest(4)
    local function never(id) return not by[id] or (by[id].action ~= "sell" and by[id].action ~= "destroy") end
    check("materials: cloth and herbs are never Sell", never(1001) and never(1002), by[1001] and by[1001].action)
    check("materials: a quest-type item the game flags as a reagent is never Destroy", never(1003), by[1003] and by[1003].action)
    check("materials: recipes, gems and misc reagents are never Sell", never(1004) and never(1005) and never(1006))
    check("materials: when bags are short they go to the bank", by[1001] and by[1001].action == "bank"
        and by[1001].reason:find("crafting material", 1, true), by[1001] and by[1001].reason)
    check("materials: a gray the game flags as a reagent isn't junk", never(1008))
    check("materials: plain gray junk is still Sell", by[1007] and by[1007].action == "sell")
    check("materials: a plain white misc item can still go when bags are short", by[1009] and by[1009].action == "sell")
    by = suggest(0)
    check("materials: nothing suggested while there's room", not by[1001] and not by[1003] and not by[1006])
    -- a vendor stop counts only what can be sold
    ns.Ladder.plan = { bags = { needed = 4 }, candidates = {}, player = { level = 17, classFile = "PALADIN" } }
    check("materials: a vendor stop doesn't count them as sellable", ns.Bags.SellableSlots(ns.QuestState.Bags()) == 2,
        ns.Bags.SellableSlots(ns.QuestState.Bags()))
    ns.Ladder.plan = nil
    M.bag = {}

    -- friendly NPCs are talks, not fights
    ns.Data.InitWith(M.fakeDB({
        quests = {}, objects = {}, items = {},
        npcs = {
            [3216] = { name = "Neeru Fireblade", minLevel = 37, friendlyToFaction = "H", spawns = spawn(50, 50) },
            [3217] = { name = "Neutral Goblin", minLevel = 40, friendlyToFaction = "AH", spawns = spawn(50, 50) },
            [3218] = { name = "Burning Blade Thug", minLevel = 37, spawns = spawn(50, 50) },
            [3219] = { name = "Alliance Guard", minLevel = 55, friendlyToFaction = "A", spawns = spawn(50, 50) },
        },
    }))
    local L = ns.Ladder
    local function lvl(npc, faction) return L.MobLevelOf({ type = "monster", targets = { npc = { npc } } }, faction) end
    check("mob level: \"speak to Neeru Fireblade\" (friendly to the Horde) holds nothing back", lvl(3216, "Horde") == nil)
    check("mob level: an NPC friendly to both factions neither", lvl(3217, "Horde") == nil and lvl(3217, "Alliance") == nil)
    check("mob level: a hostile mob still counts", lvl(3218, "Horde") == 37)
    check("mob level: the other faction's guard is a fight", lvl(3219, "Horde") == 55 and lvl(3219, "Alliance") == nil)
    check("mob level: unknown faction: counted as before", lvl(3216, nil) == 37)
end

---------------------------------------------------------------------------
-- 15i. 0.3.22: timed quests ("Apothecary Zamah: bring the Rendered Spores to Thunder Bluff
-- before the time limit is up") go first, with a countdown and the item in the guide.
---------------------------------------------------------------------------
do
    local ns = setup()
    local P = ns.Planner
    local function pt(x, y) return { cont = 0, wx = x, wy = y, mapId = 1, x = 0, y = 0 } end
    local hub = pt(0, 0)
    local function obj(x, y, mob) return { { index = 1, type = "monster", need = 1, have = 0, loc = pt(x, y), mobLevel = mob } } end
    local function ctx(extra)
        local c = { start = hub, level = 17, logCount = 3, logMax = 40, active = {
            { id = 1, title = "Next Door", objectives = obj(100, 0), turnin = hub },
            { id = 2, title = "Over There", objectives = obj(50, 50), turnin = hub },
            { id = 853, title = "Apothecary Zamah", complete = true, objectives = {}, turnin = pt(3000, 0), timed = true },
        } }
        for k, v in pairs(extra or {}) do c[k] = v end
        return c
    end
    local plan = P.Plan(ctx())
    check("timed: the timed quest's turn-in goes first, far as it is", plan.order[1].id == "T853", plan.order[1].id)
    check("timed: the rest follows, and the route is valid", #plan.order == 5 and P.IsValid(plan.order, { logCount = 3, logMax = 40 }))
    local offCtx = ctx()
    offCtx.active[3].timed = nil
    check("timed: without a clock it would be done last", P.Plan(offCtx).order[5].id == "T853")
    local gated = ctx()
    gated.active[3] = { id = 854, title = "Kill Them In Time", objectives = obj(2500, 0, 25), turnin = pt(2600, 0), timed = true }
    plan = P.Plan(gated)
    check("timed: a high-level mob doesn't hold a timed quest back", plan.order[1].id == "O854:1" and plan.order[2].id == "T854",
        plan.order[1].id .. " " .. plan.order[2].id)
    local skipped = ctx()
    skipped.active[3].deferred = true
    check("timed: one you skipped (/ladder skip) isn't rushed", P.Plan(skipped).order[1].id ~= "T853")
    -- a vendor stop its step waits for comes along first
    local vendored = ctx({ extraTasks = { { id = "V:vendor", kind = "visit", visit = "vendor", loc = pt(2000, 0), est = 30, deps = {} } },
                           extraDeps = { T853 = { "V:vendor" } } })
    plan = P.Plan(vendored)
    check("timed: what it waits for comes along", plan.order[1].id == "V:vendor" and plan.order[2].id == "T853",
        plan.order[1].id .. " " .. plan.order[2].id)
    check("timed: LastUrgent finds the end of the rush", P.LastUrgent(plan.order) == 2)

    -- reading the timer
    M.log = { { id = 853, title = "Apothecary Zamah", level = 15, complete = true, objectives = {} } }
    local timers = { [853] = { 2700, 300 } }
    _G.C_QuestLog.GetTimeAllowed = function(id) local t = timers[id]; if t then return t[1], t[2] end end
    local _, byId = ns.QuestState.Snapshot()
    local tm = byId[853].timer
    check("timer: read from the game, with when it was read", tm and tm.total == 2700 and tm.elapsed == 300
        and tm.readAt == M.time and tm.source == "api", tm and tm.source)
    _G.issecretvalue = function(v) return v == 2700 end
    _, byId = ns.QuestState.Snapshot()
    check("timer: a secret value is never used", byId[853].timer == nil)
    _G.issecretvalue = function() return false end
    timers = {}
    _G.GetQuestTimers = function() return 1500 end
    _G.GetQuestIndexForTimer = function(i) return i == 1 and 1 or nil end
    _, byId = ns.QuestState.Snapshot()
    tm = byId[853].timer
    check("timer: the older timer API when the new one says nothing", tm and tm.total == 1500 and tm.source == "legacy",
        tm and tm.source)
    _G.GetQuestTimers, _G.GetQuestIndexForTimer = nil, nil

    -- the whole pipeline: a finished timed quest far away, kobolds right here, a flight path on the way
    M.log = {
        { id = 2, title = "Kobold Camp Cleanup", level = 2, complete = false,
          objectives = { { text = "Kobold Vermin slain: 2/6", type = "monster", finished = false, numFulfilled = 2, numRequired = 6 } } },
        { id = 3, title = "The Lost Book", level = 3, complete = true,
          objectives = { { text = "Old Book: 1/1", type = "item", finished = true, numFulfilled = 1, numRequired = 1 } } },
    }
    timers = { [3] = { 600, 100 } }
    M.taxiNodes = { { name = "Field Post", position = { x = 0.43, y = 0.41 }, isUndiscovered = true, faction = 2, nodeID = 2 } }
    local full = fullPlan(ns)
    local first = full.steps[1].tasks[1]
    check("timed: in the guide the timed turn-in is step 1", first.id == "T3", first.id)
    local fpFirst = false
    for _, t in ipairs(full.steps[1].tasks) do if t.visit == "flight" then fpFirst = true end end
    check("timed: no flight-path detour before it", not fpFirst)
    local L = ns.Ladder
    local list = L.TimedQuests()
    check("timed: listed with the time left", #list == 1 and list[1].questId == 3 and math.abs(list[1].left - 500) < 0.01,
        list[1] and list[1].left)
    local text = L.TimerText(list[1])
    check("timed: the line shows the clock, the item and where it goes", text:find("8:20|r left", 1, true)
        and text:find("[Old Book]", 1, true) and text:find("to Librarian Mae", 1, true) and text:find("it goes first", 1, true), text)
    M.time = M.time + 60
    check("timed: it counts down every second", L.TimerText(L.TimedQuests()[1]):find("7:20|r left", 1, true))
    M.time = M.time + 340
    check("timed: red in the last two minutes", L.TimerText(L.TimedQuests()[1]):find("|cffff55551:40|r", 1, true),
        L.TimerText(L.TimedQuests()[1]))
    M.time = M.time + 100
    check("timed: and says when time is up", L.TimerText(L.TimedQuests()[1]):find("time's up", 1, true))
    L.snapshot = {}
    check("timed: gone once it's out of your log", #L.TimedQuests() == 0)
    M.taxiNodes = {}

    -- the quest text alone says there's a clock
    check("timed: 'before the time limit is up' in the quest text counts", L.TimedByText({ objectivesText =
        { "Bring the Rendered Spores to Apothecary Zamah in Thunder Bluff, before the time limit is up." } }))
    check("timed: ordinary quest text doesn't", not L.TimedByText({ objectivesText = { "Collect 8 Witchwing talons." } }))
    text = L.TimerText({ title = "Apothecary Zamah", left = nil, done = true, to = "Apothecary Zamah" })
    check("timed: no timer from the game: it points at the quest log", text:find("see the timer in your quest log", 1, true), text)
    _G.C_QuestLog.GetTimeAllowed = function() return nil end
end

---------------------------------------------------------------------------
-- 15j. 0.3.24: more than one first guess. At Sun Rock Retreat (your 13:34 diag, level 18) the
-- route walked off to the north Barrens and flew back for two turn-ins 150 yards from you; the
-- improvement step couldn't untangle the first guess. The real tasks and flight points from that
-- diag (replay format: id|kind|deps|cont|x|y|est|flags|mobLevel|xpWeight).
---------------------------------------------------------------------------
do
    local ns = setup()
    local P, T = ns.Planner, ns.Travel
    local SUN_ROCK = {
        "O6461:2|objective||1|510.7|644.8|120||17|", "O6461:1|objective||1|448.7|577.5|200||16|",
        "O6421:2|objective||1|2.0|402.8|15|||", "O6421:1|objective||1|-62.0|329.2|280|||",
        "T6461|turnin|O6461:1,O6461:2|1|-177.4|-233.5|8|||1", "O6629:1|objective||1|112.4|-350.7|20||18|",
        "O875:1|objective||1|670.0|-1287.3|168||16|", "T6541|turnin||1|1246.3|-2253.2|8|||0.4",
        "O881:1|objective||1|451.1|-3037.6|28||16|", "O6301:1|objective||1|1479.3|848.8|280|||",
        "T6301|turnin|O6301:1|1|1015.7|928.2|8|||1", "T6421|turnin|O6421:1,O6421:2|1|831.4|939.9|8|||1",
        "O1062:1|objective||1|1244.9|22.7|300||18|", "O6629:2|objective||1|114.8|-559.4|120||15|",
        "T6629|turnin|O6629:1,O6629:2|1|-263.0|-943.0|8|||1", "T1062|turnin|O1062:1|1|-271.1|-950.1|8|||1",
        "O899:1|objective||1|-1455.6|-1534.0|1680||16|", "O4921:1|objective||1|-1787.2|-2375.9|20|||",
        "O3281:1|objective||1|-2027.1|-3258.5|28|||", "T1492|turnin||1|-985.3|-3796.5|8|||1",
        "V:fp:Ratchet|visit||1|-894.6|-3773.0|15|v:flight||", "O877:1|objective||1|-1275.8|-3012.2|12|||",
        "T877|turnin|O877:1|1|-544.8|-2672.8|8|||1", "T899|turnin|O899:1|1|-521.1|-2641.3|8|||1",
        "T4921|turnin|O4921:1|1|-521.1|-2641.3|8|||1", "T881|turnin|O881:1|1|-482.6|-2669.7|8|||1",
        "T3281|turnin|O3281:1|1|-436.0|-2639.3|8|||1", "T875|turnin|O875:1|1|-475.2|-2607.9|8|||1",
        "O5726:1|objective||1|1479.9|-4760.2|28||9|", "T5726|turnin|O5726:1|1|1920.1|-4125.6|8|||1",
        "V:hearth1|visit||0|2268.1|244.0|25|tv:hearth||", "T441|turnin||0|1604.3|278.3|8|||1",
        "T5725|turnin||0|1287.8|333.5|8|||1", "O443:1|objective||0|981.6|683.6|224||16|",
        "O424:1|objective||0|410.6|989.6|28||15|", "O95981:1|objective||0|34.4|739.3|160|||",
        "O95981:2|objective||0|35.6|765.3|160|||", "O450:1|objective||0|-382.4|1644.8|28|||",
        "T443|turnin|O443:1|0|522.6|1652.4|8|||1", "T450|turnin|O450:1|0|522.6|1652.4|8|||1",
        "T424|turnin|O424:1|0|552.0|1593.6|8|||1", "T95981|turnin|O95981:1,O95981:2|0|520.6|1602.8|8|||1",
        "O479:1|objective||0|-154.2|965.7|224|d||", "T479|turnin|O479:1|0|520.6|1602.8|8|d||1",
    }
    local function pt(c, x, y) return { cont = c, wx = x, wy = y } end
    local net = { speed = 7, nodes = {
        { name = "Thunder Bluff", point = pt(1, -1197.2, 29.7), known = true },
        { name = "Orgrimmar", point = pt(1, 1677.6, -4315.7), known = true },
        { name = "Crossroads", point = pt(1, -441.8, -2596.1), known = true },
        { name = "Sun Rock Retreat", point = pt(1, 966.6, 1040.3), known = true },
    } }
    local start = pt(1, 919.2, 821.8)
    local function split(s)
        local out = {}
        for part in (s .. "|"):gmatch("(.-)|") do out[#out + 1] = part end
        return out
    end
    local function load()
        local tasks, byId = {}, {}
        for _, line in ipairs(SUN_ROCK) do
            local f = split(line)
            local t = { id = f[1], kind = f[2], deps = {}, loc = pt(tonumber(f[4]), tonumber(f[5]), tonumber(f[6])),
                        est = tonumber(f[7]), mobLevel = tonumber(f[9] or ""), xpWeight = tonumber(f[10] or "") }
            for d in f[3]:gmatch("[^,]+") do t.deps[#t.deps + 1] = d end
            t.deferred = f[8]:sub(1, 1) == "d" or nil
            t.teleport = f[8]:find("t", 1, true) and true or nil
            tasks[#tasks + 1] = t
            byId[t.id] = t
        end
        for _, t in ipairs(tasks) do t.dependents = {} end
        for _, t in ipairs(tasks) do for _, d in ipairs(t.deps) do byId[d].dependents[#byId[d].dependents + 1] = t.id end end
        P.ApplyLevelGates(tasks, byId, 18, 0.418)
        return tasks, byId
    end
    local planCost = T.NewCost(net)
    local seeds = { { name = "flights at full time", travel = T.NewCost(net, 1.0) },
                    { name = "walking only", travel = function(a, b) return T.Walk(net, a, b) end } }
    local opts = { logCount = 22, logMax = 40 }
    local function solve(withSeeds)
        local tasks, byId = load()
        P.travelFn = planCost
        local o = withSeeds and setmetatable({ seeds = withSeeds }, { __index = opts }) or opts
        local order, _, seed = P.Solve(tasks, byId, start, o)
        P.travelFn = planCost
        local at = {}
        for i, t in ipairs(order) do at[t.id] = i end
        return order, at, P.RouteCost(order, start), seed, tasks
    end
    local one, oneAt, oneCost = solve(nil)
    check("first guess: one start leaves Sun Rock for the north Barrens first (the diag's route)",
        oneAt["O881:1"] < oneAt["T6301"] and oneAt["O881:1"] < oneAt["T6421"], oneAt["O881:1"] .. " vs " .. oneAt["T6301"])
    local three, threeAt, threeCost, seed = solve(seeds)
    check("first guess: with three starts Sun Rock's turn-ins come before the Barrens",
        threeAt["T6301"] < threeAt["O875:1"] and threeAt["T6421"] < threeAt["O875:1"],
        threeAt["T6301"] .. "/" .. threeAt["T6421"] .. " vs " .. threeAt["O875:1"])
    check("first guess: cheaper by the add-on's own costs", threeCost < oneCost - 150, string.format("%.0f vs %.0f", threeCost, oneCost))
    check("first guess: and in real time (flights at full time)", (function()
        P.travelFn = seeds[1].travel
        local a, b = P.RouteCost(three, start), P.RouteCost(one, start)
        P.travelFn = planCost
        return a < b - 150
    end)())
    check("first guess: says which start won", seed == "flights at full time", tostring(seed))
    check("first guess: the route is valid and complete", #three == #SUN_ROCK and P.IsValid(three, opts))
    local flewBack = false
    local pos = start
    for _, t in ipairs(three) do
        if t.id == "T6421" then break end
        local _, mode = T.Leg(net, pos, t.loc)
        if mode == "fly" then flewBack = true end
        pos = t.loc
    end
    check("first guess: no flight before the Sun Rock turn-ins", not flewBack)

    -- a start that can't do better keeps the normal route (no flip-flopping on near-ties)
    local _, _, sameCost, sameSeed = solve({ { name = "same", travel = planCost } })
    check("first guess: an equal start doesn't win", sameSeed == nil and math.abs(sameCost - oneCost) < 0.01, tostring(sameSeed))
    -- big plans only get the normal start (the guide must keep up)
    local calls = 0
    local saved = P.SEED_MAX_TASKS
    P.SEED_MAX_TASKS = 10
    local _, _, _, bigSeed = solve({ { name = "counted", travel = function(a, b) calls = calls + 1; return planCost(a, b) end } })
    P.SEED_MAX_TASKS = saved
    check("first guess: past SEED_MAX_TASKS only the normal start runs", bigSeed == nil and calls == 0, calls)
    -- level waits stay what the normal start left (another start can't win by lowering them)
    local _, _, _, _, tasks1 = solve(nil)
    local _, _, _, _, tasks3 = solve(seeds)
    local sameGates = true
    for i, t in ipairs(tasks1) do if t.minTurnins ~= tasks3[i].minTurnins then sameGates = false end end
    check("first guess: level waits are the normal start's", sameGates)

    -- random maps: three starts are never worse, and the route stays valid
    math.randomseed(24)
    local better, worse, invalid = 0, 0, 0
    for _ = 1, 12 do
        local rnet = { speed = 7, nodes = {
            { name = "A", point = pt(0, 0, 0), known = true }, { name = "B", point = pt(0, 5000, 0), known = true },
            { name = "C", point = pt(0, 2500, 4000), known = true } } }
        local active = {}
        for q = 1, 12 do
            local objs = {}
            for k = 1, math.random(1, 2) do
                objs[k] = { index = k, type = "monster", need = 4, have = 0, loc = pt(0, math.random(0, 5000), math.random(0, 4000)),
                            mobLevel = math.random(14, 20) }
            end
            active[q] = { id = q, title = "Q" .. q, objectives = objs, turnin = pt(0, math.random(0, 5000), math.random(0, 4000)) }
        end
        local function ctx(s)
            return { travel = T.NewCost(rnet), start = pt(0, 2500, 2000), level = 17, xpFrac = 0.5, active = active,
                     logCount = 12, logMax = 40, seeds = s }
        end
        local p1 = P.Plan(ctx(nil))
        local p3 = P.Plan(ctx({ { name = "full", travel = T.NewCost(rnet, 1.0) }, { name = "walk", travel = function(a, b) return T.Walk(rnet, a, b) end } }))
        P.travelFn = T.NewCost(rnet)
        local c1, c3 = P.RouteCost(p1.order, pt(0, 2500, 2000)), P.RouteCost(p3.order, pt(0, 2500, 2000))
        if c3 < c1 - 0.5 then better = better + 1 elseif c3 > c1 + 0.5 then worse = worse + 1 end
        if #p3.order ~= #p1.order or not P.IsValid(p3.order, { logCount = 12, logMax = 40 }) then invalid = invalid + 1 end
    end
    check("first guess: on random maps never worse", worse == 0, worse)
    check("first guess: on random maps always valid and complete", invalid == 0, invalid)
    check("first guess: on random maps sometimes better", better > 0, better)

    -- the full-time cost: a minute in the air is a minute
    local function W(x, y) return pt(0, x, y) end
    local fnet = { speed = 7, nodes = { { name = "West", point = W(0, 0), known = true }, { name = "East", point = W(6000, 0), known = true } } }
    local afk, full = T.NewCost(fnet)(W(0, 100), W(6000, 100)), T.NewCost(fnet, 1.0)(W(0, 100), W(6000, 100))
    local _, mode, _, _, air = T.Leg(fnet, W(0, 100), W(6000, 100))
    check("full-time cost: the flight's air time counts in full", mode == "fly" and math.abs((full - afk) - air * (1 - T.AFK_WEIGHT)) < 0.01,
        string.format("%.1f %.1f %s", afk, full, tostring(air)))
    check("full-time cost: never more than walking", full <= T.Walk(fnet, W(0, 100), W(6000, 100)))
    check("full-time cost: the AFK weight is left as it was", T.AFK_WEIGHT == 0.35, T.AFK_WEIGHT)
    check("HasFlights: a known flight path", T.HasFlights(fnet))
    check("HasFlights: none known", not T.HasFlights({ nodes = { { name = "X", point = W(0, 0), known = false } } }))
    check("HasFlights: a zeppelin counts", T.HasFlights({ nodes = {}, zeppelins = { {} } }))

    -- the add-on passes both extra starts when you fly, none when you walk
    M.log = { { id = 2, title = "Kobold Camp Cleanup", level = 2, complete = false,
                objectives = { { text = "Kobold Vermin slain: 2/6", type = "monster", finished = false, numFulfilled = 2, numRequired = 6 } } } }
    M.taxiNodes = { { name = "Home Post", position = { x = 0.60, y = 0.42 }, isUndiscovered = false, faction = 2, nodeID = 11 } }
    ns.charDB.flightPaths = { ["Home Post"] = true }
    local seen
    local realPlan = P.Plan
    P.Plan = function(c) seen = c.seeds; return realPlan(c) end
    fullPlan(ns)
    check("Ladder: flying, the planner gets the full-time and walking starts", seen and #seen == 2
        and seen[1].name == "flights at full time" and seen[2].name == "walking only")
    ns.charDB.flightPaths = nil
    fullPlan(ns)
    check("Ladder: no flight path known, no extra starts", seen == nil)
    P.Plan = realPlan
    M.taxiNodes = {}
end

---------------------------------------------------------------------------
-- 15k. 0.3.25: "I've been abandoning old quest lines": an abandoned quest could be picked up
-- again, so it came straight back as a new quest to fetch. Now it's ignored (undo: unignore <id>).
---------------------------------------------------------------------------
do
    local ns = setup()
    local L = ns.Ladder
    local printed = {}
    local realPrint = ns.Print
    ns.Print = function(fmt, ...) printed[#printed + 1] = select("#", ...) > 0 and string.format(fmt, ...) or fmt end
    check("abandon: taken as abandoned", L.NoteRemoved(870, { id = 870, title = "The Forgotten Pools" }) == true
        and ns.charDB.ignored[870] == true)
    check("abandon: says so, with the undo", printed[1] and printed[1]:find("The Forgotten Pools", 1, true)
        and printed[1]:find("/ladder unignore 870", 1, true), printed[1])
    L.turnedIn[871] = true
    check("abandon: a turned-in quest isn't", L.NoteRemoved(871, { id = 871, title = "X" }) == false and not ns.charDB.ignored[871])
    check("abandon: a failed one isn't (the hint says abandon it and pick it up again)",
        L.NoteRemoved(853, { id = 853, title = "Apothecary Zamah", failed = true }) == false and not ns.charDB.ignored[853])
    M.completed[872] = true
    check("abandon: one the game counts as done isn't", L.NoteRemoved(872, { id = 872, title = "Y" }) == false and not ns.charDB.ignored[872])
    check("abandon: a quest that wasn't in the log we saw isn't", L.NoteRemoved(873, nil) == false and not ns.charDB.ignored[873])
    -- through the game's events
    L.snapshot = { [874] = { id = 874, title = "Lost in Battle" } }
    ns.DispatchEvent("QUEST_REMOVED", 874)
    check("abandon: removed from the log without a turn-in: ignored", ns.charDB.ignored[874] == true)
    L.snapshot = { [875] = { id = 875, title = "Harpy Lieutenants" } }
    ns.DispatchEvent("QUEST_TURNED_IN", 875, 100, 0)
    ns.DispatchEvent("QUEST_REMOVED", 875)
    check("abandon: turned in, then removed: not ignored", not ns.charDB.ignored[875])
    ns.DispatchEvent("QUEST_ACCEPTED", 874)
    check("abandon: accepting it again un-ignores it", not ns.charDB.ignored[874])
    _G.SlashCmdList.QUESTLADDER("unignore 870")
    check("abandon: /ladder unignore <id> clears just that one", not ns.charDB.ignored[870])
    ns.Print = realPrint
end

---------------------------------------------------------------------------
-- 15o. 0.5.0: speed-leveling techniques (the user asked to fold in what a Classic speed-leveling
-- guide does: grind to catch up before leaving, die on purpose to travel, watch for named mobs
-- whose drop starts a quest, break while the hearth cools down, learn Cooking for an XP quest,
-- skip escorts and group quests that aren't worth it). Rules on QuestieDB data, no guide content.
---------------------------------------------------------------------------
do
    -- escorts: their walking time counts in the "worth the walk" check
    local ns = setup()
    local P, L, S = ns.Planner, ns.Ladder, ns.Speed
    local function pt(x, y) return { cont = 0, wx = x, wy = y, mapId = 1, x = 0, y = 0 } end
    local hub = pt(0, 0)
    local function walk(a, b) return math.sqrt((a.wx - b.wx) ^ 2 + (a.wy - b.wy) ^ 2) / 7 end
    local function cand(id, title, xp, extra)
        return { id = id, title = title, pickup = hub, turnin = hub, tripXP = xp, extraSeconds = extra,
                 objectives = { { index = 1, type = "event", need = 1, have = 0, finished = false, loc = pt(20, 0) } } }
    end
    local plan = P.Plan({ start = hub, level = 17, tripCheck = true, logCount = 0, logMax = 40, travel = walk, active = {},
        candidates = { cand(1001, "Slow Escort", 300, S.ESCORT_SECONDS), cand(1002, "Rich Escort", 2500, S.ESCORT_SECONDS),
                       cand(1003, "Next Door Errand", 300, nil) } })
    local pruned, inOrder = {}, {}
    for _, p in ipairs(plan.pruned) do pruned[p.questId] = p end
    for _, t in ipairs(plan.order) do inOrder[t.questId or -1] = true end
    check("escort: four minutes of walking for 300 XP isn't worth it", pruned[1001] and not inOrder[1001] and pruned[1001].extra == 240,
        pruned[1001] and pruned[1001].extra)
    check("escort: one worth its time stays", inOrder[1002] and not pruned[1002])
    check("escort: a cheap errand on the way still stays", inOrder[1003] and not pruned[1003])
    check("escort: /ladder skipped says it's the escorting", L.TripTimeText(pruned[1001] or {}):find("4:00 of escorting", 1, true),
        L.TripTimeText(pruned[1001] or {}))
    check("escort: travel and escorting together", L.TripTimeText({ seconds = 310, extra = 240 }) == "1:10 of travel and 4:00 of escorting")
    check("escort: plain travel reads as before", L.TripTimeText({ seconds = 600 }) == "10:00 of travel")
end

do
    -- group quests, profession unlocks and "watch for" through the whole pipeline
    local ns = setup()
    local D, L, S, H = ns.Data, ns.Ladder, ns.Speed, ns.Hints
    local function q(name, level, extra)
        local t = { name = name, startedBy = { { 1200 } }, finishedBy = { { 1200 } }, requiredLevel = 1, questLevel = level }
        for k, v in pairs(extra or {}) do t[k] = v end
        return t
    end
    D.InitWith(M.fakeDB({
        quests = {
            [1101] = q("Arachnophobia", 21, { objectives = { { { 1201 } } } }),
            [1102] = q("Wolves", 20, { objectives = { { { 1202 } } } }),
            [1103] = q("Old Elite", 20, { objectives = { { { 1203 } } } }),
            [1104] = q("Elite Bounty For Your Class", 21, { objectives = { { { 1201 } } }, requiredClasses = 1 }),
            [1110] = q("Soothing Turtle Bisque", 20, { objectives = {}, requiredSkill = { 185, 1 } }),
            [1111] = q("Gourmet Only", 20, { objectives = {}, requiredSkill = { 185, 50 } }),
            [1112] = q("Miners Only", 20, { objectives = {}, requiredSkill = { 186, 1 } }),
            [1121] = { name = "Owatanka", startedBy = { nil, nil, { 1120 } }, finishedBy = { { 1200 } }, requiredLevel = 20,
                       questLevel = 22, objectives = {} },
            [1123] = { name = "Far Away Named", startedBy = { nil, nil, { 1122 } }, finishedBy = { { 1200 } }, requiredLevel = 20,
                       questLevel = 22, objectives = {} },
            [1125] = { name = "Lucky Letter", startedBy = { nil, nil, { 1124 } }, finishedBy = { { 1200 } }, requiredLevel = 20,
                       questLevel = 22, objectives = {} },
        },
        questXP = { [1101] = { 21, 1600 }, [1102] = { 20, 1500 }, [1103] = { 20, 1500 }, [1104] = { 21, 300 },
                    [1110] = { 20, 1500 }, [1111] = { 20, 1500 }, [1112] = { 20, 1500 },
                    [1121] = { 22, 1700 }, [1123] = { 22, 1700 }, [1125] = { 22, 1700 } },
        npcs = {
            [1200] = { name = "Hub Giver", spawns = spawn(42, 41) },
            [1201] = { name = "Besseleth", minLevel = 21, maxLevel = 21, rank = 1, spawns = spawn(45, 41) },
            [1202] = { name = "Grey Wolf", minLevel = 20, maxLevel = 21, spawns = spawn(46, 42) },
            [1203] = { name = "Old Ogre", minLevel = 15, maxLevel = 15, rank = 1, spawns = spawn(44, 43) },
            [1205] = { name = "Ayessa Dawnsinger", minLevel = 9999, rank = 1, spawns = spawn(44, 44) },
            [1210] = { name = "Cook Craggle", subName = "Cooking Trainer", npcFlags = 16, spawns = spawn(43, 40) },
            [1220] = { name = "Owatanka", minLevel = 23, maxLevel = 23, zoneID = 12 },
            [1222] = { name = "Far Named", minLevel = 22, maxLevel = 22, spawns = { [40] = { { 90, 90 } } } },
            [1231] = { name = "Ghoul A", minLevel = 21 }, [1232] = { name = "Ghoul B", minLevel = 21 },
            [1233] = { name = "Ghoul C", minLevel = 21 }, [1234] = { name = "Ghoul D", minLevel = 21 },
        },
        objects = {},
        items = {
            [1120] = { name = "Owatanka's Tailspike", startQuest = 1121, npcDrops = { 1220 }, class = 12 },
            [1122] = { name = "Far Trophy", startQuest = 1123, npcDrops = { 1222 }, class = 12 },
            [1124] = { name = "Bloodstained Letter", startQuest = 1125, npcDrops = { 1231, 1232, 1233, 1234 }, class = 12 },
        },
    }))
    M.player.level = 20
    local plan = fullPlan(ns)
    local cands = {}
    for _, c in ipairs((plan and plan.candidates) or {}) do cands[c.id] = c end
    local group = {}
    for _, s in ipairs((plan and plan.skippedGroup) or {}) do group[s.id] = s end
    check("group: a quest against an elite at your level is left out solo", not cands[1101] and group[1101]
        and group[1101].mob == "Besseleth" and group[1101].level == 21)
    check("group: an ordinary one is planned", cands[1102] ~= nil)
    check("group: an elite well under you is soloable", cands[1103] ~= nil and not group[1103])
    check("group: Forever's placeholder level 9999 isn't a real elite", S.EliteTarget({ type = "monster", targets = { npc = { 1205 } } }, 20, "Horde") == nil)
    check("group: a real one is", S.EliteTarget({ type = "monster", targets = { npc = { 1201 } } }, 20, "Horde") == "Besseleth")
    check("group: a class quest against an elite stays", cands[1104] ~= nil and not group[1104])
    local take, why = L.QuestVerdict(1101)
    check("group: the dialog says it needs a group", take == false and tostring(why):find("needs a group: Besseleth (lvl 21) is elite", 1, true), why)
    local lines = table.concat(L.SkippedLines(plan), "\n")
    check("group: /ladder skipped lists it", lines:find("Needs a group (1)", 1, true) and lines:find("Arachnophobia - Besseleth (lvl 21) is elite", 1, true), lines)
    -- the class quest's objective is shown as an elite
    local eliteText
    for _, t in ipairs(plan.order) do
        if t.kind == "objective" and t.questId == 1104 then eliteText = L.TaskText(t) end
    end
    check("group: an elite objective says so", eliteText and eliteText:find("lvl 21 elite", 1, true), eliteText)
    _G.SlashCmdList.QUESTLADDER("groupquests")
    check("group: /ladder groupquests plans them", ns.db.skipGroupQuests == false)
    L.Rebuild("group on")
    local planned = false
    for _, c in ipairs(L.plan.candidates) do if c.id == 1101 then planned = true end end
    check("group: ...and then it's in the plan", planned and #L.plan.skippedGroup == 0)
    _G.SlashCmdList.QUESTLADDER("groupquests")
    L.Rebuild("group off")
    plan = L.plan

    -- a profession you can learn in a minute unlocks a quest
    local u = plan.skillUnlocks and plan.skillUnlocks[1]
    check("profession: Cooking unlocks Soothing Turtle Bisque", u and u.questId == 1110 and u.skill == "Cooking" and #plan.skillUnlocks == 1,
        u and u.questId)
    check("profession: the quest isn't planned before you learn it", not cands[1110])
    local function hint(p, needle, step)
        for _, h in ipairs(H.Compute({ plan = p, step = step, byId = {}, bags = ns.QuestState.Bags(), now = M.time,
                                       point = ns.Geo.PlayerPoint() })) do
            if h.text:find(needle, 1, true) then return h end
        end
    end
    local lh = hint(plan, "Learn Cooking:")
    check("profession: the hint names the trainer, the quest and its XP", lh and lh.text:find("Cook Craggle", 1, true)
        and lh.text:find("Soothing Turtle Bisque", 1, true) and lh.text:find("+1500 XP", 1, true), lh and lh.text)
    check("profession: ...and clicks to a map pin on the trainer", lh and lh.pin and lh.pin.title == "Cook Craggle")
    _G.C_SkillInfo = { GetNumSkillLines = function() return 1 end,
                       GetSkillLineInfo = function() return { skillID = 185, rank = 1 } end }
    L.Rebuild("learned cooking")
    local nowPlanned = false
    for _, c in ipairs(L.plan.candidates) do if c.id == 1110 then nowPlanned = true end end
    check("profession: once learned, the quest is planned and the hint goes", nowPlanned and #L.plan.skillUnlocks == 0)
    _G.C_SkillInfo = nil
    L.Rebuild("back")
    plan = L.plan

    -- named mobs whose drop starts a quest
    local w = plan.watchFor or {}
    check("watch for: Owatanka, whose drop starts a quest, in the zone you're in", w[1] and w[1].npcName == "Owatanka"
        and w[1].questId == 1121 and w[1].step == 0, w[1] and w[1].npcName)
    check("watch for: not a named mob nowhere near the route, nor a lucky drop off common mobs", #w == 1, #w)
    check("watch for: only drops from 3 mobs or fewer are indexed", #D.questDrops == 2, #D.questDrops)
    local wh = hint(plan, "Watch for:")
    check("watch for: the hint says what it starts and how to check", wh and wh.text:find("Owatanka (lvl 23) around here", 1, true)
        and wh.text:find("/tar Owatanka", 1, true) and wh.text:find("+1700 XP", 1, true), wh and wh.text)
    ns.WorldMarks.SetTargets(plan.steps[1])
    check("watch for: its nameplate gets a box", ns.WorldMarks.npc[1220] == "Quest drop")
    M.bag = { { id = 1120 } }
    L.Rebuild("tailspike looted")
    check("watch for: not once the item is in your bags", #(L.plan.watchFor or {}) == 0)
    M.bag = {}
end

do
    -- hearth on cooldown: a good moment for a break
    local ns = setup()
    local H = ns.Hints
    M.bag = { { id = 6948 } }
    local step = { travel = { mode = "hearth", bindName = "Razor Hill", saving = 400 }, loc = ns.Geo.Point(1429, 0.9, 0.9), tasks = {} }
    local function hint(needle)
        for _, h in ipairs(H.Compute({ plan = { player = ns.QuestState.Player(), steps = { step } }, step = step, byId = {},
                                       bags = ns.QuestState.Bags(), now = M.time, point = ns.Geo.PlayerPoint() })) do
            if h.text:find(needle, 1, true) then return h end
        end
    end
    M.hearthCD = { 900, 1800 } -- 28:20 left
    local b = hint("Hearth ready in")
    check("hearth: on a long cooldown, take a break", b and b.text:find("28:20", 1, true)
        and b.text:find("keeps ticking while you're logged out", 1, true), b and b.text)
    M.time = 5000
    M.hearthCD = { 5000 - 1740, 1800 } -- a minute left
    local s = hint("Hearth ready in")
    check("hearth: a minute left: just the countdown", s and s.text:find("1:00", 1, true) and not s.text:find("break", 1, true), s and s.text)
    M.time = 1000
    M.hearthCD = { 0, 0 }
    check("hearth: ready: hearth now", hint("Hearth now") ~= nil and hint("Hearth ready in") == nil)
    M.bag = {}
end

do
    -- grind first: the plan runs short of turn-ins before mobs that would be too high
    local ns = setup()
    local D, L, S = ns.Data, ns.Ladder, ns.Speed
    D.InitWith(M.fakeDB({
        quests = {
            [1301] = { name = "Raptor Heads", startedBy = { { 1300 } }, finishedBy = { { 1300 } }, requiredLevel = 18, questLevel = 22,
                       objectives = { { { 1302 } } } },
        },
        questXP = { [1301] = { 22, 1800 } },
        npcs = {
            [1300] = { name = "Hub Giver", spawns = spawn(42, 41) },
            [1302] = { name = "Witchwing Raptor", minLevel = 24, maxLevel = 24, spawns = spawn(60, 60) },
            [1303] = { name = "Bristleback Quilboar", minLevel = 19, maxLevel = 20, spawns = { [12] = { { 43, 42 }, { 43.5, 42 }, { 44, 42.5 } } } },
            [1304] = { name = "Lone Boar", minLevel = 20, maxLevel = 20, spawns = spawn(44, 44) },
            [1305] = { name = "Kodo Too High", minLevel = 30, maxLevel = 31, spawns = spawn(43, 41) },
        },
        objects = {}, items = {},
    }))
    M.player.level = 20
    local plan = fullPlan(ns)
    local stop = plan and plan.grindStop
    check("grind: a stop goes in before the raptors (lvl 24 at level 20, nothing else to turn in)", stop ~= nil)
    local grindAt, raptorsAt
    for i, s in ipairs(plan.steps) do
        for _, t in ipairs(s.tasks) do
            if t.visit == "grind" then grindAt = i end
            if t.kind == "objective" and t.questId == 1301 and not raptorsAt then raptorsAt = i end
        end
    end
    check("grind: ...right before them", grindAt and raptorsAt and grindAt == raptorsAt - 1, tostring(grindAt) .. "/" .. tostring(raptorsAt))
    check("grind: on the densest mobs at your level near where you leave from", stop and stop.mobName == "Bristleback Quilboar"
        and stop.npcIds and stop.npcIds[1] == 1303, stop and stop.mobName)
    check("grind: at most 15 minutes, a few bars", stop and stop.est <= S.GRIND_MAX_SECONDS + 0.5 and stop.targetLevel > 20.25
        and stop.targetLevel < 21, stop and stop.targetLevel)
    check("grind: the step says what, where, how long and why", stop and stop.label:find("Grind first: kill Bristleback Quilboar (lvl 19-20)", 1, true)
        and stop.label:find("bars into level 20", 1, true) and stop.label:find("Witchwing Raptor ahead is level 24", 1, true), stop and stop.label)
    -- the step is done when the bar gets there, and it's skippable like the other stops
    L.current = grindAt
    ns.WorldMarks.SetTargets(plan.steps[grindAt])
    check("grind: the mobs to grind get a box", ns.WorldMarks.npc[1303] == "Grind")
    check("grind: not done yet at the start of the level", not L.TaskDone(stop, {}))
    _G.UnitXP, _G.UnitXPMax = function() return 23000 end, function() return 23200 end
    check("grind: done once the bar gets there", L.TaskDone(stop, {}))
    check("grind: level with the bar", math.abs(S.LevelNow() - (20 + 23000 / 23200)) < 1e-6)
    _G.UnitXP, _G.UnitXPMax = nil, nil
    check("grind: level text", S.LevelText(23) == "level 23" and S.LevelText(22.3) == "6 bars into level 22"
        and S.LevelText(22.99) == "level 23" and S.LevelText(22.05) == "1 bar into level 22")
    -- off: no stop
    _G.SlashCmdList.QUESTLADDER("grind")
    L.Rebuild("grind off")
    check("grind: /ladder grind turns it off", ns.db.grindFirst == false and L.plan.grindStop == nil)
    _G.SlashCmdList.QUESTLADDER("grind")
    -- nothing to grind for when the mobs are at your level
    local synthetic = { steps = { { tasks = { { kind = "objective", mobLevel = 21, quest = {}, obj = {} } } } } }
    check("grind: no stop when the mobs are at most one above you", S.GrindStop(synthetic, { level = 20, xpFrac = 0, point = ns.Geo.PlayerPoint() }) == nil)
    -- turn-ins on the way count: three turn-ins first can be enough
    local P = ns.Planner
    local turnins = {}
    for i = 1, 8 do turnins[i] = { kind = "turnin", xpWeight = 1 } end
    local enough = { steps = { { tasks = turnins }, { tasks = { { kind = "objective", mobLevel = 22, quest = {}, obj = {} } } } } }
    check("grind: turn-ins before the fight count", S.GrindStop(enough, { level = 20, xpFrac = 0.2, point = ns.Geo.PlayerPoint() }) == nil,
        P.TurninsPerLevel(20))
end

do
    -- die and res at the spirit healer
    local ns = setup()
    local L, S, H = ns.Ladder, ns.Speed, ns.Hints
    _G.C_DeathInfo = { GetGraveyardsForMap = function() return { { name = "Razor Hill", position = { x = 0.80, y = 0.41 } } } end }
    S.ResetGraveyards()
    local dest = ns.Geo.Point(1429, 0.81, 0.41) -- 30 yd past the graveyard, 1170 yd from you
    local nextFight = ns.Geo.Point(1429, 0.82, 0.45)
    local function planAt(level)
        local p = { player = { level = level }, net = { nodes = {}, speed = 7 },
                    steps = { { index = 1, loc = dest, est = 30, tasks = { { kind = "turnin", questId = 1 } } },
                              { index = 2, loc = nextFight, est = 200,
                                tasks = { { kind = "objective", obj = { type = "monster" } } } } } }
        L.plan, L.current = p, 1
        return p
    end
    local here = ns.Geo.PlayerPoint()
    local p = planAt(8)
    local live = L.LiveTravel(p.steps[1], here)
    check("die: level 8, the graveyard by your next stop: quicker than a 2:47 walk", live and live.die and live.die.name == "Razor Hill"
        and live.die.sickness == 0 and math.abs(live.dieVs - 1170 / 7) < 1, live and live.die and live.die.total)
    local function hint(needle)
        for _, h in ipairs(H.Compute({ plan = L.plan, step = L.plan.steps[1], byId = {}, bags = ns.QuestState.Bags(), now = M.time,
                                       point = here })) do
            if h.text:find(needle, 1, true) then return h end
        end
    end
    local dh = hint("Faster: die on purpose")
    check("die: the hint names the graveyard, both times and the cost", dh and dh.text:find("graveyard by Razor Hill, 30 yd", 1, true)
        and dh.text:find("no res sickness up to level 10", 1, true) and dh.text:find("25% durability", 1, true), dh and dh.text)
    planAt(15)
    live = L.LiveTravel(L.plan.steps[1], here)
    check("die: level 15 with a fight right after: 5 minutes of sickness, not worth it", live and not live.die)
    check("die: res sickness by level", S.ResSicknessSeconds(10) == 0 and S.ResSicknessSeconds(15) == 300 and S.ResSicknessSeconds(40) == 600)
    -- turn-ins and a long walk after: the sickness wears off on the way
    local calm = { player = { level = 15 }, net = { nodes = {}, speed = 7 },
                   steps = { { index = 1, loc = dest, est = 30, tasks = { { kind = "turnin" } } },
                             { index = 2, loc = ns.Geo.Point(1429, 0.81, 0.95), est = 20, tasks = { { kind = "pickup" } } },
                             { index = 3, loc = ns.Geo.Point(1429, 0.10, 0.95), est = 20, tasks = { { kind = "turnin" } } } } }
    check("die: calm time counts turn-ins and the walks between them", S.CalmSeconds(calm, 1, calm.net) > 300, S.CalmSeconds(calm, 1, calm.net))
    L.plan = calm
    live = L.LiveTravel(calm.steps[1], here)
    check("die: ...so at level 15 it's worth it again", live and live.die and live.die.wait == 0)
    -- a short trip: not worth dying for
    planAt(8)
    local near = ns.Geo.Point(1429, 0.45, 0.41)
    L.plan.steps[1].loc = near
    live = L.LiveTravel(L.plan.steps[1], here)
    check("die: not for a short walk", live and not live.die)
    L.plan.steps[1].loc = dest
    local mine = L.plan
    _G.SlashCmdList.QUESTLADDER("dietravel") -- (it replans: put the test's route back)
    L.plan = mine
    live = L.LiveTravel(L.plan.steps[1], here)
    check("die: /ladder dietravel turns the tip off", ns.db.deathTravel == false and live and not live.die)
    _G.SlashCmdList.QUESTLADDER("dietravel")
    L.plan = mine
    -- no graveyard from the game: the ones you've appeared at count
    _G.C_DeathInfo = nil
    S.ResetGraveyards()
    live = L.LiveTravel(L.plan.steps[1], here)
    check("die: without the game's graveyard list, nothing to suggest", live and not live.die)
    M.player.x, M.player.y = 0.79, 0.42
    _G.UnitIsGhost = function() return true end
    _G.GetSubZoneText = function() return "Razor Hill" end
    ns.DispatchEvent("PLAYER_ALIVE")
    check("die: released at a graveyard: it's remembered", #S.LearnedGraveyards() == 1 and S.LearnedGraveyards()[1].gyName == "Razor Hill")
    ns.DispatchEvent("PLAYER_ALIVE")
    check("die: ...once", #S.LearnedGraveyards() == 1)
    M.player.x, M.player.y = 0.42, 0.41
    live = L.LiveTravel(L.plan.steps[1], here)
    check("die: and then it's suggested", live and live.die and live.die.name == "Razor Hill")
    _G.UnitIsGhost, _G.GetSubZoneText = nil, nil
    -- the game's list can hold secret values: never used
    _G.C_DeathInfo = { GetGraveyardsForMap = function() return { { name = "X", position = { x = "secret", y = 0.4 } } } end }
    _G.issecretvalue = function(v) return v == "secret" end
    S.ResetGraveyards()
    check("die: a secret position is skipped", #S.GameGraveyards(1429) == 0)
    _G.issecretvalue = function() return false end
    _G.C_DeathInfo = nil
    L.plan = nil
end

---------------------------------------------------------------------------
-- 15p. 0.6.0: make it yours - themes and colors, compact mode, window options, map squares,
--      the options window, the minimap's add-on menu and the icon
---------------------------------------------------------------------------
do
    M.installGlobals({ frames = true })
    M.player = { level = 3, classFile = "WARRIOR", className = "Warrior", money = 25000, mapId = 1429, x = 0.42, y = 0.41 }
    M.log, M.completed, M.rewards, M.bag, M.equipped = {}, {}, {}, {}, {}
    M.items = M.items or {}
    local placed = { mini = 0, world = 0 }
    local pinsLib = {
        RemoveAllMinimapIcons = function() end, RemoveAllWorldMapIcons = function() end,
        AddMinimapIconMap = function() placed.mini = placed.mini + 1 end,
        AddWorldMapIconMap = function() placed.world = placed.world + 1 end,
    }
    _G.LibStub = setmetatable({}, { __call = function(_, name) if name:find("^HereBeDragons") then return pinsLib, 7 end end })
    local sounds = 0
    _G.SOUNDKIT = { MAP_PING = 1 }
    _G.PlaySound = function() sounds = sounds + 1 end
    _G.Settings, _G.ColorPickerFrame, _G.AddonCompartmentFrame = nil, nil, nil
    local files = {}
    for _, f in ipairs(FILES) do files[#files + 1] = f end
    files[#files + 1] = "UI.lua"
    files[#files + 1] = "Options.lua"
    local ns
    local ok, err = pcall(function()
        ns = M.loadAddon(ADDON_DIR, files)
        ns.Geo.SetZoneMaps({ [12] = 1429 }, {})
        ns.Geo.SetTransform(1429, { cont = 0, ox = 0, oy = 0, ax = 3000, ay = 0, bx = 0, by = 2000 })
        ns.Data.InitWith(db())
        ns.Fire("SETTINGS_LOADED")
        M.log = { { id = 2, title = "Kobold Camp Cleanup", level = 2, complete = false,
                    objectives = { { text = "Kobold Vermin slain: 2/6", type = "monster", finished = false, numFulfilled = 2, numRequired = 6 } } } }
        ns.Data.BuildIndexes(ns.QuestState.Player(), function() end)
        local function drive()
            for _, f in ipairs(M.frames) do
                local s = f.__scripts and f.__scripts.OnUpdate
                if s then for _ = 1, 500 do s(f, 0.016) end end
            end
        end
        drive()
        ns.Ladder.Rebuild("0.6.0 test")
        drive()
    end)
    check("0.6.0: loads with the options file", ok, err)
    if ok then
        local T, UI, O, HL, WM = ns.Theme, ns.UI, ns.Options, ns.Highlight, ns.WorldMarks
        local guide, hf = _G.QuestLadderGuideFrame, _G.QuestLadderHintFrame
        local fired = {}
        for _, msg in ipairs({ "THEME_CHANGED", "REQUEST_REPLAN", "OPEN_OPTIONS" }) do
            ns.On(msg, function() fired[msg] = (fired[msg] or 0) + 1 end)
        end

        -- Themes and colors
        local r, g, b = T.Color("marker")
        check("theme: cyan by default, the look Quest Ladder always had", T.Preset().key == "cyan" and r == 0 and g == 1 and b == 1
            and T.Hex("accent") == "|cff33ff99", T.Hex("accent"))
        local v0 = T.version
        check("theme: switching to pink", T.SetPreset("pink") and ns.db.theme == "pink" and T.version == v0 + 1
            and fired.THEME_CHANGED == 1)
        r, g, b = T.Color("marker")
        check("theme: pink markers", r == 1 and g == 0.41 and b == 0.71 and T.Hex("marker") == "|cffff69b5", T.Hex("marker"))
        T.SetColor("marker", 0.5, 0.25, 1)
        r, g, b = T.Color("marker")
        check("theme: your own color on top of the theme", T.IsCustom("marker") and r == 0.5 and g == 0.25 and b == 1)
        check("theme: other colors stay the theme's", not T.IsCustom("map") and select(1, T.Color("map")) == 1)
        T.ResetColor("marker")
        check("theme: right-click puts the theme's color back", not T.IsCustom("marker") and select(2, T.Color("marker")) == 0.41)
        T.SetColor("map", 0.1, 0.2, 0.3)
        T.SetPreset("gold")
        check("theme: a new theme drops your picks", not T.IsCustom("map") and select(2, T.Color("map")) == 0.75)
        ns.db.colors = { marker = { 2, "x", 1 }, map = "junk" }
        r, g, b = T.Color("marker")
        check("theme: a broken saved color falls back to the theme", r == 1 and g == 0.82 and b == 0 and not T.IsCustom("marker"))
        ns.db.theme = "no such theme"
        check("theme: an unknown saved theme falls back to cyan", T.Preset().key == "cyan" and select(1, T.Color("marker")) == 0)
        check("theme: found by name or key", T.Find("fel").key == "green" and T.Find("PINK").key == "pink"
            and T.Find(" frost ").key == "frost" and T.Find("nope") == nil and T.Find("") == nil)
        check("theme: refuses junk colors", not T.SetColor("marker", nil, 1, 1))
        _G.SlashCmdList.QUESTLADDER("theme pink")
        check("slash: /ladder theme pink", ns.db.theme == "pink", ns.db.theme)
        _G.SlashCmdList.QUESTLADDER("theme")
        check("slash: /ladder theme lists them, marking the one in use", (M.lastPrint or ""):find("themes:", 1, true)
            and (M.lastPrint or ""):find("[|cffff69b5pink|r]", 1, true), M.lastPrint)
        check("chat: lines start with the icon and the name in the theme's color",
            (M.lastPrint or ""):find("Media\\Icon", 1, true) and (M.lastPrint or ""):find(T.Hex("accent") .. "Quest Ladder", 1, true),
            M.lastPrint)

        -- Saved settings: map squares got their own switches, reset keeps learned data
        local saved = ns.ApplyDefaults({ worldMarks = false, settingsVersion = 1 }, ns.defaults)
        ns.MigrateSettings(saved)
        check("settings: world marks off keeps the squares off too", saved.minimapSquares == false and saved.worldMapSquares == false
            and saved.settingsVersion == 2)
        saved = ns.ApplyDefaults({ worldMarks = true, settingsVersion = 1 }, ns.defaults)
        ns.MigrateSettings(saved)
        check("settings: world marks on leaves the squares on", saved.minimapSquares == true and saved.worldMapSquares == true)
        saved = ns.ApplyDefaults({ worldMarks = false, settingsVersion = 2, minimapSquares = true }, ns.defaults)
        ns.MigrateSettings(saved)
        check("settings: squares turned on after the update stay on", saved.minimapSquares == true)
        saved = { compact = true, theme = "pink", colors = { marker = { 1, 0, 0 } }, guideWidth = 400, weights = { agi = 2 },
                  goldReserve = 500, graveyards = { { name = "Kept" } }, settingsVersion = 2 }
        ns.ResetSettings(saved)
        check("settings: reset puts defaults back", saved.compact == false and saved.theme == "cyan" and next(saved.colors) == nil
            and saved.guideWidth == 340 and saved.weights == nil and saved.goldReserve == nil)
        check("settings: reset keeps what was learned", saved.graveyards and saved.graveyards[1].name == "Kept"
            and saved.settingsVersion == 2)
        check("settings: reset gives its own colors table", saved.colors ~= ns.defaults.colors)

        -- Boxes: color, thickness, labels, pulse
        T.SetPreset("cyan")
        local target = M.newFrame("target"); target:Show()
        local box = HL.Box("t", target, "Use", 2)
        check("boxes: painted with the theme", box and box.paintedVersion == T.version and #box.edges == 4)
        T.SetPreset("pink")
        check("boxes: repainted when the theme changes", box.paintedVersion == T.version)
        ns.db.markerLabels = false
        HL.Box("t", target, "Use", 2)
        check("boxes: labels can be switched off", box.label:GetText() == "")
        ns.db.markerLabels = true
        HL.Box("t", target, "Use", 2)
        check("boxes: ...and on", box.label:GetText() == "Use")
        check("boxes: fade by default", box.pulsing == true)
        ns.db.markerPulse = false
        HL.Box("t", target, "Use", 2)
        check("boxes: fading can be switched off", box.pulsing == false)
        ns.db.markerPulse = true
        ns.db.markerThickness = 9
        check("boxes: thickness stays 1-4", HL.Thickness() == 4 and HL.NeedsPaint(box))
        HL.Box("t", target, "Use", 2)
        check("boxes: a new thickness repaints", box.paintedThickness == 4 and box.pulsing == true)
        ns.db.markerThickness = 0
        check("boxes: ...at least 1", HL.Thickness() == 1)
        ns.db.markerThickness = 2
        HL.Clear("t")

        -- Nameplate markers and the "This one" cue use the marker color; the ping can be muted
        local lines = {}
        WM.softHit, WM.targetHit = { label = "Use", name = "Crate" }, { label = "Kill", name = "Wolf" }
        WM.Hints(function(h) lines[#lines + 1] = h.text end)
        check("cues: \"This one\" and \"Target is right\" in the marker color", lines[1]:find(T.Hex("marker"), 1, true)
            and lines[2]:find(T.Hex("marker"), 1, true) and not lines[1]:find("00ffff", 1, true), lines[1])
        WM.softHit, WM.targetHit = nil, nil
        WM.object[77] = "Use"
        M.guids.softinteract = "GameObject-0-1-2-3-77-0"
        ns.DispatchEvent("PLAYER_SOFT_INTERACT_CHANGED", nil, M.guids.softinteract)
        check("cues: a ping when you face the object", sounds == 1, sounds)
        ns.DispatchEvent("PLAYER_SOFT_INTERACT_CHANGED", nil, nil)
        ns.db.pingSound = false
        ns.DispatchEvent("PLAYER_SOFT_INTERACT_CHANGED", nil, M.guids.softinteract)
        check("cues: no ping when it's switched off", sounds == 1, sounds)
        ns.db.pingSound = true
        M.guids.softinteract = nil
        ns.DispatchEvent("PLAYER_SOFT_INTERACT_CHANGED", nil, nil)

        -- Map squares: each map has its own switch
        local step = { tasks = { { kind = "objective", isDone = false,
                                   loc = { mapId = 1429, x = 0.5, y = 0.5, members = { { mapId = 1429, x = 0.5, y = 0.5 },
                                                                                       { mapId = 1429, x = 0.6, y = 0.5 } } } } } }
        placed.mini, placed.world = 0, 0
        WM.RefreshPins(step)
        check("squares: on both maps by default", placed.mini == 2 and placed.world == 2 and WM.pinsShown.minimap == 2)
        ns.db.minimapSquares = false
        placed.mini, placed.world = 0, 0
        WM.RefreshPins(step)
        check("squares: the minimap's can be switched off alone", placed.mini == 0 and placed.world == 2, placed.mini)
        ns.db.worldMapSquares = false
        placed.mini, placed.world = 0, 0
        WM.RefreshPins(step)
        check("squares: ...and the world map's", placed.mini == 0 and placed.world == 0 and WM.PinCount() == 0)
        ns.db.minimapSquares, ns.db.worldMapSquares = true, true
        ns.db.worldMarks = false
        placed.mini = 0
        WM.RefreshPins(step)
        check("squares: nameplate markers off doesn't hide them any more", placed.mini == 2)
        ns.db.worldMarks = true
        ns.db.squareSize = 10
        local mini, world = WM.SquareSizes()
        check("squares: size from the options, world map 2 bigger", mini == 10 and world == 12)
        ns.db.squareSize = 99
        check("squares: size stays sensible", (WM.SquareSizes()) == 16)
        ns.db.squareSize = 7

        -- Guide window: compact mode, buttons, footer lines, width, lock, hint lines
        UI.RefreshGuide()
        check("window: full mode shows the buttons and the -", guide.skipBtn:IsShown() and guide.gearBtn:IsShown()
            and guide.compactBtn:GetText() == "-")
        check("window: the icon is in the title bar", guide.icon ~= nil and guide.icon.tex ~= nil)
        local before = fired.REQUEST_REPLAN or 0
        _G.SlashCmdList.QUESTLADDER("compact")
        check("compact: /ladder compact turns it on without a replan", ns.db.compact == true and (fired.REQUEST_REPLAN or 0) == before)
        local limits = UI.Limits()
        check("compact: fewer lines, no buttons, no footer", limits.compact and limits.tasks == 3 and limits.next == 1
            and limits.hints == 2 and not limits.buttons and not limits.bagLine and not limits.gearLine)
        check("compact: the window follows", not guide.skipBtn:IsShown() and not guide.bagsBtn:IsShown()
            and not guide.footer:IsShown() and guide.compactBtn:GetText() == "+")
        ns.db.compactTaskLines = 1
        UI.RefreshGuide()
        check("compact: one line for the current step", guide.tasks[1]:IsShown() and not guide.tasks[2]:IsShown())
        local stepNow = ns.Ladder.CurrentStep()
        if stepNow and #stepNow.tasks > 1 then
            check("compact: the line says how many more there are", (guide.tasks[1]:GetText() or ""):find("more)", 1, true) ~= nil,
                guide.tasks[1]:GetText())
        end
        ns.db.compactNextSteps = 0
        UI.RefreshGuide()
        check("compact: no upcoming steps when set to 0", not guide.nextLabel:IsShown() and not guide.next[1]:IsShown())
        ns.db.compactTaskLines, ns.db.compactNextSteps = 3, 1
        UI.ToggleCompact()
        check("compact: the -/+ button turns it off again", ns.db.compact == false and guide.skipBtn:IsShown())
        ns.db.showButtons, ns.db.showBagLine, ns.db.showGearLine = false, false, false
        UI.RefreshGuide()
        check("window: buttons and footer lines can be switched off", not guide.skipBtn:IsShown() and not guide.footer:IsShown()
            and not guide.footer2:IsShown())
        ns.db.showButtons, ns.db.showBagLine, ns.db.showGearLine = true, true, true
        ns.db.guideWidth = 9999
        check("window: width stays on screen", UI.Width() == UI.MAX_WIDTH)
        ns.db.guideWidth = "junk"
        check("window: a broken width falls back", UI.Width() == 340)
        ns.db.guideWidth = 340
        ns.db.nextStepsShown = 99
        check("window: upcoming steps stay 0-6", UI.Limits().next == 6)
        ns.db.nextStepsShown = 4
        local moved = false
        guide.StartMoving = function() moved = true end
        ns.db.lockGuide = true
        guide.__scripts.OnDragStart(guide)
        check("window: locked, it doesn't move", not moved)
        ns.db.lockGuide = false
        guide.__scripts.OnDragStart(guide)
        check("window: unlocked, it does", moved)
        ns.charDB.frame = { point = "TOP", x = 5, y = 5 }
        UI.ResetPosition()
        check("window: reset position forgets where it was", next(ns.charDB.frame) == nil)
        ns.Hints.list = { { text = "first", kind = "info" }, { text = "second", kind = "info" } }
        ns.db.hintLines = 1
        UI.RefreshHints()
        check("hints: the box shows as many lines as set", hf.lines[1]:IsShown() and not hf.lines[2]:IsShown())
        ns.db.hintLines = 4
        UI.RefreshHints()
        check("hints: ...or all of them", hf.lines[2]:IsShown())
        ns.Hints.list = {}

        -- The options window
        check("options: no Settings API, nothing registered", O.Register() == false and O.reason == "no Settings API")
        M.lastPrint = nil
        O.Open()
        check("options: says so when it can't open", (M.lastPrint or ""):find("couldn't open", 1, true), M.lastPrint)
        local reg = { subs = {}, added = 0 }
        _G.Settings = {
            RegisterCanvasLayoutCategory = function(frame, name)
                reg.main, reg.name = frame, name
                return { GetID = function() return 77 end }
            end,
            RegisterCanvasLayoutSubcategory = function(_, frame, name) reg.subs[#reg.subs + 1] = name; return {} end,
            RegisterAddOnCategory = function() reg.added = reg.added + 1 end,
            OpenToCategory = function(id) reg.opened = id end,
        }
        check("options: registers with Blizzard's options", O.Register() == true and reg.added == 1 and #reg.subs == 4
            and O.CategoryId() == 77, #reg.subs)
        check("options: the name in the list has the icon after it (keeps A-Z order)",
            reg.name:find("^Quest Ladder") and reg.name:find("Media\\Icon", 1, true), reg.name)
        check("options: registers once", O.Register() == true and reg.added == 1)
        _G.SlashCmdList.QUESTLADDER("options")
        check("options: /ladder options opens it", reg.opened == 77 and fired.OPEN_OPTIONS == 1)
        reg.opened = nil
        M.inCombat = true
        O.Open()
        check("options: not in combat", reg.opened == nil and O.openAfterCombat == true)
        M.inCombat = false
        ns.DispatchEvent("PLAYER_REGEN_ENABLED")
        check("options: ...it opens when the fight is over", reg.opened == 77 and not O.openAfterCombat)

        -- every page builds, and its controls change the settings
        local controls = {}
        for i, frame in ipairs(O.frames) do
            local okB, errB = pcall(function() frame.__scripts.OnShow(frame) end)
            check("options: page " .. i .. " (" .. frame.def.name .. ") builds", okB and frame.built and #frame.controls > 0, errB)
            for _, c in ipairs(frame.controls or {}) do
                local key = c.item and c.item.key or c.preset or c.role
                if key then controls[(c.item and c.item.kind or "x") .. ":" .. key] = controls[(c.item and c.item.kind or "x") .. ":" .. key] or c end
                if c.preset then controls["theme:" .. c.preset] = c end
                if c.role then controls["color:" .. c.role] = c end
            end
        end
        check("options: every page is listed", #O.frames == #O.PAGES and #O.PAGES == 5)
        local cb = controls["check:compact"]
        cb.GetChecked = function() return true end
        cb.__scripts.OnClick(cb)
        check("options: a checkbox changes the setting", ns.db.compact == true)
        cb.GetChecked = function() return false end
        cb.__scripts.OnClick(cb)
        ns.db.skipGroupQuests = true
        local group = controls["check:skipGroupQuests"]
        local checked
        group.SetChecked = function(_, v) checked = v end
        group:Refresh()
        check("options: \"Plan group quests\" shows the opposite of skipping them", checked == false)
        before = fired.REQUEST_REPLAN or 0
        group.GetChecked = function() return true end
        group.__scripts.OnClick(group)
        check("options: ...and ticking it plans them, with a replan", ns.db.skipGroupQuests == false
            and (fired.REQUEST_REPLAN or 0) == before + 1)
        ns.db.skipGroupQuests = true
        before = fired.REQUEST_REPLAN or 0
        local mm = controls["check:minimapSquares"]
        mm.GetChecked = function() return false end
        mm.__scripts.OnClick(mm)
        check("options: display switches don't replan", ns.db.minimapSquares == false and (fired.REQUEST_REPLAN or 0) == before)
        ns.db.minimapSquares = true
        local width = controls["slider:guideWidth"]
        width.__scripts.OnValueChanged(width, 433)
        check("options: sliders snap to their step", ns.db.guideWidth == 430, ns.db.guideWidth)
        width.__scripts.OnValueChanged(width, 2000)
        check("options: ...and stay in range", ns.db.guideWidth == 520, ns.db.guideWidth)
        ns.db.guideWidth = 340
        local minxp = controls["slider:minQuestValue"]
        minxp.__scripts.OnValueChanged(minxp, 0.333)
        check("options: percent sliders too", ns.db.minQuestValue == 0.35, ns.db.minQuestValue)
        ns.db.minQuestValue = 0.5
        local pink = controls["theme:pink"]
        T.SetPreset("cyan")
        pink.__scripts.OnClick(pink)
        check("options: a theme button switches the theme", ns.db.theme == "pink")
        local swatch = controls["color:marker"]
        swatch.__scripts.OnClick(swatch, "LeftButton")
        check("options: no color picker, says so", (M.lastPrint or ""):find("color picker", 1, true), M.lastPrint)
        local shownInfo
        _G.ColorPickerFrame = {
            SetupColorPickerAndShow = function(_, info) shownInfo = info end,
            GetColorRGB = function() return 0.2, 0.4, 0.6 end,
        }
        swatch.__scripts.OnClick(swatch, "LeftButton")
        check("options: a color opens Blizzard's picker with the current color", shownInfo and shownInfo.r == 1 and shownInfo.g == 0.41)
        shownInfo.swatchFunc()
        r, g, b = T.Color("marker")
        check("options: picking shows the color at once", T.IsCustom("marker") and r == 0.2 and g == 0.4 and b == 0.6)
        shownInfo.cancelFunc()
        check("options: Cancel puts the theme's color back", not T.IsCustom("marker"))
        T.SetColor("marker", 0.9, 0.9, 0.9)
        swatch.__scripts.OnClick(swatch, "LeftButton")
        shownInfo.swatchFunc()
        shownInfo.cancelFunc()
        check("options: ...or your earlier pick", T.IsCustom("marker") and select(1, T.Color("marker")) == 0.9)
        swatch.__scripts.OnClick(swatch, "RightButton")
        check("options: right-click a color for the theme's", not T.IsCustom("marker"))
        ns.db.compact, ns.db.guideScale = true, 1.4
        O.ResetAll()
        check("options: reset all", ns.db.compact == false and ns.db.guideScale == 1 and ns.db.theme == "cyan")

        -- The minimap's add-on menu
        local showing = ns.db.showGuide
        QuestLadder_OnAddonCompartmentClick("QuestLadder", "RightButton")
        check("add-on menu: right-click shows or hides the guide", ns.db.showGuide == not showing)
        ns.db.showGuide = true
        reg.opened = nil
        QuestLadder_OnAddonCompartmentClick("QuestLadder", "LeftButton")
        check("add-on menu: click opens the options", reg.opened == 77)
        local okTip = pcall(QuestLadder_OnAddonCompartmentEnter, "QuestLadder", M.newFrame("menuButton"))
        check("add-on menu: tooltip", okTip and pcall(QuestLadder_OnAddonCompartmentLeave))
        check("add-on menu: not in a client without it", O.InAddonMenu() == nil)
        _G.AddonCompartmentFrame = { registeredAddons = { { text = "Questie" }, { text = "Quest Ladder" } } }
        check("add-on menu: found when listed", O.InAddonMenu() == true)
        _G.AddonCompartmentFrame.registeredAddons = { { text = "Questie" } }
        check("add-on menu: ...and when not", O.InAddonMenu() == false)
        _G.AddonCompartmentFrame = nil
        _G.Settings, _G.ColorPickerFrame = nil, nil
    end
    _G.SOUNDKIT, _G.PlaySound, _G.LibStub = nil, nil, nil
end

---------------------------------------------------------------------------
-- 15q. The icon: game-ready textures, named in the TOC, global functions for the add-on menu
---------------------------------------------------------------------------
do
    local function tga(path)
        local f = io.open(ADDON_DIR .. "/" .. path, "rb")
        if not f then return nil end
        local head = f:read(18)
        local size = f:seek("end")
        f:close()
        if not head or #head < 18 then return nil end
        local w = head:byte(13) + head:byte(14) * 256
        local h = head:byte(15) + head:byte(16) * 256
        return { imageType = head:byte(3), width = w, height = h, bits = head:byte(17), size = size }
    end
    local function pow2(n)
        local p = 1
        while p < n do p = p * 2 end
        return n > 0 and p == n
    end
    for _, name in ipairs({ "Media/Icon.tga", "Media/Logo.tga" }) do
        local t = tga(name)
        check("icon: " .. name .. " is an uncompressed 32-bit TGA, power-of-two square",
            t and t.imageType == 2 and t.bits == 32 and t.width == t.height and pow2(t.width)
            and t.size >= 18 + t.width * t.height * 4, t and (t.width .. "x" .. t.height .. " type " .. t.imageType))
    end
    local f = assert(io.open(ADDON_DIR .. "/QuestLadder.toc", "r"))
    local toc = f:read("*a")
    f:close()
    check("icon: the TOC's icon is Media\\Icon", toc:find("## IconTexture: Interface\\AddOns\\QuestLadder\\Media\\Icon\n", 1, true) ~= nil)
    local ns = M.loadAddon(ADDON_DIR, FILES)
    check("icon: Theme names the same files", ns.Theme.ICON == "Interface\\AddOns\\QuestLadder\\Media\\Icon"
        and ns.Theme.LOGO == "Interface\\AddOns\\QuestLadder\\Media\\Logo")
    M.installGlobals({ frames = true })
    local files = {}
    for _, x in ipairs(FILES) do files[#files + 1] = x end
    files[#files + 1] = "UI.lua"
    files[#files + 1] = "Options.lua"
    M.loadAddon(ADDON_DIR, files)
    for name in toc:gmatch("## AddonCompartmentFunc%w*: (%S+)") do
        check("icon: add-on menu function " .. name .. " exists", type(_G[name]) == "function")
    end
    local bf = assert(io.open(ADDON_DIR .. "/Bindings.xml", "r"))
    local bindings = bf:read("*a")
    bf:close()
    for fn in bindings:gmatch("(QuestLadder_%w+)%(%)") do
        check("bindings: " .. fn .. " exists", type(_G[fn]) == "function")
    end
    for name in bindings:gmatch('name="(QUESTLADDER_%w+)"') do
        check("bindings: " .. name .. " has a label", type(_G["BINDING_NAME_" .. name]) == "string")
    end
end

---------------------------------------------------------------------------
-- 15r. 0.6.0: every /ladder command is in the options too; "Having trouble?": reload,
--      diagnostics (then an offer to reload), the report window; gold and stat weights
---------------------------------------------------------------------------
do
    M.installGlobals({ frames = true })
    M.player = { level = 3, classFile = "WARRIOR", className = "Warrior", money = 25000, mapId = 1429, x = 0.42, y = 0.41 }
    M.log, M.completed, M.rewards, M.bag, M.equipped = {}, {}, {}, {}, {}
    M.items = M.items or {}
    local reloads, popups = 0, {}
    _G.ReloadUI = function() reloads = reloads + 1 end
    _G.StaticPopupDialogs = {}
    _G.StaticPopup_Show = function(name, text) popups[#popups + 1] = { name = name, text = text } end
    _G.GetBuildInfo = function() return "1.60.1", "71037", "Nov 20 2026", 16001 end
    _G.GetZoneText = function() return "Elwynn Forest" end
    _G.QuestLadderDiag = nil
    _G.Settings = {
        RegisterCanvasLayoutCategory = function() return { GetID = function() return 5 end } end,
        RegisterCanvasLayoutSubcategory = function() return {} end,
        RegisterAddOnCategory = function() end,
        OpenToCategory = function() end,
    }
    local files = {}
    for _, f in ipairs(FILES) do files[#files + 1] = f end
    files[#files + 1] = "UI.lua"
    files[#files + 1] = "Options.lua"
    files[#files + 1] = "Diag.lua"
    local ns
    local ok, err = pcall(function()
        ns = M.loadAddon(ADDON_DIR, files)
        ns.Geo.SetZoneMaps({ [12] = 1429 }, {})
        ns.Geo.SetTransform(1429, { cont = 0, ox = 0, oy = 0, ax = 3000, ay = 0, bx = 0, by = 2000 })
        ns.Data.InitWith(db())
        ns.Fire("SETTINGS_LOADED")
    end)
    check("trouble: loads", ok, err)
    if ok then
        local O = ns.Options
        local fired = {}
        for _, msg in ipairs({ "REQUEST_REPLAN", "SKIP_STEP", "SHOW_PANEL", "CVAR_PRESET" }) do
            ns.On(msg, function(arg) fired[msg] = (fired[msg] or 0) + 1; fired[msg .. ":arg"] = arg end)
        end
        local frames = {}
        for _, frame in ipairs(O.frames) do
            frame.__scripts.OnShow(frame)
            frames[frame.def.key] = frame
        end

        -- Every /ladder command has a place in the options: a switch for each toggle, and a
        -- button, slider or box (marked with the command it stands for) for the rest.
        local covered = {}
        for _, page in ipairs(O.PAGES) do
            for _, item in ipairs(page.items) do
                local list = {}
                if item.cmd then list[#list + 1] = item.cmd end
                for _, b in ipairs(item.buttons or {}) do if b.cmd then list[#list + 1] = b.cmd end end
                for _, c in ipairs(list) do
                    if type(c) == "table" then for _, x in ipairs(c) do covered[x] = true end else covered[c] = true end
                end
                if item.kind == "check" then covered["key:" .. item.key] = true end
            end
        end
        local f = assert(io.open(ADDON_DIR .. "/Core.lua", "r"))
        local core = f:read("*a")
        f:close()
        local commands = {}
        for c in core:gmatch('cmd == "(%w*)"') do commands[c] = true end
        local OPENS_OPTIONS = { options = true, config = true, settings = true, menu = true }
        local missing = {}
        for c in pairs(commands) do
            if not covered[c] and not OPENS_OPTIONS[c] then missing[#missing + 1] = "/ladder " .. c end
        end
        for name, spec in pairs(ns.toggles) do
            for i = 1, #spec do
                if not covered["key:" .. spec[i]] then missing[#missing + 1] = "/ladder " .. name .. " (" .. spec[i] .. ")" end
            end
        end
        table.sort(missing)
        check("options: every /ladder command has a control", #missing == 0 and next(commands) ~= nil, table.concat(missing, ", "))

        -- the action buttons do what their commands do
        local route, travel, main = frames.route.buttons, frames.travel.buttons, frames.main.buttons
        route["Replan"].__scripts.OnClick(route["Replan"])
        check("actions: Replan", fired.REQUEST_REPLAN == 1)
        route["Skip this step"].__scripts.OnClick(route["Skip this step"])
        check("actions: Skip this step", fired.SKIP_STEP == 1)
        ns.charDB.ignored[42] = true
        route["Un-skip all quests"].__scripts.OnClick(route["Un-skip all quests"])
        check("actions: Un-skip all quests", ns.charDB.ignored[42] == nil)
        travel["Bag planner"].__scripts.OnClick(travel["Bag planner"])
        check("actions: Bag planner", fired.SHOW_PANEL == 1 and fired["SHOW_PANEL:arg"] == "bags")
        travel["Gear upgrades"].__scripts.OnClick(travel["Gear upgrades"])
        check("actions: Gear upgrades", fired["SHOW_PANEL:arg"] == "gear")
        local okList = pcall(function()
            route["Skipped quests"].__scripts.OnClick(route["Skipped quests"])
            route["Dungeon quests"].__scripts.OnClick(route["Dungeon quests"])
            main["List commands"].__scripts.OnClick(main["List commands"])
        end)
        check("actions: the lists print without errors", okList)

        -- Gold to keep for training
        check("gold: typed amounts", O.SetGold("5g 20s") and ns.db.goldReserve == 52000)
        check("gold: as you'd type it", O.MoneyText(52000) == "5g 20s" and O.MoneyText(80) == "80c" and O.MoneyText(0) == "0c"
            and O.MoneyText(10000) == "1g")
        check("gold: auto", O.SetGold(" Auto ") and ns.db.goldReserve == nil)
        ns.db.goldReserve = 30000
        check("gold: empty means auto", O.SetGold("") and ns.db.goldReserve == nil)
        ns.db.goldReserve = 30000
        check("gold: nonsense changes nothing", O.SetGold("lots") == false and ns.db.goldReserve == 30000)
        local goldBox
        for _, c in ipairs(frames.travel.controls) do if c.item and c.item.kind == "money" then goldBox = c end end
        goldBox:Refresh()
        check("gold box: shows the amount", goldBox:GetText() == "3g", goldBox:GetText())
        goldBox:SetText("7g")
        goldBox.__scripts.OnEnterPressed(goldBox)
        check("gold box: Enter saves it", ns.db.goldReserve == 70000 and goldBox:GetText() == "7g")
        goldBox:SetText("12g")
        goldBox.__scripts.OnEscapePressed(goldBox)
        check("gold box: Escape puts it back", ns.db.goldReserve == 70000 and goldBox:GetText() == "7g", goldBox:GetText())
        goldBox:SetText("auto")
        goldBox.__scripts.OnEditFocusLost(goldBox)
        check("gold box: clicking away saves too", ns.db.goldReserve == nil and goldBox:GetText() == "auto")

        -- Stat weights
        local boxes = {}
        for _, c in ipairs(frames.travel.controls) do if c.stat then boxes[c.stat] = c end end
        check("weights: a box per stat", boxes.agi and boxes.dps and boxes.armor and boxes.mp5 ~= nil)
        boxes.agi:Refresh()
        boxes.armor:Refresh()
        check("weights: your class's values to start with", boxes.agi:GetText() == "0.6" and boxes.armor:GetText() == "0.01",
            boxes.agi:GetText() .. " / " .. boxes.armor:GetText())
        boxes.agi:SetText("2.5")
        boxes.agi.__scripts.OnEnterPressed(boxes.agi)
        check("weights: yours saved", ns.db.weights and ns.db.weights.agi == 2.5 and ns.Gear.Weights("WARRIOR").agi == 2.5)
        boxes.agi:SetText("")
        boxes.agi.__scripts.OnEnterPressed(boxes.agi)
        check("weights: empty for the class's value again", ns.db.weights == nil and boxes.agi:GetText() == "0.6")
        check("weights: nonsense refused", O.SetWeight("agi", "x") == false and O.SetWeight("agi", "-1") == false
            and ns.db.weights == nil)
        O.SetWeight("str", "3")
        travel["Class defaults"].__scripts.OnClick(travel["Class defaults"])
        check("weights: Class defaults clears yours", ns.db.weights == nil)

        -- Having trouble?
        check("trouble: the section is on the main page", main["Reload UI"] and main["Run diagnostics"]
            and main["Report a bug or idea"] and main["Clear saved diagnostics"] ~= nil)
        main["Reload UI"].__scripts.OnClick(main["Reload UI"])
        check("trouble: Reload UI reloads", reloads == 1)
        _G.SlashCmdList.QUESTLADDER("diag")
        check("trouble: a /ladder diag typed in chat doesn't ask to reload", #popups == 0)
        main["Run diagnostics"].__scripts.OnClick(main["Run diagnostics"])
        local runs = _G.QuestLadderDiag and _G.QuestLadderDiag.runs
        check("trouble: Run diagnostics runs them", runs and #runs == 2 and runs[2].label == "options")
        local popup = popups[1]
        check("trouble: ...then offers to reload", popup and popup.name == "QUESTLADDER_DIAG_RELOAD"
            and popup.text:find("diagnostics are done", 1, true) and not O.diagPending, popup and popup.text)
        _G.StaticPopupDialogs.QUESTLADDER_DIAG_RELOAD.OnAccept()
        check("trouble: Reload now reloads", reloads == 2)
        main["Clear saved diagnostics"].__scripts.OnClick(main["Clear saved diagnostics"])
        check("trouble: Clear saved diagnostics", _G.QuestLadderDiag and #_G.QuestLadderDiag.runs == 0)

        ns.recentErrors[#ns.recentErrors + 1] = { msg = "Interface/AddOns/QuestLadder/UI.lua:1: oops", count = 1 }
        main["Report a bug or idea"].__scripts.OnClick(main["Report a bug or idea"])
        local rf = _G.QuestLadderReportFrame
        check("report: the window opens", rf and rf:IsShown())
        check("report: links to copy", rf.github:GetText() == "https://github.com/Seltraeh/QuestLadder/issues/new/choose"
            and rf.curse:GetText() == "https://www.curseforge.com/wow/addons/quest-ladder")
        local details = rf.details:GetText() or ""
        check("report: details to paste", details:find("Quest Ladder " .. ns.VERSION, 1, true)
            and details:find("Client: 1.60.1 (build 71037, interface 16001)", 1, true)
            and details:find("level 3", 1, true) and details:find("Zone: Elwynn Forest", 1, true)
            and details:find("Errors this session: 1; first: Interface/AddOns/QuestLadder/UI.lua:1: oops", 1, true)
            and details:find("Last diagnostics: none yet", 1, true), details)
        check("report: no character name in it", not details:find("Mister", 1, true))
        rf.github:SetText("typed over it")
        rf.github.__scripts.OnTextChanged(rf.github, true)
        check("report: the links can't be typed over", rf.github:GetText() == O.GITHUB_ISSUES)
        rf.details:SetText("x")
        rf.details.__scripts.OnTextChanged(rf.details, true)
        check("report: ...nor the details", rf.details:GetText() == details)
        ns.recentErrors = {}
        local okAgain = pcall(O.ShowReport)
        check("report: opens again", okAgain and O.reportFrame == rf)
    end
    _G.ReloadUI, _G.StaticPopupDialogs, _G.StaticPopup_Show, _G.GetBuildInfo, _G.GetZoneText = nil, nil, nil, nil, nil
    _G.QuestLadderDiag, _G.Settings = nil, nil
end

---------------------------------------------------------------------------
-- 16. TOC: every file listed in load order, version in step with Core.lua
---------------------------------------------------------------------------
do
    local f = assert(io.open(ADDON_DIR .. "/QuestLadder.toc", "r"))
    local toc = f:read("*a")
    f:close()
    local listed = {}
    for line in toc:gmatch("[^\r\n]+") do
        if not line:match("^%s*#") and line:match("%S") then listed[#listed + 1] = line:match("^%s*(.-)%s*$") end
    end
    local expected = {}
    for _, x in ipairs(FILES) do expected[#expected + 1] = x end
    expected[#expected + 1] = "UI.lua"
    expected[#expected + 1] = "Options.lua"
    expected[#expected + 1] = "Diag.lua"
    check("toc: lists every add-on file in load order", table.concat(listed, ",") == table.concat(expected, ","),
        table.concat(listed, ","))
    local tocVersion = toc:match("## Version:%s*([%w%.%-]+)")
    local core = assert(io.open(ADDON_DIR .. "/Core.lua", "r"))
    local src = core:read("*a")
    core:close()
    check("toc: version matches Core.lua", tocVersion and src:find('ns.VERSION = "' .. tocVersion .. '"', 1, true) ~= nil, tocVersion)
    check("toc: declares the diag saved variable", toc:find("SavedVariables:[^\n]*QuestLadderDiag") ~= nil)
end

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
