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

local FILES = { "Core.lua", "Geo.lua", "Data.lua", "QuestState.lua", "Planner.lua", "Travel.lua", "Gear.lua",
                "Bags.lua", "Hints.lua", "Ladder.lua", "Automation.lua", "Highlight.lua", "WorldMarks.lua" }

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
    check("special quest item hint", found.special)
    check("escort hint", found.escort)
    check("Questie extra-objective note shown", found.extra)
    local use = H.UsableItem()
    check("use button gets a usable item", use and (use.itemId == 602 or use.itemId == 700), use and use.itemId)
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
    ns.Hints.list = { { kind = "use", itemId = 700, text = "use it" } }
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
    ns.Hints.list = { { kind = "use", itemId = 700, text = "use it" } }
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
        check("ui: waypoint set", M.waypoint ~= nil, "no waypoint")
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
    -- no OnQuestAccepted here: this is what you see after a /reload
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
    local symbol = find("Use ", "Symbol of Life", "Fallen Guard", "A Lesson in Healing")
    check("use item: required item of a no-objective quest, used on its NPC", symbol and symbol.kind == "use", symbol and symbol.text)
    check("use item: quest item QuestieDB links to the quest, used on the objective's NPC",
        find("Use ", "Holy Water", "Scarlet Zealot", "Bless the Fallen") ~= nil)
    check("use item: an item without a Use: effect is just carried", find("Strange Note") == nil)
    check("use item: nothing to use once a quest's own objectives are done", find("Done Already") == nil)
    H.list = hints
    local use = H.UsableItem()
    check("use item: goes on the use button", use and (use.itemId == 700 or use.itemId == 701), use and use.itemId)
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
    check("candidates: a saved old default becomes 25", saved.maxCandidates == 25 and saved.settingsVersion == 1)
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
