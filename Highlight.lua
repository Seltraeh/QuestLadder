-- Quest Ladder: RuneLite-style boxes on the interface (cyan unless you pick a theme or color).
--   * the quest item to use / the hearthstone to press, inside your open bags
--   * the bag button holding it when the bags are closed ("open this bag")
--   * gear upgrades to equip, and junk to sell while a vendor window is open
--   * the reward to pick in the quest-complete window
--   * our "use item" button when it has something for you
-- Works with Blizzard's bags, Bagnon/Bagnonium and Baganator.
-- Boxes are plain overlay frames. Boxes on bag item buttons and reward buttons are children of
-- the button (like CanIMogIt's overlays), so they stay above it when its window is raised; the
-- rest are parented to UIParent. Nothing is ever changed on the buttons themselves.

local _, ns = ...
local HL = {}
ns.Highlight = HL

local pool, active = {}, {}

--- Line thickness from the options (1-4 pixels).
function HL.Thickness()
    local t = tonumber(ns.db.markerThickness) or 2
    return math.max(1, math.min(4, math.floor(t + 0.5)))
end

--- Colors a box (or a nameplate marker: same layout) with the theme's marker color and the
--- chosen thickness. `f.edges` holds { texture, horizontal } pairs.
function HL.Paint(f)
    local r, g, b = ns.Theme.Color("marker")
    local thick = HL.Thickness()
    for _, e in ipairs(f.edges or {}) do
        e[1]:SetColorTexture(r, g, b, 1)
        if e[2] then e[1]:SetHeight(thick) else e[1]:SetWidth(thick) end
    end
    if f.label then f.label:SetTextColor(r, g, b) end
    f.paintedVersion, f.paintedThickness = ns.Theme.version, thick
end

--- True when a box was painted before the last color or thickness change.
function HL.NeedsPaint(f)
    return f.paintedVersion ~= ns.Theme.version or f.paintedThickness ~= HL.Thickness()
end

--- The four edges of a box around `f`, painted.
function HL.AddEdges(f)
    f.edges = {}
    for _, spec in ipairs({ { "TOPLEFT", "TOPRIGHT", true }, { "BOTTOMLEFT", "BOTTOMRIGHT", true },
                            { "TOPLEFT", "BOTTOMLEFT", false }, { "TOPRIGHT", "BOTTOMRIGHT", false } }) do
        local t = f:CreateTexture(nil, "OVERLAY")
        t:SetPoint(spec[1])
        t:SetPoint(spec[2])
        f.edges[#f.edges + 1] = { t, spec[3] }
    end
end

---------------------------------------------------------------------------
-- Box frames
---------------------------------------------------------------------------
local function newBox()
    local f = CreateFrame("Frame", nil, UIParent)
    f:EnableMouse(false)
    HL.AddEdges(f)
    f.label = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.label:SetPoint("BOTTOM", f, "TOP", 0, 1)
    if f.CreateAnimationGroup then
        local ag = f:CreateAnimationGroup()
        ag:SetLooping("BOUNCE")
        local a = ag:CreateAnimation("Alpha")
        a:SetFromAlpha(1)
        a:SetToAlpha(0.35)
        a:SetDuration(0.6)
        f.pulse = ag
    end
    HL.Paint(f)
    f:Hide()
    return f
end

--- Starts or stops a box's fading, as the options say.
local function setPulse(box)
    if not box.pulse then return end
    if ns.db.markerPulse then
        if not box.pulsing then box.pulse:Play(); box.pulsing = true end
    else
        if box.pulsing then box.pulse:Stop(); box.pulsing = false end
        box:SetAlpha(1)
    end
end

--- Shows (or moves) the box `key` around `target`.
--- With `attach`, the box becomes a child of the target (item buttons in bags and the reward
--- window). Those windows raise themselves, and everything inside them, when you click or sort
--- them; a box floating on UIParent then ends up underneath. As a child it moves, rises and hides
--- with its window. Other targets (the bag bar, our use button) keep a UIParent box.
function HL.Box(key, target, label, pad, attach)
    if not target then return HL.Clear(key) end
    local box = active[key]
    if not box then
        box = table.remove(pool) or newBox()
        active[key] = box
    end
    attach = attach and true or false
    if box.target ~= target or box.attached ~= attach then
        -- Re-anchoring next to a protected button is fine for our own frame, but be
        -- conservative in combat and keep the old position until it ends.
        if InCombatLockdown() and target.IsProtected and target:IsProtected() and box.target then return box end
        pad = pad or 1
        local parent = attach and target or UIParent
        if box:GetParent() ~= parent then box:SetParent(parent) end
        box:ClearAllPoints()
        box:SetPoint("TOPLEFT", target, "TOPLEFT", -pad, pad)
        box:SetPoint("BOTTOMRIGHT", target, "BOTTOMRIGHT", pad, -pad)
        box.target, box.attached = target, attach
    end
    -- Layering is re-applied on every update, not just when placed: the target's window may
    -- have been raised since. (Only our own unprotected frame is touched.)
    if target.GetFrameStrata then box:SetFrameStrata(target:GetFrameStrata()) end
    if target.GetFrameLevel then box:SetFrameLevel((target:GetFrameLevel() or 1) + (attach and 10 or 20)) end
    if HL.NeedsPaint(box) then HL.Paint(box) end
    box.label:SetText(ns.db.markerLabels and label or "")
    if not box:IsShown() then box:Show() end
    setPulse(box)
    return box
end

function HL.Clear(key)
    local box = active[key]
    if not box then return end
    active[key] = nil
    if box.pulse then box.pulse:Stop() end
    box.pulsing = false
    box:Hide()
    box:ClearAllPoints()
    -- Don't leave pooled boxes inside Blizzard's (or a bag add-on's) frames.
    if box.attached then box:SetParent(UIParent) end
    box.target, box.attached = nil, false
    pool[#pool + 1] = box
end

function HL.ClearAll()
    for key in pairs(active) do HL.Clear(key) end
end

function HL.Active() return active end

---------------------------------------------------------------------------
-- Finding Blizzard's buttons
---------------------------------------------------------------------------
local function matchIn(frame, bag, slot)
    if not (frame and frame.IsShown and frame:IsShown() and frame.EnumerateValidItems) then return nil end
    local ok, found = pcall(function()
        for _, button in frame:EnumerateValidItems() do
            if button.GetBagID and button:GetBagID() == bag and button:GetID() == slot then return button end
        end
    end)
    return ok and found or nil
end

--- The bag slot button for (bag, slot) if that bag is open in Blizzard's bag frames.
--- (Third-party bag add-ons draw their own buttons; then only the bag-bar box is shown.)
function HL.BagItemButton(bag, slot)
    -- Bagnon / Baganator first, when installed
    local fromAddon = HL.AddonItemButton(bag, slot)
    if fromAddon then return fromAddon end
    -- Modern container frames (Forever uses the Mainline UI)
    if ContainerFrameCombinedBags then
        local b = matchIn(ContainerFrameCombinedBags, bag, slot)
        if b then return b end
    end
    if ContainerFrameUtil_EnumerateContainerFrames then
        local ok, found = pcall(function()
            for _, frame in ContainerFrameUtil_EnumerateContainerFrames() do
                local b = matchIn(frame, bag, slot)
                if b then return b end
            end
        end)
        if ok and found then return found end
    end
    -- Classic-style numbered frames
    for i = 1, (NUM_CONTAINER_FRAMES or 13) do
        local frame = _G["ContainerFrame" .. i]
        if frame and frame:IsShown() and frame.GetID and frame:GetID() == bag then
            for j = 1, 40 do
                local b = _G["ContainerFrame" .. i .. "Item" .. j]
                if not b then break end
                if b:GetID() == slot then return b end
            end
        end
    end
    return nil
end

---------------------------------------------------------------------------
-- Bag add-ons: Bagnon / Bagnonium (BagBrother core) and Baganator draw their own item
-- buttons. Both expose bag + slot on each button, so we walk their visible windows and
-- index the buttons by "bag:slot". The index is rebuilt when it goes stale.
---------------------------------------------------------------------------
local addonIndex, addonIndexTime = {}, 0

local function buttonBag(b)
    if b.GetBag then
        local ok, v = pcall(b.GetBag, b)
        if ok and type(v) == "number" then return v end
    end
    if b.GetBagID then
        local ok, v = pcall(b.GetBagID, b)
        if ok and type(v) == "number" then return v end
    end
    return nil
end

local function isItemButton(f)
    if not (f.GetID and (f.GetBag or f.GetBagID)) then return false end
    if f.IsObjectType then
        local ok1, isItem = pcall(f.IsObjectType, f, "ItemButton")
        local ok2, isButton = pcall(f.IsObjectType, f, "Button")
        return (ok1 and isItem) or (ok2 and isButton) or false
    end
    return true
end

local function collect(frame, out, depth)
    if depth > 8 or not frame or not frame.GetChildren then return end
    for _, child in ipairs({ frame:GetChildren() }) do
        if child.IsVisible and child:IsVisible() then
            if isItemButton(child) then
                local bag, slot = buttonBag(child), child:GetID()
                if bag and type(slot) == "number" and slot > 0 then out[bag .. ":" .. slot] = child end
            else
                collect(child, out, depth + 1)
            end
        end
    end
end

--- Visible top-level windows of supported bag add-ons.
function HL.AddonBagRoots()
    local roots = {}
    -- Bagnon / Bagnonium: frames registered with BagBrother.Frames (entries become frames once built)
    if BagBrother and BagBrother.Frames and BagBrother.Frames.Iterate then
        pcall(function()
            for _, f in BagBrother.Frames:Iterate() do
                if type(f) == "table" and f.IsVisible and f[0] and f:IsVisible() and (f.id == nil or f.id == "inventory") then
                    roots[#roots + 1] = f
                end
            end
        end)
    end
    -- Baganator: one backpack window per skin ("frame group")
    if Baganator then
        local skins = { "", "blizzard", "dark", "elvui", "gw2_ui", "ndui" }
        if Baganator.API and Baganator.API.Skins and Baganator.API.Skins.GetCurrentSkin then
            local ok, current = pcall(Baganator.API.Skins.GetCurrentSkin)
            if ok and type(current) == "string" then table.insert(skins, 1, current) end
        end
        for _, skin in ipairs(skins) do
            for _, prefix in ipairs({ "Baganator_SingleViewBackpackViewFrame", "Baganator_CategoryViewBackpackViewFrame" }) do
                local f = _G[prefix .. skin]
                if f and f.IsVisible and f:IsVisible() then roots[#roots + 1] = f end
            end
        end
    end
    return roots
end

function HL.UsingBagAddon()
    return (BagBrother ~= nil and BagBrother.Frames ~= nil) or Baganator ~= nil
end

local function rebuildAddonIndex()
    addonIndex = {}
    for _, root in ipairs(HL.AddonBagRoots()) do collect(root, addonIndex, 0) end
    -- Bagnon also names its buttons globally; cheap fallback if the walk found nothing.
    if next(addonIndex) == nil and BagBrother then
        for _, prefix in ipairs({ "BagBrotherContainerItem", "BagBrotherItem" }) do
            for i = 1, 400 do
                local b = _G[prefix .. i]
                if not b then break end
                if b:IsVisible() then
                    local bag, slot = buttonBag(b), b:GetID()
                    if bag and slot and slot > 0 then addonIndex[bag .. ":" .. slot] = b end
                end
            end
        end
    end
    addonIndexTime = GetTime and GetTime() or 0
end
HL.RebuildAddonIndex = rebuildAddonIndex

--- Button for (bag, slot) inside a bag add-on's window, or nil.
function HL.AddonItemButton(bag, slot)
    if not HL.UsingBagAddon() then return nil end
    local key = bag .. ":" .. slot
    local b = addonIndex[key]
    -- Buttons are recycled when bags change: verify before trusting the cache.
    if b and b:IsVisible() and buttonBag(b) == bag and b:GetID() == slot then return b end
    local now = GetTime and GetTime() or 0
    if not b or now - addonIndexTime > 0.5 then
        rebuildAddonIndex()
        b = addonIndex[key]
        if b and b:IsVisible() then return b end
    end
    return nil
end

--- The bag button on the action bar for a bag (0 = backpack).
function HL.BagBarButton(bag)
    local b
    -- One-big-inventory add-ons open everything from the backpack button.
    if bag == 0 or HL.UsingBagAddon() then b = MainMenuBarBackpackButton
    else b = _G["CharacterBag" .. (bag - 1) .. "Slot"] end
    if b and b.IsVisible and b:IsVisible() then return b end
    return nil
end

--- The quest reward button for choice `index` in the open quest-complete window.
function HL.RewardButton(index)
    local rf = QuestInfoRewardsFrame
    if rf and rf.RewardButtons then
        for _, b in ipairs(rf.RewardButtons) do
            if b:IsShown() and (b.type == nil or b.type == "choice") and b:GetID() == index then return b end
        end
    end
    for _, name in ipairs({ "QuestInfoRewardsFrameQuestInfoItem", "QuestRewardItem" }) do
        local b = _G[name .. index]
        if b and b:IsShown() then return b end
    end
    return nil
end

---------------------------------------------------------------------------
-- What to highlight
---------------------------------------------------------------------------
HL.rewardIndex = nil

local function firstSlot(bags, itemId)
    for _, s in ipairs((bags and bags.slots) or {}) do
        if s.itemId == itemId then return s end
    end
    return nil
end

local function slotAt(bags, bag, slot)
    for _, s in ipairs((bags and bags.slots) or {}) do
        if s.bag == bag and s.slot == slot then return s end
    end
    return nil
end

--- env = { bags = QS.Bags(), suggestions = Bags.Suggestions(...) }
function HL.Update(env)
    if not ns.db.highlights then HL.ClearAll() return end
    env = env or {}
    local bags = env.bags or ns.QuestState.Bags()
    local want = {}
    local items = {} -- ordered { itemId, label }

    local use = ns.Hints and ns.Hints.UsableItem()
    if use then
        items[#items + 1] = { itemId = use.itemId,
            label = (ns.Travel and use.itemId == ns.Travel.HEARTHSTONE) and "Hearth" or "Use" }
    end
    for _, e in ipairs(env.suggestions or {}) do
        if e.action == "equip" then items[#items + 1] = { itemId = e.itemId, label = "Equip", bag = e.bag, slot = e.slot } end
    end
    local atVendor = MerchantFrame and MerchantFrame.IsShown and MerchantFrame:IsShown()
    if atVendor then
        local n = 0
        for _, e in ipairs(env.suggestions or {}) do
            if e.action == "sell" and n < 10 then
                items[#items + 1] = { itemId = e.itemId, label = "Sell", bag = e.bag, slot = e.slot }
                n = n + 1
            end
        end
    end

    local bagBoxes = {}
    for _, it in ipairs(items) do
        -- A suggestion's bag/slot goes stale when items move: use it only if the item is still there.
        local s
        if it.bag and it.slot then
            local at = slotAt(bags, it.bag, it.slot)
            if at and at.itemId == it.itemId then s = at end
        end
        s = s or firstSlot(bags, it.itemId)
        if s and s.bag then
            local key = "i:" .. s.bag .. ":" .. s.slot
            local btn = HL.BagItemButton(s.bag, s.slot)
            if btn then
                local box = HL.Box(key, btn, it.label, 1, true)
                if box then box.itemId = it.itemId end
                want[key] = true
            elseif not bagBoxes[s.bag] then
                local bb = HL.BagBarButton(s.bag)
                if bb then
                    local bkey = "b:" .. s.bag
                    -- Say why: "Open: Use", "Open: Equip", "Open: Hearth", "Open: Sell"
                    local box = HL.Box(bkey, bb, "Open: " .. it.label, 2)
                    if box then box.itemId = it.itemId end
                    want[bkey] = true
                    bagBoxes[s.bag] = true
                end
            end
        end
    end

    local useBtn = QuestLadderUseButton
    if use and useBtn and useBtn:IsShown() then
        HL.Box("use", useBtn, nil, 2)
        want.use = true
    end

    if HL.rewardIndex and QuestFrame and QuestFrame:IsShown() then
        local rb = HL.RewardButton(HL.rewardIndex)
        if rb then
            HL.Box("reward", rb, "Pick this", 2, true)
            want.reward = true
        end
    end

    for key in pairs(active) do
        if not want[key] then HL.Clear(key) end
    end
end

---------------------------------------------------------------------------
-- Events and hooks for instant updates
---------------------------------------------------------------------------
local function soon() ns.Debounce("highlight", 0.05, function() ns.Fire("HIGHLIGHT_REFRESH") end) end

ns.RegisterEvent("QUEST_COMPLETE", function()
    HL.rewardIndex = nil
    local n = GetNumQuestChoices and GetNumQuestChoices() or 0
    if n > 1 then
        local choices = {}
        for i = 1, n do
            local link = GetQuestItemLink("choice", i)
            local itemId = ns.QuestState.ItemIdFromLink(link)
            if itemId then choices[#choices + 1] = { index = i, itemId = itemId, link = link } end
        end
        local pick = ns.Gear.BestChoice(choices, ns.QuestState.Player())
        HL.rewardIndex = pick and pick.index
    end
    soon()
end)
ns.RegisterEvent("QUEST_FINISHED", function() HL.rewardIndex = nil; HL.Clear("reward") end)
ns.RegisterEvent("MERCHANT_SHOW", soon)
ns.RegisterEvent("MERCHANT_CLOSED", soon)

--- 0.6.0: a new color, thickness, label or pulse setting shows on the boxes already up.
function HL.Restyle()
    for _, box in pairs(active) do
        if HL.NeedsPaint(box) then HL.Paint(box) end
        setPulse(box)
    end
    soon()
end
ns.On("THEME_CHANGED", HL.Restyle)
ns.On("SETTINGS_CHANGED", HL.Restyle)

ns.On("SETTINGS_LOADED", function()
    if not hooksecurefunc then return end
    for _, fn in ipairs({ "ToggleAllBags", "OpenAllBags", "CloseAllBags", "ToggleBag", "OpenBag",
                          "ToggleBackpack", "OpenBackpack" }) do
        if _G[fn] then hooksecurefunc(fn, soon) end
    end
end)
