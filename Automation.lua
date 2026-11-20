-- Quest Ladder: optional quest dialog automation.
-- These run only after YOU open an NPC's dialog (that click is the hardware event), the same
-- way Leatrix Plus and Questie's auto-accept work. Nothing here moves, targets or fights.
-- Hold Shift while talking to an NPC to suspend it.

local _, ns = ...
local Auto = {}
ns.Automation = Auto

local function suspended()
    return IsShiftKeyDown and IsShiftKeyDown()
end

--- Quest IDs the current plan wants picked up.
local function plannedPickups()
    local set = {}
    local plan = ns.Ladder and ns.Ladder.plan
    if not plan then return set end
    for _, t in ipairs(plan.order or {}) do
        if t.kind == "pickup" then set[t.questId] = true end
    end
    return set
end

local function rewardIndexFor(questId)
    local plan = ns.Ladder and ns.Ladder.plan
    local t = plan and plan.byId and plan.byId["T" .. questId]
    return t and t.rewardIndex
end

---------------------------------------------------------------------------
-- Quest frames
---------------------------------------------------------------------------
ns.RegisterEvent("QUEST_DETAIL", function()
    if not ns.db.autoAccept or suspended() then return end
    local questId = GetQuestID and GetQuestID()
    if questId and plannedPickups()[questId] then
        AcceptQuest()
    end
end)

ns.RegisterEvent("QUEST_PROGRESS", function()
    if not ns.db.autoTurnIn or suspended() then return end
    if IsQuestCompletable and IsQuestCompletable() then CompleteQuest() end
end)

ns.RegisterEvent("QUEST_COMPLETE", function()
    if not ns.db.autoTurnIn or suspended() then return end
    local n = GetNumQuestChoices and GetNumQuestChoices() or 0
    if n <= 1 then
        GetQuestReward(n == 1 and 1 or 0)
        return
    end
    if not ns.db.autoPickReward then return end
    -- Score the rewards shown in this dialog (works for quests the plan did not know about).
    local choices = {}
    for i = 1, n do
        local link = GetQuestItemLink("choice", i)
        local itemId = ns.QuestState.ItemIdFromLink(link)
        if itemId then choices[#choices + 1] = { index = i, itemId = itemId, link = link } end
    end
    local pick = ns.Gear.BestChoice(choices, ns.QuestState.Player())
    local index = (pick and pick.index) or rewardIndexFor(GetQuestID and GetQuestID() or 0)
    if index then GetQuestReward(index) end
end)

---------------------------------------------------------------------------
-- Gossip and greeting lists: open the right quest for you
---------------------------------------------------------------------------
ns.RegisterEvent("GOSSIP_SHOW", function()
    if suspended() or not C_GossipInfo then return end
    if ns.db.autoTurnIn and C_GossipInfo.GetActiveQuests then
        for _, q in ipairs(C_GossipInfo.GetActiveQuests() or {}) do
            if q.isComplete and q.questID then
                C_GossipInfo.SelectActiveQuest(q.questID)
                return
            end
        end
    end
    if ns.db.autoAccept and C_GossipInfo.GetAvailableQuests then
        local wanted = plannedPickups()
        for _, q in ipairs(C_GossipInfo.GetAvailableQuests() or {}) do
            if q.questID and wanted[q.questID] then
                C_GossipInfo.SelectAvailableQuest(q.questID)
                return
            end
        end
    end
end)

ns.RegisterEvent("QUEST_GREETING", function()
    if suspended() then return end
    if ns.db.autoTurnIn and GetNumActiveQuests then
        for i = 1, GetNumActiveQuests() do
            local _, isComplete = GetActiveTitle(i)
            if isComplete then
                SelectActiveQuest(i)
                return
            end
        end
    end
    if ns.db.autoAccept and GetNumAvailableQuests and GetAvailableQuestInfo then
        local wanted = plannedPickups()
        for i = 1, GetNumAvailableQuests() do
            local questId = select(5, GetAvailableQuestInfo(i))
            if questId and wanted[questId] then
                SelectAvailableQuest(i)
                return
            end
        end
    end
end)
