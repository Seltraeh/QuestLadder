-- Quest Ladder: live game state. Reads the player's quest log, objectives, quest items,
-- rewards, bag contents and character facts using read-only client APIs.

local _, ns = ...
local QS = {}
ns.QuestState = QS

local Geo = ns.Geo

---------------------------------------------------------------------------
-- Player
---------------------------------------------------------------------------
function QS.Player()
    local _, classFile = UnitClass("player")
    local className = UnitClass("player")
    local _, raceFile, raceId = UnitRace("player")
    local p = {
        level = UnitLevel("player") or 1,
        classFile = classFile,
        className = className,
        raceId = raceId,
        raceFile = raceFile,
        faction = UnitFactionGroup("player"),
        money = GetMoney and GetMoney() or 0,
        point = Geo.PlayerPoint(),
        inCombat = InCombatLockdown and InCombatLockdown() or false,
        logMax = 20,
        skills = QS.Skills(),
    }
    if C_QuestLog and C_QuestLog.GetMaxNumQuestsCanAccept then
        local ok, n = pcall(C_QuestLog.GetMaxNumQuestsCanAccept)
        if ok and type(n) == "number" and not ns.IsSecret(n) and n > 0 then p.logMax = n end
    end
    -- How far into the current level you are (0..1), for the planner's mob-level rule.
    p.xpFrac = 0
    if UnitXP and UnitXPMax then
        local okA, xp = pcall(UnitXP, "player")
        local okB, max = pcall(UnitXPMax, "player")
        if okA and okB and type(xp) == "number" and type(max) == "number"
            and not ns.AnySecret(xp, max) and max > 0 then
            p.xpFrac = math.max(0, math.min(1, xp / max))
        end
    end
    return p
end

--- Profession ranks keyed by skill line ID (Forever: C_SkillInfo; Classic: globals).
function QS.Skills()
    local skills = {}
    if C_SkillInfo and C_SkillInfo.GetNumSkillLines then
        local ok, n = pcall(C_SkillInfo.GetNumSkillLines)
        if ok and n then
            for i = 1, n do
                local okInfo, line = pcall(C_SkillInfo.GetSkillLineInfo, i)
                if okInfo and line and not line.isHeader and line.skillID then
                    skills[line.skillID] = line.rank or 0
                end
            end
        end
    end
    return skills
end

--- Quests at or below this level difference stop giving XP ("grey").
function QS.GreenRange(level)
    if C_QuestLog and C_QuestLog.GetTrivialRange then
        local ok, r = pcall(C_QuestLog.GetTrivialRange)
        if ok and type(r) == "number" then return r end
    end
    if GetQuestGreenRange then
        local ok, r = pcall(GetQuestGreenRange)
        if ok and type(r) == "number" then return r end
    end
    if level <= 5 then return 5 elseif level <= 39 then return math.floor(level / 10) + 5 end
    return math.min(9 + math.floor((level - 40) / 10), 11)
end

---------------------------------------------------------------------------
-- Quest log
---------------------------------------------------------------------------
local function itemIdFromLink(link)
    if type(link) ~= "string" then return nil end
    return tonumber(link:match("item:(%d+)"))
end
QS.ItemIdFromLink = itemIdFromLink

local function readObjectives(questId)
    local out = {}
    local ok, list = pcall(C_QuestLog.GetQuestObjectives, questId)
    if not ok or type(list) ~= "table" then return out end
    for i, o in ipairs(list) do
        out[#out + 1] = {
            index = i,
            text = o.text or "",
            type = o.type,                  -- "monster", "item", "object", "event", "reputation", "log", ...
            finished = o.finished and true or false,
            have = o.numFulfilled or 0,
            need = o.numRequired or 0,
        }
    end
    return out
end

local function readRewards(questId)
    local rewards = { choices = {}, fixed = {} }
    if GetNumQuestLogChoices then
        local ok, n = pcall(GetNumQuestLogChoices, questId, false)
        if ok and n then
            for i = 1, n do
                local okL, link = pcall(GetQuestLogItemLink, "choice", i, questId)
                local okI, _, _, _, _, _, itemId = pcall(GetQuestLogChoiceInfo, i, questId)
                local id = (okI and itemId) or (okL and itemIdFromLink(link))
                if id then rewards.choices[#rewards.choices + 1] = { index = i, itemId = id, link = okL and link or nil } end
            end
        end
    end
    if GetNumQuestLogRewards then
        local ok, n = pcall(GetNumQuestLogRewards, questId)
        if ok and n then
            for i = 1, n do
                local okL, link = pcall(GetQuestLogItemLink, "reward", i, questId)
                local id = okL and itemIdFromLink(link)
                if id then rewards.fixed[#rewards.fixed + 1] = { index = i, itemId = id, link = link } end
            end
        end
    end
    rewards.hasItems = (#rewards.choices + #rewards.fixed) > 0
    return rewards
end

local function readTag(questId)
    if not (C_QuestLog and C_QuestLog.GetQuestTagInfo) then return nil end
    local ok, info = pcall(C_QuestLog.GetQuestTagInfo, questId)
    if ok and type(info) == "table" then return info end
    return nil
end

local function readWaypoint(questId)
    if not (C_QuestLog and C_QuestLog.GetNextWaypoint) then return nil end
    local ok, mapId, x, y = pcall(C_QuestLog.GetNextWaypoint, questId)
    if ok and not ns.AnySecret(mapId, x, y) and mapId and x and y then return Geo.Point(mapId, x, y) end
    return nil
end

--- Quest POIs the game shows on the player's current map (blob centres).
function QS.MapPOIs(mapId)
    local out = {}
    if not (mapId and C_QuestLog and C_QuestLog.GetQuestsOnMap) then return out end
    local ok, list = pcall(C_QuestLog.GetQuestsOnMap, mapId)
    if not ok or type(list) ~= "table" then return out end
    for _, info in ipairs(list) do
        if not ns.AnySecret(info.questID, info.x, info.y) and info.questID and info.x and info.y then
            out[info.questID] = Geo.Point(mapId, info.x, info.y)
        end
    end
    return out
end

--- Snapshot of every quest in the log. Returns list, byId.
function QS.Snapshot()
    local list, byId = {}, {}
    if not (C_QuestLog and C_QuestLog.GetNumQuestLogEntries) then return list, byId end
    local numEntries = C_QuestLog.GetNumQuestLogEntries()
    for i = 1, numEntries do
        local info = C_QuestLog.GetInfo(i)
        if info and not info.isHeader and info.questID and info.questID > 0 and not info.isHidden then
            local id = info.questID
            local q = {
                id = id,
                title = info.title,
                level = info.level or 0,
                logIndex = i,
                suggestedGroup = info.suggestedGroup or 0,
                complete = (C_QuestLog.IsComplete and C_QuestLog.IsComplete(id)) or false,
                failed = (C_QuestLog.IsFailed and C_QuestLog.IsFailed(id)) or false,
                objectives = readObjectives(id),
                rewards = readRewards(id),
                tag = readTag(id),
                waypoint = readWaypoint(id),
            }
            if C_QuestLog.ReadyForTurnIn then
                local ok, ready = pcall(C_QuestLog.ReadyForTurnIn, id)
                if ok and ready then q.complete = true end
            end
            -- timed quests ("bring the Rendered Spores before the time limit is up"): readAt lets
            -- the guide count down every second without asking the game again
            if C_QuestLog.GetTimeAllowed then
                local ok, total, elapsed = pcall(C_QuestLog.GetTimeAllowed, id)
                if ok and not ns.AnySecret(total, elapsed) and type(total) == "number" and total > 0 then
                    q.timer = { total = total, elapsed = tonumber(elapsed) or 0, readAt = GetTime and GetTime() or 0,
                                source = "api" }
                end
            end
            if GetQuestLogSpecialItemInfo then
                local ok, link, _, charges = pcall(GetQuestLogSpecialItemInfo, i)
                local itemId = ok and itemIdFromLink(link)
                if itemId then q.specialItem = { itemId = itemId, link = link, charges = charges } end
            end
            list[#list + 1] = q
            byId[id] = q
        end
    end
    QS.ReadLegacyTimers(list)
    return list, byId
end

--- The older timer API (GetQuestTimers: seconds left for each timed quest, GetQuestIndexForTimer:
--- its quest log line), for timed quests GetTimeAllowed didn't report.
function QS.ReadLegacyTimers(list)
    if not (GetQuestTimers and GetQuestIndexForTimer) then return end
    local ok, timers = pcall(function() return { GetQuestTimers() } end)
    if not ok then return end
    local now = GetTime and GetTime() or 0
    for i, left in ipairs(timers) do
        local okIndex, logIndex = pcall(GetQuestIndexForTimer, i)
        if okIndex and not ns.AnySecret(left, logIndex) and type(left) == "number" and left > 0 then
            for _, q in ipairs(list) do
                if q.logIndex == logIndex and not q.timer then
                    q.timer = { total = left, elapsed = 0, readAt = now, source = "legacy" }
                end
            end
        end
    end
end

function QS.IsComplete(questId)
    if C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted then
        local ok, done = pcall(C_QuestLog.IsQuestFlaggedCompleted, questId)
        return ok and done or false
    end
    return false
end

---------------------------------------------------------------------------
-- Bags
---------------------------------------------------------------------------
local NUM_BAGS = NUM_BAG_SLOTS or 4

--- Returns { free, total, slots = { {bag, slot, itemId, link, count, quality, bound, questInfo} },
---           counts = { [itemId] = total } }
function QS.Bags()
    local result = { free = 0, total = 0, slots = {}, counts = {} }
    if not C_Container then return result end
    for bag = 0, NUM_BAGS do
        local numSlots = C_Container.GetContainerNumSlots(bag) or 0
        local free, family = C_Container.GetContainerNumFreeSlots(bag)
        -- Only general-purpose bags count for quest items (family 0).
        if (family or 0) == 0 then
            result.free = result.free + (free or 0)
            result.total = result.total + numSlots
        end
        for slot = 1, numSlots do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID then
                local entry = {
                    bag = bag, slot = slot,
                    itemId = info.itemID,
                    link = info.hyperlink,
                    count = info.stackCount or 1,
                    quality = info.quality,
                    bound = info.isBound,
                    noValue = info.hasNoValue,
                }
                if C_Container.GetContainerItemQuestInfo then
                    local ok, qi = pcall(C_Container.GetContainerItemQuestInfo, bag, slot)
                    if ok and type(qi) == "table" and (qi.isQuestItem or qi.questID) then entry.questInfo = qi end
                end
                result.slots[#result.slots + 1] = entry
                result.counts[info.itemID] = (result.counts[info.itemID] or 0) + entry.count
            end
        end
    end
    return result
end
