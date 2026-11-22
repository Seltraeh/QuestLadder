-- Quest Ladder: marking things in the world for the current step.
--
-- WoW does not let add-ons draw on 3D objects the way RuneLite can, so this uses the hooks the
-- game does offer:
--   * NPCs: a cyan box on their nameplate with a label under it (quest mobs, quest givers, turn-ins)
--   * Objects (books, crates, herbs, ore): Blizzard's soft-target system tells us what you are
--     facing; when it is the objective you get a "this one" cue, and the nameplate the game
--     shows for that object gets the box. /ladder interacticons turns on Blizzard's own icons
--     over interactable objects.
--   * Places: small cyan boxes on the minimap and world map at the objective's spawn points
--     (via the standalone HereBeDragons library; Questie's own copy is private to Questie).

local _, ns = ...
local WM = {}
ns.WorldMarks = WM

WM.npc = {}     -- npcId -> label
WM.object = {}  -- objectId -> label
WM.mobs = {}    -- npcId -> true for mobs you fight (kill objectives and item drops)
WM.softHit = nil
WM.targetHit = nil

local CYAN_R, CYAN_G, CYAN_B = 0.0, 1.0, 1.0

---------------------------------------------------------------------------
-- GUIDs: "Creature-0-[server]-[instance]-[zone]-[npcId]-[spawn]"
-- (Forever obfuscates the server and spawn parts; the ID part stays readable.)
---------------------------------------------------------------------------
function WM.ParseGUID(guid)
    if type(guid) ~= "string" or ns.IsSecret(guid) then return nil end
    local kind, _, _, _, _, id = strsplit("-", guid)
    return kind, tonumber(id)
end

--- The current step's label for a GUID (an NPC or an object), and the GUID's kind.
function WM.LabelFor(guid)
    local kind, id = WM.ParseGUID(guid)
    if not id then return nil end
    if kind == "GameObject" then return WM.object[id], kind end
    if kind == "Creature" or kind == "Vehicle" then return WM.npc[id], kind end
    return nil
end

---------------------------------------------------------------------------
-- Targets for the current step
---------------------------------------------------------------------------
local LABEL = { monster = "Kill", item = "Loot", object = "Use", event = "Go" }

local function addGiver(point, label)
    if not point or not point.giverId then return end
    if point.giverId > 0 then WM.npc[point.giverId] = label else WM.object[-point.giverId] = label end
end

function WM.SetTargets(step)
    WM.npc, WM.object, WM.mobs = {}, {}, {}
    if step then
        for _, t in ipairs(step.tasks) do
            if not t.isDone then
                if t.kind == "pickup" then
                    addGiver(t.loc, "Accept")
                elseif t.kind == "turnin" then
                    addGiver(t.loc, (t.quest and t.quest.useFirst) and "Use item on" or "Turn in")
                elseif t.kind == "objective" and t.obj and t.obj.targets then
                    local label = LABEL[t.obj.type] or "Quest"
                    -- item drops count too: the Burning Blade Medallion means killing Yarrog
                    local fight = t.obj.type == "monster" or t.obj.type == "item"
                    for _, id in ipairs(t.obj.targets.npc or {}) do
                        WM.npc[id] = label
                        if fight then WM.mobs[id] = true end
                    end
                    for _, id in ipairs(t.obj.targets.object or {}) do WM.object[id] = label end
                elseif t.kind == "visit" and t.npcId then
                    WM.npc[t.npcId] = (t.visit == "flight" and "Flight path") or (t.visit == "bind" and "Innkeeper")
                        or (t.visit == "vendor" and "Vendor") or "Trainer"
                end
                -- Questie's hidden objectives can name a creature to use an item on.
                local db = t.quest and t.quest.db
                for _, row in ipairs((db and db.extraObjectives) or {}) do
                    for _, ref in ipairs(row[5] or {}) do
                        if ref[1] == "monster" and ref[2] then WM.npc[ref[2]] = "Use item on" end
                        if ref[1] == "object" and ref[2] then WM.object[ref[2]] = "Use item on" end
                    end
                end
            end
        end
    end
    WM.NoticeEnemyPlates()
    WM.RefreshNameplates()
    WM.RefreshPins(step)
    if WM.RefreshTargetHits then WM.RefreshTargetHits() end
end

--- Quest mobs can only be boxed when enemy nameplates are shown. Say so once per session, the
--- first time a step has mobs to kill (or loot) while they're off (nothing is changed for you).
function WM.StepHasMobs()
    return next(WM.mobs) ~= nil
end

function WM.NoticeEnemyPlates()
    if WM.toldEnemyPlates or not ns.db.worldMarks or not WM.StepHasMobs() then return end
    local get = (C_CVar and C_CVar.GetCVar) or GetCVar
    local ok, value = pcall(get, "nameplateShowEnemies")
    if ok and not ns.IsSecret(value) and value == "0" then
        WM.toldEnemyPlates = true
        ns.Print("enemy nameplates are off, so this step's quest mobs can't get a cyan box. "
            .. "Press V (or Options > Nameplates) to show them.")
    end
end

---------------------------------------------------------------------------
-- Nameplates
---------------------------------------------------------------------------
--- What the box goes around. An NPC's nameplate has a health bar; an object's nameplate (the
--- game shows one for the object you face) has no health bar, so the box goes around its name.
local function anchorFor(plate, kind)
    local uf = plate.UnitFrame
    if kind == "GameObject" then return (uf and uf.name) or uf or plate end
    return (uf and (uf.healthBar or uf.HealthBarsContainer)) or uf or plate
end

local function newMark(plate)
    local m = CreateFrame("Frame", nil, plate)
    for _, spec in ipairs({ { "TOPLEFT", "TOPRIGHT", true }, { "BOTTOMLEFT", "BOTTOMRIGHT", true },
                            { "TOPLEFT", "BOTTOMLEFT", false }, { "TOPRIGHT", "BOTTOMRIGHT", false } }) do
        local t = m:CreateTexture(nil, "OVERLAY")
        t:SetColorTexture(CYAN_R, CYAN_G, CYAN_B, 1)
        t:SetPoint(spec[1])
        t:SetPoint(spec[2])
        if spec[3] then t:SetHeight(2) else t:SetWidth(2) end
    end
    m.label = m:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    -- under the box: the mob's name sits right above its health bar, and a label there covered it
    m.label:SetPoint("TOP", m, "BOTTOM", 0, -2)
    m.label:SetTextColor(CYAN_R, CYAN_G, CYAN_B)
    plate.QuestLadderMark = m
    return m
end

local function markFor(plate, kind)
    local m = plate.QuestLadderMark or newMark(plate)
    -- the game reuses plates for other units, so place the box every time
    local anchor = anchorFor(plate, kind)
    m:ClearAllPoints()
    m:SetPoint("TOPLEFT", anchor, "TOPLEFT", -3, 3)
    m:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", 3, -3)
    return m
end

function WM.DecoratePlate(unit)
    if not (C_NamePlate and C_NamePlate.GetNamePlateForUnit) then return end
    local plate = C_NamePlate.GetNamePlateForUnit(unit)
    if not plate or (plate.IsForbidden and plate:IsForbidden()) then return end
    local label, kind
    if ns.db.worldMarks then
        local ok, guid = pcall(UnitGUID, unit)
        if ok then label, kind = WM.LabelFor(guid) end
    end
    if label then
        local m = markFor(plate, kind)
        m.label:SetText(label)
        m:Show()
    elseif plate.QuestLadderMark then
        plate.QuestLadderMark:Hide()
    end
end

function WM.RefreshNameplates()
    if not (C_NamePlate and C_NamePlate.GetNamePlates) then return end
    for _, plate in ipairs(C_NamePlate.GetNamePlates() or {}) do
        local unit = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
        if unit then WM.DecoratePlate(unit) end
    end
end

ns.RegisterEvent("NAME_PLATE_UNIT_ADDED", function(_, unit) WM.DecoratePlate(unit) end)
ns.RegisterEvent("NAME_PLATE_UNIT_REMOVED", function(_, unit)
    local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit(unit)
    if plate and plate.QuestLadderMark then plate.QuestLadderMark:Hide() end
end)

---------------------------------------------------------------------------
-- Soft target (what you are facing) and your target
---------------------------------------------------------------------------
local function lookup(guid)
    return (WM.LabelFor(guid))
end

local function safeName(unit)
    local ok, name = pcall(UnitName, unit)
    if ok and not ns.IsSecret(name) and name then return name end
    return nil
end

--- What you've selected: your target and what you're facing (soft target), as
--- { kind = "Creature"|"GameObject"|..., id, name }. Used by the use button (Hints.UseReady),
--- so it works with world markers off too. Secret GUIDs are skipped.
function WM.Selected()
    local out = {}
    for _, unit in ipairs({ "target", "softinteract" }) do
        local ok, guid = pcall(UnitGUID, unit)
        if ok then
            local kind, id = WM.ParseGUID(guid)
            if id then out[#out + 1] = { kind = kind, id = id, name = safeName(unit), unit = unit } end
        end
    end
    return out
end

local lastSoftStep = false
ns.RegisterEvent("PLAYER_SOFT_INTERACT_CHANGED", function(_, _, newGuid)
    local label = ns.db.worldMarks and lookup(newGuid)
    local was = WM.softHit
    if label then
        WM.softHit = { label = label, name = safeName("softinteract") }
        if not was and PlaySound and SOUNDKIT and SOUNDKIT.MAP_PING then PlaySound(SOUNDKIT.MAP_PING) end
    else
        WM.softHit = nil
    end
    -- facing (or turning away from) one of this step's targets can bring up the use button
    local onStep = lookup(newGuid) ~= nil
    if (was ~= nil) ~= (WM.softHit ~= nil) or onStep ~= lastSoftStep then ns.Fire("HINTS_CHANGED") end
    lastSoftStep = onStep
end)

--- Re-checks what you target and face against the current step's targets. Called when you
--- change target, and when the step's targets change: otherwise "Target is right: Use item on
--- Deathguard Falgan" stayed up after that step was done, until you clicked something else.
function WM.RefreshTargetHits()
    local okT, targetGuid = pcall(UnitGUID, "target")
    local label = ns.db.worldMarks and okT and lookup(targetGuid)
    WM.targetHit = label and { label = label, name = safeName("target") } or nil
    local okS, softGuid = pcall(UnitGUID, "softinteract")
    local softLabel = ns.db.worldMarks and okS and lookup(softGuid)
    WM.softHit = softLabel and { label = softLabel, name = safeName("softinteract") } or nil
end

ns.RegisterEvent("PLAYER_TARGET_CHANGED", function()
    local label = ns.db.worldMarks and lookup(UnitGUID("target"))
    WM.targetHit = label and { label = label, name = safeName("target") } or nil
    ns.Fire("HINTS_CHANGED")
end)

--- Hints for the hint box (called from Hints.Compute). `covered` names the cues ("target",
--- "softinteract") a use-item line already gives: you use an item on that, you don't interact.
function WM.Hints(push, covered)
    covered = covered or {}
    if WM.softHit and not covered.softinteract then
        push({ priority = 99, kind = "info",
               text = string.format("|cff00ffff>> This one:|r %s%s - press your Interact key",
                   WM.softHit.label, WM.softHit.name and (" " .. WM.softHit.name) or "") })
    end
    if WM.targetHit and not covered.target then
        push({ priority = 64, kind = "info",
               text = string.format("|cff00ffffTarget is right:|r %s %s", WM.targetHit.label, WM.targetHit.name or "") })
    end
end

---------------------------------------------------------------------------
-- Minimap and world map boxes (HereBeDragons-Pins, loaded by Questie)
---------------------------------------------------------------------------
local pinPool, usedPins = {}, {}

--- Diagnostics: minimap + world map boxes currently placed.
function WM.PinCount() return #usedPins end

local function pinFrame(size)
    local f = table.remove(pinPool)
    if not f then
        f = CreateFrame("Frame", nil, UIParent)
        f.fill = f:CreateTexture(nil, "OVERLAY")
        f.fill:SetAllPoints()
        f.fill:SetColorTexture(CYAN_R, CYAN_G, CYAN_B, 0.85)
    end
    f:SetSize(size, size)
    usedPins[#usedPins + 1] = f
    return f
end

function WM.RefreshPins(step)
    local pins = LibStub and LibStub("HereBeDragons-Pins-2.0", true)
    if not pins then return end
    pins:RemoveAllMinimapIcons(WM)
    if pins.RemoveAllWorldMapIcons then pins:RemoveAllWorldMapIcons(WM) end
    for i = #usedPins, 1, -1 do
        usedPins[i]:Hide()
        pinPool[#pinPool + 1] = usedPins[i]
        usedPins[i] = nil
    end
    if not (ns.db.worldMarks and step) then return end
    local count = 0
    for _, t in ipairs(step.tasks) do
        if t.loc and not t.isDone then
            for _, p in ipairs(t.loc.members or { t.loc }) do
                if count >= 30 then break end
                if p.mapId and p.x and p.y then
                    pins:AddMinimapIconMap(WM, pinFrame(7), p.mapId, p.x, p.y, true, false)
                    if pins.AddWorldMapIconMap then
                        pins:AddWorldMapIconMap(WM, pinFrame(9), p.mapId, p.x, p.y, HBD_PINS_WORLDMAP_SHOW_PARENT or 1)
                    end
                    count = count + 1
                end
            end
        end
    end
end

---------------------------------------------------------------------------
-- Optional Blizzard settings presets (only when you ask, never in combat)
---------------------------------------------------------------------------
local PRESETS = {
    interacticons = {
        text = "Blizzard's interact icons are on: interactable objects in front of you get an icon.",
        cvars = { SoftTargetInteract = "3", SoftTargetIconInteract = "1", SoftTargetIconGameObject = "1" },
    },
    npcplates = {
        text = "Friendly NPC nameplates are on: quest givers and turn-ins get a cyan marker.",
        cvars = { nameplateShowFriendlyNPCs = "1" },
    },
}

ns.On("CVAR_PRESET", function(name)
    local preset = PRESETS[name]
    if not preset then return end
    if InCombatLockdown() then ns.Print("can't change settings in combat") return end
    local setter = (C_CVar and C_CVar.SetCVar) or SetCVar
    if not setter then return end
    for k, v in pairs(preset.cvars) do pcall(setter, k, v) end
    ns.Print(preset.text)
end)
