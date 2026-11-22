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
--- QuestieDB's NPC data; nil when no mob is involved. NPCs friendly to you (`faction`: "Horde"
--- or "Alliance") aren't fights: "speak to Neeru Fireblade" is a level-37 "monster" objective in
--- QuestieDB, and it held a level-12 quest back until 37 more quests were turned in.
local function mobLevelOf(o, faction)
    if o.type ~= "monster" and o.type ~= "item" then return nil end
    local mine = (faction == "Horde" and "H") or (faction == "Alliance" and "A") or nil
    local best
    for _, id in ipairs((o.targets and o.targets.npc) or {}) do
        local friendly = Data.Npc(id, "friendlyToFaction")
        local talk = friendly == "AH" or (mine ~= nil and friendly == mine)
        local lv = not talk and tonumber(Data.Npc(id, "minLevel"))
        if lv and lv > 0 and (not best or lv < best) then best = lv end
    end
    return best
end
Ladder.MobLevelOf = mobLevelOf

--- Quest text that says there's a clock ("before the time limit is up"): a timed quest even when
--- the game's timer can't be read.
local TIMED_PHRASES = { "time limit", "before time runs out", "before the time runs out", "allowed time" }
function Ladder.TimedByText(db)
    for _, line in ipairs((db and db.objectivesText) or {}) do
        local l = type(line) == "string" and line:lower() or ""
        for _, p in ipairs(TIMED_PHRASES) do
            if l:find(p, 1, true) then return true end
        end
    end
    return false
end

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
    -- the quest's home: its turn-in NPC nearest you (objectives are looked for on its continent)
    local home = db and Geo.Nearest((Data.GiverPoints(db.finishedBy)), player.point)
    for _, o in ipairs(sq.objectives) do
        local e = { index = o.index, text = o.text, type = o.type, finished = o.finished, have = o.have, need = o.need }
        local pts, inst, itemId, sourceName, sourceKind, targets = objectivePoints(o, db, counters)
        e.itemId, e.sourceName, e.sourceKind, e.targets = itemId, sourceName, sourceKind, targets
        e.mobLevel = mobLevelOf(e, player.faction)
        if pts and #pts > 0 then
            e.loc = Geo.BestCluster(pts, player.point, 90, home)
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
    -- a timed quest goes first (Planner.RushUrgent) and gets a countdown in the guide
    q.timer = sq.timer
    q.timed = sq.timer ~= nil or Ladder.TimedByText(db)
    if q.timed then
        -- the item it's about: what the giver handed you (the Rendered Spores), else its first quest item
        q.timedItem = (db and db.sourceItemId and db.sourceItemId ~= 0) and db.sourceItemId or q.questItems[1]
    end
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
    Ladder.MarkSpeedFacts(q, player)
    return q
end

--- 0.5.0: an escort's walking time counts in the "worth the walk" check, and objectives against
--- elites at your level are marked (Speed: "Escorts and group quests").
function Ladder.MarkSpeedFacts(q, player)
    local Speed = ns.Speed
    if not Speed then return end
    if q.escort then q.extraSeconds = Speed.ESCORT_SECONDS end
    for _, o in ipairs(q.objectives or {}) do
        o.elite = Speed.EliteTarget(o, player.level, player.faction) ~= nil or nil
    end
    q.groupMob, q.groupLevel = Speed.NeedsGroup(q, player.level, player.faction)
end

local function dbObjectives(db, ref, home, faction)
    local out = {}
    local objs = db.objectives or {}
    local idx = 0
    local instanceOnly = false
    local function push(kind, text, pts, inst, itemId, sourceName, sourceKind, targets)
        idx = idx + 1
        local e = { index = idx, type = kind, text = text, finished = false, have = 0, need = 1,
                    itemId = itemId, sourceName = sourceName, sourceKind = sourceKind, targets = targets }
        e.mobLevel = mobLevelOf(e, faction)
        if pts and #pts > 0 then e.loc = Geo.BestCluster(pts, ref, 90, home)
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
    local home = Geo.Nearest((Data.GiverPoints(db.finishedBy)), pickupPoint)
    local objectives, instanceOnly = dbObjectives(db, pickupPoint, home, player and player.faction)
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
    if player then Ladder.MarkSpeedFacts(c, player) end
    return c
end

local function levelOk(db, player, green, above)
    if (db.reqLevel or 0) > player.level then return false end
    local ql = (db.level and db.level > 0) and db.level or player.level
    return ql >= player.level - green and ql <= player.level + above
end

---------------------------------------------------------------------------
-- Quest value: skip quests that give too little for your level
---------------------------------------------------------------------------
-- A quest you haven't accepted is only planned when, at your level, it gives at least
-- minQuestValue (default half) of what a solid quest at your level gives (Data.SolidQuestXP),
-- or its reward is gear you would wear, or it leads to a quest that is worth it (breadcrumbs,
-- chain starts), or it's a quest for your class (spells, class items). Quests QuestieDB has no
-- XP for are kept. Quests in your log are never dropped: abandon one to skip it.

--- What a quest gives you now and how that compares with a solid quest at your level:
--- returns ratio, xpNow (ratio nil when unknown).
function Ladder.QuestWorth(questId, level)
    local xp, questLevel = Data.QuestXP(questId)
    if not xp then return nil, nil end
    local now = Data.XPAtLevel(xp, questLevel, level)
    local solid = Data.SolidQuestXP(level)
    if not solid or solid <= 0 then return nil, now end
    return now / solid, now
end

local function maxPlayerLevel()
    if GetMaxPlayerLevel then
        local ok, v = pcall(GetMaxPlayerLevel)
        if ok and type(v) == "number" and not ns.IsSecret(v) then return v end
    end
    return 60
end

local function rewardsUpgrade(questId, player)
    local Gear = ns.Gear
    if not Gear then return false end
    for _, itemId in ipairs(Data.rewardItems[questId] or {}) do
        local info = Gear.ItemInfo(itemId)
        if info and Gear.CanEquip(itemId, info, player, 2) then
            local up = Gear.CompareToEquipped(info.link, info, player.classFile, player.level)
            if Gear.IsUpgrade(up) then return true end
        end
    end
    return false
end

--- Quests that stay in the plan whatever they're worth or wherever they send you: for your class
--- (spells, class items), Forever's must-do extras, or a reward you'd wear. Returns the reason.
function Ladder.KeepReason(questId, player)
    local db = Data.Quest(questId)
    if db and db.classes and db.classes ~= 0 then return "class" end
    if ns.Goodies and ns.Goodies.MustDo(questId) then return "goodie" end
    if rewardsUpgrade(questId, player) then return "upgrade" end
    return nil
end

--- Is this not-yet-accepted quest worth planning? Returns ok, ratio, why ("upgrade", "leads on",
--- "class", "unknown" or nil).
function Ladder.WorthDoing(questId, player, depth)
    local min = ns.db.minQuestValue or 0
    if min <= 0 or player.level >= maxPlayerLevel() then return true end
    local ratio = Ladder.QuestWorth(questId, player.level)
    if ratio == nil then return true, nil, "unknown" end
    if ratio >= min then return true, ratio end
    local db = Data.Quest(questId)
    if db and db.classes and db.classes ~= 0 then return true, ratio, "class" end
    if rewardsUpgrade(questId, player) then return true, ratio, "upgrade" end
    -- Forever's extras: camping unlocks, Library books, the sleeping bag chain, crates, bag rewards
    if ns.Goodies and ns.Goodies.MustDo(questId) then return true, ratio, "goodie" end
    if (depth or 0) < 2 then
        for _, nextId in ipairs(Data.followUps[questId] or {}) do
            local nextDb = Data.Quest(nextId)
            if nextDb and (nextDb.reqLevel or 0) <= player.level + 2 then
                local ok, _, why = Ladder.WorthDoing(nextId, player, (depth or 0) + 1)
                if ok and why ~= "unknown" then return true, ratio, "leads on" end
            end
        end
    end
    return false, ratio
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
    Ladder.skippedLowValue = {}
    Ladder.skippedGroup = {}
    Ladder.skillUnlocks = {}
    local whyOf = {}
    local function worth(qid, db)
        local ok, ratio, why = Ladder.WorthDoing(qid, player)
        if not ok and #Ladder.skippedLowValue < 40 then
            local _, now = Ladder.QuestWorth(qid, player.level)
            Ladder.skippedLowValue[#Ladder.skippedLowValue + 1] = { id = qid, title = db.name, xp = now, ratio = ratio }
        end
        whyOf[qid] = why
        return ok
    end
    -- 0.5.0: a quest against elites at your level needs a group; solo, it's left out unless it's a
    -- class quest, a gear upgrade or a must-do extra (/ladder groupquests plans them)
    local function soloOk(c)
        if not c.groupMob or not opts.skipGroupQuests then return true end
        if whyOf[c.id] == "class" or whyOf[c.id] == "upgrade" or whyOf[c.id] == "goodie" or Ladder.KeepReason(c.id, player) then
            return true
        end
        if #Ladder.skippedGroup < 20 then
            Ladder.skippedGroup[#Ladder.skippedGroup + 1] = { id = c.id, title = c.title, mob = c.groupMob, level = c.groupLevel }
        end
        return false
    end
    for _, e in ipairs(near) do
        if #out >= maxC or checked > 250 then break end
        local qid = e.questId
        if not planned[qid] and not ns.charDB.ignored[qid] then
            checked = checked + 1
            local db = Data.Quest(qid)
            if db and levelOk(db, player, green, opts.levelsAbove) then
                if Data.IsAvailableNow(qid, state) then
                    if worth(qid, db) then
                        local c = enrichCandidate(qid, e.point, player)
                        if c and not (opts.skipDungeonQuests and c.dungeon)
                            and not (opts.skipEscortsAndElites and c.escort) and soloOk(c) then
                            out[#out + 1] = c
                            planned[qid] = true
                        end
                    end
                elseif ns.Speed and #Ladder.skillUnlocks < ns.Speed.SKILL_UNLOCKS_MAX then
                    -- 0.5.0: only a profession you can learn in a minute keeps you from it
                    local skillId, skill = ns.Speed.SkillUnlock(qid, db, state)
                    if skillId and Ladder.WorthDoing(qid, player) then
                        local _, xp = Ladder.QuestWorth(qid, player.level)
                        Ladder.skillUnlocks[#Ladder.skillUnlocks + 1] = { questId = qid, title = db.name, skillId = skillId,
                                                                          skill = skill, xp = xp, point = e.point }
                    end
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
                    if db and levelOk(db, player, green, opts.levelsAbove + 1) and Data.IsAvailable(fq, chainState)
                        and worth(fq, db) then
                        local from = parent.turnin or parent.pickup or player.point
                        local pts = Data.GiverPoints(db.startedBy)
                        local start = Geo.Nearest(pts, from)
                        local d = start and Geo.Distance(from, start)
                        if start and d and d <= opts.pickupRadius * 1.5 then
                            local c = enrichCandidate(fq, start, player)
                            if c and not (opts.skipDungeonQuests and c.dungeon) and soloOk(c) then
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
    for _, c in ipairs(out) do Ladder.SetTripValue(c, whyOf[c.id], player, planned) end
    return out
end

--- What a new quest is worth for the "worth the trip" check (Planner.PruneTrips): c.tripXP =
--- its XP at your level (a solid quest's when QuestieDB doesn't know), plus the best next quest
--- in its chain when it only "leads on" and that one isn't planned yet. Class quests, gear
--- upgrades and Forever's must-do quests get c.keep (never dropped for distance).
function Ladder.SetTripValue(c, why, player, planned)
    local keep = (why == "class" or why == "upgrade" or why == "goodie") and why or Ladder.KeepReason(c.id, player)
    c.worthWhy = keep or why
    if keep then c.keep = true end
    local _, now = Ladder.QuestWorth(c.id, player.level)
    local xp = now or Data.SolidQuestXP(player.level)
    if why == "leads on" then
        local best = 0
        for _, nextId in ipairs(Data.followUps[c.id] or {}) do
            if planned[nextId] then best = 0 break end
            local _, nextXP = Ladder.QuestWorth(nextId, player.level)
            if nextXP and nextXP > best then best = nextXP end
        end
        xp = (xp or 0) + best
    end
    c.tripXP = xp
end

---------------------------------------------------------------------------
-- Outgrown quests in your log (0.4.0)
---------------------------------------------------------------------------
-- "Once my character gets to a certain level (+3 to 4) above the area's proposed quests, it may
-- be time to move on from some of my older quests." So a quest in your log OUTGROWN_LEVELS or
-- more under you joins the "worth the trip" check new quests get (Planner.PruneTrips): it stays
-- when it's on the way or its XP pays for the walk, and goes (the hint box says to abandon it
-- for log space) when the route would drag you back to an old zone for it. Classic only cuts
-- quest XP from 6 levels over, so at +3 most still pay; the check is about the travel. Class
-- quests, gear upgrades, Forever's must-do quests and timed quests always stay.
Ladder.OUTGROWN_LEVELS = 3

--- XP a quest in your log gives now: the game's figure, else QuestieDB's at your level.
local function logQuestXP(questId, level)
    if GetQuestLogRewardXP then
        local ok, v = pcall(GetQuestLogRewardXP, questId)
        if ok and type(v) == "number" and not ns.IsSecret(v) and v > 0 then return v end
    end
    local _, now = Ladder.QuestWorth(questId, level)
    return now or Data.SolidQuestXP(level)
end

--- Sets q.outgrown and q.tripXP on the quests in your log you've outgrown. `planned` is the set
--- of quest IDs already in the plan (a follow-up that's planned counts on its own).
function Ladder.MarkOutgrown(active, player, planned)
    local level = player.level or 1
    for _, q in ipairs(active) do
        q.outgrown, q.tripXP = nil, nil
        local ql = q.level
        if type(ql) ~= "number" or ns.IsSecret(ql) or ql <= 0 then
            local db = Data.Quest(q.id)
            ql = db and db.level
        end
        if type(ql) == "number" and ql > 0 and ql <= level - Ladder.OUTGROWN_LEVELS and not q.timed
            and not Ladder.KeepReason(q.id, player) then
            local xp = logQuestXP(q.id, level) or 0
            -- a chain that leads on to a quest still worth doing carries that quest's XP too
            local best = 0
            for _, nextId in ipairs(Data.followUps[q.id] or {}) do
                if planned and planned[nextId] then best = 0 break end
                local nextDb = Data.Quest(nextId)
                if nextDb and (nextDb.reqLevel or 0) <= level + 2 and Ladder.WorthDoing(nextId, player, 1) then
                    local _, nx = Ladder.QuestWorth(nextId, level)
                    if nx and nx > best then best = nx end
                end
            end
            q.outgrown, q.tripXP = true, xp + best
        end
    end
end

--- Quests in your log worth dropping when it's full and better ones are around: the ones the
--- route dropped as outgrown first, then outgrown ones you haven't started, least XP first.
--- Returns up to `n` { id, title, level, xp, why }.
function Ladder.WeakestInLog(plan, n)
    local out, seen = {}, {}
    for _, p in ipairs((plan and plan.outgrown) or {}) do
        if #out >= n then break end
        local q = p.quest or {}
        out[#out + 1] = { id = p.questId, title = p.title, level = q.level, xp = p.xp, why = "outgrown, off the route" }
        seen[p.questId] = true
    end
    local rest = {}
    for _, q in ipairs((plan and plan.active) or {}) do
        if not seen[q.id] and q.outgrown and not q.complete then
            local started = false
            for _, o in ipairs(q.objectives or {}) do
                if o.finished or (type(o.numFulfilled) == "number" and o.numFulfilled > 0) then started = true end
            end
            if not started then rest[#rest + 1] = q end
        end
    end
    table.sort(rest, function(a, b)
        if (a.tripXP or 0) ~= (b.tripXP or 0) then return (a.tripXP or 0) < (b.tripXP or 0) end
        return a.id < b.id
    end)
    for _, q in ipairs(rest) do
        if #out >= n then break end
        out[#out + 1] = { id = q.id, title = q.title, level = q.level, xp = q.tripXP, why = "outgrown, not started" }
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

Ladder.AvailabilityState = availabilityState -- for tests

---------------------------------------------------------------------------
-- Next area: where the quests worth doing are, once few are left around you
---------------------------------------------------------------------------
Ladder.FEW_GOOD_NEARBY = 5   -- fewer new quests than this near you: look further afield
Ladder.NEXT_AREA_MIN = 5     -- an area needs at least this many quests worth doing

local function zoneName(mapId)
    if not (mapId and C_Map and C_Map.GetMapInfo) then return nil end
    local ok, info = pcall(C_Map.GetMapInfo, mapId)
    if ok and type(info) == "table" and type(info.name) == "string" and not ns.IsSecret(info.name) then return info.name end
    return nil
end

--- The area on your continent (Data's 400-yard starter cells, neighbours counted together) with
--- the most quests worth doing that you could pick up, beyond the pickup radius. `planned` = quest
--- IDs already in the plan. Returns { count, zone, giver, point, seconds, mode } or nil.
function Ladder.NextArea(player, state, planned, net)
    local cont = player.point and player.point.cont
    local grid = cont ~= nil and Data.starterGrid[cont]
    if not grid then return nil end
    local opts = ns.db
    local green = QS.GreenRange(player.level)
    local verdict, cells = {}, {}
    for key, cell in pairs(grid) do
        for _, e in ipairs(cell) do
            local qid = e.questId
            local good = verdict[qid]
            if good == nil then
                good = false
                if not planned[qid] and not ns.charDB.ignored[qid] then
                    local db = Data.Quest(qid)
                    good = db ~= nil and levelOk(db, player, green, opts.levelsAbove)
                        and Data.IsAvailableNow(qid, state) and (Ladder.WorthDoing(qid, player)) or false
                end
                verdict[qid] = good
            end
            if good then
                cells[key] = cells[key] or {}
                cells[key][qid] = e.point
            end
        end
        ns.MaybeYield(20)
    end
    local best
    for key, quests in pairs(cells) do
        local cx, cy = key:match("^(-?%d+):(-?%d+)$")
        cx, cy = tonumber(cx), tonumber(cy)
        local union, byGiver = {}, {}
        local n = 0
        for dx = -1, 1 do
            for dy = -1, 1 do
                for qid, p in pairs(cells[(cx + dx) .. ":" .. (cy + dy)] or {}) do
                    if not union[qid] then
                        union[qid] = true
                        n = n + 1
                        local g = p.giverId or 0
                        byGiver[g] = byGiver[g] or { count = 0, point = p }
                        byGiver[g].count = byGiver[g].count + 1
                    end
                end
            end
        end
        local rep
        for _, g in pairs(byGiver) do
            if not rep or g.count > rep.count then rep = g end
        end
        local dist = rep and Geo.Distance(player.point, rep.point)
        if n >= Ladder.NEXT_AREA_MIN and dist and dist > opts.pickupRadius
            and (not best or n > best.count or (n == best.count and dist < best.dist)) then
            best = { count = n, point = rep.point, giver = rep.point.giverName, dist = dist }
        end
    end
    if not best then return nil end
    best.zone = zoneName(best.point.mapId)
    if net then
        local o = ns.Travel.Options(net, player.point, best.point)
        best.mode = o.pick
        best.seconds = (o.pick == "fly" and o.fly and o.fly.total) or (o.pick == "zeppelin" and o.zeppelin and o.zeppelin.total) or o.walk
    end
    return best
end

--- "12 quests worth doing in Hillsbrad Foothills (around Magistrate Burnside), ~4:10 by flight"
function Ladder.NextAreaText(area)
    local how = ""
    if area.seconds then
        local by = (area.mode == "fly" and " by flight") or (area.mode == "zeppelin" and " by zeppelin") or " on foot"
        how = ", ~" .. Ladder.Clock(area.seconds) .. by
    end
    return string.format("%d quests worth doing in %s%s%s", area.count, area.zone or "an area nearby",
        area.giver and (" (around " .. area.giver .. ")") or "", how)
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
        local tripCheck = ns.db.tripCheck and player.level < maxPlayerLevel() or nil
        if tripCheck then
            local plannedIds = {}
            for _, c in ipairs(candidates) do plannedIds[c.id] = true end
            Ladder.MarkOutgrown(active, player, plannedIds)
        end

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
        -- Other first guesses for the route (Planner: "More than one first guess"). With walking
        -- only they'd all be the same route.
        local seeds
        if ns.db.useFlights and ns.Travel.HasFlights(net) then
            seeds = {
                { name = "flights at full time", travel = ns.Travel.NewCost(net, 1.0) },
                { name = "walking only", travel = walkOnly },
            }
        end

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
            -- new quests must earn their detour (Planner.PruneTrips); XP means nothing at max level
            tripCheck = tripCheck,
            seeds = seeds,
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

        -- few quests worth doing left around you (after the ones not worth the trip are out):
        -- say where the next good area is
        local nextArea
        local fresh, planned, prunedId = 0, {}, {}
        for _, p in ipairs(plan.pruned or {}) do prunedId[p.questId] = true end
        for _, q in ipairs(active) do planned[q.id] = true end
        for _, c in ipairs(candidates) do
            if not prunedId[c.id] then
                planned[c.id] = true
                if not c.chainedFrom then fresh = fresh + 1 end
            end
        end
        if Data.ready and fresh < Ladder.FEW_GOOD_NEARBY and ns.db.includeUnstarted then
            nextArea = Ladder.NextArea(player, state, planned, ns.db.useFlights and net or { nodes = {}, speed = net.speed })
        end

        plan.player = player
        plan.logCount, plan.logMax = ctx.logCount, ctx.logMax
        plan.candidates = candidates
        plan.nextArea = nextArea
        plan.skippedLowValue = Ladder.skippedLowValue
        plan.skippedGroup = Ladder.skippedGroup
        plan.skillUnlocks = Ladder.skillUnlocks
        -- Forever extras worked out once per plan (the hint box reads them every second)
        if ns.Goodies and Data.ready then
            plan.bagToBuy = ns.Goodies.BagToBuy(player)
            plan.cozyStart = ns.Goodies.CozyStart(player, byId, state)
        end
        -- 0.5.0: named mobs near the route whose drop starts a quest worth doing
        if ns.Speed and Data.ready and ns.db.includeUnstarted then
            plan.watchFor = ns.Speed.WatchFor(plan, player, state, byId)
        end
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
    -- a timed quest goes first: no hearth, inn or flight-path detour before it's done
    local rushUntil = ns.Planner.LastUrgent(order)

    -- 1) Hearth-aware route with your current inn (only kept when it really pays off).
    local hearth, why
    if ns.db.useHearth then
        hearth, why = Travel.HearthAware(order, start, net, cost, { logCount = logCount, logMax = logMax,
                                                                     minK = rushUntil > 0 and rushUntil or nil })
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
                for i, d in ipairs(detours) do
                    if i > rushUntil and (not detour or d < detour) then k, detour = i, d end
                end
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
            local rushStep = 0
            for i, s in ipairs(plan.steps) do
                for _, t in ipairs(s.tasks) do if t.urgent then rushStep = i end end
            end
            local list = Travel.SuggestDiscoveries(plan.steps, start, net, cost, Travel.DISCOVER_MAX_DETOUR, taken)
            local pick
            for _, p in ipairs(list) do
                if p.index > rushStep then pick = p break end
            end
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

    -- 3b) 0.5.0: grind here first when the plan would send you on under-levelled
    plan.grindStop = nil
    if ns.Speed and player.level < maxPlayerLevel() then
        local k, task = ns.Speed.GrindStop(plan, player)
        if k then
            plan.steps = Travel.WithInserted(plan.steps, k, stopStep(task))
            plan.grindStop = task
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
    -- 0.5.0: or die on purpose, when the graveyard you'd appear at is next to where you're going
    local Speed = ns.Speed
    if Speed and ns.db.deathTravel and o.walkable then
        local best = (out.mode == "fly" and out.fly and out.fly.total)
            or (out.mode == "zeppelin" and out.zeppelin and out.zeppelin.total) or out.walk
        if best and best >= Speed.DEATH_MIN_WAY then
            local level = (plan.player and plan.player.level) or 1
            local die = Speed.DeathOption(plan.net, here, step.loc, level, Speed.CalmSeconds(plan, step.index, plan.net))
            if Speed.DeathWorthIt(die, best) then out.die, out.dieVs = die, best end
        end
    end
    return out
end

local function clock(seconds)
    seconds = math.max(0, math.floor((seconds or 0) + 0.5))
    return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end
Ladder.Clock = clock

--- "5:10 of travel", or with an escort "1:10 of travel and 4:00 of escorting".
function Ladder.TripTimeText(p)
    local extra = p.extra or 0
    if extra <= 0 then return clock(p.seconds) .. " of travel" end
    local travel = math.max(0, (p.seconds or 0) - extra)
    if travel < 1 then return clock(extra) .. " of escorting" end
    return string.format("%s of travel and %s of escorting", clock(travel), clock(extra))
end

--- /ladder skipped: the new quests the plan leaves out, and why. Returns the lines (for tests).
function Ladder.SkippedLines(plan)
    plan = plan or Ladder.plan
    local lines = {}
    if not plan then return { "no plan yet" } end
    local pruned = plan.pruned or {}
    local level = plan.player and plan.player.level
    if #pruned > 0 then
        lines[#lines + 1] = string.format("Not worth the walk from here (%d):", #pruned)
        for _, p in ipairs(pruned) do
            local grind = level and ns.Planner.GrindRate(level) * (p.seconds or 0)
            lines[#lines + 1] = string.format("  %s - %s XP%s, but adds %s (killing mobs that long gives ~%s XP)",
                tostring(p.title or p.questId), p.xp and tostring(math.floor(p.xp + 0.5)) or "?",
                (p.together or 1) > 1 and string.format(" (%d quests out there together: %d XP)", p.together,
                    math.floor((p.groupXP or 0) + 0.5)) or "",
                Ladder.TripTimeText(p), grind and tostring(math.floor(grind + 0.5)) or "?")
        end
    end
    local group = plan.skippedGroup or {}
    if #group > 0 then
        lines[#lines + 1] = string.format("Needs a group (%d) - /ladder groupquests plans them:", #group)
        for _, s in ipairs(group) do
            lines[#lines + 1] = string.format("  %s - %s%s is elite", tostring(s.title or s.id), tostring(s.mob or "its target"),
                s.level and (" (lvl " .. s.level .. ")") or "")
        end
    end
    local outgrown = plan.outgrown or {}
    if #outgrown > 0 then
        lines[#lines + 1] = string.format("Outgrown, in your log but not worth the trip any more (%d) - abandon them to free log space:", #outgrown)
        for _, p in ipairs(outgrown) do
            local q = p.quest or {}
            local grind = level and ns.Planner.GrindRate(level) * (p.seconds or 0)
            lines[#lines + 1] = string.format("  %s%s - %s XP%s, but %s of travel (killing mobs that long gives ~%s XP)",
                tostring(p.title or p.questId), q.level and (" [" .. q.level .. "]") or "",
                p.xp and tostring(math.floor(p.xp + 0.5)) or "?",
                (p.together or 1) > 1 and string.format(" (%d quests out there together: %d XP)", p.together,
                    math.floor((p.groupXP or 0) + 0.5)) or "",
                clock(p.seconds), grind and tostring(math.floor(grind + 0.5)) or "?")
        end
    end
    if plan.logCount and plan.logMax and plan.logCount >= plan.logMax - 1 then
        local weak = Ladder.WeakestInLog(plan, 5)
        if #weak > 0 then
            lines[#lines + 1] = string.format("Your log is %d/%d. Weakest to drop first:", plan.logCount, plan.logMax)
            for _, w in ipairs(weak) do
                lines[#lines + 1] = string.format("  %s%s - %s XP, %s", tostring(w.title or w.id), w.level and (" [" .. w.level .. "]") or "",
                    w.xp and tostring(math.floor(w.xp + 0.5)) or "?", w.why)
            end
        end
    end
    local low = plan.skippedLowValue or {}
    if #low > 0 then
        lines[#lines + 1] = string.format("Too little XP for your level (%d):", #low)
        for i, s in ipairs(low) do
            if i > 15 then lines[#lines + 1] = "  ..." break end
            lines[#lines + 1] = string.format("  %s - %s XP (%s%% of a solid quest)", tostring(s.title or s.id),
                s.xp and tostring(math.floor(s.xp + 0.5)) or "?", s.ratio and tostring(math.floor(s.ratio * 100 + 0.5)) or "?")
        end
    end
    if #lines == 0 then
        lines[1] = "nothing skipped: every quest in reach is in the plan"
    else
        lines[#lines + 1] = "/ladder trips turns the distance check off, /ladder minxp 0 the XP one."
    end
    return lines
end

--- 0.4.0: take it or leave it, for a quest an NPC offers you (the hint box shows it while the
--- dialog is open, so you don't have to weigh every quest yourself). Returns take (true/false),
--- the reason, and the quest's name; nil when there's nothing to say.
function Ladder.QuestVerdict(questId)
    if type(questId) ~= "number" or ns.IsSecret(questId) or questId <= 0 then return nil end
    local plan = Ladder.plan
    local db = Data.Quest(questId)
    local title = (db and db.name) or ("quest " .. questId)
    for i, s in ipairs((plan and plan.steps) or {}) do
        for _, t in ipairs(s.tasks or {}) do
            if t.kind == "pickup" and t.questId == questId then
                return true, string.format("on your route (step %d)", i), title
            end
        end
    end
    if ns.charDB.ignored[questId] then
        return false, string.format("you dropped it before (/ladder unignore %d plans it again)", questId), title
    end
    if not db then return nil end
    local player = (plan and plan.player) or QS.Player()
    local level = player.level or 1
    local opts = ns.db
    local ql = (db.level and db.level > 0) and db.level or level
    if ql > level + (opts.levelsAbove or 2) then
        return false, string.format("level %d is too high for now (you're %d)", ql, level), title
    end
    if ql < level - QS.GreenRange(level) then
        return false, string.format("grey for you (level %d): next to no XP", ql), title
    end
    for _, p in ipairs((plan and plan.pruned) or {}) do
        if p.questId == questId then
            return false, string.format("not worth the walk: %s XP for %s", p.xp and tostring(math.floor(p.xp + 0.5)) or "?",
                Ladder.TripTimeText(p)), title
        end
    end
    for _, s in ipairs((plan and plan.skippedLowValue) or {}) do
        if s.id == questId then
            return false, string.format("too little XP for your level (%s)", s.xp and tostring(math.floor(s.xp + 0.5)) or "?"), title
        end
    end
    if opts.skipDungeonQuests and ns.Goodies and ns.Goodies.IsDungeonQuest(db) then
        return false, "its objectives are inside a dungeon (/ladder dungeons plan to plan those)", title
    end
    if opts.skipEscortsAndElites and isEscort(db) then return false, "an escort or elite quest", title end
    for _, s in ipairs((plan and plan.skippedGroup) or {}) do
        if s.id == questId then
            return false, string.format("needs a group: %s%s is elite (/ladder groupquests plans these)", tostring(s.mob or "its target"),
                s.level and (" (lvl " .. s.level .. ")") or ""), title
        end
    end
    for _, u in ipairs((plan and plan.skillUnlocks) or {}) do
        if u.questId == questId then
            return false, string.format("needs %s: learn it at a %s trainer first", u.skill, u.skill), title
        end
    end
    if plan and plan.logCount and plan.logMax and plan.logCount >= plan.logMax then
        return false, string.format("your quest log is full (%d/%d) - /ladder outgrown says what to drop", plan.logCount, plan.logMax), title
    end
    if Ladder.WorthDoing(questId, player) then
        return true, "worth its XP but not planned yet: take it and the route adds it", title
    end
    return false, "too little XP for your level", title
end

--- Timed quests in your log, soonest out first: { questId, title, left (seconds, nil when only
--- the quest text says there's a clock), itemId, to (turn-in NPC), done }. Counts down every
--- second from when the game's timer was read.
function Ladder.TimedQuests(now)
    now = now or (GetTime and GetTime()) or 0
    local out = {}
    for _, q in ipairs((Ladder.plan and Ladder.plan.active) or {}) do
        if q.timed and not q.deferred then
            local live = Ladder.snapshot and Ladder.snapshot[q.id]
            if live or not Ladder.snapshot then -- still in your log
                local timer = (live and live.timer) or q.timer
                local left = timer and (timer.total - timer.elapsed - (now - (timer.readAt or now))) or nil
                out[#out + 1] = { questId = q.id, title = q.title, left = left, itemId = q.timedItem,
                                  to = q.turninName, done = (live and live.complete) or q.complete }
            end
        end
    end
    table.sort(out, function(a, b) return (a.left or math.huge) < (b.left or math.huge) end)
    return out
end

local WATCH = "|TInterface\\Icons\\INV_Misc_PocketWatch_01:14|t "
Ladder.TIMER_RED_SECONDS = 120

--- "[watch] Timed: Apothecary Zamah - 23:41 left - bring [Rendered Spores] to Apothecary Zamah (it goes first)"
function Ladder.TimerText(e)
    local item = e.itemId and (Data.ItemName(e.itemId)
        or (C_Item and C_Item.GetItemNameByID and select(2, pcall(C_Item.GetItemNameByID, e.itemId))))
    if type(item) ~= "string" or ns.IsSecret(item) then item = nil end
    local to = e.to or "the quest giver"
    local what
    if e.done then
        what = item and ("bring |cffffffff[" .. item .. "]|r to " .. to) or ("turn it in to " .. to)
    else
        what = "finish it" .. (item and (" (|cffffffff[" .. item .. "]|r)") or "") .. " and turn it in to " .. to
    end
    local left
    if e.left == nil then
        left = "see the timer in your quest log"
    elseif e.left <= 0 then
        left = "|cffff5555time's up|r"
    else
        left = ((e.left < Ladder.TIMER_RED_SECONDS) and "|cffff5555" or "|cffffffff") .. clock(e.left) .. "|r left"
    end
    return string.format("%s|cffff8800Timed:|r |cffffd200%s|r - %s - %s (it goes first)", WATCH, tostring(e.title), left, what)
end

function Ladder.PrintSkipped()
    local lines = Ladder.SkippedLines()
    ns.Print(lines[1])
    for i = 2, #lines do print(lines[i]) end
end

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
        if t.visit == "grind" then return ns.Speed ~= nil and ns.Speed.ReachedLevel(t.targetLevel) end
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

--- 0.4.1: the arrow to Blizzard's map pin is the game's "In-Game Navigation" marker, and on clients
--- that have the setting (CVar showInGameNavigation) it can be off. Then the pin is on the map with
--- no arrow on screen. Forever's settings don't offer it and the game reports no such CVar, so
--- there this never speaks up. TomTom's arrow doesn't depend on it.
function Ladder.InGameNavigationOff()
    local get = (C_CVar and C_CVar.GetCVar) or GetCVar
    local ok, value = pcall(get, "showInGameNavigation")
    return ok and not ns.IsSecret(value) and value == "0" or false
end

--- Say so once per session, the first time a pin goes on the map (nothing is changed for you).
function Ladder.NoticeNoArrow()
    if Ladder.toldNoArrow or not Ladder.InGameNavigationOff() then return end
    Ladder.toldNoArrow = true
    ns.Print("the game's In-Game Navigation setting is off, so the map pin has no arrow on screen. "
        .. "Type /console showInGameNavigation 1 to turn it on (or install TomTom for its arrow)")
end

--- 0.3.29: a pin somewhere other than the current step, from clicking a hint line (where the
--- Cozy Sleeping Bag chain starts, a bag vendor, the riding trainer). Same pin as the route's:
--- the map's own waypoint with its arrow, or a TomTom arrow. The route's pin comes back when you
--- move on to the next step. Returns true when a pin was placed.
local extraUid
function Ladder.PinTo(loc, title)
    if not (loc and loc.mapId and loc.x and loc.y) then return false end
    local label = "Quest Ladder: " .. (title or "pin")
    if TomTom and TomTom.AddWaypoint then
        if extraUid and TomTom.RemoveWaypoint then pcall(TomTom.RemoveWaypoint, TomTom, extraUid) end
        local ok, uid = pcall(TomTom.AddWaypoint, TomTom, loc.mapId, loc.x, loc.y,
            { title = label, persistent = false, minimap = true, world = true, crazy = true })
        if ok then extraUid = uid end
        return ok
    end
    if not (C_Map and C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates) then return false end
    if C_Map.CanSetUserWaypointOnMap then
        local okC, can = pcall(C_Map.CanSetUserWaypointOnMap, loc.mapId)
        if okC and not can then return false end
    end
    local okP, point = pcall(UiMapPoint.CreateFromCoordinates, loc.mapId, loc.x, loc.y)
    if not okP or not point then return false end
    local ok = pcall(C_Map.SetUserWaypoint, point)
    if ok and C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
        pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, true)
    end
    if ok then
        Ladder.NoticeNoArrow()
        Ladder.OurPinPlaced(loc)
    end
    return ok
end

--- Clicking a hint line that names a place: pin it, and say where in chat.
function Ladder.PinHint(h)
    local pin = h and h.pin
    if not pin then return false end
    local ok = Ladder.PinTo(pin, pin.title)
    local where = ns.Goodies and ns.Goodies.PlaceText and ns.Goodies.PlaceText(pin)
    if ok then
        ns.Print(string.format("map pin placed on %s%s - the route's pin comes back at the next step", pin.title or "the spot",
            where and (" (" .. where .. ")") or ""))
    else
        ns.Print(string.format("couldn't place a map pin there%s", where and (" (" .. where .. ")") or ""))
    end
    return ok
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
        local ok = pcall(C_Map.SetUserWaypoint, UiMapPoint.CreateFromCoordinates(loc.mapId, loc.x, loc.y))
        if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
            pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, true)
        end
        if ok then
            Ladder.NoticeNoArrow()
            Ladder.OurPinPlaced(loc)
        end
    end
end

---------------------------------------------------------------------------
-- 0.5.0: unhide Blizzard's arrow to Quest Ladder's pin
---------------------------------------------------------------------------
-- On Forever, Blizzard's navigation rated a pin 5,300 yards away "Invalid", and its arrow frame
-- (SuperTrackedFrame) draws an Invalid target fully see-through, although the frame was placed,
-- on screen, and its edge arrow pointed the right way (diag 2026-11-22; the user's own pin too).
-- The user chose to have Quest Ladder show it, for the pins Quest Ladder places: a hook that runs
-- after the frame's own UpdateAlpha (hooksecurefunc: Blizzard's code and values stay untouched)
-- makes it visible while the target is rated Invalid, has a screen position, and the tracked pin
-- is ours. The user's own pins and tracked quests look as Blizzard draws them. /ladder arrow
-- turns it off. Display only.
Ladder.lastPin, Ladder.ourPinTracked, Ladder.arrowHooked = nil, false, false
Ladder.PIN_SAME = 0.002

--- The user waypoint as plain numbers: mapId, x, y (nil when there is none or it's secret).
local function userWaypoint()
    if not (C_Map and C_Map.GetUserWaypoint) then return nil end
    local ok, wp = pcall(C_Map.GetUserWaypoint)
    if not ok or type(wp) ~= "table" or ns.IsSecret(wp) then return nil end
    local pos, x, y = wp.position, nil, nil
    if type(pos) == "table" and not ns.IsSecret(pos) then
        if pos.GetXY then
            local okXY, px, py = pcall(pos.GetXY, pos)
            if okXY then x, y = px, py end
        else
            x, y = pos.x, pos.y
        end
    end
    if ns.AnySecret(wp.uiMapID, x, y) or type(x) ~= "number" or type(y) ~= "number" then return nil end
    return wp.uiMapID, x, y
end

--- Is the tracked pin the one Quest Ladder placed last? (re-checked when the pin or tracking changes)
function Ladder.RefreshOurPin()
    local pin, tracked = Ladder.lastPin, false
    if pin then
        local mapId, x, y = userWaypoint()
        if mapId == pin.mapId and math.abs(x - pin.x) < Ladder.PIN_SAME and math.abs(y - pin.y) < Ladder.PIN_SAME
            and C_SuperTrack and C_SuperTrack.IsSuperTrackingUserWaypoint then
            local okT, t = pcall(C_SuperTrack.IsSuperTrackingUserWaypoint)
            tracked = okT and not ns.IsSecret(t) and t == true
        end
    end
    Ladder.ourPinTracked = tracked
    return tracked
end

function Ladder.OurPinPlaced(loc)
    Ladder.lastPin = { mapId = loc.mapId, x = loc.x, y = loc.y }
    Ladder.HookNavigationArrow()
    Ladder.RefreshOurPin()
end

--- Runs after Blizzard's arrow frame sets its alpha.
function Ladder.ArrowAlphaHook(frame)
    if not (ns.db.unhideArrow and Ladder.ourPinTracked and C_Navigation and C_Navigation.GetTargetState) then return end
    local invalid = (Enum and Enum.NavigationState and Enum.NavigationState.Invalid) or 0
    local okS, state = pcall(C_Navigation.GetTargetState)
    if not okS or ns.IsSecret(state) or state ~= invalid then return end
    if C_Navigation.HasValidScreenPosition then
        local okV, onScreen = pcall(C_Navigation.HasValidScreenPosition)
        if not okV or ns.IsSecret(onScreen) or onScreen ~= true then return end
    end
    if type(frame) == "table" and frame.SetAlpha then pcall(frame.SetAlpha, frame, 1) end
end

function Ladder.HookNavigationArrow()
    if Ladder.arrowHooked then return true end
    local f = _G.SuperTrackedFrame
    if type(f) ~= "table" or type(f.UpdateAlpha) ~= "function" or not hooksecurefunc then return false end
    Ladder.arrowHooked = pcall(hooksecurefunc, f, "UpdateAlpha", Ladder.ArrowAlphaHook) and true or false
    return Ladder.arrowHooked
end

ns.RegisterEvent("USER_WAYPOINT_UPDATED", function() Ladder.RefreshOurPin() end)
ns.RegisterEvent("SUPER_TRACKING_CHANGED", function() Ladder.RefreshOurPin() end)
ns.RegisterEvent("ADDON_LOADED", function(_, name)
    if name == "Blizzard_QuestNavigation" then Ladder.HookNavigationArrow() end
end)

---------------------------------------------------------------------------
-- Text for the UI
---------------------------------------------------------------------------
local VERB = { monster = "Kill", item = "Loot", object = "Use", event = "Go to", reputation = "Reputation" }

--- XP a quest gives you now: the game's figure for quests in your log, else QuestieDB's.
function Ladder.QuestXPNow(questId)
    if not questId then return nil end
    if GetQuestLogRewardXP then -- 0 for quests not in your log: then QuestieDB's figure is used
        local ok, v = pcall(GetQuestLogRewardXP, questId)
        if ok and type(v) == "number" and not ns.IsSecret(v) and v > 0 then return v end
    end
    local level = (Ladder.plan and Ladder.plan.player and Ladder.plan.player.level) or 1
    local _, now = Ladder.QuestWorth(questId, level)
    return now
end

local function xpText(questId)
    local xp = Ladder.QuestXPNow(questId)
    if not xp or xp <= 0 then return "" end
    return string.format(" |cff888888(+%d XP)|r", math.floor(xp + 0.5))
end

local function goodieText(questId)
    local note = ns.Goodies and ns.Goodies.MustDo(questId)
    return note and (" |cff66ccff[" .. note .. "]|r") or ""
end

function Ladder.TaskText(t)
    local q = t.quest
    local title = q and (q.title or ("Quest " .. t.questId)) or ""
    if t.kind == "pickup" then
        if q.pickup and q.pickup.foundItem then
            -- a quest that starts from an item lying here (a Library book, a note)
            return string.format("Pick up |cffffd100%s|r here and right-click it to start |cffffd100%s|r%s%s",
                q.pickupName or "the item", title, xpText(t.questId), goodieText(t.questId))
        end
        return string.format("Accept |cffffd100%s|r%s%s%s", title, q.pickupName and (" from " .. q.pickupName) or "",
            xpText(t.questId), goodieText(t.questId))
    elseif t.kind == "turnin" then
        local pick = t.rewardPick and (" - pick |cff00ff00" .. t.rewardPick .. "|r") or ""
        if q.useFirst and ns.Hints and ns.Hints.ItemCount(q.useFirst) > 0 then
            return string.format("Use |cff66ccff[%s]|r%s, then turn in |cffffd100%s|r%s%s", ns.Hints.ItemName(q.useFirst),
                q.turninName and (" on " .. q.turninName) or "", title, xpText(t.questId), pick)
        end
        return string.format("Turn in |cffffd100%s|r%s%s%s", title, q.turninName and (" to " .. q.turninName) or "",
            xpText(t.questId), pick)
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
            local color = ((lvl and o.mobLevel >= lvl + 2) or o.elite) and "|cffff8800" or "|cff888888"
            where = where .. string.format(" %s(lvl %d%s)|r", color, o.mobLevel, o.elite and " elite" or "")
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
    Ladder.HookNavigationArrow()
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

---------------------------------------------------------------------------
-- Abandoned quests aren't suggested again
---------------------------------------------------------------------------
-- Abandoning is how you skip a quest in your log, but an abandoned quest can be picked up again,
-- so it came straight back as a new quest to fetch (0.3.25: old quest lines dropped after the
-- Zamah run). Removed from the log without being turned in = abandoned: it joins the ignored list
-- (like /ladder skip on a pickup). Not when it had failed (the hint box says to abandon those and
-- pick them up again). Accept it again and it's planned as usual; /ladder unignore <id> undoes it.
-- The list is saved with your character, so after Forever's cold-start SavedVariables bug it may
-- come back empty: then those quests are simply suggested again.
Ladder.ABANDON_CHECK_DELAY = 1.5
Ladder.turnedIn = {}

--- A quest left your log. `known` = its last snapshot entry (nil if it wasn't in the log we saw).
--- Returns true when it was taken as abandoned.
function Ladder.NoteRemoved(questId, known)
    if type(questId) ~= "number" or ns.IsSecret(questId) or not known then return false end
    if Ladder.turnedIn[questId] or known.failed then return false end
    if C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted then
        local ok, done = pcall(C_QuestLog.IsQuestFlaggedCompleted, questId)
        if ok and done == true and not ns.IsSecret(done) then return false end
    end
    if ns.charDB.ignored[questId] then return false end
    ns.charDB.ignored[questId] = true
    ns.charDB.deferred[questId] = nil
    ns.Print("abandoned %s: it won't be suggested again (/ladder unignore %d to undo)", tostring(known.title or questId), questId)
    return true
end

ns.RegisterEvent("QUEST_LOG_UPDATE", onLogUpdate)
ns.RegisterEvent("QUEST_ACCEPTED", function(_, a, b)
    -- Forever/Mainline pass (questId); Classic passed (questLogIndex, questId).
    local questId = b or a
    if type(questId) == "number" and not ns.IsSecret(questId) then
        ns.charDB.ignored[questId] = nil -- picked up again: you want it after all
        Ladder.turnedIn[questId] = nil
    end
    requestReplan("accepted", 1.0)
end)
ns.RegisterEvent("QUEST_TURNED_IN", function(_, questId)
    if type(questId) == "number" and not ns.IsSecret(questId) then Ladder.turnedIn[questId] = true end
    requestReplan("turned in", 1.0)
end)
ns.RegisterEvent("QUEST_REMOVED", function(_, questId)
    local known = type(questId) == "number" and not ns.IsSecret(questId) and Ladder.snapshot and Ladder.snapshot[questId] or nil
    if known then
        -- the turn-in event can come just after the removal: decide a moment later
        local function decide() if Ladder.NoteRemoved(questId, known) then requestReplan("abandoned", 0.1) end end
        if C_Timer and C_Timer.After then C_Timer.After(Ladder.ABANDON_CHECK_DELAY, decide) else decide() end
    end
    requestReplan("removed", 1.0)
end)
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
-- 0.5.0: a "Grind first" stop ends when the bar gets there
ns.RegisterEvent("PLAYER_XP_UPDATE", function()
    if Ladder.plan and Ladder.plan.grindStop and not Ladder.plan.grindStop.isDone then onLogUpdate() end
end)
ns.On("REQUEST_REPLAN", function(reason)
    if reason == "bind changed" and Ladder.plan and Ladder.plan.byId["V:bind"] then
        Ladder.plan.byId["V:bind"].done = true
    end
end)
ns.RegisterEvent("BAG_UPDATE_DELAYED", function() ns.Debounce("bags", 1.0, function() ns.Fire("BAGS_CHANGED") end) end)
