-- Quest Ladder: bag planner. Works out what can go so the upcoming quest steps fit,
-- keeping `reserveSlots` free for gathering/profession materials.

local _, ns = ...
local Bags = {}
ns.Bags = Bags

local Data = ns.Data

local KEEP_ITEMS = { [6948] = true } -- Hearthstone

-- Profession tools are never sold. QuestieDB has the Mining Pick, Blacksmith Hammer, Skinning
-- Knife and Arclight Spanner as "miscellaneous" weapons (class 2, subclass 14) and fishing poles
-- as their own weapon type (subclass 20), so they read as weapons you can't train. A few
-- tools are trade goods instead; those are listed by item ID.
local TOOL_IDS = {
    [6218] = true, [6339] = true, [11130] = true, [11145] = true, [16207] = true, -- enchanting rods
    [9149] = true,  -- Philosopher's Stone
    [10498] = true, -- Gyromatic Micro-Adjustor
}
function Bags.IsTool(itemId, info)
    if TOOL_IDS[itemId] then return true end
    return info ~= nil and info.classID == 2 and (info.subClassID == 14 or info.subClassID == 20)
        and (info.quality or 1) >= 1 -- a gray "broken" one is still junk
end
-- Crafting materials are money: cloth, leather, herbs, ore and bars, meat, elemental and
-- enchanting materials, gems and recipes. They are never put up for "Sell" or "Destroy"; when
-- bags are short they're suggested for the bank (or the AH). The game flags crafting reagents
-- itself (GetItemInfo's isCraftingReagent); the item classes catch the rest.
local MATERIAL_CLASSES = {
    [3] = true,  -- gems
    [5] = true,  -- reagents
    [7] = true,  -- trade goods
    [9] = true,  -- recipes
}
function Bags.IsMaterial(itemId, info)
    if not info then return false end
    if info.craftingReagent then return true end
    if (info.quality or 1) == 0 then return false end -- gray: vendor trash
    if MATERIAL_CLASSES[info.classID or -1] then return true end
    return info.classID == 15 and info.subClassID == 1 -- miscellaneous: reagent
end

local NEVER_SUGGEST_CLASSES = {
    [0] = true,  -- consumables (food, water, potions, bandages)
    [1] = true,  -- containers
    [5] = true,  -- reagents
    [6] = true,  -- projectiles
    [11] = true, -- quivers
    [13] = true, -- keys
}

--- Items any quest in the log or the plan still needs.
function Bags.NeededItems(byId, plan)
    local need = {}
    local function addQuest(qid)
        local db = Data.Quest(qid)
        if not db then return end
        if db.sourceItemId ~= 0 then need[db.sourceItemId] = true end
        for _, id in ipairs(db.requiredSourceItems or {}) do need[id] = true end
        for _, row in ipairs(db.objectives[3] or {}) do need[row[1]] = true end
    end
    for qid, q in pairs(byId or {}) do
        addQuest(qid)
        if q.specialItem then need[q.specialItem.itemId] = true end
    end
    if plan then
        for _, c in ipairs(plan.candidates or {}) do addQuest(c.id) end
    end
    return need
end

local function relatedToPlan(itemId, plannedIds)
    local related = Data.Item(itemId, "relatedQuests")
    local starts = Data.Item(itemId, "startQuest")
    if starts and starts ~= 0 then return true end
    for _, qid in ipairs(related or {}) do
        if plannedIds[qid] then return true end
    end
    return false
end

--- Returns a sorted list of suggestions:
--- { bag, slot, itemId, link, name, count, action = "sell"|"destroy"|"ah"|"bank", reason, value }
function Bags.Suggestions(bags, byId, plan)
    local out = {}
    if not bags then return out end
    local need = Bags.NeededItems(byId, plan)
    local plannedIds = {}
    for qid in pairs(byId or {}) do plannedIds[qid] = true end
    for _, c in ipairs((plan and plan.candidates) or {}) do plannedIds[c.id] = true end
    local player = plan and plan.player or { level = UnitLevel and UnitLevel("player") or 1,
                                             classFile = select(2, UnitClass("player")) }
    local Gear, Prices = ns.Gear, ns.Prices

    for _, s in ipairs(bags.slots or {}) do
        local id = s.itemId
        local info = Gear.ItemInfo(s.link or id)
        if info and not KEEP_ITEMS[id] and not need[id] and not s.questInfo and not Bags.IsTool(id, info) then
            local vendor = (info.sellPrice or 0) * (s.count or 1)
            local ah = Prices.AH(id, s.link)
            local entry = { bag = s.bag, slot = s.slot, itemId = id, link = s.link or info.link,
                            name = info.name, count = s.count, value = vendor }
            -- Gear first, gray or not: at low levels a gray piece can beat what you wear (or an
            -- empty slot), and it was being sold as junk.
            if Bags.IsMaterial(id, info) then
                -- crafting materials: never "Sell" or "Destroy"; the bank (or the AH) when space is short
                if plan and plan.bags and plan.bags.needed > 0 then
                    entry.action, entry.reason = "bank", "crafting material - bank it or sell it on the AH"
                    if ah and ah > vendor then entry.value = ah end
                    out[#out + 1] = entry
                end
            elseif (info.classID == 2 or info.classID == 4) and Gear.SLOTS[info.equipLoc or ""] then
                local canNow = Gear.CanEquip(id, info, player, 0)
                local canSoon = canNow or Gear.CanEquip(id, info, player, 3)
                local up = canSoon and Gear.CompareToEquipped(entry.link, info, player.classFile, player.level)
                if Gear.IsUpgrade(up) then
                    if canNow then
                        entry.action, entry.reason = "equip", Gear.UpgradeText(up) .. " - equip it"
                        entry.pct = up.pct
                        out[#out + 1] = entry
                    end
                    -- an upgrade within 3 levels: keep it, nothing to suggest yet
                elseif info.quality == 0 then
                    if vendor > 0 then
                        entry.action, entry.reason = "sell", canSoon and "junk (not better than what you wear)" or "junk"
                        out[#out + 1] = entry
                    end
                else
                    if ah and not s.bound and ah > vendor * 1.5 and (info.quality or 0) >= 2 then
                        entry.action, entry.reason, entry.value = "ah", "not an upgrade - worth more on the AH", ah
                    else
                        entry.action, entry.reason = "sell", canSoon and "worse than what you wear" or "you can't use it"
                    end
                    out[#out + 1] = entry
                end
            elseif info.quality == 0 then
                if vendor > 0 then
                    entry.action, entry.reason = "sell", "junk"
                    out[#out + 1] = entry
                end
            elseif info.classID == 12 then
                if not relatedToPlan(id, plannedIds) then
                    entry.action, entry.reason = "destroy", "quest item no quest in your log or plan needs"
                    out[#out + 1] = entry
                end
            elseif not NEVER_SUGGEST_CLASSES[info.classID or -1] and (info.quality or 0) <= 1 then
                -- Misc whites: only suggest when space is actually short.
                if plan and plan.bags and plan.bags.needed > 0 then
                    if ah and ah > vendor then
                        entry.action, entry.reason, entry.value = "bank", "bank it or sell on the AH", ah
                    else
                        entry.action, entry.reason = "sell", "low value"
                    end
                    out[#out + 1] = entry
                end
            end
        end
    end
    local ORDER = { equip = 0, sell = 1, destroy = 2, ah = 3, bank = 4 }
    table.sort(out, function(a, b)
        if ORDER[a.action] ~= ORDER[b.action] then return ORDER[a.action] < ORDER[b.action] end
        return (a.value or 0) < (b.value or 0)
    end)
    return out
end

--- Number of bag slots a vendor visit would free (junk + gear you don't need).
function Bags.SellableSlots(bags)
    local list = Bags.Suggestions(bags, ns.Ladder and ns.Ladder.snapshot or {}, ns.Ladder and ns.Ladder.plan)
    local n = 0
    for _, e in ipairs(list) do
        if e.action == "sell" then n = n + 1 end
    end
    return n
end

--- One-line summary for the guide.
function Bags.Summary(plan)
    if not plan or not plan.bags then return nil end
    local b = plan.bags
    local usable = b.free - b.reserve
    if b.needed > 0 then
        return string.format("|cffff8800Bags: %d free, next steps need %d (+%d reserved)|r", b.free, b.peak, b.reserve)
    end
    return string.format("Bags: %d free, next steps need %d |cff00ff00ok|r", b.free, math.max(b.peak, 0)), usable
end
