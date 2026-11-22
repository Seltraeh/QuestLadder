-- Quest Ladder: the options window (Game Menu > Options > AddOns > Quest Ladder, or /ladder options).
-- Five pages under Blizzard's options: the main page (icon, quick switches, colors), the guide
-- window, markers and map, route and quests, travel and bags. Every switch here is also a saved
-- setting with a default (Core.lua), so nothing breaks if the saved settings don't load.
-- Also the entry in the minimap's add-on menu (the TOC's AddonCompartmentFunc).

local _, ns = ...
local Options = {}
ns.Options = Options

local Theme = ns.Theme

Options.NAME = "Quest Ladder"

---------------------------------------------------------------------------
-- What each option is
---------------------------------------------------------------------------
-- kind: "logo" | "header" | "note" | "check" | "slider" | "themes" | "colors" | "buttons"
-- check/slider: key (in ns.db), label, tip; invert (the box shows the opposite of the
-- setting, e.g. "Plan group quests" for skipGroupQuests); replan (the route depends on it).
-- slider: min, max, step, fmt ("percent", "scale", "yards" or nil for a plain number).

local function percent(v) return string.format("%d%%", math.floor(v * 100 + 0.5)) end
local FORMATS = {
    percent = percent,
    scale = function(v) return string.format("%.2fx", v) end,
    yards = function(v) return string.format("%d yards", v) end,
    levels = function(v) return (v == 1) and "1 level" or string.format("%d levels", v) end,
    px = function(v) return string.format("%d px", v) end,
}

local function blizzardPreset(name)
    return function() ns.Fire("CVAR_PRESET", name) end
end

--- A button that runs a /ladder command, so the options and the commands do the same thing.
local function slash(command)
    return function() SlashCmdList.QUESTLADDER(command) end
end

Options.GITHUB_ISSUES = "https://github.com/Seltraeh/QuestLadder/issues/new/choose"
Options.CURSEFORGE = "https://www.curseforge.com/wow/addons/quest-ladder"

Options.PAGES = {
    { key = "main", name = Options.NAME, items = {
        { kind = "logo" },
        { kind = "header", text = "Show" },
        { kind = "check", key = "showGuide", label = "Show the guide window", cmd = "",
          tip = "Also /ladder, or a key binding (Options > Keybindings > AddOns)." },
        { kind = "check", key = "compact", label = "Compact mode",
          tip = "Just the current step: fewer lines, no buttons, no bag or gear line. Also the -/+ button on the window, or right-click its icon." },
        { kind = "check", key = "showHints", label = "Show the hint box",
          tip = "\"Don't forget\" lines under the guide: items to use, vendors, quests to grab on the way." },
        { kind = "header", text = "Colors" },
        { kind = "note", text = "Pick a theme, or click a color below to choose your own. Right-click a color to put the theme's back." },
        { kind = "themes", cmd = { "theme", "color", "colors" } },
        { kind = "colors" },
        { kind = "slider", key = "bgAlpha", label = "Window background opacity", min = 0, max = 1, step = 0.05, fmt = "percent" },
        { kind = "buttons", buttons = {
            { text = "Reset colors", width = 120, tip = "Back to the theme's own colors.",
              fn = function() Theme.SetPreset(Theme.Preset().key) end },
            { text = "Reset all settings", width = 150, tip = "Every Quest Ladder setting back to its default (asks first).",
              fn = function() Options.ConfirmResetAll() end },
        } },
        { kind = "header", text = "Having trouble?" },
        { kind = "note", text = "Something not working, or an idea to make Quest Ladder better? Run the diagnostics first: "
            .. "they check what works on your client and save it for a bug report. Then tell us on GitHub or CurseForge." },
        { kind = "buttons", buttons = {
            { text = "Reload UI", width = 110, fn = function() Options.Reload() end,
              tip = "Same as /reload: reloads the interface, which also saves settings and diagnostics." },
            { text = "Run diagnostics", width = 140, cmd = "diag", fn = function() Options.RunDiag() end,
              tip = "/ladder diag: checks what works on this client. When it's done it offers to reload, which saves the results." },
            { text = "Report a bug or idea", width = 170, fn = function() Options.ShowReport() end,
              tip = "Links to GitHub and CurseForge, and your details to paste into the report." },
        } },
        { kind = "buttons", buttons = {
            { text = "List commands", width = 130, cmd = "help", fn = slash("help"), tip = "/ladder help: every command, in chat." },
            { text = "Clear saved diagnostics", width = 180, fn = slash("diag clear"),
              tip = "/ladder diag clear: empties the diagnostics runs saved so far." },
        } },
        { kind = "check", key = "debug", label = "Debug messages in chat" },
    } },
    { key = "window", name = "Guide window", items = {
        { kind = "header", text = "Size and place" },
        { kind = "slider", key = "guideScale", label = "Scale", min = 0.6, max = 1.6, step = 0.05, fmt = "scale" },
        { kind = "slider", key = "guideWidth", label = "Width (the hint box matches it)", min = 260, max = 520, step = 10, fmt = "px" },
        { kind = "check", key = "lockGuide", label = "Lock the window in place", tip = "Stops it moving when you drag it." },
        { kind = "buttons", buttons = {
            { text = "Reset position", width = 130, tip = "Puts the guide back on the right side of the screen.",
              fn = function() if ns.UI then ns.UI.ResetPosition() end end },
        } },
        { kind = "header", text = "What it shows" },
        { kind = "slider", key = "nextStepsShown", label = "Upcoming steps", min = 0, max = 6, step = 1 },
        { kind = "check", key = "showButtons", label = "Skip, Replan, Bags and Gear buttons" },
        { kind = "check", key = "showBagLine", label = "Bag space line", tip = "Free slots and what the next steps need." },
        { kind = "check", key = "showGearLine", label = "Next gear upgrade line", tip = "The next quest reward that's an upgrade, and from which step." },
        { kind = "slider", key = "hintLines", label = "Hint box lines", min = 1, max = 4, step = 1 },
        { kind = "header", text = "Compact mode" },
        { kind = "note", text = "For when you need the screen: the current step only, no buttons and no bag or gear line. The hint box shows at most 2 lines." },
        { kind = "check", key = "compact", label = "Compact mode" },
        { kind = "slider", key = "compactTaskLines", label = "Lines for the current step", min = 1, max = 7, step = 1 },
        { kind = "slider", key = "compactNextSteps", label = "Upcoming steps", min = 0, max = 3, step = 1 },
    } },
    { key = "markers", name = "Markers and map", items = {
        { kind = "header", text = "Boxes and markers" },
        { kind = "check", key = "highlights", label = "Boxes in your bags and the quest reward window",
          tip = "The item to use, gear to equip, junk to sell at a vendor, and the reward to pick." },
        { kind = "check", key = "worldMarks", label = "Markers on quest NPCs' nameplates, and the \"This one\" cue",
          tip = "Quest mobs need enemy nameplates on (V)." },
        { kind = "check", key = "markerLabels", label = "Labels on boxes and markers (Use, Kill, Turn in)" },
        { kind = "check", key = "markerPulse", label = "Boxes fade in and out" },
        { kind = "slider", key = "markerThickness", label = "Line thickness", min = 1, max = 4, step = 1, fmt = "px" },
        { kind = "check", key = "pingSound", label = "Ping when you face this step's object" },
        { kind = "check", key = "tooltipNotes", label = "Quest Ladder notes on item tooltips", tip = "\"Sell\", \"Bank\", \"Equip\" and why." },
        { kind = "header", text = "Map squares" },
        { kind = "note", text = "Squares where this step's targets are (needs the HereBeDragons library). Questie draws its own icons there too: turn these off if that's enough for you." },
        { kind = "check", key = "minimapSquares", label = "Squares on the minimap" },
        { kind = "check", key = "worldMapSquares", label = "Squares on the world map" },
        { kind = "slider", key = "squareSize", label = "Square size", min = 3, max = 16, step = 1, fmt = "px" },
        { kind = "header", text = "Map pin and arrow" },
        { kind = "check", key = "waypoints", label = "Map pin on the current step (and TomTom's arrow)", replan = true },
        { kind = "check", key = "unhideArrow", label = "Show Blizzard's arrow to the pin when the game hides it",
          tip = "Forever draws the arrow see-through for far-away pins. Only Quest Ladder's own pins are changed." },
        { kind = "header", text = "Game settings" },
        { kind = "note", text = "These change Blizzard's own settings, only when you click them." },
        { kind = "buttons", buttons = {
            { text = "Interact icons", width = 140, cmd = "interacticons", fn = blizzardPreset("interacticons"),
              tip = "Blizzard's icons over objects you can use (quest objects get easier to spot)." },
            { text = "Friendly nameplates", width = 160, cmd = "npcplates", fn = blizzardPreset("npcplates"),
              tip = "Shows friendly NPC nameplates, so quest givers and turn-ins get a marker." },
        } },
    } },
    { key = "route", name = "Route and quests", items = {
        { kind = "header", text = "Right now" },
        { kind = "buttons", buttons = {
            { text = "Replan", width = 100, cmd = "replan", fn = slash("replan"), tip = "/ladder replan: rebuild the route now." },
            { text = "Skip this step", width = 130, cmd = "skip", fn = slash("skip"),
              tip = "/ladder skip: this step's new quests are left out, the rest goes to the end." },
            { text = "Un-skip all quests", width = 150, cmd = "unignore", fn = slash("unignore"),
              tip = "/ladder unignore: quests you skipped or abandoned can be suggested again. (/ladder unignore <quest id> for one.)" },
        } },
        { kind = "buttons", buttons = {
            { text = "Skipped quests", width = 130, cmd = { "skipped", "outgrown" }, fn = slash("skipped"),
              tip = "/ladder skipped: new quests left out of the plan and quests you've outgrown, and why (in chat)." },
            { text = "Dungeon quests", width = 130, cmd = "dungeons", fn = slash("dungeons"),
              tip = "/ladder dungeons: dungeon quests you can pick up now, by dungeon (in chat)." },
        } },
        { kind = "header", text = "Quest dialogs" },
        { kind = "note", text = "Only in a quest dialog you opened yourself. Holding Shift while you talk to the NPC skips all of these." },
        { kind = "check", key = "autoAccept", label = "Accept planned quests" },
        { kind = "check", key = "autoTurnIn", label = "Turn in quests with no reward choice" },
        { kind = "check", key = "autoPickReward", label = "Also pick the best reward when there's a choice" },
        { kind = "header", text = "Which quests" },
        { kind = "check", key = "includeUnstarted", label = "Plan quests you haven't picked up yet", replan = true },
        { kind = "check", key = "tripCheck", label = "Skip quests not worth the walk", replan = true,
          tip = "When killing mobs for that long would earn more XP. /ladder skipped lists them." },
        { kind = "check", key = "skipGroupQuests", invert = true, label = "Plan group quests (elites at your level)", replan = true },
        { kind = "check", key = "skipDungeonQuests", invert = true, label = "Plan dungeon quests", replan = true },
        { kind = "check", key = "skipEscortsAndElites", label = "Skip escort and elite quests", replan = true },
        { kind = "slider", key = "levelsAbove", label = "Quests up to this far above your level", min = 0, max = 5, step = 1,
          fmt = "levels", replan = true },
        { kind = "slider", key = "minQuestValue", label = "Skip new quests worth less than this share of a solid quest's XP",
          min = 0, max = 1, step = 0.05, fmt = "percent", replan = true, cmd = "minxp" },
        { kind = "slider", key = "pickupRadius", label = "How far to look for quest givers", min = 300, max = 2000, step = 100,
          fmt = "yards", replan = true },
        { kind = "header", text = "Speed-leveling" },
        { kind = "check", key = "grindFirst", label = "\"Grind first\" stops before mobs that would be too high", replan = true },
        { kind = "check", key = "deathTravel", label = "Say when dying and resurrecting is quicker than walking", replan = true },
    } },
    { key = "travel", name = "Travel, bags and more", items = {
        { kind = "header", text = "Travel" },
        { kind = "check", key = "useFlights", label = "Fly where it's quicker", replan = true },
        { kind = "check", key = "useHearth", label = "Plan when to use your hearthstone", replan = true },
        { kind = "check", key = "suggestBind", label = "Suggest binding at a better inn", replan = true },
        { kind = "check", key = "discoverFlights", label = "Pick up flight paths on the way", replan = true },
        { kind = "header", text = "Bags and gear" },
        { kind = "buttons", buttons = {
            { text = "Bag planner", width = 120, cmd = "bags", fn = slash("bags"), tip = "/ladder bags: what to sell, bank or destroy." },
            { text = "Gear upgrades", width = 130, cmd = "gear", fn = slash("gear"),
              tip = "/ladder gear: upgrades from quest rewards and the Auction House (Auctionator)." },
        } },
        { kind = "slider", key = "reserveSlots", label = "Bag slots to keep free", min = 0, max = 20, step = 1, replan = true,
          cmd = "reserve" },
        { kind = "money", key = "goldReserve", cmd = "gold", label = "Gold to keep for training",
          tip = "AH suggestions never spend it. Type an amount like 5g or 2g 50s and press Enter; empty or auto = worked out from your level." },
        { kind = "header", text = "Stat weights" },
        { kind = "note", text = "What one point of each stat is worth when gear is compared. Your class's values to start with; "
            .. "the ones you change show in gold. Empty a box for your class's value again." },
        { kind = "weights", cmd = "weight" },
        { kind = "buttons", buttons = {
            { text = "Class defaults", width = 130, fn = slash("weight reset"),
              tip = "/ladder weight reset: every stat back to your class's value." },
        } },
    } },
}

---------------------------------------------------------------------------
-- Reading and changing settings
---------------------------------------------------------------------------
function Options.Get(item)
    local v = ns.db[item.key]
    if item.kind == "check" then
        v = v and true or false
        if item.invert then v = not v end
        return v
    end
    return tonumber(v) or item.min or 0
end

local function snap(item, v)
    v = tonumber(v) or item.min
    v = math.max(item.min, math.min(item.max, v))
    local step = item.step or 1
    v = item.min + math.floor((v - item.min) / step + 0.5) * step
    return tonumber(string.format("%.2f", v))
end
Options.Snap = snap

function Options.Set(item, value)
    if item.kind == "check" then
        value = value and true or false
        if item.invert then value = not value end
    else
        value = snap(item, value)
    end
    if ns.db[item.key] == value then return end
    ns.db[item.key] = value
    ns.Fire("SETTINGS_CHANGED")
    if item.replan then
        ns.Debounce("QuestLadder.optionsReplan", 0.5, function() ns.Fire("REQUEST_REPLAN", "settings") end)
    end
end

function Options.ResetAll()
    ns.ResetSettings(ns.db)
    Theme.Changed()
    ns.Fire("SETTINGS_CHANGED")
    ns.Fire("REQUEST_REPLAN", "settings")
    if ns.UI then ns.UI.ResetPosition() end
    ns.Print("every setting is back to its default")
end

function Options.ConfirmResetAll()
    if not (StaticPopupDialogs and StaticPopup_Show) then Options.ResetAll() return end
    StaticPopupDialogs.QUESTLADDER_RESET_ALL = StaticPopupDialogs.QUESTLADDER_RESET_ALL or {
        text = "Put every Quest Ladder setting back to its default?\n\nColors, window, markers and route options. "
            .. "Learned flight paths, graveyards and ignored quests stay.",
        button1 = YES or "Yes", button2 = NO or "No",
        OnAccept = function() Options.ResetAll() end,
        timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
    }
    StaticPopup_Show("QUESTLADDER_RESET_ALL")
end

--- Opens Blizzard's color picker for one color. Dragging shows the color live; Cancel puts back
--- what you had (your own color, or the theme's).
function Options.PickColor(role)
    local picker = ColorPickerFrame
    if not (picker and picker.SetupColorPickerAndShow) and C_AddOns and C_AddOns.LoadAddOn then
        pcall(C_AddOns.LoadAddOn, "Blizzard_ColorPickerFrame")
        picker = ColorPickerFrame
    end
    if not (picker and picker.SetupColorPickerAndShow) then
        ns.Print("the color picker isn't available here: pick a theme instead (/ladder theme)")
        return false
    end
    local before = Theme.IsCustom(role) and { Theme.Color(role) } or nil
    local r, g, b = Theme.Color(role)
    local info = {
        r = r, g = g, b = b, hasOpacity = false,
        swatchFunc = function()
            local okC, nr, ng, nb = pcall(picker.GetColorRGB, picker)
            if okC then Theme.SetColor(role, nr, ng, nb) end
        end,
        cancelFunc = function()
            if before then Theme.SetColor(role, before[1], before[2], before[3]) else Theme.ResetColor(role) end
        end,
    }
    local ok = pcall(picker.SetupColorPickerAndShow, picker, info)
    return ok
end

---------------------------------------------------------------------------
-- Widgets (plain frames and Blizzard's stock textures, no templates needed)
---------------------------------------------------------------------------
local LEFT = 16

local SLIDER_BACKDROP = {
    bgFile = "Interface\\Buttons\\UI-SliderBar-Background",
    edgeFile = "Interface\\Buttons\\UI-SliderBar-Border",
    tile = true, tileSize = 8, edgeSize = 8,
    insets = { left = 3, right = 3, top = 6, bottom = 6 },
}

local SWATCH_BACKDROP = {
    bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1,
}

local function tooltip(owner, title, text)
    if not text and not title then return end
    owner:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if title then GameTooltip:AddLine(title, 1, 1, 1) end
        if type(text) == "function" then text = text() end
        if text then GameTooltip:AddLine(text, 1, 0.82, 0, true) end
        GameTooltip:Show()
    end)
    owner:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function font(parent, template)
    local fs = parent:CreateFontString(nil, "OVERLAY", template)
    fs:SetJustifyH("LEFT")
    return fs
end

local build = {}

function build.logo(page)
    local c = page.content
    local tex = c:CreateTexture(nil, "ARTWORK")
    tex:SetTexture(Theme.LOGO)
    tex:SetSize(64, 64)
    tex:SetPoint("TOPLEFT", LEFT, -page.y)
    local title = font(c, _G.GameFontNormalHuge and "GameFontNormalHuge" or "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", tex, "TOPRIGHT", 12, -6)
    local version = font(c, "GameFontHighlightSmall")
    version:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    version:SetText(string.format("Version %s  -  by Seltraeh", tostring(ns.VERSION)))
    local about = font(c, "GameFontHighlightSmall")
    about:SetPoint("TOPLEFT", version, "BOTTOMLEFT", 0, -4)
    about:SetWidth(page.width - LEFT - 100)
    about:SetText("Step-by-step questing for WoW: Forever. Type /ladder help for every command.")
    about:SetTextColor(0.75, 0.75, 0.75)
    page.y = page.y + 76
    page.controls[#page.controls + 1] = {
        Refresh = function() title:SetText(Theme.Wrap("accent", Options.NAME)) end,
    }
end

function build.header(page, item)
    local c = page.content
    page.y = page.y + 8
    local fs = font(c, "GameFontNormalLarge")
    fs:SetPoint("TOPLEFT", LEFT, -page.y)
    fs:SetText(item.text)
    local line = c:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(1, 1, 1, 0.15)
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", LEFT, -(page.y + 22))
    line:SetWidth(page.width - 2 * LEFT)
    page.y = page.y + 30
end

function build.note(page, item)
    local fs = font(page.content, "GameFontHighlightSmall")
    fs:SetPoint("TOPLEFT", LEFT + 4, -page.y)
    fs:SetWidth(page.width - 2 * LEFT - 8)
    fs:SetWordWrap(true)
    fs:SetText(item.text)
    fs:SetTextColor(0.75, 0.75, 0.75)
    page.y = page.y + math.max(12, fs:GetStringHeight() or 12) + 8
end

function build.check(page, item)
    local cb = CreateFrame("CheckButton", nil, page.content)
    cb:SetSize(26, 26)
    cb:SetPoint("TOPLEFT", LEFT, -page.y)
    cb:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
    cb:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
    cb:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight", "ADD")
    cb:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
    cb.label = font(cb, "GameFontHighlight")
    cb.label:SetPoint("LEFT", cb, "RIGHT", 4, 1)
    cb.label:SetText(item.label)
    -- the label can be clicked too
    cb:SetHitRectInsets(0, -math.min(page.width - 60, (cb.label:GetStringWidth() or 200) + 8), 0, 0)
    cb.item = item
    cb:SetScript("OnClick", function(self) Options.Set(item, self:GetChecked() and true or false) end)
    tooltip(cb, item.label, item.tip)
    cb.Refresh = function(self) self:SetChecked(Options.Get(item)) end
    page.controls[#page.controls + 1] = cb
    page.y = page.y + 28
end

function build.slider(page, item)
    local c = page.content
    local label = font(c, "GameFontHighlight")
    label:SetPoint("TOPLEFT", LEFT + 4, -page.y)
    label:SetText(item.label)
    local s = CreateFrame("Slider", nil, c, "BackdropTemplate")
    s:SetOrientation("HORIZONTAL")
    s:SetSize(240, 17)
    s:SetPoint("TOPLEFT", LEFT + 4, -(page.y + 20))
    s:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    if s.SetBackdrop then s:SetBackdrop(SLIDER_BACKDROP) end
    s:SetMinMaxValues(item.min, item.max)
    s:SetValueStep(item.step)
    if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
    s:EnableMouseWheel(true)
    s.valueText = font(c, "GameFontHighlightSmall")
    s.valueText:SetPoint("LEFT", s, "RIGHT", 10, 0)
    s.item = item
    local fmt = FORMATS[item.fmt] or function(v) return tostring(v) end
    s:SetScript("OnValueChanged", function(self, v)
        v = snap(item, v)
        self.valueText:SetText(fmt(v))
        if self.refreshing then return end
        Options.Set(item, v)
    end)
    s:SetScript("OnMouseWheel", function(self, delta)
        self:SetValue(snap(item, (self:GetValue() or item.min) + delta * item.step))
    end)
    tooltip(s, item.label, item.tip)
    s.Refresh = function(self)
        local v = snap(item, Options.Get(item))
        self.refreshing = true
        self:SetValue(v)
        self.refreshing = false
        self.valueText:SetText(fmt(v))
    end
    page.controls[#page.controls + 1] = s
    page.y = page.y + 48
end

function build.buttons(page, item)
    local x = LEFT + 4
    for _, spec in ipairs(item.buttons) do
        local b = CreateFrame("Button", nil, page.content, "UIPanelButtonTemplate")
        b:SetSize(spec.width or 120, 22)
        b:SetPoint("TOPLEFT", x, -page.y)
        b:SetText(spec.text)
        b:SetScript("OnClick", function() spec.fn() end)
        tooltip(b, spec.text, spec.tip)
        page.buttons[spec.text] = b
        x = x + (spec.width or 120) + 8
    end
    page.y = page.y + 30
end

--- A one-line text box. `commit(self)` runs on Enter and when you click away; Escape puts back
--- what was there. While you type, refreshes from elsewhere leave it alone.
local function newEditBox(parent, width)
    local eb = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
    eb:SetSize(width, 22)
    eb:SetAutoFocus(false)
    local fontObject = _G.GameFontHighlightSmall or _G.ChatFontNormal
    if fontObject then eb:SetFontObject(fontObject) end
    eb:SetTextInsets(6, 6, 0, 0)
    if eb.SetBackdrop then
        eb:SetBackdrop(SWATCH_BACKDROP)
        eb:SetBackdropColor(0, 0, 0, 0.6)
        eb:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
    end
    -- (ClearFocus fires OnEditFocusLost: `committing` stops that saving a second time)
    eb:SetScript("OnEnterPressed", function(self)
        self.committing = true
        if self.commit then self:commit() end
        self:ClearFocus()
        self.committing = false
        if self.Refresh then self:Refresh() end
    end)
    eb:SetScript("OnEditFocusLost", function(self)
        if self.commit and not self.committing then
            self.committing = true
            self:commit()
            self.committing = false
            if self.Refresh then self:Refresh() end
        end
    end)
    eb:SetScript("OnEscapePressed", function(self)
        self.committing = true
        self:ClearFocus()
        self.committing = false
        if self.Refresh then self:Refresh() end
    end)
    return eb
end

local function trim(text) return ((text or ""):gsub("^%s+", ""):gsub("%s+$", "")) end

--- Copper as you'd type it: "5g 20s", "80s", "35c".
function Options.MoneyText(copper)
    copper = math.floor(tonumber(copper) or 0)
    local g, sv, c = math.floor(copper / 10000), math.floor((copper % 10000) / 100), copper % 100
    local parts = {}
    if g > 0 then parts[#parts + 1] = g .. "g" end
    if sv > 0 then parts[#parts + 1] = sv .. "s" end
    if c > 0 or #parts == 0 then parts[#parts + 1] = c .. "c" end
    return table.concat(parts, " ")
end

--- Sets the training gold from what you typed: an amount, or empty / "auto" for by-level.
function Options.SetGold(text)
    text = trim(text):lower()
    if text == "" or text == "auto" then
        ns.db.goldReserve = nil
    else
        local copper = ns.ParseMoney(text)
        if not copper then
            ns.Print("gold to keep: type an amount like 5g or 2g 50s, or auto")
            return false
        end
        ns.db.goldReserve = copper
    end
    ns.Fire("SETTINGS_CHANGED")
    return true
end

local function autoGoldText()
    if not (ns.Gear and ns.Gear.Reserve and ns.QuestState) then return "" end
    local ok, player = pcall(ns.QuestState.Player)
    if not ok or type(player) ~= "table" then return "" end
    local okR, copper = pcall(ns.Gear.Reserve, player.level, player)
    if not okR or type(copper) ~= "number" then return "" end
    return ns.FormatMoney(copper)
end

function build.money(page, item)
    local c = page.content
    local label = font(c, "GameFontHighlight")
    label:SetPoint("TOPLEFT", LEFT + 4, -page.y)
    label:SetText(item.label)
    local eb = newEditBox(c, 110)
    eb:SetPoint("TOPLEFT", LEFT + 4, -(page.y + 20))
    local hint = font(c, "GameFontHighlightSmall")
    hint:SetPoint("LEFT", eb, "RIGHT", 10, 0)
    hint:SetTextColor(0.75, 0.75, 0.75)
    eb.item = item
    eb.commit = function(self) Options.SetGold(self:GetText()) end
    eb.Refresh = function(self)
        if self.HasFocus and self:HasFocus() then return end
        local v = ns.db.goldReserve
        self:SetText(v and Options.MoneyText(v) or "auto")
        local auto = autoGoldText()
        hint:SetText(v and "empty or auto: by level" or ("by level: " .. auto))
    end
    tooltip(eb, item.label, item.tip)
    page.controls[#page.controls + 1] = eb
    page.y = page.y + 50
end

Options.WEIGHT_STATS = {
    { "str", "Strength" }, { "agi", "Agility" }, { "sta", "Stamina" }, { "int", "Intellect" },
    { "spi", "Spirit" }, { "armor", "Armor" }, { "dps", "Weapon DPS" }, { "rdps", "Ranged DPS" },
    { "ap", "Attack power" }, { "rap", "Ranged AP" }, { "sp", "Spell power" }, { "heal", "Healing" },
    { "hit", "Hit" }, { "crit", "Crit" }, { "mp5", "Mana per 5" }, { "def", "Defense" },
}

--- Your class (the stat weights' starting values), WARRIOR when the game doesn't say.
function Options.ClassFile()
    if UnitClass then
        local ok, _, classFile = pcall(UnitClass, "player")
        if ok and type(classFile) == "string" and not ns.IsSecret(classFile) then return classFile end
    end
    return "WARRIOR"
end

local function numberText(v)
    local text = string.format("%.3f", v):gsub("0+$", ""):gsub("%.$", "")
    return text
end

--- Sets one stat's weight from what you typed; empty means your class's value again.
function Options.SetWeight(stat, text)
    text = trim(text)
    local w = ns.db.weights
    if text == "" then
        if type(w) == "table" then
            w[stat] = nil
            if next(w) == nil then ns.db.weights = nil end
        end
    else
        local n = tonumber(text)
        if not n or n < 0 or n > 100 then
            ns.Print("stat weight: type a number like 1.5 (or leave it empty for your class's value)")
            return false
        end
        if type(w) ~= "table" then w = {}; ns.db.weights = w end
        w[stat] = n
    end
    ns.Fire("SETTINGS_CHANGED")
    return true
end

function build.weights(page)
    local c = page.content
    local perRow = 4
    local colWidth = math.floor((page.width - 2 * LEFT) / perRow)
    for i, entry in ipairs(Options.WEIGHT_STATS) do
        local stat, name = entry[1], entry[2]
        local row, col = math.floor((i - 1) / perRow), (i - 1) % perRow
        local x, y = LEFT + 4 + col * colWidth, -(page.y + row * 28)
        local label = font(c, "GameFontHighlightSmall")
        label:SetPoint("TOPLEFT", x, y - 5)
        label:SetWidth(colWidth - 60)
        label:SetWordWrap(false)
        label:SetText(name)
        local eb = newEditBox(c, 48)
        eb:SetPoint("TOPLEFT", x + colWidth - 56, y)
        eb.stat = stat
        eb.commit = function(self) Options.SetWeight(stat, self:GetText()) end
        eb.Refresh = function(self)
            if self.HasFocus and self:HasFocus() then return end
            local over = type(ns.db.weights) == "table" and tonumber(ns.db.weights[stat])
            local base = (ns.Gear.DEFAULT_WEIGHTS[Options.ClassFile()] or ns.Gear.DEFAULT_WEIGHTS.WARRIOR)[stat] or 0
            self:SetText(numberText(over or base))
            if over then self:SetTextColor(1, 0.82, 0) else self:SetTextColor(1, 1, 1) end
        end
        tooltip(eb, name, "/ladder weight " .. stat .. " <n>. Empty: your class's value.")
        page.controls[#page.controls + 1] = eb
    end
    page.y = page.y + math.ceil(#Options.WEIGHT_STATS / perRow) * 28 + 6
end

--- A button per theme: its own background, its marker color as a swatch, its name in its
--- accent color. A check mark shows the theme in use.
function build.themes(page)
    local c = page.content
    local perRow, w, h, gap = 4, 120, 24, 8
    local x0 = LEFT + 4
    for i, p in ipairs(Theme.PRESETS) do
        local row, col = math.floor((i - 1) / perRow), (i - 1) % perRow
        local b = CreateFrame("Button", nil, c, "BackdropTemplate")
        b:SetSize(w, h)
        b:SetPoint("TOPLEFT", x0 + col * (w + gap), -(page.y + row * (h + 6)))
        local colors = p.colors
        if b.SetBackdrop then
            b:SetBackdrop(SWATCH_BACKDROP)
            b:SetBackdropColor(colors.background[1], colors.background[2], colors.background[3], 1)
            b:SetBackdropBorderColor(colors.border[1], colors.border[2], colors.border[3], 1)
        end
        local sw = b:CreateTexture(nil, "ARTWORK")
        sw:SetSize(12, 12)
        sw:SetPoint("LEFT", 6, 0)
        sw:SetColorTexture(colors.marker[1], colors.marker[2], colors.marker[3], 1)
        local text = font(b, "GameFontHighlightSmall")
        text:SetPoint("LEFT", sw, "RIGHT", 6, 0)
        text:SetText(p.name)
        text:SetTextColor(colors.accent[1], colors.accent[2], colors.accent[3])
        local mark = b:CreateTexture(nil, "OVERLAY")
        mark:SetSize(16, 16)
        mark:SetPoint("RIGHT", -2, 0)
        mark:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
        b:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
        b:SetScript("OnClick", function() Theme.SetPreset(p.key) end)
        tooltip(b, p.name, "Use this theme's colors (your own color picks are dropped).")
        b.Refresh = function()
            if Theme.Preset().key == p.key then mark:Show() else mark:Hide() end
        end
        b.preset = p.key
        page.controls[#page.controls + 1] = b
    end
    page.y = page.y + math.ceil(#Theme.PRESETS / perRow) * (h + 6) + 8
end

--- One swatch per color, two columns. Click: Blizzard's color picker. Right-click: the theme's color.
function build.colors(page)
    local c = page.content
    local colWidth = math.floor((page.width - 2 * LEFT) / 2)
    for i, role in ipairs(Theme.ROLES) do
        local row, col = math.floor((i - 1) / 2), (i - 1) % 2
        local b = CreateFrame("Button", nil, c, "BackdropTemplate")
        b:SetSize(22, 22)
        b:SetPoint("TOPLEFT", LEFT + 4 + col * colWidth, -(page.y + row * 28))
        if b.SetBackdrop then b:SetBackdrop(SWATCH_BACKDROP) end
        local label = font(c, "GameFontHighlight")
        label:SetPoint("LEFT", b, "RIGHT", 8, 0)
        label:SetWidth(colWidth - 40)
        label:SetWordWrap(false)
        b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        b:SetScript("OnClick", function(_, button)
            if button == "RightButton" then Theme.ResetColor(role.key) else Options.PickColor(role.key) end
        end)
        tooltip(b, role.name, function()
            return (role.tip and (role.tip .. "\n\n") or "") .. "Click to pick a color. Right-click: the theme's color."
        end)
        b.role = role.key
        b.Refresh = function(self)
            local r, g, bl = Theme.Color(role.key)
            if self.SetBackdropColor then
                self:SetBackdropColor(r, g, bl, 1)
                self:SetBackdropBorderColor(1, 1, 1, 0.8)
            end
            label:SetText(role.name .. (Theme.IsCustom(role.key) and " |cff888888(yours)|r" or ""))
        end
        page.controls[#page.controls + 1] = b
    end
    page.y = page.y + math.ceil(#Theme.ROLES / 2) * 28 + 8
end

---------------------------------------------------------------------------
-- Having trouble? Reload, diagnostics, and a report window with links to copy
---------------------------------------------------------------------------
function Options.Reload()
    local reload = ReloadUI or (C_UI and C_UI.Reload)
    if type(reload) == "function" then
        reload()
        return true
    end
    ns.Print("type /reload to reload the interface")
    return false
end

--- Runs /ladder diag; when the results are in, offers to reload so the game saves them.
function Options.RunDiag()
    Options.diagPending = true
    ns.Fire("RUN_DIAG", "options")
end

function Options.AskReload(run)
    local counts = (type(run) == "table" and type(run.counts) == "table") and run.counts or {}
    local fine = (counts.ok or 0) + (counts.info or 0) + (counts.skip or 0)
    local look = (counts.warn or 0) + (counts.fail or 0) + (counts.error or 0)
    if not (StaticPopupDialogs and StaticPopup_Show) then
        ns.Print("diagnostics done: /reload to save them")
        return false
    end
    StaticPopupDialogs.QUESTLADDER_DIAG_RELOAD = StaticPopupDialogs.QUESTLADDER_DIAG_RELOAD or {
        text = "%s", button1 = "Reload now", button2 = "Later",
        OnAccept = function() Options.Reload() end,
        timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
    }
    StaticPopup_Show("QUESTLADDER_DIAG_RELOAD", string.format(
        "Quest Ladder's diagnostics are done: %d fine, %d to look at (listed in chat).\n\n"
        .. "Reload now? The game saves the results when the interface reloads, ready to attach to a bug report.",
        fine, look))
    return true
end

ns.On("DIAG_DONE", function(run)
    if not Options.diagPending then return end
    Options.diagPending = nil
    Options.AskReload(run)
end)

--- fn(...)'s results, or nil when it's missing, errors or returns a secret value.
local function plainCall(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c, d = pcall(fn, ...)
    if not ok or ns.AnySecret(a, b, c, d) then return nil end
    return a, b, c, d
end

local REPORT_ADDONS = { "Questie", "QuestieDB", "Auctionator", "TomTom", "HereBeDragons", "Bagnon", "BagBrother", "Baganator" }

--- What a bug report needs, as text to paste: versions, character level and class, zone, other
--- add-ons, a few settings, the last diagnostics and the errors caught this session. No names.
function Options.ReportText()
    local lines = {}
    local function add(fmt, ...) lines[#lines + 1] = string.format(fmt, ...) end
    local function onOff(v) return v and "on" or "off" end
    add("Quest Ladder %s", tostring(ns.VERSION))
    local version, build, _, toc = plainCall(GetBuildInfo)
    if version then add("Client: %s (build %s, interface %s)", tostring(version), tostring(build), tostring(toc)) end
    local level = plainCall(UnitLevel, "player")
    if level then
        add("Character: level %s %s %s", tostring(level), tostring(plainCall(UnitRace, "player") or ""),
            tostring(plainCall(UnitClass, "player") or ""))
    end
    local zone = plainCall(GetZoneText)
    local mapId = C_Map and plainCall(C_Map.GetBestMapForUnit, "player")
    if zone or mapId then add("Zone: %s (map %s)", tostring(zone or "?"), tostring(mapId or "?")) end
    local isLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
    local meta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    local loaded = {}
    for _, name in ipairs(REPORT_ADDONS) do
        if plainCall(isLoaded, name) then
            local v = plainCall(meta, name, "Version")
            loaded[#loaded + 1] = v and (name .. " " .. tostring(v)) or name
        end
    end
    add("Other add-ons: %s", (#loaded > 0) and table.concat(loaded, ", ") or "none of the usual ones")
    local custom = {}
    for _, role in ipairs(Theme.ROLES) do
        if Theme.IsCustom(role.key) then custom[#custom + 1] = role.key end
    end
    add("Settings: theme %s%s, compact %s, plan new quests %s, waypoints %s, map squares %s/%s",
        Theme.Preset().key, (#custom > 0) and (" + own " .. table.concat(custom, ", ")) or "", onOff(ns.db.compact),
        onOff(ns.db.includeUnstarted), onOff(ns.db.waypoints), onOff(ns.db.minimapSquares), onOff(ns.db.worldMapSquares))
    local runs = type(QuestLadderDiag) == "table" and type(QuestLadderDiag.runs) == "table" and QuestLadderDiag.runs
    local last = runs and runs[#runs]
    if type(last) == "table" and type(last.counts) == "table" then
        local c = last.counts
        add("Last diagnostics: %s (%d ok, %d warn, %d fail)", tostring(last.time or "?"), c.ok or 0, c.warn or 0,
            (c.fail or 0) + (c.error or 0))
    else
        add("Last diagnostics: none yet")
    end
    local errors = ns.recentErrors or {}
    if #errors == 0 then
        add("Errors this session: none")
    else
        add("Errors this session: %d; first: %s", #errors, tostring(errors[1].msg):sub(1, 300))
    end
    return table.concat(lines, "\n")
end

local REPORT_BACKDROP = {
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
}

--- A text box you can select and copy from but not change. (Add-ons can't open web pages or
--- use the clipboard: you press Ctrl+C yourself.)
local function copyBox(parent, width, height, multi)
    local eb = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
    eb:SetAutoFocus(false)
    eb:SetMultiLine(multi and true or false)
    eb:SetSize(width, height)
    local fontObject = _G.GameFontHighlightSmall or _G.ChatFontNormal
    if fontObject then eb:SetFontObject(fontObject) end
    eb:SetTextInsets(6, 6, 3, 3)
    local function selectAll(self) if self.HighlightText then self:HighlightText() end end
    eb:SetScript("OnEditFocusGained", selectAll)
    eb:SetScript("OnMouseUp", selectAll)
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    eb:SetScript("OnEnterPressed", function(self) if not multi then self:ClearFocus() end end)
    -- typing (or pasting) puts the text back: it's there to copy
    eb:SetScript("OnTextChanged", function(self, userInput)
        if userInput and self.fixed and self:GetText() ~= self.fixed then
            self:SetText(self.fixed)
            selectAll(self)
        end
    end)
    eb.SetFixed = function(self, text)
        self.fixed = text
        self:SetText(text)
        self:SetCursorPosition(0)
    end
    return eb
end

local function boxBackdrop(frame)
    if not frame.SetBackdrop then return end
    frame:SetBackdrop(SWATCH_BACKDROP)
    frame:SetBackdropColor(0, 0, 0, 0.6)
    frame:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
end

local function buildReport()
    local f = CreateFrame("Frame", "QuestLadderReportFrame", UIParent, "BackdropTemplate")
    f:SetSize(520, 470)
    f:SetPoint("CENTER")
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    if f.SetBackdrop then f:SetBackdrop(REPORT_BACKDROP) end
    if UISpecialFrames then tinsert(UISpecialFrames, "QuestLadderReportFrame") end -- Escape closes it
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 0, 0)

    local width = 480
    local y = 14
    local function text(template, str, gap, color)
        local fs = font(f, template)
        fs:SetPoint("TOPLEFT", 20, -y)
        fs:SetWidth(width)
        fs:SetWordWrap(true)
        fs:SetText(str)
        if color then fs:SetTextColor(color[1], color[2], color[3]) end
        y = y + math.max(12, fs:GetStringHeight() or 12) + (gap or 6)
        return fs
    end
    f.title = text("GameFontNormalLarge", "", 10)
    text("GameFontHighlightSmall", "Thank you! Bug reports and ideas both help. WoW add-ons can't open web pages, so: "
        .. "click a link below, press Ctrl+C to copy it, and paste it into your browser.", 10, { 0.85, 0.85, 0.85 })
    text("GameFontNormal", "GitHub: bug reports and ideas (free GitHub account)", 4)
    f.github = copyBox(f, width, 24)
    f.github:SetPoint("TOPLEFT", 20, -y)
    boxBackdrop(f.github)
    y = y + 32
    text("GameFontNormal", "CurseForge: the add-on's page (Comments)", 4)
    f.curse = copyBox(f, width, 24)
    f.curse:SetPoint("TOPLEFT", 20, -y)
    boxBackdrop(f.curse)
    y = y + 32
    text("GameFontNormal", "Paste these details into your report (click, Ctrl+C):", 4)
    local holder = CreateFrame("Frame", nil, f, "BackdropTemplate")
    holder:SetSize(width, 130)
    holder:SetPoint("TOPLEFT", 20, -y)
    boxBackdrop(holder)
    local okS, scroll = pcall(CreateFrame, "ScrollFrame", nil, holder, "UIPanelScrollFrameTemplate")
    if not okS or not scroll then scroll = CreateFrame("ScrollFrame", nil, holder) end
    scroll:SetPoint("TOPLEFT", 4, -4)
    scroll:SetPoint("BOTTOMRIGHT", -26, 4)
    f.details = copyBox(scroll, width - 34, 120, true)
    scroll:SetScrollChild(f.details)
    y = y + 138
    text("GameFontHighlightSmall", "For a bug, Run diagnostics first and reload when it asks. Then attach this file to "
        .. "your report (on GitHub, rename it to QuestLadder.txt first): World of Warcraft\\_forever_\\WTF\\Account\\"
        .. "<your account>\\SavedVariables\\QuestLadder.lua. It holds your Quest Ladder settings and what the add-on "
        .. "saw (quests, bags, where you were); no passwords or account details.", 10, { 0.85, 0.85, 0.85 })

    local diag = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    diag:SetSize(140, 22)
    diag:SetPoint("BOTTOMLEFT", 20, 14)
    diag:SetText("Run diagnostics")
    diag:SetScript("OnClick", function() Options.RunDiag() end)
    local done = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    done:SetSize(100, 22)
    done:SetPoint("BOTTOMRIGHT", -20, 14)
    done:SetText(CLOSE or "Close")
    done:SetScript("OnClick", function() f:Hide() end)
    f:SetHeight(math.max(y + 50, 300))
    f:Hide()
    return f
end

--- The "Report a bug or idea" window: links to copy and the details to paste.
function Options.ShowReport()
    local f = Options.reportFrame or buildReport()
    Options.reportFrame = f
    if f.SetBackdropColor then
        local r, g, b = Theme.Color("background")
        f:SetBackdropColor(r, g, b, 0.95)
        local br, bg, bb = Theme.Color("border")
        f:SetBackdropBorderColor(br, bg, bb, 1)
    end
    f.title:SetText(Theme.Name(16) .. ": report a bug or share an idea")
    f.github:SetFixed(Options.GITHUB_ISSUES)
    f.curse:SetFixed(Options.CURSEFORGE)
    f.details:SetFixed(Options.ReportText())
    f:Show()
    -- the GitHub link is selected, ready for Ctrl+C
    f.github:SetFocus()
    if f.github.HighlightText then f.github:HighlightText() end
    return f
end

---------------------------------------------------------------------------
-- Pages
---------------------------------------------------------------------------
Options.frames = {}

local function newScroll(frame)
    local ok, scroll = pcall(CreateFrame, "ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    if not ok or not scroll then
        scroll = CreateFrame("ScrollFrame", nil, frame)
        scroll:EnableMouseWheel(true)
        scroll:SetScript("OnMouseWheel", function(self, delta)
            local max = self:GetVerticalScrollRange() or 0
            local v = math.max(0, math.min(max, (self:GetVerticalScroll() or 0) - delta * 40))
            self:SetVerticalScroll(v)
        end)
    end
    scroll:SetPoint("TOPLEFT", 0, -6)
    scroll:SetPoint("BOTTOMRIGHT", -28, 6)
    return scroll
end

--- Fills a page's frame with its controls (once, the first time it's shown).
function Options.BuildPage(frame)
    if frame.built then return frame end
    local def = frame.def
    local scroll = newScroll(frame)
    local content = CreateFrame("Frame", nil, scroll)
    local width = scroll:GetWidth()
    if type(width) ~= "number" or width < 300 then width = 600 end
    content:SetSize(width, 400)
    scroll:SetScrollChild(content)
    local page = { content = content, width = width, y = 12, controls = {}, buttons = {} }
    for _, item in ipairs(def.items) do
        local fn = build[item.kind]
        if fn then fn(page, item) end
    end
    content:SetHeight(page.y + 16)
    frame.scroll, frame.content, frame.controls, frame.buttons = scroll, content, page.controls, page.buttons
    frame.built = true
    Options.RefreshFrame(frame)
    return frame
end

function Options.RefreshFrame(frame)
    for _, control in ipairs(frame.controls or {}) do
        if control.Refresh then
            local ok, err = pcall(control.Refresh, control)
            if not ok then ns.ReportError(err) end
        end
    end
end

function Options.RefreshAll()
    for _, frame in ipairs(Options.frames) do
        if frame.built then Options.RefreshFrame(frame) end
    end
end

local function newPageFrame(def)
    local frame = CreateFrame("Frame", "QuestLadderOptions_" .. def.key)
    frame.def = def
    frame.name = def.name
    frame:Hide()
    frame:SetScript("OnShow", function(self)
        Options.BuildPage(self)
        Options.RefreshFrame(self)
    end)
    -- Blizzard's Defaults button on a page: same as Reset all (it asks first)
    frame.OnDefault = function() Options.ConfirmResetAll() end
    frame.OnRefresh = function(self) if self.built then Options.RefreshFrame(self) end end
    frame.OnCommit = function() end
    Options.frames[#Options.frames + 1] = frame
    return frame
end

--- The name in Blizzard's list: the icon after the name, so the list stays in A-Z order.
function Options.CategoryName()
    return Options.NAME .. " " .. Theme.IconText(14)
end

--- Registers the pages with Blizzard's options window (Game Menu > Options > AddOns).
function Options.Register()
    if Options.category then return true end
    if not (Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory) then
        Options.reason = "no Settings API"
        return false
    end
    local mainFrame = Options.frames[1] or newPageFrame(Options.PAGES[1])
    local ok, category = pcall(Settings.RegisterCanvasLayoutCategory, mainFrame, Options.CategoryName())
    if not ok or not category then
        Options.reason = "RegisterCanvasLayoutCategory failed: " .. tostring(category)
        return false
    end
    Options.category = category
    for i = 2, #Options.PAGES do
        local frame = Options.frames[i] or newPageFrame(Options.PAGES[i])
        if Settings.RegisterCanvasLayoutSubcategory then
            local okSub, sub = pcall(Settings.RegisterCanvasLayoutSubcategory, category, frame, Options.PAGES[i].name)
            if okSub then frame.category = sub end
        end
    end
    local okAdd, err = pcall(Settings.RegisterAddOnCategory, category)
    if not okAdd then Options.reason = "RegisterAddOnCategory failed: " .. tostring(err) end
    return okAdd
end

function Options.CategoryId()
    local cat = Options.category
    if not cat then return nil end
    if cat.GetID then
        local ok, id = pcall(cat.GetID, cat)
        if ok and id ~= nil and not ns.IsSecret(id) then return id end
    end
    return cat.ID
end

--- Opens the options at Quest Ladder's page (after combat, if you're fighting).
function Options.Open()
    if InCombatLockdown and InCombatLockdown() then
        Options.openAfterCombat = true
        ns.Print("the options open when this fight is over")
        return false
    end
    Options.Register()
    local id = Options.CategoryId()
    if id ~= nil and Settings and Settings.OpenToCategory then
        local ok = pcall(Settings.OpenToCategory, id)
        if ok then return true end
    end
    ns.Print("couldn't open the options window here; /ladder help lists the commands")
    return false
end

ns.On("OPEN_OPTIONS", Options.Open)
ns.On("SETTINGS_LOADED", function() Options.Register() end)
ns.On("LOGIN", function() Options.Register() end)
ns.On("SETTINGS_CHANGED", Options.RefreshAll)
ns.On("THEME_CHANGED", Options.RefreshAll)
ns.RegisterEvent("PLAYER_REGEN_ENABLED", function()
    if Options.openAfterCombat then
        Options.openAfterCombat = nil
        Options.Open()
    end
end)

---------------------------------------------------------------------------
-- The minimap's add-on menu (AddonCompartmentFunc in the TOC)
---------------------------------------------------------------------------
--- True when Quest Ladder is in the minimap's add-on menu (nil when the game has no such menu).
function Options.InAddonMenu()
    local frame = AddonCompartmentFrame
    if type(frame) ~= "table" or type(frame.registeredAddons) ~= "table" then return nil end
    for _, entry in ipairs(frame.registeredAddons) do
        local text = type(entry) == "table" and entry.text
        if type(text) == "string" and not ns.IsSecret(text) and text:find(Options.NAME, 1, true) then return true end
    end
    return false
end

function QuestLadder_OnAddonCompartmentClick(_, buttonName)
    if buttonName == "RightButton" then
        SlashCmdList.QUESTLADDER("")
    else
        ns.Fire("OPEN_OPTIONS")
    end
end

function QuestLadder_OnAddonCompartmentEnter(_, button)
    if not GameTooltip then return end
    GameTooltip:SetOwner(button or UIParent, "ANCHOR_LEFT")
    GameTooltip:AddLine(Theme.Name(14) .. " " .. tostring(ns.VERSION), 1, 1, 1)
    GameTooltip:AddLine("Click: options", 1, 1, 1)
    GameTooltip:AddLine("Right-click: show or hide the guide", 1, 1, 1)
    GameTooltip:Show()
end

function QuestLadder_OnAddonCompartmentLeave()
    if GameTooltip then GameTooltip:Hide() end
end
