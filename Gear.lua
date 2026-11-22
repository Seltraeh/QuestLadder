-- Quest Ladder: gear advisor.
--   * picks the best quest reward (an upgrade you can wear now, including anything for an empty
--     slot; otherwise highest sell value)
--   * flags upgrades coming from quests later in the plan, so you don't buy that slot
--   * finds affordable Auction House upgrades from Auctionator's price data
-- Purchases are always made by you in the AH window; this only recommends.

local _, ns = ...
local Gear = {}
ns.Gear = Gear
local Prices = {}
ns.Prices = Prices

local Data = ns.Data

---------------------------------------------------------------------------
-- Prices (Auctionator API v1 + vendor price)
---------------------------------------------------------------------------
local CALLER = "QuestLadder"

function Prices.HasAuctionator()
    return Auctionator and Auctionator.API and Auctionator.API.v1
        and type(Auctionator.API.v1.GetAuctionPriceByItemID) == "function" or false
end

--- Last price Auctionator saw, in copper, or nil (never 0 for "unknown").
function Prices.AH(itemId, link)
    if not Prices.HasAuctionator() then return nil end
    local api = Auctionator.API.v1
    local ok, price
    if link and api.GetAuctionPriceByItemLink then
        ok, price = pcall(api.GetAuctionPriceByItemLink, CALLER, link)
        if ok and type(price) == "number" and price > 0 then return price end
    end
    ok, price = pcall(api.GetAuctionPriceByItemID, CALLER, itemId)
    if ok and type(price) == "number" and price > 0 then return price end
    return nil
end

function Prices.Vendor(itemId)
    if not (C_Item and C_Item.GetItemInfo) then return 0 end
    local sell = select(11, C_Item.GetItemInfo(itemId))
    return sell or 0
end

--- Opens Auctionator's search for these exact item names (you buy manually).
function Prices.Search(names)
    if not Prices.HasAuctionator() then return false end
    local api = Auctionator.API.v1
    local fn = api.MultiSearchExact or api.MultiSearch
    if not fn then return false end
    return pcall(fn, CALLER, names)
end

---------------------------------------------------------------------------
-- Stat weights (leveling defaults; override with /ladder weight <stat> <n>)
---------------------------------------------------------------------------
local STAT_KEYS = {
    ITEM_MOD_STRENGTH_SHORT = "str",
    ITEM_MOD_AGILITY_SHORT = "agi",
    ITEM_MOD_STAMINA_SHORT = "sta",
    ITEM_MOD_INTELLECT_SHORT = "int",
    ITEM_MOD_SPIRIT_SHORT = "spi",
    RESISTANCE0_NAME = "armor",
    ITEM_MOD_DAMAGE_PER_SECOND_SHORT = "dps",
    ITEM_MOD_ATTACK_POWER_SHORT = "ap",
    ITEM_MOD_RANGED_ATTACK_POWER_SHORT = "rap",
    ITEM_MOD_SPELL_POWER_SHORT = "sp",
    ITEM_MOD_SPELL_DAMAGE_DONE_SHORT = "sp",
    ITEM_MOD_SPELL_HEALING_DONE_SHORT = "heal",
    ITEM_MOD_HIT_RATING_SHORT = "hit",
    ITEM_MOD_CRIT_RATING_SHORT = "crit",
    ITEM_MOD_MANA_REGENERATION_SHORT = "mp5",
    ITEM_MOD_DEFENSE_SKILL_RATING_SHORT = "def",
}
Gear.STAT_KEYS = STAT_KEYS

-- Relative values per point. "dps" is weapon DPS for melee slots; "rdps" for the ranged slot.
-- Rough leveling heuristics: 1 weapon DPS ~ 14 attack power ~ 7 strength for physical classes.
Gear.DEFAULT_WEIGHTS = {
    WARRIOR = { str = 1.0, agi = 0.6, sta = 0.5, ap = 0.5, armor = 0.01, dps = 7.0, rdps = 0.5, hit = 1.0, crit = 1.0, def = 0.2 },
    ROGUE   = { agi = 1.0, str = 0.5, sta = 0.4, ap = 0.5, armor = 0.01, dps = 7.0, rdps = 0.5, hit = 1.0, crit = 1.0 },
    HUNTER  = { agi = 1.0, int = 0.35, sta = 0.4, rap = 0.5, ap = 0.1, armor = 0.01, dps = 0.8, rdps = 7.0, hit = 1.0, crit = 1.0 },
    PALADIN = { str = 1.0, int = 0.45, sta = 0.6, agi = 0.3, ap = 0.5, sp = 0.3, armor = 0.01, dps = 6.0, rdps = 0.2 },
    SHAMAN  = { str = 1.0, agi = 0.5, int = 0.6, sta = 0.5, ap = 0.5, sp = 0.5, armor = 0.01, dps = 6.0, rdps = 0.2, mp5 = 1.0 },
    DRUID   = { str = 0.8, agi = 0.8, int = 0.6, spi = 0.5, sta = 0.5, ap = 0.5, sp = 0.5, armor = 0.01, dps = 1.0 },
    MAGE    = { int = 1.0, spi = 0.7, sta = 0.5, sp = 1.2, armor = 0.003, rdps = 3.0, hit = 1.0, crit = 1.0, mp5 = 1.0 },
    PRIEST  = { int = 0.9, spi = 1.0, sta = 0.5, sp = 1.1, heal = 0.4, armor = 0.003, rdps = 3.0, mp5 = 1.0 },
    WARLOCK = { int = 0.6, spi = 0.6, sta = 1.0, sp = 1.2, armor = 0.003, rdps = 3.0, hit = 1.0 },
}

function Gear.Weights(classFile)
    local base = Gear.DEFAULT_WEIGHTS[classFile or ""] or Gear.DEFAULT_WEIGHTS.WARRIOR
    local over = ns.db and ns.db.weights
    if not over then return base end
    local w = {}
    for k, v in pairs(base) do w[k] = v end
    for k, v in pairs(over) do w[k] = v end
    return w
end

---------------------------------------------------------------------------
-- Equip slots and proficiencies
---------------------------------------------------------------------------
local SLOTS = {
    INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 },
    INVTYPE_CHEST = { 5 }, INVTYPE_ROBE = { 5 }, INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 },
    INVTYPE_FEET = { 8 }, INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 },
    INVTYPE_FINGER = { 11, 12 }, INVTYPE_TRINKET = { 13, 14 }, INVTYPE_CLOAK = { 15 },
    INVTYPE_WEAPON = { 16, 17 }, INVTYPE_WEAPONMAINHAND = { 16 }, INVTYPE_2HWEAPON = { 16 },
    INVTYPE_WEAPONOFFHAND = { 17 }, INVTYPE_SHIELD = { 17 }, INVTYPE_HOLDABLE = { 17 },
    INVTYPE_RANGED = { 18 }, INVTYPE_RANGEDRIGHT = { 18 }, INVTYPE_THROWN = { 18 }, INVTYPE_RELIC = { 18 },
}
Gear.SLOTS = SLOTS
local SLOT_NAMES = {
    [1] = "Head", [2] = "Neck", [3] = "Shoulder", [5] = "Chest", [6] = "Waist", [7] = "Legs", [8] = "Feet",
    [9] = "Wrist", [10] = "Hands", [11] = "Ring", [12] = "Ring", [13] = "Trinket", [14] = "Trinket",
    [15] = "Back", [16] = "Main hand", [17] = "Off hand", [18] = "Ranged",
}
Gear.SLOT_NAMES = SLOT_NAMES

-- Armor subclass: 1 cloth, 2 leather, 3 mail, 4 plate, 6 shield. Highest type each class wears.
local ARMOR = {
    WARRIOR = { 3, 4 }, PALADIN = { 3, 4 }, HUNTER = { 2, 3 }, SHAMAN = { 2, 3 },
    ROGUE = { 2, 2 }, DRUID = { 2, 2 }, MAGE = { 1, 1 }, PRIEST = { 1, 1 }, WARLOCK = { 1, 1 },
}
local SHIELD = { WARRIOR = true, PALADIN = true, SHAMAN = true }
-- Weapon subclasses each class can train.
local WEAPONS = {
    WARRIOR = { 0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 13, 15, 16, 18 },
    PALADIN = { 0, 1, 4, 5, 6, 7, 8 },
    HUNTER  = { 0, 1, 2, 3, 6, 7, 8, 10, 13, 15, 16, 18 },
    ROGUE   = { 2, 3, 4, 7, 13, 15, 16, 18 },
    PRIEST  = { 4, 10, 15, 19 },
    SHAMAN  = { 0, 1, 4, 5, 10, 13, 15 },
    MAGE    = { 7, 10, 15, 19 },
    WARLOCK = { 7, 10, 15, 19 },
    DRUID   = { 4, 5, 10, 13, 15 },
}

local function contains(list, v)
    for i = 1, #list do if list[i] == v then return true end end
    return false
end

--- Proficiency check used when the client API cannot answer.
function Gear.Proficient(classFile, level, classID, subClassID, equipLoc)
    if classID == 4 then
        if subClassID == 0 then return true end -- misc: rings, trinkets, necks, cloaks
        if subClassID == 6 then return SHIELD[classFile] or false end
        if equipLoc == "INVTYPE_CLOAK" then return true end
        local a = ARMOR[classFile]
        if not a then return subClassID == 1 end
        local maxType = (level >= 40) and a[2] or a[1]
        return subClassID <= maxType and subClassID >= 1 and subClassID <= 4
    elseif classID == 2 then
        local w = WEAPONS[classFile]
        return w and contains(w, subClassID) or false
    end
    return false
end

---------------------------------------------------------------------------
-- Scoring
---------------------------------------------------------------------------
local function getStats(link)
    if not link then return nil end
    local fn = (C_Item and C_Item.GetItemStats) or GetItemStats
    if not fn then return nil end
    local ok, stats = pcall(fn, link)
    if ok and type(stats) == "table" then return stats end
    return nil
end
Gear.GetStats = getStats

--- Scores a stats table for a slot. Exposed for tests.
function Gear.ScoreStats(stats, weights, slot)
    if not stats then return 0, false end
    local score, primary = 0, false
    for key, value in pairs(stats) do
        local stat = STAT_KEYS[key]
        if stat and type(value) == "number" and not ns.IsSecret(value) then
            if stat == "dps" and slot == 18 then stat = "rdps" end
            if stat ~= "armor" and stat ~= "dps" and stat ~= "rdps" then primary = true end
            score = score + (weights[stat] or 0) * value
        end
    end
    return score, primary
end

local function equippedLink(slot)
    if GetInventoryItemLink then
        local ok, link = pcall(GetInventoryItemLink, "player", slot)
        if ok and not ns.IsSecret(link) then return link end
    end
    return nil
end

local function itemInfo(itemOrLink)
    if not (C_Item and C_Item.GetItemInfo) then return nil end
    local name, link, quality, ilvl, minLevel, _, _, _, equipLoc, _, sellPrice, classID, subClassID, bindType,
          _, _, isCraftingReagent = C_Item.GetItemInfo(itemOrLink)
    if not name then return nil end
    return { name = name, link = link, quality = quality, ilvl = ilvl, minLevel = minLevel or 0,
             equipLoc = equipLoc, sellPrice = sellPrice or 0, classID = classID, subClassID = subClassID,
             bindType = bindType,
             -- the game's own "Crafting Reagent" flag (used in a profession recipe)
             craftingReagent = (isCraftingReagent == true and not ns.IsSecret(isCraftingReagent)) or nil }
end
Gear.ItemInfo = itemInfo

--- "%s Armor" (the game's ARMOR_TEMPLATE) as a pattern that captures the number.
local armorPattern
local function getArmorPattern()
    if armorPattern then return armorPattern end
    local template = (type(ARMOR_TEMPLATE) == "string" and not ns.IsSecret(ARMOR_TEMPLATE)) and ARMOR_TEMPLATE or "%s Armor"
    local i = template:find("%s", 1, true)
    if not i then template, i = "%s Armor", 1 end
    local function esc(s) return (s:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")) end
    armorPattern = "^" .. esc(template:sub(1, i - 1)) .. "([%d,%.]+)" .. esc(template:sub(i + 2)) .. "$"
    return armorPattern
end

--- Armor read from the item's tooltip text ("30 Armor"), or nil. Read-only (C_TooltipInfo).
local tooltipArmorCache = {}
function Gear.TooltipArmor(link)
    if type(link) ~= "string" then return nil end
    if tooltipArmorCache[link] then return tooltipArmorCache[link] end
    if not (C_TooltipInfo and C_TooltipInfo.GetHyperlink) then return nil end
    local ok, data = pcall(C_TooltipInfo.GetHyperlink, link)
    if not ok or type(data) ~= "table" or ns.IsSecret(data) or type(data.lines) ~= "table" then return nil end
    local pattern = getArmorPattern()
    for _, line in ipairs(data.lines) do
        local text = type(line) == "table" and line.leftText
        if type(text) == "string" and not ns.IsSecret(text) then
            local num = text:match(pattern)
            local armor = num and tonumber((num:gsub("[,%.]", "")))
            if armor and armor > 0 then
                tooltipArmorCache[link] = armor
                return armor
            end
        end
    end
    return nil
end

--- The item's stats for scoring. Plain armor is most of what low-level gear has, so when the
--- client's stat list leaves armor out, it is read from the tooltip instead.
function Gear.ItemStats(link)
    local stats = getStats(link)
    if stats and stats.RESISTANCE0_NAME ~= nil then return stats end
    local info = link and itemInfo(link)
    if not (info and info.classID == 4) then return stats end
    local armor = Gear.TooltipArmor(link)
    if not armor then return stats end
    local copy = { RESISTANCE0_NAME = armor }
    for k, v in pairs(stats or {}) do copy[k] = v end
    return copy
end

function Gear.Score(link, slot, classFile)
    return Gear.ScoreStats(Gear.ItemStats(link), Gear.Weights(classFile), slot)
end

function Gear.CanEquip(itemId, info, player, levelSlack)
    if not info or not info.equipLoc or info.equipLoc == "" or not SLOTS[info.equipLoc] then return false end
    if (info.minLevel or 0) > player.level + (levelSlack or 0) then return false end
    if C_PlayerInfo and C_PlayerInfo.CanUseItem then
        local ok, can = pcall(C_PlayerInfo.CanUseItem, itemId)
        if ok and type(can) == "boolean" and not ns.IsSecret(can) then
            -- CanUseItem is false for "not yet" level too; trust it only when the level is met.
            if (info.minLevel or 0) <= player.level then return can end
        end
    end
    return Gear.Proficient(player.classFile, player.level, info.classID, info.subClassID, info.equipLoc)
end

--- Can this character put a one-hander in the off hand? The client says when it can,
--- else Classic's training levels.
local DUAL_WIELD_LEVEL = { ROGUE = 10, WARRIOR = 20, HUNTER = 20 }
function Gear.CanDualWield(classFile, level)
    if CanDualWield then
        local ok, v = pcall(CanDualWield)
        if ok and not ns.IsSecret(v) then return v and true or false end
    end
    local need = DUAL_WIELD_LEVEL[classFile or ""]
    return need ~= nil and (level or 1) >= need
end

--- The equipped main-hand link when it is a two-hander, else nil.
local function equippedTwoHander()
    local link = equippedLink(16)
    local info = link and itemInfo(link)
    if info and info.equipLoc == "INVTYPE_2HWEAPON" then return link end
    return nil
end

--- Compares an item to what is equipped. Returns { slot, delta, pct, new, old, empty } or nil
--- (empty: nothing is worn there now).
--- Hand rules: a one-hander only counts for the off hand if you can dual wield, and with a
--- two-hander equipped, a one-hander or an off-hand item replaces it, so that's the comparison
--- (not "better than the empty off hand").
function Gear.CompareToEquipped(link, info, classFile, level)
    local slots = SLOTS[info.equipLoc]
    if not slots then return nil end
    if not level then
        local ok, lv = pcall(UnitLevel, "player")
        level = (ok and not ns.IsSecret(lv) and lv) or 1
    end
    local twoHander = equippedTwoHander()
    local best
    for _, slot in ipairs(slots) do
        local offHandWeapon = slot == 17 and info.equipLoc == "INVTYPE_WEAPON"
        if not (offHandWeapon and not Gear.CanDualWield(classFile, level)) then
            local newScore = Gear.Score(link, slot, classFile)
            local oldScore, empty
            if info.equipLoc == "INVTYPE_2HWEAPON" then
                local main, off = equippedLink(16), equippedLink(17)
                oldScore = Gear.Score(main, 16, classFile) + Gear.Score(off, 17, classFile)
                empty = main == nil and off == nil
            elseif twoHander and (slot == 16 or slot == 17) then
                oldScore, empty = Gear.Score(twoHander, 16, classFile), false
            else
                local worn = equippedLink(slot)
                oldScore, empty = Gear.Score(worn, slot, classFile), worn == nil
            end
            local delta = newScore - oldScore
            if not best or delta > best.delta or (delta == best.delta and empty and not best.empty) then
                local pct = oldScore > 0 and (delta / oldScore * 100) or (newScore > 0 and 100 or 0)
                best = { slot = slot, delta = delta, pct = pct, new = newScore, old = oldScore, empty = empty }
            end
        end
    end
    return best
end

--- Is this comparison an upgrade worth acting on? Anything you can wear beats an empty slot.
--- Otherwise it has to be better by MIN_GAIN points or MIN_PCT percent: plain low-level gear
--- only has armor (0.01 a point), so a fixed points bar alone missed real upgrades.
Gear.MIN_GAIN, Gear.MIN_PCT = 0.5, 2
function Gear.IsUpgrade(up)
    if not up then return false end
    if up.empty then return true end
    if up.delta <= 0 then return false end
    return up.delta >= Gear.MIN_GAIN or up.pct >= Gear.MIN_PCT
end

--- "+40%", or "big upgrade" past 300%: plain low-level gear scores almost nothing, so a piece
--- with real stats read "+1814%" (Long Draping Cape over a bare cape).
Gear.BIG_UPGRADE_PCT = 300
function Gear.PctText(pct)
    if (pct or 0) > Gear.BIG_UPGRADE_PCT then return "big upgrade" end
    return string.format("+%d%%", math.floor((pct or 0) + 0.5))
end

local function upgradeText(up)
    if up.empty then return "fills your empty " .. (SLOT_NAMES[up.slot] or "gear") .. " slot" end
    if (up.pct or 0) > Gear.BIG_UPGRADE_PCT then return "big upgrade" end
    return "upgrade " .. Gear.PctText(up.pct)
end
Gear.UpgradeText = upgradeText

---------------------------------------------------------------------------
-- Quest rewards
---------------------------------------------------------------------------
--- choices = { {index, itemId, link}, ... }. Returns { index, itemId, name, reason, upgrade } or nil.
--- An item you can wear now that beats what you wear (or fills an empty slot) wins; the biggest
--- gain first. Only when none does, the one that sells for most.
function Gear.BestChoice(choices, player)
    if not choices or #choices == 0 then return nil end
    local best, bestValue, bestBag
    for _, c in ipairs(choices) do
        local info = itemInfo(c.link or c.itemId)
        if info and info.classID == 1 and ns.Goodies then
            -- a bag: more room beats vendor money when nothing here is gear you'd wear
            local slots = ns.Goodies.BagSlots(c.itemId)
            if ns.Goodies.IsBagUpgrade(slots) and (not bestBag or slots > bestBag.slots) then
                bestBag = { index = c.index, itemId = c.itemId, name = info.name, slots = slots,
                            reason = string.format("more bag space: %d slots", slots) }
            end
        end
        if info then
            local up = Gear.CanEquip(c.itemId, info, player, 0) and Gear.CompareToEquipped(c.link or info.link, info, player.classFile, player.level)
            if Gear.IsUpgrade(up) then
                local cur = best and best.upgrade
                if not cur or up.delta > cur.delta or (up.delta == cur.delta and up.empty and not cur.empty) then
                    best = { index = c.index, itemId = c.itemId, name = info.name, upgrade = up, reason = upgradeText(up) }
                end
            elseif not best or not best.upgrade then
                local value = info.sellPrice or 0
                if not bestValue or value > bestValue then
                    bestValue = value
                    best = { index = c.index, itemId = c.itemId, name = info.name,
                             reason = "none beats what you wear; best sell value " .. ns.FormatMoney(value) }
                end
            end
        end
    end
    if bestBag and not (best and best.upgrade) then return bestBag end
    return best
end

--- Marks turn-in tasks in the plan with the reward to pick, and remembers upcoming upgrades per slot.
function Gear.AnnotatePlan(plan, snapshotById)
    Gear.upcoming = {}
    if not plan then return end
    local player = plan.player
    for si, step in ipairs(plan.steps) do
        for _, t in ipairs(step.tasks) do
            if t.kind == "turnin" then
                local live = snapshotById and snapshotById[t.questId]
                if live and live.rewards then
                    local pick
                    if #live.rewards.choices > 1 then
                        pick = Gear.BestChoice(live.rewards.choices, player)
                        if pick then
                            t.rewardPick = pick.name .. " (" .. pick.reason .. ")"
                            t.rewardIndex = pick.index
                        end
                    end
                    local list = {}
                    for _, c in ipairs(live.rewards.choices) do list[#list + 1] = c end
                    for _, c in ipairs(live.rewards.fixed) do list[#list + 1] = c end
                    for _, c in ipairs(list) do
                        local info = itemInfo(c.link or c.itemId)
                        if info and Gear.CanEquip(c.itemId, info, player, 1) then
                            local up = Gear.CompareToEquipped(c.link or info.link, info, player.classFile, player.level)
                            if Gear.IsUpgrade(up) and (#live.rewards.choices <= 1 or (pick and pick.itemId == c.itemId)) then
                                local prev = Gear.upcoming[up.slot]
                                if not prev or prev.step > si then
                                    Gear.upcoming[up.slot] = { step = si, itemId = c.itemId, name = info.name,
                                        pct = up.pct, questId = t.questId, title = t.quest.title }
                                end
                            end
                        end
                    end
                elseif t.quest and t.quest.candidate then
                    -- Not accepted yet: QuestieDB knows which gear it can reward.
                    for _, itemId in ipairs(Data.rewardItems[t.questId] or {}) do
                        local info = itemInfo(itemId)
                        if not info and C_Item and C_Item.RequestLoadItemDataByID then
                            pcall(C_Item.RequestLoadItemDataByID, itemId)
                        elseif info and Gear.CanEquip(itemId, info, player, 2) then
                            local up = Gear.CompareToEquipped(info.link, info, player.classFile, player.level)
                            if Gear.IsUpgrade(up) then
                                local prev = Gear.upcoming[up.slot]
                                if not prev or prev.step > si then
                                    Gear.upcoming[up.slot] = { step = si, itemId = itemId, name = info.name,
                                        pct = up.pct, questId = t.questId, title = t.quest.title, maybe = true }
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end

---------------------------------------------------------------------------
-- Gold budget
---------------------------------------------------------------------------
--- Copper kept back for class training. Auto: roughly what the next few trainer visits cost.
--- Copper kept back: training, plus Apprentice Riding (100g) from level 35 until you can ride
--- (Paladins and Warlocks get riding from their class mount quest at 40, so not for them).
Gear.RIDING_COST = 1000000
Gear.RIDING_SAVE_FROM = 35
function Gear.NeedsRidingGold(player)
    if not player or (player.level or 0) < Gear.RIDING_SAVE_FROM then return false end
    if player.classFile == "PALADIN" or player.classFile == "WARLOCK" then return false end
    local riding = ns.Travel and ns.Travel.RIDING_SKILL
    return not (player.skills and riding and player.skills[riding])
end

function Gear.Reserve(level, player)
    if ns.db.goldReserve then return ns.db.goldReserve end
    local copper = math.floor(level * level * 35)
    if Gear.NeedsRidingGold(player) then copper = copper + Gear.RIDING_COST end
    return copper
end

function Gear.Budget(player)
    local money = player.money or (GetMoney and GetMoney()) or 0
    return math.max(0, money - Gear.Reserve(player.level, player))
end

---------------------------------------------------------------------------
-- Auction House upgrades from Auctionator's price data
---------------------------------------------------------------------------
Gear.ahResults = nil
Gear.ahStatus = nil

--- Scans equippable items around your level that Auctionator has seen on the AH and that you
--- can afford, then scores them against what you wear. Calls done(list, status).
function Gear.FindAHUpgrades(player, done)
    if not Prices.HasAuctionator() then
        Gear.ahStatus = "Install Auctionator and run a scan at the Auction House to get prices."
        if done then done({}, Gear.ahStatus) end
        return
    end
    if not Data.ready then
        Gear.ahStatus = "Still indexing items, try again in a moment."
        if done then done({}, Gear.ahStatus) end
        return
    end
    local budget = Gear.Budget(player)
    local ids = Data.GearInLevelRange(player.level - 7, player.level)
    Gear.ahStatus = "Checking prices..."
    ns.Async("QuestLadder.ah", function()
        local priced = {}
        for i = 1, #ids do
            local id = ids[i]
            local price = Prices.AH(id)
            if price and price <= budget then priced[#priced + 1] = { itemId = id, price = price } end
            ns.MaybeYield(200)
        end
        -- Load item data for the priced ones (client cache), capped.
        table.sort(priced, function(a, b) return a.price < b.price end)
        local capped = {}
        for i = 1, math.min(#priced, 150) do
            capped[i] = priced[i]
            if C_Item.RequestLoadItemDataByID and not C_Item.GetItemInfo(priced[i].itemId) then
                pcall(C_Item.RequestLoadItemDataByID, priced[i].itemId)
            end
        end
        local waited = 0
        while waited < 120 do -- up to ~120 frames for the client to answer
            local missing = 0
            for i = 1, #capped do
                if not C_Item.GetItemInfo(capped[i].itemId) then missing = missing + 1 end
            end
            if missing == 0 then break end
            waited = waited + 1
            coroutine.yield()
        end
        local results = {}
        for i = 1, #capped do
            local e = capped[i]
            local info = itemInfo(e.itemId)
            if info and info.bindType ~= 1 and Gear.CanEquip(e.itemId, info, player, 0) then
                local up = Gear.CompareToEquipped(info.link, info, player.classFile, player.level)
                if Gear.IsUpgrade(up) then
                    local stats = getStats(info.link)
                    local _, primary = Gear.ScoreStats(stats, Gear.Weights(player.classFile), up.slot)
                    results[#results + 1] = {
                        source = "ah", itemId = e.itemId, name = info.name, link = info.link, price = e.price,
                        slot = up.slot, pct = up.pct, delta = up.delta,
                        randomSuffix = (not primary) and (info.quality or 0) >= 2,
                        soon = Gear.upcoming and Gear.upcoming[up.slot],
                    }
                end
            end
            ns.MaybeYield(20)
        end
        -- Best upgrade per slot, then by size of upgrade.
        local perSlot = {}
        for _, r in ipairs(results) do
            local cur = perSlot[r.slot]
            if not cur or r.delta > cur.delta or (r.delta == cur.delta and r.price < cur.price) then perSlot[r.slot] = r end
        end
        local list = {}
        for _, r in pairs(perSlot) do list[#list + 1] = r end
        table.sort(list, function(a, b) return a.pct > b.pct end)
        Gear.ahResults = list
        Gear.ahStatus = (#list == 0) and "No affordable upgrades in Auctionator's price data." or nil
    end, function()
        if done then done(Gear.ahResults or {}, Gear.ahStatus) end
    end)
end

--- Upgrades from quests in the plan, for the gear panel.
function Gear.QuestUpgradeList()
    local list = {}
    for slot, u in pairs(Gear.upcoming or {}) do
        list[#list + 1] = { source = "quest", slot = slot, itemId = u.itemId, name = u.name, pct = u.pct,
                            step = u.step, title = u.title, maybe = u.maybe }
    end
    table.sort(list, function(a, b) return a.step < b.step end)
    return list
end
