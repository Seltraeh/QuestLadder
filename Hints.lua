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

    -- 1) The quest giver handed you an item.
    if db.sourceItemId and db.sourceItemId ~= 0 then
        local id = db.sourceItemId
        if itemIsUsable(id) then
            addReminder("use:" .. questId, {
                priority = 90, questId = questId, itemId = id, kind = "use",
                text = "Right-click " .. colorItem(itemName(id)) .. " (just given to you) to progress " .. colorQuest(title),
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
            push({ priority = 88, kind = "use", itemId = s.itemId, bag = s.bag, slot = s.slot,
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
        if needsUse and not q.failed then
            local items = Hints.UseItemsFor(id, q, bagUse)
            local t = stepTask[id]
            for k, itemId in ipairs(items) do
                if k > 2 then break end
                if t then
                    local on = Hints.UseTarget(t)
                    push({ priority = 92, kind = "use", itemId = itemId, questId = id,
                           text = "Use " .. colorItem(itemName(itemId)) .. (on and (" on |cffffffff" .. on .. "|r") or " here")
                               .. " for " .. colorQuest(q.title) })
                elseif not q.complete then
                    push({ priority = 40, kind = "use", itemId = itemId, questId = id,
                           text = "Quest item: " .. colorItem(itemName(itemId)) .. " for " .. colorQuest(q.title) })
                end
            end
        end
        if q.timer then
            local left = q.timer.total - q.timer.elapsed - (now - (env.snapshotTime or now))
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
    if ns.WorldMarks then ns.WorldMarks.Hints(push) end

    -- Travel: hearth now, set your inn, learn a flight path
    if env.step then
        local tr = env.step.travel
        if tr and tr.mode == "hearth" and ns.Travel then
            local has, readyIn = ns.Travel.HearthState()
            local d = env.point and env.step.loc and Geo.Distance(env.point, env.step.loc)
            if has and (readyIn or 0) <= 0 and d and d > 250 then
                push({ priority = 94, kind = "use", itemId = ns.Travel.HEARTHSTONE,
                       text = string.format("|cff66ccffHearth now|r to %s - saves ~%d min of travel",
                           tr.bindName or "your inn", math.max(1, math.floor((tr.saving or 0) / 60 + 0.5))) })
            end
        elseif tr and tr.mode == "fly" then
            push({ priority = 55, kind = "info",
                   text = string.format("Take the flight from |cffffffff%s|r to |cffffffff%s|r - you can AFK on the way",
                       tr.from.name or "the flight master", tr.to.name or "?") })
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

--- The best hint that has an item to use (drives the secure "use item" button).
function Hints.UsableItem()
    for _, h in ipairs(Hints.list) do
        if h.kind == "use" and h.itemId and itemCount(h.itemId) > 0 then return h end
    end
    return nil
end

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
