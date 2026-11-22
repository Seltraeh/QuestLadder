-- Quest Ladder: guide window (RuneLite-style "quick guide"), hint box, bag and gear panels.

local _, ns = ...
local UI = {}
ns.UI = UI

local Geo, Ladder, Hints = ns.Geo, ns.Ladder, ns.Hints

local MAX_TASK_LINES = 7
local MAX_NEXT_LINES = 6
local MAX_HINT_LINES = 4
local COMPACT_HINT_LINES = 2
local COMPACT_MAX_NEXT = 3
UI.MIN_WIDTH, UI.MAX_WIDTH = 260, 520

local BACKDROP = {
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
}

local function clamp(v, lo, hi, default)
    v = tonumber(v) or default
    return math.max(lo, math.min(hi, math.floor(v + 0.5)))
end

--- The guide's width from the options (the hint box matches it).
function UI.Width()
    return clamp(ns.db.guideWidth, UI.MIN_WIDTH, UI.MAX_WIDTH, 340)
end

--- How many lines of the current step, upcoming steps and hints the guide shows right now.
function UI.Limits()
    local compact = ns.db.compact and true or false
    local hints = clamp(ns.db.hintLines, 1, MAX_HINT_LINES, MAX_HINT_LINES)
    if compact then
        return { compact = true, tasks = clamp(ns.db.compactTaskLines, 1, MAX_TASK_LINES, 3),
                 next = clamp(ns.db.compactNextSteps, 0, COMPACT_MAX_NEXT, 1),
                 hints = math.min(hints, COMPACT_HINT_LINES), buttons = false, bagLine = false, gearLine = false }
    end
    return { compact = false, tasks = MAX_TASK_LINES, next = clamp(ns.db.nextStepsShown, 0, MAX_NEXT_LINES, 4),
             hints = hints, buttons = ns.db.showButtons and true or false,
             bagLine = ns.db.showBagLine and true or false, gearLine = ns.db.showGearLine and true or false }
end

local function shown(frame, on)
    if on then frame:Show() else frame:Hide() end
end

-- Windows painted with the theme's colors, repainted when they change.
local styledFrames = {}

local function paintFrame(frame)
    if not frame.SetBackdropColor then return end
    local r, g, b = ns.Theme.Color(frame.bgRole or "background")
    local a = tonumber(ns.db.bgAlpha) or 0.85
    a = math.max(frame.minAlpha or 0, math.min(1, math.max(0, a)))
    frame:SetBackdropColor(r, g, b, a)
    local br, bgc, bb = ns.Theme.Color("border")
    frame:SetBackdropBorderColor(br, bgc, bb, 1)
end

local function styled(frame, bgRole, minAlpha)
    if frame.SetBackdrop then frame:SetBackdrop(BACKDROP) end
    frame.bgRole, frame.minAlpha = bgRole, minAlpha
    styledFrames[#styledFrames + 1] = frame
    paintFrame(frame)
end

--- Repaints every window (theme, colors or opacity changed).
function UI.Restyle()
    for _, f in ipairs(styledFrames) do paintFrame(f) end
end

--- "Quest Ladder" in the accent color, with the icon in front.
local function titled(text, size)
    return ns.Theme.IconText(size or 14) .. " " .. ns.Theme.Wrap("accent", "Quest Ladder") .. (text or "")
end

local function fontString(parent, template, width)
    local fs = parent:CreateFontString(nil, "OVERLAY", template)
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(true)
    if width then fs:SetWidth(width) end
    return fs
end

local function smallButton(parent, text, onClick, width)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width or 48, 18)
    b:SetText(text)
    b:SetNormalFontObject("GameFontNormalSmall")
    b:SetHighlightFontObject("GameFontHighlightSmall")
    b:SetScript("OnClick", onClick)
    return b
end

---------------------------------------------------------------------------
-- Guide window
---------------------------------------------------------------------------
local guide

local function savePosition(frame)
    local point, _, relPoint, x, y = frame:GetPoint()
    ns.charDB.frame = { point = point, relPoint = relPoint, x = x, y = y }
end

--- Puts the guide back where it starts (right side of the screen).
function UI.ResetPosition()
    ns.charDB.frame = {}
    if not guide then return end
    guide:ClearAllPoints()
    guide:SetPoint("RIGHT", UIParent, "RIGHT", -60, 120)
    UI.PlaceUseButton()
end

--- Compact mode on or off (the title bar's -/+ button, the icon's right-click).
function UI.ToggleCompact()
    ns.db.compact = not ns.db.compact
    ns.Fire("SETTINGS_CHANGED")
end

local function iconTooltip(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
    GameTooltip:AddLine(titled(" " .. tostring(ns.VERSION)), 1, 1, 1)
    GameTooltip:AddLine("Click: options", 1, 1, 1)
    GameTooltip:AddLine("Right-click: compact mode " .. (ns.db.compact and "off" or "on"), 1, 1, 1)
    GameTooltip:AddLine(ns.db.lockGuide and "The window is locked (unlock it in the options)"
        or "Drag the window to move it", 0.7, 0.7, 0.7)
    GameTooltip:Show()
end

local function buildGuide()
    local width = UI.Width()
    guide = CreateFrame("Frame", "QuestLadderGuideFrame", UIParent, "BackdropTemplate")
    styled(guide, "background")
    guide:SetSize(width, 120)
    guide:SetClampedToScreen(true)
    guide:SetMovable(true)
    guide:EnableMouse(true)
    guide:RegisterForDrag("LeftButton")
    guide:SetScript("OnDragStart", function(self)
        if not ns.db.lockGuide then self:StartMoving() end
    end)
    guide:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        savePosition(self)
        UI.PlaceUseButton()
    end)
    local pos = ns.charDB.frame
    if pos and pos.point then
        guide:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
    else
        guide:SetPoint("RIGHT", UIParent, "RIGHT", -60, 120)
    end

    -- 0.6.0: the icon opens the options (right-click: compact mode)
    guide.icon = CreateFrame("Button", nil, guide)
    guide.icon:SetSize(16, 16)
    guide.icon:SetPoint("TOPLEFT", 7, -6)
    guide.icon.tex = guide.icon:CreateTexture(nil, "ARTWORK")
    guide.icon.tex:SetAllPoints()
    guide.icon.tex:SetTexture(ns.Theme.ICON)
    guide.icon:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    guide.icon:SetScript("OnClick", function(_, button)
        if button == "RightButton" then UI.ToggleCompact() else ns.Fire("OPEN_OPTIONS") end
    end)
    guide.icon:SetScript("OnEnter", iconTooltip)
    guide.icon:SetScript("OnLeave", function() GameTooltip:Hide() end)

    guide.title = fontString(guide, "GameFontNormalSmall")
    guide.title:SetWordWrap(false)
    guide.title:SetPoint("LEFT", guide.icon, "RIGHT", 4, 0)

    guide.counter = fontString(guide, "GameFontHighlightSmall")
    guide.counter:SetWordWrap(false)
    guide.counter:SetPoint("LEFT", guide.title, "RIGHT", 6, 0)

    local close = CreateFrame("Button", nil, guide, "UIPanelCloseButton")
    close:SetSize(20, 20)
    close:SetPoint("TOPRIGHT", 0, 0)
    close:SetScript("OnClick", function() ns.db.showGuide = false; UI.Refresh() end)

    guide.compactBtn = smallButton(guide, "-", function() UI.ToggleCompact() end, 18)
    guide.compactBtn:SetPoint("TOPRIGHT", -22, -5)
    guide.compactBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(ns.db.compact and "Full mode: every line, upcoming steps, buttons"
            or "Compact mode: just the current step", 1, 1, 1)
        GameTooltip:Show()
    end)
    guide.compactBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    guide.gearBtn = smallButton(guide, "Gear", function() UI.ShowPanel("gear") end, 40)
    guide.gearBtn:SetPoint("RIGHT", guide.compactBtn, "LEFT", -2, 0)
    guide.bagsBtn = smallButton(guide, "Bags", function() UI.ShowPanel("bags") end, 40)
    guide.bagsBtn:SetPoint("RIGHT", guide.gearBtn, "LEFT", -2, 0)
    guide.replanBtn = smallButton(guide, "Replan", function() ns.Fire("REQUEST_REPLAN", "button") end, 50)
    guide.replanBtn:SetPoint("RIGHT", guide.bagsBtn, "LEFT", -2, 0)
    guide.skipBtn = smallButton(guide, "Skip", function() ns.Fire("SKIP_STEP") end, 40)
    guide.skipBtn:SetPoint("RIGHT", guide.replanBtn, "LEFT", -2, 0)

    guide.header = fontString(guide, "GameFontNormalLarge", width - 20)
    guide.header:SetPoint("TOPLEFT", 10, -30)

    guide.distance = fontString(guide, "GameFontHighlightSmall", width - 20)
    guide.distance:SetPoint("TOPLEFT", guide.header, "BOTTOMLEFT", 0, -2)

    guide.tasks = {}
    for i = 1, MAX_TASK_LINES do
        local fs = fontString(guide, "GameFontHighlight", width - 24)
        guide.tasks[i] = fs
    end
    guide.nextLabel = fontString(guide, "GameFontDisableSmall")
    guide.nextLabel:SetText("Then:")
    guide.next = {}
    for i = 1, MAX_NEXT_LINES do
        guide.next[i] = fontString(guide, "GameFontDisableSmall", width - 24)
    end
    guide.footer = fontString(guide, "GameFontHighlightSmall", width - 20)
    guide.footer2 = fontString(guide, "GameFontHighlightSmall", width - 20)
end

--- Title bar: icon, name, step counter, then the buttons on the right. The name steps aside
--- when the window is too narrow for it (the icon stays).
local function layoutTitle(limits)
    for _, b in ipairs({ guide.skipBtn, guide.replanBtn, guide.bagsBtn, guide.gearBtn }) do shown(b, limits.buttons) end
    guide.compactBtn:SetText(limits.compact and "+" or "-")
    guide.title:SetText(ns.Theme.Wrap("accent", "Quest Ladder"))
    local right = 22 + 20 + (limits.buttons and 178 or 0)
    local room = UI.Width() - right - 7 - 16 - 4
    local need = (guide.title:GetStringWidth() or 0) + 6 + (guide.counter:GetStringWidth() or 0)
    local showName = need <= room
    shown(guide.title, showName)
    guide.counter:ClearAllPoints()
    if showName then
        guide.counter:SetPoint("LEFT", guide.title, "RIGHT", 6, 0)
    else
        guide.counter:SetPoint("LEFT", guide.icon, "RIGHT", 4, 0)
    end
end

--- Widths and fonts that follow the options.
local function applyWidths(limits)
    local width = UI.Width()
    guide:SetWidth(width)
    for _, fs in ipairs({ guide.header, guide.distance, guide.footer, guide.footer2 }) do fs:SetWidth(width - 20) end
    for _, fs in ipairs(guide.tasks) do fs:SetWidth(width - 24) end
    for _, fs in ipairs(guide.next) do fs:SetWidth(width - 24) end
    local font = _G[limits.compact and "GameFontNormal" or "GameFontNormalLarge"]
    if font then guide.header:SetFontObject(font) end
end

local function check(done) return done and "|TInterface\\RaidFrame\\ReadyCheck-Ready:12|t " or "|cffffffff-|r " end

--- The current step's travel line, worked out from where you stand (fly or walk, with the other
--- way's time; hearth). The ticker redraws the guide when it changes.
local shownTravel
local function travelLine(step)
    local live = step and Ladder.LiveTravel(step, Geo.PlayerPoint())
    return Ladder.TravelText(step, live), live
end

--- Countdown lines for timed quests (Ladder.TimerText), redrawn every second by the ticker.
local shownTimers
local function timerText()
    local out = {}
    for _, e in ipairs(Ladder.TimedQuests()) do out[#out + 1] = Ladder.TimerText(e) end
    return table.concat(out, " | "), out
end

local function layoutGuide()
    local limits = UI.Limits()
    local plan = Ladder.plan
    local step = Ladder.CurrentStep()
    local y = guide.distance:GetStringHeight() + guide.header:GetStringHeight() + 34
    local anchor = guide.distance

    -- a timed quest's countdown first, then the current step: travel line (fly / walk / hearth), tasks
    local lines = {}
    local timers, timerList = timerText()
    shownTimers = timers
    for _, l in ipairs(timerList) do lines[#lines + 1] = l end
    local travel = travelLine(step)
    shownTravel = travel
    if travel then lines[#lines + 1] = travel end
    for _, t in ipairs(step and step.tasks or {}) do
        lines[#lines + 1] = check(t.isDone) .. Ladder.TaskText(t)
    end
    local count = 0
    -- the last line says how many more there are when the window can't show them all
    local cap = math.min(limits.tasks, MAX_TASK_LINES)
    for i = 1, MAX_TASK_LINES do
        local fs = guide.tasks[i]
        local text = (i <= cap) and lines[i] or nil
        if text then
            if i == cap and #lines > cap then
                text = text .. string.format(" |cff888888(+%d more)|r", #lines - cap)
            end
            fs:SetText(text)
            fs:ClearAllPoints()
            fs:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", (i == 1) and 4 or 0, -4)
            fs:Show()
            anchor = fs
            y = y + fs:GetStringHeight() + 4
            count = count + 1
        else
            fs:Hide()
        end
    end

    -- upcoming steps
    local nextCount = 0
    if plan then
        for i = 1, math.min(limits.next, MAX_NEXT_LINES) do
            local s = plan.steps[Ladder.current + i]
            local fs = guide.next[i]
            if s then
                local first = s.tasks[1]
                local detail = first and Ladder.TaskText(first) or ""
                detail = detail:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
                local more = (#s.tasks > 1) and string.format(" (+%d)", #s.tasks - 1) or ""
                fs:SetText(string.format("%d. %s: %s%s", Ladder.current + i, Ladder.StepTitle(s), detail, more))
                nextCount = nextCount + 1
            end
        end
    end
    if nextCount > 0 then
        guide.nextLabel:ClearAllPoints()
        guide.nextLabel:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", (count > 0) and -4 or 0, -8)
        guide.nextLabel:Show()
        y = y + guide.nextLabel:GetStringHeight() + 8
        anchor = guide.nextLabel
        for i = 1, MAX_NEXT_LINES do
            local fs = guide.next[i]
            if i <= nextCount then
                fs:ClearAllPoints()
                fs:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", (i == 1) and 4 or 0, -2)
                fs:Show()
                anchor = fs
                y = y + fs:GetStringHeight() + 2
            else
                fs:Hide()
            end
        end
    else
        guide.nextLabel:Hide()
        for i = 1, MAX_NEXT_LINES do guide.next[i]:Hide() end
    end

    -- footer: bags + gear (each can be switched off; compact mode leaves both out)
    local bagLine = limits.bagLine and ns.Bags.Summary(plan) or nil
    local gearLine
    if limits.gearLine then
        local upgrade
        for _, u in ipairs(ns.Gear.QuestUpgradeList()) do
            if u.step >= Ladder.current then upgrade = u break end
        end
        gearLine = upgrade and string.format("Gear: |cff00ff00%s|r (%s) from step %d",
            upgrade.name, ns.Gear.PctText(upgrade.pct), upgrade.step) or nil
    end
    if limits.bagLine or limits.gearLine then
        guide.footer:ClearAllPoints()
        guide.footer:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", (anchor == guide.distance) and 0 or -4, -8)
        guide.footer:SetText(bagLine or "")
        guide.footer:Show()
        y = y + guide.footer:GetStringHeight() + 8
        guide.footer2:ClearAllPoints()
        guide.footer2:SetPoint("TOPLEFT", guide.footer, "BOTTOMLEFT", 0, -2)
        guide.footer2:SetText(gearLine or "")
        guide.footer2:Show()
        y = y + guide.footer2:GetStringHeight() + 10
    else
        guide.footer:SetText("")
        guide.footer2:SetText("")
        guide.footer:Hide()
        guide.footer2:Hide()
        y = y + 6
    end
    guide:SetHeight(math.max(y, limits.compact and 40 or 60))
end

local function updateDistance()
    local step = Ladder.CurrentStep()
    if step and step.travel and step.travel.mode == "hearth" then
        guide.distance:SetText("|cff66ccffUse your Hearthstone (button below)|r")
        return
    end
    if not step or not step.loc then
        guide.distance:SetText(step and "|cff888888location unknown - check the quest log map|r" or "")
        return
    end
    local here = Geo.PlayerPoint()
    local d = here and Geo.Distance(here, step.loc)
    -- the time for the way you'd go from here: walking, a flight or a zeppelin (see the travel line)
    local live = here and Ladder.LiveTravel(step, here)
    local way = live and ((live.mode == "fly" and live.fly) or (live.mode == "zeppelin" and live.zeppelin))
    local by = way and ((live.mode == "fly") and " by flight" or " by zeppelin") or ""
    if d and d < math.huge then
        local eta = way and way.total or (live and live.walk) or d / Geo.RUN_SPEED
        guide.distance:SetText(string.format("%d yards (~%s%s)", math.floor(d), Ladder.Clock(eta), by))
    elseif d == math.huge then
        guide.distance:SetText("|cffff8800on another continent|r" .. (way and string.format(" (~%s%s)", Ladder.Clock(way.total), by) or ""))
    else
        guide.distance:SetText("")
    end
end

function UI.RefreshGuide()
    if not guide then return end
    if not ns.db.showGuide then guide:Hide() return end
    guide:Show()
    guide:SetScale(math.max(0.5, math.min(2, tonumber(ns.db.guideScale) or 1)))
    local limits = UI.Limits()
    applyWidths(limits)
    local plan = Ladder.plan
    local step = Ladder.CurrentStep()
    if not plan then
        guide.counter:SetText("")
        guide.header:SetText(Ladder.status or "Planning...")
    elseif not step then
        guide.counter:SetText("")
        guide.header:SetText(plan.nextArea
            and ("Nothing worth doing left here. Next area: " .. Ladder.NextAreaText(plan.nextArea))
            or "Nothing left to plan here - press Replan after moving to a new area")
    else
        guide.counter:SetText(string.format("step %d/%d", Ladder.current, #plan.steps))
        guide.header:SetText(Ladder.StepTitle(step))
    end
    layoutTitle(limits)
    updateDistance()
    layoutGuide()
end

---------------------------------------------------------------------------
-- Hint box + secure "use item" button
---------------------------------------------------------------------------
local hintFrame, useButton
local pendingUseItem, pendingPlace

local function buildHints()
    hintFrame = CreateFrame("Frame", "QuestLadderHintFrame", UIParent, "BackdropTemplate")
    styled(hintFrame, "hintBackground")
    hintFrame:SetSize(UI.Width(), 40)
    hintFrame:SetPoint("TOPLEFT", guide, "BOTTOMLEFT", 0, -4)
    hintFrame.lines = {}
    hintFrame.hits = {}
    for i = 1, MAX_HINT_LINES do
        local fs = fontString(hintFrame, "GameFontHighlight", UI.Width() - 20)
        hintFrame.lines[i] = fs
        -- 0.3.29: a line that names a place (the Cozy Sleeping Bag start, a bag vendor) can be
        -- clicked for a map pin. A plain button over the line: no secure code, works in combat.
        local hit = CreateFrame("Button", nil, hintFrame)
        hit:SetPoint("TOPLEFT", fs, "TOPLEFT", 0, 0)
        hit:SetPoint("BOTTOMRIGHT", fs, "BOTTOMRIGHT", 0, 0)
        hit:RegisterForClicks("LeftButtonUp")
        hit:SetScript("OnClick", function(self) Ladder.PinHint(self.hint) end)
        hit:SetScript("OnEnter", function(self)
            local pin = self.hint and self.hint.pin
            if not pin then return end
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(titled(": click for a map pin", 12), 1, 1, 1)
            GameTooltip:AddLine((pin.title or "") .. ((ns.Goodies and ns.Goodies.PlaceText(pin)) and
                ("  " .. ns.Goodies.PlaceText(pin)) or ""), 1, 1, 1)
            GameTooltip:Show()
        end)
        hit:SetScript("OnLeave", function() GameTooltip:Hide() end)
        hit:Hide()
        hintFrame.hits[i] = hit
    end

    -- The secure button lives on UIParent (not inside our frames) so our own frames never
    -- become "protected" and can still be shown/hidden/moved in combat.
    useButton = CreateFrame("Button", "QuestLadderUseButton", UIParent, "SecureActionButtonTemplate")
    useButton:SetSize(36, 36)
    useButton:RegisterForClicks("AnyUp", "AnyDown")
    useButton:SetAttribute("type", "item")
    useButton.icon = useButton:CreateTexture(nil, "ARTWORK")
    useButton.icon:SetAllPoints()
    useButton:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    useButton:SetScript("OnEnter", function(self)
        if self.itemId then
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            GameTooltip:SetItemByID(self.itemId)
            GameTooltip:AddLine(titled(": click (or your key binding) to use", 12), 1, 1, 1)
            GameTooltip:Show()
        end
    end)
    useButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
    useButton:Hide()
end

function UI.PlaceUseButton()
    if not useButton or not hintFrame then return end
    if InCombatLockdown() then pendingPlace = true return end
    local left, top = hintFrame:GetLeft(), hintFrame:GetTop()
    if not left or not top then return end
    local scale = hintFrame:GetEffectiveScale() / UIParent:GetEffectiveScale()
    useButton:ClearAllPoints()
    useButton:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", left * scale - 4, top * scale)
end

local function setUseItem(itemId)
    if InCombatLockdown() then pendingUseItem = itemId or false return end
    if useButton.itemId == itemId then return end
    useButton.itemId = itemId
    if itemId then
        useButton:SetAttribute("item", "item:" .. itemId)
        local icon = C_Item.GetItemIconByID and C_Item.GetItemIconByID(itemId)
        useButton.icon:SetTexture(icon or 134400)
        UI.PlaceUseButton()
        useButton:Show()
    else
        useButton:SetAttribute("item", nil)
        useButton:Hide()
    end
end

function UI.RefreshHints()
    if not hintFrame then return end
    local list = Hints.list
    if not ns.db.showHints or not ns.db.showGuide or #list == 0 then
        hintFrame:Hide()
    else
        hintFrame:Show()
        local width = UI.Width()
        hintFrame:SetWidth(width)
        local maxLines = UI.Limits().hints
        local y, anchor = 8, nil
        for i = 1, MAX_HINT_LINES do
            local fs = hintFrame.lines[i]
            local hit = hintFrame.hits and hintFrame.hits[i]
            local h = (i <= maxLines) and list[i] or nil
            fs:SetWidth(width - 20)
            if h then
                fs:SetText(h.text .. (h.pin and " |cff888888(click for a map pin)|r" or ""))
                fs:ClearAllPoints()
                if anchor then fs:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -4)
                else fs:SetPoint("TOPLEFT", 10, -8) end
                fs:Show()
                anchor = fs
                y = y + fs:GetStringHeight() + 4
            else
                fs:Hide()
            end
            if hit then
                hit.hint = h
                if h and h.pin then hit:Show() else hit:Hide() end
            end
        end
        hintFrame:SetHeight(y + 6)
    end
    local usable = ns.db.showHints and Hints.UsableItem()
    setUseItem(usable and usable.itemId or nil)
end

---------------------------------------------------------------------------
-- List panel (bags / gear)
---------------------------------------------------------------------------
local panel
local PANEL_ROWS = 14

local function buildPanel()
    panel = CreateFrame("Frame", "QuestLadderPanel", UIParent, "BackdropTemplate")
    styled(panel, "background", 0.85)
    panel:SetSize(420, 60)
    panel:SetPoint("CENTER", 0, 80)
    panel:SetMovable(true)
    panel:EnableMouse(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", panel.StartMoving)
    panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
    panel:SetFrameStrata("DIALOG")
    tinsert(UISpecialFrames, "QuestLadderPanel") -- Escape closes it
    panel.title = fontString(panel, "GameFontNormal")
    panel.title:SetPoint("TOPLEFT", 10, -10)
    local close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 0, 0)
    panel.status = fontString(panel, "GameFontHighlightSmall", 400)
    panel.status:SetPoint("TOPLEFT", panel.title, "BOTTOMLEFT", 0, -4)
    panel.action = smallButton(panel, "Scan", function() end, 110)
    panel.action:SetPoint("TOPRIGHT", -26, -8)
    panel.rows = {}
    for i = 1, PANEL_ROWS do
        local row = CreateFrame("Button", nil, panel)
        row:SetSize(400, 20)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(18, 18)
        row.icon:SetPoint("LEFT", 0, 0)
        row.text = fontString(row, "GameFontHighlightSmall", 300)
        row.text:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
        row.text:SetWordWrap(false)
        row.button = smallButton(row, "Find", function(self) if self.onClick then self.onClick() end end, 60)
        row.button:SetPoint("RIGHT", 0, 0)
        row:SetScript("OnEnter", function(self)
            if self.link or self.itemId then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                if self.link then GameTooltip:SetHyperlink(self.link) else GameTooltip:SetItemByID(self.itemId) end
                GameTooltip:Show()
            end
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        row:SetScript("OnClick", function(self)
            if IsModifiedClick and IsModifiedClick("CHATLINK") and self.link then ChatEdit_InsertLink(self.link) end
        end)
        panel.rows[i] = row
    end
    panel:Hide()
end

local function fillRows(entries)
    local y = 46
    for i = 1, PANEL_ROWS do
        local row, e = panel.rows[i], entries[i]
        if e then
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 10, -y)
            row.icon:SetTexture((e.itemId and C_Item.GetItemIconByID and C_Item.GetItemIconByID(e.itemId)) or 134400)
            row.text:SetText(e.text)
            row.link, row.itemId = e.link, e.itemId
            if e.buttonText then
                row.button:SetText(e.buttonText)
                row.button.onClick = e.onClick
                row.button:Show()
            else
                row.button:Hide()
            end
            row:Show()
            y = y + 22
        else
            row:Hide()
        end
    end
    panel:SetHeight(y + 10)
end

local ACTION_LABEL = {
    sell = "|cffffff00Sell|r", destroy = "|cffff5555Destroy|r", ah = "|cff66ccffAH|r",
    bank = "|cffaaaaaaBank|r", equip = "|cff00ff00Equip|r",
}

local function showBags()
    panel.title:SetText(titled(" - bag planner"))
    local plan = Ladder.plan
    local bags = ns.QuestState.Bags()
    local list = ns.Bags.Suggestions(bags, Ladder.snapshot or {}, plan)
    local b = plan and plan.bags
    local status = string.format("%d free slots, keeping %d free.", bags.free, ns.db.reserveSlots)
    if b then
        status = status .. string.format(" Next %d steps need up to %d.", math.min(ns.db.lookahead, #plan.steps), b.peak)
        if b.needed > 0 then status = status .. string.format(" |cffff8800Free %d more.|r", b.needed) end
    end
    if plan and plan.vendorStop then status = status .. " A vendor stop was added to the route." end
    panel.status:SetText(status)
    panel.action:SetText("Refresh")
    panel.action:SetScript("OnClick", showBags)
    local entries = {}
    for _, e in ipairs(list) do
        local value = (e.value and e.value > 0) and ("  " .. ns.FormatMoney(e.value)) or ""
        entries[#entries + 1] = {
            itemId = e.itemId, link = e.link,
            text = string.format("%s %s%s - %s%s", ACTION_LABEL[e.action] or e.action, e.link or e.name or "?",
                (e.count and e.count > 1) and (" x" .. e.count) or "", e.reason, value),
        }
    end
    if #entries == 0 then entries[1] = { text = "Nothing to clear - your bags are fine for the plan." } end
    fillRows(entries)
end

local function showGear(scanned)
    panel.title:SetText(titled(" - gear upgrades"))
    local player = ns.QuestState.Player()
    local budget = ns.Gear.Budget(player)
    panel.status:SetText(string.format("Spending money: %s (keeping %s for training). %s",
        ns.FormatMoney(budget), ns.FormatMoney(ns.Gear.Reserve(player.level, player)),
        ns.Prices.HasAuctionator() and "Prices from Auctionator's last scan." or "|cffff8800Auctionator not found.|r"))
    panel.action:SetText("Find AH upgrades")
    panel.action:SetScript("OnClick", function()
        panel.status:SetText("Checking Auctionator prices...")
        ns.Gear.FindAHUpgrades(player, function() showGear(true) end)
    end)
    local entries = {}
    for _, u in ipairs(ns.Gear.QuestUpgradeList()) do
        entries[#entries + 1] = {
            itemId = u.itemId,
            text = string.format("|cff00ff00Quest|r %s: %s %s - step %d (%s)%s",
                ns.Gear.SLOT_NAMES[u.slot] or "?", u.name, ns.Gear.PctText(u.pct), u.step, u.title or "",
                u.maybe and " |cff888888(if chosen)|r" or ""),
        }
    end
    for _, r in ipairs(ns.Gear.ahResults or {}) do
        local note = ""
        if r.soon then note = string.format(" |cffff8800quest reward in step %d|r", r.soon.step) end
        if r.randomSuffix then note = note .. " |cff888888random stats: check listing|r" end
        local name = r.name
        entries[#entries + 1] = {
            itemId = r.itemId, link = r.link,
            text = string.format("|cff66ccffAH|r %s: %s %s ~%s%s", ns.Gear.SLOT_NAMES[r.slot] or "?",
                r.link or r.name, ns.Gear.PctText(r.pct), ns.FormatMoney(r.price), note),
            buttonText = "Find",
            onClick = function() ns.Prices.Search({ name }) end,
        }
    end
    if #entries == 0 then
        entries[1] = { text = scanned and (ns.Gear.ahStatus or "No upgrades found.")
            or "No quest-reward upgrades planned. Open the Auction House and press Find AH upgrades." }
    end
    fillRows(entries)
end

function UI.ShowPanel(which)
    if not panel then return end
    if panel:IsShown() and panel.which == which then panel:Hide() return end
    panel.which = which
    if which == "bags" then showBags() else showGear(false) end
    panel:Show()
end

---------------------------------------------------------------------------
-- Tooltip notes on items
---------------------------------------------------------------------------
local tooltipNotes = {}
local lastSuggestions = {}

local function rebuildTooltipNotes()
    tooltipNotes = {}
    local bags = ns.QuestState.Bags()
    lastSuggestions = ns.Bags.Suggestions(bags, Ladder.snapshot or {}, Ladder.plan)
    for _, e in ipairs(lastSuggestions) do
        tooltipNotes[e.itemId] = (ACTION_LABEL[e.action] or e.action) .. " - " .. e.reason
    end
end

local function hookTooltips()
    if not (TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType) then return end
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
        if tooltip ~= GameTooltip or not data then return end
        local id = data.id
        if ns.IsSecret(id) or not id then return end
        local note = tooltipNotes[id]
        if note and ns.db.tooltipNotes then tooltip:AddLine(titled(": " .. note, 12), 1, 1, 1) end
    end)
end

---------------------------------------------------------------------------
-- Refresh + ticker
---------------------------------------------------------------------------
local cachedBags, snapshotTime, markedStep, markedKey

function UI.Refresh()
    UI.RefreshGuide()
    UI.RefreshHints()
end

local function stepKey(step)
    if not step then return "none" end
    local parts = {}
    for _, t in ipairs(step.tasks) do parts[#parts + 1] = t.id .. (t.isDone and "+" or "") end
    return table.concat(parts, ",")
end

local function refreshHighlights()
    if ns.Highlight then ns.Highlight.Update({ bags = cachedBags, suggestions = lastSuggestions }) end
end

local function tick()
    if not guide then return end
    if not cachedBags then cachedBags = ns.QuestState.Bags() end
    local step = Ladder.CurrentStep()
    local key = stepKey(step)
    if ns.WorldMarks and (step ~= markedStep or key ~= markedKey) then
        markedStep, markedKey = step, key
        ns.WorldMarks.SetTargets(step)
    end
    Ladder.UpdateWaypoint()
    -- fly-or-walk is re-checked from where you stand: redraw when it changes
    if guide:IsShown() and (travelLine(step) ~= shownTravel or timerText() ~= shownTimers) then layoutGuide() end
    Hints.Compute({
        point = Geo.PlayerPoint(),
        byId = Ladder.snapshot or {},
        bags = cachedBags,
        plan = Ladder.plan,
        step = Ladder.CurrentStep(),
        now = GetTime(),
        snapshotTime = snapshotTime,
        suggestions = lastSuggestions,
    })
    if guide:IsShown() then updateDistance() end
    UI.RefreshHints()
    refreshHighlights()
end

ns.On("SETTINGS_LOADED", function()
    buildGuide()
    buildHints()
    buildPanel()
    hookTooltips()
    UI.Refresh()
    if C_Timer and C_Timer.NewTicker then
        C_Timer.NewTicker(1, function()
            local ok, err = pcall(tick)
            if not ok then ns.ReportError(err) end
        end)
    end
end)

ns.On("PLAN_UPDATED", function()
    snapshotTime = GetTime()
    if ns.Gear and Ladder.plan then ns.Gear.AnnotatePlan(Ladder.plan, Ladder.snapshot) end
    rebuildTooltipNotes()
    UI.Refresh()
    tick()
    Ladder.UpdateWaypoint()
end)
ns.On("PROGRESS_UPDATED", function() snapshotTime = GetTime(); UI.Refresh() end)
ns.On("SETTINGS_CHANGED", function() UI.Restyle(); UI.Refresh() end)
ns.On("THEME_CHANGED", function() UI.Restyle(); UI.Refresh() end)
ns.On("HINTS_CHANGED", tick)
ns.On("SHOW_PANEL", UI.ShowPanel)
ns.On("HIGHLIGHT_REFRESH", refreshHighlights)
ns.On("BAGS_CHANGED", function()
    cachedBags = ns.QuestState.Bags()
    rebuildTooltipNotes()
    refreshHighlights()
    if panel and panel:IsShown() and panel.which == "bags" then showBags() end
end)

ns.RegisterEvent("PLAYER_REGEN_ENABLED", function()
    if pendingUseItem ~= nil then
        local id = pendingUseItem or nil
        pendingUseItem = nil
        setUseItem(id)
    end
    if pendingPlace then pendingPlace = nil; UI.PlaceUseButton() end
end)
