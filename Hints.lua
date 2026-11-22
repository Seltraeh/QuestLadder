-- Quest Ladder: "don't forget" hints for people who skip quest text.
--
-- Event-driven reminders (created when a quest is accepted) plus rules evaluated every second:
--   * items that start quests sitting in your bags
--   * quest items you need to right-click / use
--   * items the quest giver handed you
--   * objectives sitting right next to the quest giver ("grab the book before leaving")
--   * a warning when you walk away without them
--   * Questie's hidden-objective notes, escorts, timers, turn-ins right next to you
--   * bag space and reward picks from the planner

local _, ns = ...
local Hints = {}
ns.Hints = Hints

local Geo, Data = ns.Geo, ns.Data

Hints.NEARBY_YARDS = 70      -- objective counts as "right here" at the quest giver
Hints.LEAVING_YARDS = 110    -- walked away without the item
Hints.MAX_SHOWN = 4

Hints.reminders = {}  -- key -> reminder
Hints.list = {}       -- current computed hints, sorted

---------------------------------------------------------------------------
-- Item helpers
---------------------------------------------------------------------------
local function itemName(itemId)
    if C_Item and C_Item.GetItemNameByID then
        local n = C_Item.GetItemNameByID(itemId)
        if n then return n end
    end
    return Data.ItemName(itemId) or ("item " .. tostring(itemId))
end
Hints.ItemName = itemName

local function itemIsUsable(itemId)
    if C_Item and C_Item.GetItemSpell then
        local ok, spellName = pcall(C_Item.GetItemSpell, itemId)
        if ok and spellName then return true end
    end
    return false
end
Hints.ItemIsUsable = itemIsUsable

local function itemCount(itemId)
    if C_Item and C_Item.GetItemCount then
        local ok, n = pcall(C_Item.GetItemCount, itemId)
        if ok and n then return n end
    end
    return 0
end

Hints.ItemCount = itemCount

local function colorItem(name) return "|cff66ccff[" .. name .. "]|r" end
local function colorQuest(name) return "|cffffd100" .. (name or "quest") .. "|r" end

---------------------------------------------------------------------------
-- Items you have to use (not just carry) for a quest
---------------------------------------------------------------------------
--- Usable quest items in your bags, by the quests QuestieDB relates them to: { [questId] = {itemId...} }.
--- Quest-starting items are left out (they get their own hint).
function Hints.BagUseItems(bags)
    local out = {}
    for _, s in ipairs((bags and bags.slots) or {}) do
        local qi = s.questInfo
        if qi and qi.isQuestItem and not (qi.questID and qi.questID > 0) and itemIsUsable(s.itemId) then
            for _, qid in ipairs(Data.Item(s.itemId, "relatedQuests") or {}) do
                out[qid] = out[qid] or {}
                table.insert(out[qid], s.itemId)
            end
        end
    end
    return out
end

--- Items in your bags with a "Use:" effect that quest `questId` needs you to use, best first:
--- the game's special item, QuestieDB's required source items, the item the quest giver gave you,
--- then related quest items in your bags. Items you collect for the quest are left out.
function Hints.UseItemsFor(questId, q, bagUse)
    local list, seen = {}, {}
    local db = Data.Quest(questId)
    local collect = {}
    for _, row in ipairs((db and db.objectives and db.objectives[3]) or {}) do collect[row[1]] = true end
    -- `trusted`: the game's own special item (it only reports one you carry, and it's usable)
    local function add(itemId, trusted)
        if not itemId or itemId == 0 or seen[itemId] or collect[itemId] then return end
        if not trusted and (itemCount(itemId) <= 0 or not itemIsUsable(itemId)) then return end
        seen[itemId] = true
        list[#list + 1] = itemId
    end
    if q and q.specialItem then add(q.specialItem.itemId, true) end
    if db then
        for _, itemId in ipairs(db.requiredSourceItems or {}) do add(itemId) end
        add(db.sourceItemId)
    end
    for _, itemId in ipairs((bagUse and bagUse[questId]) or {}) do add(itemId) end
    return list
end

--- Who to use it on, for the step's task of that quest (the turn-in NPC, or the objective's NPC).
function Hints.UseTarget(t)
    if t.kind == "turnin" then return t.quest and t.quest.turninName end
    local npcs = t.obj and t.obj.targets and t.obj.targets.npc
    if npcs and npcs[1] then return Data.NpcName(npcs[1]) end
    return nil
end

---------------------------------------------------------------------------
-- When the use button shows a quest item
---------------------------------------------------------------------------
-- 0.3.25: the button showed Dried Seeds in Stonetalon, 4,000 yards from the Stagnant Oasis: any
-- quest item in your log could reach it. Now it's only an item for the step you're on, and only
-- once you've selected what it's used on (targeted it, or you're facing it), or you're standing
-- at it: some targets can't be selected (the oasis spot is an invisible marker), so within
-- USE_AT_YARDS of where QuestieDB has it counts too. With nothing to aim at known, being within
-- USE_NEAR_YARDS of the step's place does. Until then the hint box says what to select.
-- 0.3.26: going somewhere out of order works too. A quest further down the ladder gets its item
-- on the button by the same rule (selected, or standing at it), just below this step's item, and
-- never a "Select" hint: from afar, a later step's item stays out of the way.
-- 0.3.28: an item for what you've selected comes before one you're only standing near (99/98
-- vs 92/91), and when you face it, its line replaces the world-marker "press Interact" cue.
Hints.USE_AT_YARDS = 40
Hints.USE_NEAR_YARDS = 60

--- Which tasks of each quest the use button looks at. `now[questId]` is this step's unfinished
--- tasks; a quest with none here gets its unfinished tasks further down the ladder in
--- `later[questId]`, and the first step they're on in `at[questId]`.
function Hints.UseTasks(plan, step)
    local now, later, at = {}, {}, {}
    for _, t in ipairs((step and step.tasks) or {}) do
        if t.questId and not t.isDone then
            now[t.questId] = now[t.questId] or {}
            table.insert(now[t.questId], t)
        end
    end
    for i, s in ipairs((plan and plan.steps) or {}) do
        if s ~= step then
            for _, t in ipairs(s.tasks or {}) do
                local qid = t.questId
                if qid and not t.isDone and not now[qid] then
                    later[qid] = later[qid] or {}
                    table.insert(later[qid], t)
                    at[qid] = at[qid] or s.index or i
                end
            end
        end
    end
    return now, later, at
end

--- What a quest's item is used on, from this step's tasks of that quest: the objective's NPCs and
--- objects, Questie's "use it on" notes, and the turn-in NPC when using the item is the whole
--- quest. Returns { npc = {[id] = true}, object = {[id] = true}, names = {...} } or nil.
function Hints.UseTargets(tasks)
    local out = { npc = {}, object = {}, names = {} }
    local any = false
    local function add(kind, id)
        if type(id) ~= "number" or id <= 0 or out[kind][id] then return end
        out[kind][id] = true
        any = true
        local name = (kind == "npc") and Data.NpcName(id) or Data.ObjectName(id)
        if type(name) == "string" and name ~= "" then out.names[#out.names + 1] = name end
    end
    for _, t in ipairs(tasks or {}) do
        if t.kind == "objective" and t.obj and t.obj.targets then
            for _, id in ipairs(t.obj.targets.npc or {}) do add("npc", id) end
            for _, id in ipairs(t.obj.targets.object or {}) do add("object", id) end
        elseif t.kind == "turnin" and t.loc and t.loc.giverId then
            if t.loc.giverId > 0 then add("npc", t.loc.giverId) else add("object", -t.loc.giverId) end
        end
        local db = t.quest and t.quest.db
        for _, row in ipairs((db and db.extraObjectives) or {}) do
            for _, ref in ipairs(row[5] or {}) do
                if ref[1] == "monster" then add("npc", ref[2]) elseif ref[1] == "object" then add("object", ref[2]) end
            end
        end
    end
    return any and out or nil
end

--- Is it time to show the item? Returns ready, the name of what's selected (if anything), and
--- which of "target" / "softinteract" picked it ({ [unit] = name or true }, nil when you're
--- only standing at it).
function Hints.UseReady(targets, tasks, point)
    if targets then
        local WM = ns.WorldMarks
        local name, units
        for _, sel in ipairs((WM and WM.Selected and WM.Selected()) or {}) do
            local set = (sel.kind == "GameObject") and targets.object or targets.npc
            if sel.id and set[sel.id] then
                name = name or sel.name
                units = units or {}
                units[sel.unit or "target"] = sel.name or true
            end
        end
        if units then return true, name, units end
        if point then
            for kind, set in pairs({ npc = targets.npc, object = targets.object }) do
                for id in pairs(set) do
                    local pts = (kind == "npc") and Data.NpcPoints(id) or Data.ObjectPoints(id)
                    local _, d = Geo.Nearest(pts or {}, point)
                    if d and d <= Hints.USE_AT_YARDS then return true, nil end
                end
            end
        end
        return false
    end
    if not point then return false end
    for _, t in ipairs(tasks or {}) do
        local d = t.loc and Geo.Distance(point, t.loc)
        if d and d <= Hints.USE_NEAR_YARDS then return true, nil end
    end
    return false
end

--- How to use the button: its key when you've bound one, else click it.
function Hints.UseHow()
    local ok, key = pcall(function() return GetBindingKey and GetBindingKey("CLICK QuestLadderUseButton:LeftButton") end)
    if ok and type(key) == "string" and key ~= "" and not ns.IsSecret(key) then return "press " .. key end
    return "click the use button"
end

---------------------------------------------------------------------------
-- Reminders created on quest accept
---------------------------------------------------------------------------
local function addReminder(key, r)
    r.key = key
    r.created = GetTime and GetTime() or 0
    Hints.reminders[key] = r
end

--- Called on QUEST_ACCEPTED. `here` is the player's position at that moment
--- (standing at the quest giver).
function Hints.OnQuestAccepted(questId, here)
    local db = Data.Quest(questId)
    if not db then return end
    local title = db.name

    -- 1) The quest giver handed you an item. Where to use it comes later (Dried Seeds go to the
    -- bottom of the Stagnant Oasis), so this only says so; the use button waits for the step.
    if db.sourceItemId and db.sourceItemId ~= 0 then
        local id = db.sourceItemId
        if itemIsUsable(id) then
            addReminder("use:" .. questId, {
                priority = 90, questId = questId, itemId = id, ttl = 90,
                text = "You were given " .. colorItem(itemName(id)) .. " for " .. colorQuest(title)
                    .. " - the use button shows it when you get to where it's used",
            })
        else
            addReminder("keep:" .. questId, {
                priority = 50, questId = questId, itemId = id, ttl = 60,
                text = "You were given " .. colorItem(itemName(id)) .. " - keep it, " .. colorQuest(title) .. " needs it",
            })
        end
    end

    if here then
        -- 2) Item objectives that come from an object right here (books, crates, plants).
        for _, row in ipairs(db.objectives[3] or {}) do
            local itemId = row[1]
            local pts, _, kind, sources = Data.ItemSourcePoints(itemId)
            if kind == "object" and #pts > 0 then
                local nearest, d = Geo.Nearest(pts, here)
                if nearest and d and d <= Hints.NEARBY_YARDS then
                    local objName = sources and sources[1] and Data.ObjectName(sources[1]) or "object"
                    addReminder("grab:" .. questId .. ":" .. itemId, {
                        priority = 95, questId = questId, itemId = itemId,
                        text = "Don't leave yet: grab " .. colorItem(itemName(itemId)) .. " from the |cffffffff"
                            .. objName .. "|r nearby",
                        watch = { point = nearest, need = 1, objName = objName },
                    })
                end
            end
        end
        -- 3) Objects to click right here.
        for _, row in ipairs(db.objectives[2] or {}) do
            local objId = row[1]
            local pts = Data.ObjectPoints(objId)
            local nearest, d = Geo.Nearest(pts, here)
            if nearest and d and d <= Hints.NEARBY_YARDS then
                addReminder("click:" .. questId .. ":" .. objId, {
                    priority = 85, questId = questId, ttl = 180,
                    text = "Right here: interact with the |cffffffff" .. (Data.ObjectName(objId) or "object") .. "|r for "
                        .. colorQuest(title),
                    watch = { point = nearest, questObjective = true },
                })
            end
        end
    end

    -- 4) Questie's hidden-objective notes ("Use the Gnomish Tools on the console", ...)
    for i, row in ipairs(db.extraObjectives or {}) do
        local text = row[3]
        if text and text ~= "" then
            addReminder("extra:" .. questId .. ":" .. i, {
                priority = 70, questId = questId, sticky = true,
                text = colorQuest(title) .. ": " .. text,
            })
        end
    end

    -- 5) Escorts: the usual way to fail.
    for _, line in ipairs(db.objectivesText or {}) do
        local l = line:lower()
        if l:find("escort", 1, true) or l:find("protect", 1, true) then
            addReminder("escort:" .. questId, {
                priority = 80, questId = questId, sticky = true,
                text = "Escort quest " .. colorQuest(title) .. ": stay close to the NPC and let them lead",
            })
            break
        end
    end
end

---------------------------------------------------------------------------
-- Per-tick evaluation
---------------------------------------------------------------------------
--- env = { point, byId (quest snapshot), bags (QS.Bags()), plan, step, now }
function Hints.Compute(env)
    local out = {}
    local now = env.now or 0
    local byId = env.byId or {}
    local function push(h) out[#out + 1] = h end

    -- Reminders: expire, resolve, escalate
    for key, r in pairs(Hints.reminders) do
        local live = byId[r.questId]
        local remove = false
        local young = (now - (r.created or now)) < 5 -- the quest log snapshot may lag the accept event
        if (not live and not young) or (live and live.complete) then remove = true end
        if r.ttl and (now - r.created) > r.ttl then remove = true end
        if r.kind == "use" and live and live.complete then remove = true end
        if not remove and r.watch then
            local w = r.watch
            if w.need and itemCount(r.itemId) >= w.need then
                remove = true
            elseif env.point and w.point then
                local d = Geo.Distance(env.point, w.point)
                if d and d > Hints.LEAVING_YARDS then
                    if w.need then
                        r.leftAt = r.leftAt or now
                        if now - r.leftAt > 90 then
                            remove = true
                        else
                            push({ priority = 100, kind = "warn", questId = r.questId, itemId = r.itemId,
                                   text = "|cffff5555You left without|r " .. colorItem(itemName(r.itemId))
                                       .. " - it's back at the " .. (w.objName or "quest giver") })
                        end
                    else
                        remove = true -- object-click reminders lapse once you move on
                    end
                end
            end
        end
        if remove then
            Hints.reminders[key] = nil
        elseif not r.leftAt then
            push(r)
        end
    end

    -- Quest starters in bags
    for _, s in ipairs((env.bags and env.bags.slots) or {}) do
        local qi = s.questInfo
        if qi and qi.questID and qi.questID > 0 and not qi.isActive then
            push({ priority = 88, kind = "use", itemId = s.itemId, bag = s.bag, slot = s.slot, button = true,
                   text = "Right-click " .. colorItem(itemName(s.itemId)) .. " in your bags - it starts a quest" })
        end
    end

    -- Gear upgrades already in your bags: these get a cyan "Equip" box, so say what it is.
    local equips = 0
    for _, e in ipairs(env.suggestions or {}) do
        if e.action == "equip" and equips < 2 then
            equips = equips + 1
            push({ priority = 50, kind = "equip", itemId = e.itemId,
                   text = "Upgrade in your bags: equip " .. colorItem(e.name or itemName(e.itemId))
                       .. (e.pct and (" (" .. ns.Gear.PctText(e.pct) .. ")") or "") })
        end
    end

    -- Items to use for a quest. The game flags some as the quest's "special item"; many others
    -- are only known from QuestieDB ("use the Symbol of Life to resurrect Deathguard Falgan"):
    -- the quest's required source items, the item its giver hands you, or a quest item in your
    -- bags that QuestieDB links to the quest. Worked out every tick, so it survives /reload.
    local stepQuests, stepTask = {}, {}
    if env.step then
        for _, t in ipairs(env.step.tasks) do
            stepQuests[t.questId or -1] = t.kind
            if t.questId and not stepTask[t.questId] then stepTask[t.questId] = t end
        end
    end
    local stepTasks, laterTasks, laterAt = Hints.UseTasks(env.plan, env.step)
    local useCovers = {} -- "target" / "softinteract" whose cue is a use-item line instead
    local bagUse = Hints.BagUseItems(env.bags)
    -- Questie's hidden-objective notes for this step's quests ("Use the Gnomish Tools on the
    -- console"): the reminder made when you accepted the quest doesn't survive a /reload.
    for qid in pairs(stepTask) do
        local db = Data.Quest(qid)
        for _, row in ipairs((db and db.extraObjectives) or {}) do
            local text = row[3]
            if type(text) == "string" and text ~= "" then
                push({ priority = 70, kind = "info", questId = qid, text = colorQuest(db.name) .. ": " .. text })
            end
        end
    end
    for id, q in pairs(byId) do
        -- A complete quest only still needs its item when it has no tracked objectives: then
        -- using the item IS the objective (the game counts such quests as ready to turn in).
        local needsUse = not q.complete or #(q.objectives or {}) == 0
        -- This step's quests, or a later step's once you're at its target (see "When the use
        -- button shows a quest item").
        local tasks = stepTasks[id]
        local later = not tasks and laterTasks[id]
        if needsUse and not q.failed and (tasks or later) then
            local items = Hints.UseItemsFor(id, q, bagUse)
            if #items > 0 then
                local targets = Hints.UseTargets(tasks or later)
                local ready, selected, units = Hints.UseReady(targets, tasks or later, env.point)
                local what = targets and targets.names[1]
                if ready then
                    -- 0.3.28: facing the Bubbling Fissure showed ">> This one: Use Bubbling Fissure -
                    -- press your Interact key", but it's the Dried Seeds you use on it. When what
                    -- you've selected is an item's target, this line is the cue instead, and it says
                    -- to use the item. An item for what you've selected also beats one you're only
                    -- standing near, so the button holds what the line says.
                    local facing = units and units.softinteract
                    for u in pairs(units or {}) do useCovers[u] = true end
                    for k, itemId in ipairs(items) do
                        if k > 2 then break end
                        local on = (type(facing) == "string" and facing) or selected or what
                            or Hints.UseTarget(stepTask[id] or later[1])
                        push({ priority = (units and 99 or 92) - (later and 1 or 0), kind = "use", itemId = itemId,
                               questId = id, button = true,
                               text = (facing and (ns.Theme.Hex("marker") .. ">> This one:|r ") or "") .. "Use " .. colorItem(itemName(itemId))
                                   .. (on and (" on |cffffffff" .. on .. "|r") or " here") .. " for " .. colorQuest(q.title)
                                   .. (later and string.format(" (step %d, but you're here)", laterAt[id] or 0) or "")
                                   .. (units and (" - " .. Hints.UseHow()) or "") })
                    end
                elseif later then
                    -- a later step's item stays out of the way until you get there
                elseif what then
                    push({ priority = 84, kind = "info", questId = id,
                           text = "Select |cffffffff" .. what .. "|r (target it, or face it) to use "
                               .. colorItem(itemName(items[1])) .. " for " .. colorQuest(q.title) })
                else
                    push({ priority = 84, kind = "info", questId = id,
                           text = "Use " .. colorItem(itemName(items[1])) .. " at the marked spot for " .. colorQuest(q.title)
                               .. " - the button shows it when you're there" })
                end
            end
        end
        -- the guide shows the countdown; with the guide hidden, the hint box does
        if q.timer and not ns.db.showGuide then
            local left = q.timer.total - q.timer.elapsed - (now - (q.timer.readAt or env.snapshotTime or now))
            if left > 0 then
                push({ priority = 96, kind = "warn", questId = id,
                       text = string.format("|cffff8800Timed:|r %s - %d:%02d left", colorQuest(q.title),
                           math.floor(left / 60), math.floor(left % 60)) })
            end
        end
        if q.failed then
            local db = ns.Data and ns.Data.Quest(id)
            local starters = db and db.startedBy and db.startedBy[1]
            local giver = type(starters) == "table" and starters[1] and ns.Data.NpcName(starters[1])
            push({ priority = 90, kind = "warn", questId = id,
                   text = colorQuest(q.title) .. " |cffff5555failed|r - abandon it in your quest log, then pick it up again"
                       .. (giver and (" from " .. giver) or "") })
        end
    end

    -- Planner-driven hints for the current step
    local plan = env.plan
    if env.step then
        for _, t in ipairs(env.step.tasks) do
            if t.kind == "turnin" and t.rewardPick then
                push({ priority = 75, kind = "reward", questId = t.questId,
                       text = "Reward: pick |cff00ff00" .. t.rewardPick .. "|r from " .. colorQuest(t.quest.title) })
            end
            if t.kind == "turnin" and env.point and t.loc and not t.isDone then
                local d = Geo.Distance(env.point, t.loc)
                if d and d < 40 and byId[t.questId] and byId[t.questId].complete then
                    push({ priority = 65, kind = "info", questId = t.questId,
                           text = "Turn in " .. colorQuest(t.quest.title) .. " right here" ..
                               (t.quest.turninName and (" (" .. t.quest.turninName .. ")") or "") })
                end
            end
        end
    end
    -- World markers: you're facing / targeting the right thing
    if ns.WorldMarks then ns.WorldMarks.Hints(push, useCovers) end
    -- an NPC's quest dialog is open: which of their quests to take
    Hints.DialogHints(push)

    -- Travel: hearth now, set your inn, learn a flight path
    if env.step then
        local tr = env.step.travel
        if tr and tr.mode == "hearth" and ns.Travel then
            local has, readyIn = ns.Travel.HearthState()
            local d = env.point and env.step.loc and Geo.Distance(env.point, env.step.loc)
            if has and (readyIn or 0) <= 0 and d and d > 250 then
                push({ priority = 94, kind = "use", itemId = ns.Travel.HEARTHSTONE, button = true,
                       text = string.format("|cff66ccffHearth now|r to %s - saves ~%d min of travel",
                           tr.bindName or "your inn", math.max(1, math.floor((tr.saving or 0) / 60 + 0.5))) })
            elseif has and (readyIn or 0) > 0 and ns.Speed then
                -- 0.5.0: the stone is cooling down: a break costs nothing, the cooldown ticks while logged out
                local h = ns.Speed.HearthWaitHint(readyIn)
                if h then push(h) end
            end
        else
            -- the same fly-or-walk call as the guide's travel line (re-checked from where you stand)
            local live = ns.Ladder and ns.Ladder.LiveTravel and env.point and ns.Ladder.LiveTravel(env.step, env.point)
            local f = live and live.mode == "fly" and live.fly
            if f then
                push({ priority = 55, kind = "info",
                       text = string.format("Take the flight from |cffffffff%s|r to |cffffffff%s|r - you can AFK on the way",
                           f.from.name or "the flight master", f.to.name or "?") })
            end
        end
        for _, t in ipairs(env.step.tasks) do
            if t.kind == "visit" and t.visit == "bind" and not t.isDone then
                push({ priority = 78, kind = "info",
                       text = "Talk to |cffffffff" .. (t.npcName or "the innkeeper") ..
                           "|r and choose \"Make this inn your home\" - you'll hearth back here later" })
            elseif t.kind == "visit" and t.visit == "flight" and not t.isDone then
                push({ priority = 78, kind = "info",
                       text = "Talk to the flight master to learn |cffffffff" .. (t.nodeName or "this flight path") ..
                           "|r (you don't have to fly)" })
            end
        end
    end
    if plan and plan.bags and plan.bags.needed and plan.bags.needed > 0 then
        local at = plan.bags.overflowAt or 1
        push({ priority = 72, kind = "bags",
               text = string.format("|cffff8800Bags:|r free %d more slot%s before step %d (/ladder bags)",
                   plan.bags.needed, plan.bags.needed == 1 and "" or "s", at) })
    end
    -- New quests left out because their detour isn't worth it
    local pruned = plan and plan.pruned
    if pruned and #pruned > 0 then
        push({ priority = 40, kind = "info",
               text = string.format("|cff66ccffSkipped:|r %d quest%s here %s not worth the walk (/ladder skipped)",
                   #pruned, #pruned == 1 and "" or "s", #pruned == 1 and "is" or "are") })
    end
    -- 0.4.0: quests in your log you've outgrown that the route left out, or, with the log (nearly)
    -- full, which ones to drop first. Abandoning one never re-suggests it (/ladder unignore).
    local outgrown = plan and plan.outgrown
    local logText = plan and plan.logCount and plan.logMax and string.format(" (log %d/%d)", plan.logCount, plan.logMax) or ""
    local function names(list)
        local parts = {}
        for i, e in ipairs(list) do
            if i > 3 then parts[#parts + 1] = "..." break end
            parts[#parts + 1] = colorQuest(e.title or tostring(e.questId or e.id))
                .. ((e.level or (e.quest and e.quest.level)) and (" [" .. (e.level or e.quest.level) .. "]") or "")
        end
        return table.concat(parts, ", ")
    end
    if outgrown and #outgrown > 0 then
        push({ priority = 46, kind = "info",
               text = string.format("|cff66ccffOutgrown:|r %d quest%s in your log %s not worth the trip any more: %s - abandon %s to free log space%s (/ladder outgrown)",
                   #outgrown, #outgrown == 1 and "" or "s", #outgrown == 1 and "is" or "are", names(outgrown),
                   #outgrown == 1 and "it" or "them", logText) })
    elseif plan and plan.logCount and plan.logMax and plan.logCount >= plan.logMax - 1 and ns.Ladder then
        local weak = ns.Ladder.WeakestInLog(plan, 3)
        if #weak > 0 then
            push({ priority = 74, kind = "warn",
                   text = string.format("|cffff8800Quest log %d/%d:|r to make room, drop the weakest first: %s (/ladder outgrown)",
                       plan.logCount, plan.logMax, names(weak)) })
        end
    end
    -- Few quests worth doing left around you: where the next good area is
    local area = plan and plan.nextArea
    if area and ns.Ladder then
        push({ priority = 45, kind = "info", text = "|cff66ccffNext area:|r " .. ns.Ladder.NextAreaText(area) })
    end
    -- Forever extras: riding, a bigger bag, the sleeping bag chain, supply crates
    if ns.Goodies then ns.Goodies.Hints(push, env) end
    -- 0.5.0 speed-leveling: watch for a named mob's quest drop, learn a profession for a quest,
    -- grind here first, die and res when that's quicker
    if ns.Speed then ns.Speed.Hints(push, env) end

    table.sort(out, function(a, b)
        if (a.priority or 0) ~= (b.priority or 0) then return (a.priority or 0) > (b.priority or 0) end
        return (a.text or "") < (b.text or "")
    end)
    -- de-duplicate identical text
    local seen, final = {}, {}
    for _, h in ipairs(out) do
        if not seen[h.text] then
            seen[h.text] = true
            final[#final + 1] = h
        end
    end
    Hints.list = final
    return final
end

--- The best hint that has an item to use now (drives the secure "use item" button and its bag
--- box). Only hints marked `button`: a quest starter in your bags, the hearthstone when the route
--- says hearth, and a quest item once you're at what it's used on (this step's first, then a
--- later step's).
function Hints.UsableItem()
    for _, h in ipairs(Hints.list) do
        if h.kind == "use" and h.button and h.itemId and itemCount(h.itemId) > 0 then return h end
    end
    return nil
end

---------------------------------------------------------------------------
-- 0.4.0: take it or leave it, while an NPC's quest dialog is open
---------------------------------------------------------------------------
-- "Allow the user to accept missions and level without too much thought": when you talk to a
-- quest giver, the hint box says which of their quests to take and which to leave, with the
-- reason (Ladder.QuestVerdict). Read-only: accepting stays yours (or auto-accept's, which only
-- takes quests on the route, inside the dialog you opened).
Hints.dialog = nil -- { quests = { { id, take, why, title } } }

function Hints.SetDialogQuests(ids, source)
    local out, seen = {}, {}
    for _, id in ipairs(ids or {}) do
        if type(id) == "number" and not ns.IsSecret(id) and not seen[id] and ns.Ladder then
            seen[id] = true
            local ok, take, why, title = pcall(ns.Ladder.QuestVerdict, id)
            if ok and take ~= nil then out[#out + 1] = { id = id, take = take, why = why, title = title } end
        end
    end
    Hints.dialog = (#out > 0) and { quests = out, source = source } or nil
    ns.Fire("HINTS_CHANGED")
end

--- `source`: only clear what that frame put up (the gossip window closes after the quest text
--- it led to has opened).
function Hints.ClearDialog(source)
    if Hints.dialog and (not source or Hints.dialog.source == source) then
        Hints.dialog = nil
        ns.Fire("HINTS_CHANGED")
    end
end

--- The dialog's lines: one per quest, takes first (pushed by Compute).
function Hints.DialogHints(push)
    local d = Hints.dialog
    if not d then return end
    for i, e in ipairs(d.quests) do
        if i > 4 then break end
        push({ priority = 98 - i * 0.01, kind = e.take and "info" or "warn", questId = e.id,
               text = string.format("%s %s - %s", e.take and "|cff00ff00Take:|r" or "|cffff8800Skip:|r",
                   colorQuest(e.title or tostring(e.id)), e.why or "") })
    end
end

ns.RegisterEvent("QUEST_DETAIL", function()
    local ok, id = pcall(function() return GetQuestID and GetQuestID() end)
    Hints.SetDialogQuests({ ok and id or nil }, "quest")
end)

ns.RegisterEvent("GOSSIP_SHOW", function()
    local ids = {}
    if C_GossipInfo and C_GossipInfo.GetAvailableQuests then
        local ok, list = pcall(C_GossipInfo.GetAvailableQuests)
        for _, q in ipairs((ok and list) or {}) do
            if type(q) == "table" then ids[#ids + 1] = q.questID end
        end
    end
    Hints.SetDialogQuests(ids, "gossip")
end)

ns.RegisterEvent("QUEST_GREETING", function()
    local ids = {}
    if GetNumAvailableQuests and GetAvailableQuestInfo then
        local okN, n = pcall(GetNumAvailableQuests)
        for i = 1, (okN and type(n) == "number" and n) or 0 do
            local ok, id = pcall(function() return select(5, GetAvailableQuestInfo(i)) end)
            if ok then ids[#ids + 1] = id end
        end
    end
    Hints.SetDialogQuests(ids, "quest")
end)

ns.RegisterEvent("QUEST_FINISHED", function() Hints.ClearDialog("quest") end)
ns.RegisterEvent("GOSSIP_CLOSED", function() Hints.ClearDialog("gossip") end)

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
ns.RegisterEvent("QUEST_ACCEPTED", function(_, a, b)
    -- Forever/Mainline pass (questId); Classic passed (questLogIndex, questId).
    local questId = b or a
    if type(questId) ~= "number" then return end
    Hints.OnQuestAccepted(questId, Geo.PlayerPoint())
    ns.Fire("HINTS_CHANGED")
end)
