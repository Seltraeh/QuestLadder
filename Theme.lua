-- Quest Ladder: colors and the add-on's icon.
-- Every color you can change lives here: a theme (a set of colors that go together) plus any
-- single color you picked yourself on top of it. The boxes, nameplate markers, map squares and
-- windows all ask this file for their color, and repaint when it says something changed.

local _, ns = ...
local Theme = {}
ns.Theme = Theme

Theme.ICON = "Interface\\AddOns\\QuestLadder\\Media\\Icon"
Theme.LOGO = "Interface\\AddOns\\QuestLadder\\Media\\Logo"

--- What each color paints, in the order the options page lists them.
Theme.ROLES = {
    { key = "marker", name = "Boxes and nameplate markers",
      tip = "The boxes around bag items, the reward to pick, the use button and quest NPCs' nameplates, and the \"This one\" cue." },
    { key = "map", name = "Minimap and world map squares",
      tip = "The small squares on the minimap and world map where this step's targets are." },
    { key = "accent", name = "Quest Ladder title text",
      tip = "The \"Quest Ladder\" name in the guide window, chat messages and item tooltips." },
    { key = "background", name = "Guide window background" },
    { key = "hintBackground", name = "Hint box background" },
    { key = "border", name = "Window borders" },
}

--- The themes. Cyan is the look Quest Ladder always had.
Theme.PRESETS = {
    { key = "cyan", name = "Cyan", colors = {
        marker = { 0.00, 1.00, 1.00 }, map = { 0.00, 1.00, 1.00 }, accent = { 0.20, 1.00, 0.60 },
        background = { 0.05, 0.05, 0.08 }, hintBackground = { 0.15, 0.08, 0.02 }, border = { 0.40, 0.40, 0.50 } } },
    { key = "pink", name = "Pink", colors = {
        marker = { 1.00, 0.41, 0.71 }, map = { 1.00, 0.55, 0.80 }, accent = { 1.00, 0.62, 0.85 },
        background = { 0.12, 0.04, 0.10 }, hintBackground = { 0.20, 0.06, 0.14 }, border = { 0.85, 0.45, 0.70 } } },
    { key = "lavender", name = "Lavender", colors = {
        marker = { 0.75, 0.50, 1.00 }, map = { 0.80, 0.60, 1.00 }, accent = { 0.85, 0.72, 1.00 },
        background = { 0.08, 0.05, 0.12 }, hintBackground = { 0.13, 0.07, 0.18 }, border = { 0.55, 0.40, 0.75 } } },
    { key = "gold", name = "Gold", colors = {
        marker = { 1.00, 0.82, 0.00 }, map = { 1.00, 0.75, 0.20 }, accent = { 1.00, 0.85, 0.30 },
        background = { 0.08, 0.06, 0.03 }, hintBackground = { 0.16, 0.10, 0.03 }, border = { 0.70, 0.55, 0.25 } } },
    { key = "green", name = "Fel green", colors = {
        marker = { 0.40, 1.00, 0.20 }, map = { 0.50, 1.00, 0.30 }, accent = { 0.60, 1.00, 0.40 },
        background = { 0.03, 0.08, 0.04 }, hintBackground = { 0.06, 0.12, 0.04 }, border = { 0.30, 0.60, 0.30 } } },
    { key = "red", name = "Crimson", colors = {
        marker = { 1.00, 0.25, 0.25 }, map = { 1.00, 0.35, 0.30 }, accent = { 1.00, 0.50, 0.45 },
        background = { 0.10, 0.03, 0.03 }, hintBackground = { 0.16, 0.05, 0.03 }, border = { 0.60, 0.25, 0.25 } } },
    { key = "frost", name = "Frost", colors = {
        marker = { 0.85, 0.95, 1.00 }, map = { 0.70, 0.90, 1.00 }, accent = { 0.75, 0.90, 1.00 },
        background = { 0.04, 0.06, 0.10 }, hintBackground = { 0.06, 0.09, 0.14 }, border = { 0.50, 0.60, 0.75 } } },
}

local byKey = {}
for _, p in ipairs(Theme.PRESETS) do byKey[p.key] = p end

--- Goes up by one on every change; frames that painted with an older number repaint.
Theme.version = 1

local function db() return ns.db or {} end

--- The current theme (Cyan when the saved name is unknown).
function Theme.Preset(key)
    return byKey[key or db().theme] or byKey.cyan
end

--- Finds a theme by key or by the start of its name ("pink", "Fel", "fel green").
function Theme.Find(text)
    text = (text or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" then return nil end
    if byKey[text] then return byKey[text] end
    for _, p in ipairs(Theme.PRESETS) do
        if p.name:lower():sub(1, #text) == text then return p end
    end
    return nil
end

local function valid(c)
    if type(c) ~= "table" then return false end
    for i = 1, 3 do
        local v = c[i]
        if type(v) ~= "number" or v ~= v or v < 0 or v > 1 then return false end
    end
    return true
end

--- True when you picked this color yourself (instead of taking the theme's).
function Theme.IsCustom(role)
    local colors = db().colors
    return type(colors) == "table" and valid(colors[role])
end

--- r, g, b for a role: your own pick, else the theme's.
function Theme.Color(role)
    local colors = db().colors
    local c = type(colors) == "table" and colors[role]
    if not valid(c) then c = Theme.Preset().colors[role] or Theme.Preset("cyan").colors[role] or { 1, 1, 1 } end
    return c[1], c[2], c[3]
end

--- The chat color code for a role: "|cffrrggbb".
function Theme.Hex(role)
    local r, g, b = Theme.Color(role)
    local function byte(v) return math.floor(v * 255 + 0.5) end
    return string.format("|cff%02x%02x%02x", byte(r), byte(g), byte(b))
end

--- Text in a role's color.
function Theme.Wrap(role, text)
    return Theme.Hex(role) .. tostring(text) .. "|r"
end

--- The icon as inline text (chat, tooltips, the guide's title).
function Theme.IconText(size)
    size = size or 14
    return string.format("|T%s:%d:%d|t", Theme.ICON, size, size)
end

--- "<icon> Quest Ladder" in the accent color, for chat lines and tooltips.
function Theme.Name(size)
    return Theme.IconText(size) .. " " .. Theme.Wrap("accent", "Quest Ladder")
end

function Theme.Changed()
    Theme.version = Theme.version + 1
    ns.Fire("THEME_CHANGED")
end

--- Switches to a theme. Colors you picked yourself are dropped, so the theme shows as it is.
function Theme.SetPreset(key)
    local p = byKey[key]
    if not p then return false end
    local d = db()
    d.theme = p.key
    d.colors = {}
    Theme.Changed()
    return true
end

local function round(v) return math.floor(math.max(0, math.min(1, v)) * 1000 + 0.5) / 1000 end

--- Your own color for one role, on top of the theme.
function Theme.SetColor(role, r, g, b)
    if type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" then return false end
    if ns.AnySecret(r, g, b) then return false end
    local d = db()
    if type(d.colors) ~= "table" then d.colors = {} end
    d.colors[role] = { round(r), round(g), round(b) }
    Theme.Changed()
    return true
end

--- Back to the theme's color for one role.
function Theme.ResetColor(role)
    local d = db()
    if type(d.colors) == "table" then d.colors[role] = nil end
    Theme.Changed()
end
