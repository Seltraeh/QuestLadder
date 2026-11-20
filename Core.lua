-- Quest Ladder: core namespace, settings, events, async scheduler, slash commands.
-- Everything here is plain UI-addon code: no protected calls, no automation of movement or combat.

local ADDON, ns = ...
ns.ADDON = ADDON or "QuestLadder"
ns.VERSION = "0.3.18"

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------
-- Forever has a known cold-start SavedVariables restore bug (see Questie's
-- docs/saved-variables-investigation.md). Every setting therefore has a sane default and
-- nothing important is stored only in SavedVariables: the plan is rebuilt live each session.
ns.defaults = {
    showGuide = true,
    showHints = true,
    guideScale = 1,
    nextStepsShown = 4,

    includeUnstarted = true,   -- plan quests you have not picked up yet (from QuestieDB)
    maxCandidates = 25,        -- how many not-yet-accepted quests to pull into the plan (was 12)
    pickupRadius = 900,        -- yards: how far away a quest giver may be to be considered
    chainDepth = 2,            -- follow-up quests to chain after a planned turn-in
    levelsAbove = 2,           -- skip quests more than this many levels above you
    skipDungeonQuests = true,  -- objectives that only exist inside instances
    skipEscortsAndElites = false,

    autoAccept = true,         -- accept quests that are in the plan when YOU open the quest dialog
    autoTurnIn = true,         -- complete quests with zero or one reward when YOU open the dialog
    autoPickReward = false,    -- also choose the best-scoring reward when there is a choice
    -- Holding Shift while talking to an NPC always suspends the automation above.

    waypoints = true,          -- put Blizzard's map pin / TomTom arrow on the current step
    useFlights = true,         -- route through flight paths you know
    useHearth = true,          -- plan where to use the hearthstone
    suggestBind = true,        -- suggest binding at a better inn when it saves 3+ minutes
    discoverFlights = true,    -- add flight masters within a ~1 minute detour
    highlights = true,         -- cyan boxes on bag items, bag buttons and the reward to pick
    worldMarks = true,         -- cyan markers on quest NPC nameplates and minimap/map boxes
    reserveSlots = 2,          -- bag slots to always keep free (gathering, profession mats, loot)
    goldReserve = nil,         -- copper to keep for training; nil = automatic by level
    lookahead = 10,            -- steps considered for bag-space and gear timing

    weights = nil,             -- optional per-stat weight overrides (see Gear.lua)
    debug = false,
}

local function applyDefaults(dst, src)
    for k, v in pairs(src) do
        if dst[k] == nil then
            if type(v) == "table" then
                dst[k] = {}
                applyDefaults(dst[k], v)
            else
                dst[k] = v
            end
        end
    end
    return dst
end
ns.ApplyDefaults = applyDefaults

--- Saved settings hold every default as a value, so a changed default needs a one-time update.
--- Only values still at the old default change; anything you set yourself stays.
--- 1 (0.3.15): maxCandidates 12 -> 25, so all the quests around a hub fit in the plan.
function ns.MigrateSettings(db)
    local v = db.settingsVersion or 0
    if v < 1 and db.maxCandidates == 12 then db.maxCandidates = ns.defaults.maxCandidates end
    db.settingsVersion = 1
end

-- Usable before ADDON_LOADED (and in tests): defaults until the saved table arrives.
ns.db = applyDefaults({}, ns.defaults)
ns.charDB = { ignored = {}, deferred = {}, frame = {} }

---------------------------------------------------------------------------
-- Output helpers
---------------------------------------------------------------------------
local PREFIX = "|cff33ff99Quest Ladder|r: "
function ns.Print(fmt, ...)
    local msg = select("#", ...) > 0 and string.format(fmt, ...) or tostring(fmt)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. msg)
    else
        print(PREFIX .. msg)
    end
end

function ns.Debug(fmt, ...)
    if ns.db and ns.db.debug then ns.Print("|cff888888" .. fmt .. "|r", ...) end
end

-- Midnight/Forever "secret values": never compute with them. Ask issecretvalue() before any
-- other test of a value: even `v ~= nil` or `if v then` counts as using it.
function ns.IsSecret(v)
    return issecretvalue ~= nil and issecretvalue(v) == true
end

--- True when any argument is a secret value (nil arguments are fine).
function ns.AnySecret(...)
    for i = 1, select("#", ...) do
        if ns.IsSecret((select(i, ...))) then return true end
    end
    return false
end

function ns.SafeCall(fn, ...)
    if not fn then return false end
    return pcall(fn, ...)
end

-- Errors caught by our own pcalls (events, messages, background jobs, the UI ticker) are kept
-- here for /ladder diag, then passed on to the normal error handler (BugSack, or Blizzard's).
ns.recentErrors = {}
local MAX_ERRORS = 30

function ns.ReportError(err)
    local msg = ns.IsSecret(err) and "<secret>" or tostring(err)
    if #msg > 500 then msg = msg:sub(1, 500) .. "..." end
    local now = GetTime and GetTime() or 0
    local found
    for _, e in ipairs(ns.recentErrors) do
        if e.msg == msg then found = e break end
    end
    if found then
        found.count, found.last = found.count + 1, now
    else
        if #ns.recentErrors >= MAX_ERRORS then table.remove(ns.recentErrors, 1) end
        table.insert(ns.recentErrors, { msg = msg, count = 1, first = now, last = now })
    end
    if geterrorhandler then geterrorhandler()(err) else print(err) end
end

function ns.FormatMoney(copper)
    copper = math.floor(copper or 0)
    if GetCoinTextureString then return GetCoinTextureString(copper) end
    local g = math.floor(copper / 10000)
    local s = math.floor((copper % 10000) / 100)
    local c = copper % 100
    if g > 0 then return string.format("%dg %ds %dc", g, s, c) end
    if s > 0 then return string.format("%ds %dc", s, c) end
    return string.format("%dc", c)
end

function ns.ParseMoney(text)
    text = (text or ""):lower()
    local total, found = 0, false
    for num, unit in text:gmatch("(%d+)%s*([gsc]?)") do
        found = true
        num = tonumber(num)
        if unit == "g" or unit == "" then total = total + num * 10000
        elseif unit == "s" then total = total + num * 100
        else total = total + num end
    end
    return found and total or nil
end

---------------------------------------------------------------------------
-- Internal messages (module-to-module)
---------------------------------------------------------------------------
local listeners = {}
function ns.On(msg, fn)
    listeners[msg] = listeners[msg] or {}
    table.insert(listeners[msg], fn)
end

function ns.Fire(msg, ...)
    local list = listeners[msg]
    if not list then return end
    for i = 1, #list do
        local ok, err = pcall(list[i], ...)
        if not ok then ns.ReportError(err) end
    end
end

---------------------------------------------------------------------------
-- Game events
---------------------------------------------------------------------------
local eventHandlers = {}
local eventFrame = CreateFrame and CreateFrame("Frame") or nil
ns.eventFrame = eventFrame

function ns.RegisterEvent(event, fn)
    if not eventHandlers[event] then
        eventHandlers[event] = {}
        if eventFrame then
            -- Some events do not exist on every client; never let that break loading.
            pcall(eventFrame.RegisterEvent, eventFrame, event)
        end
    end
    table.insert(eventHandlers[event], fn)
end

--- Runs every handler registered for a game event (also used by the offline tests).
function ns.DispatchEvent(event, ...)
    local list = eventHandlers[event]
    if not list then return end
    for i = 1, #list do
        local ok, err = pcall(list[i], event, ...)
        if not ok then ns.ReportError(err) end
    end
end

if eventFrame then
    eventFrame:SetScript("OnEvent", function(_, event, ...) ns.DispatchEvent(event, ...) end)
end

---------------------------------------------------------------------------
-- Async jobs: heavy index building and planning run in coroutines with a
-- per-frame time budget so the game never hitches.
---------------------------------------------------------------------------
local jobs = {}
local BUDGET_MS = 5
local runner = CreateFrame and CreateFrame("Frame") or nil
local clock = debugprofilestop or function() return os.clock() * 1000 end

local function runJobs()
    local start = clock()
    while #jobs > 0 and (clock() - start) < BUDGET_MS do
        local job = jobs[1]
        local ok, err = coroutine.resume(job.co)
        if not ok then
            table.remove(jobs, 1)
            ns.ReportError(err)
        elseif coroutine.status(job.co) == "dead" then
            table.remove(jobs, 1)
            if job.done then
                local okDone, errDone = pcall(job.done)
                if not okDone then ns.ReportError(errDone) end
            end
        end
    end
    if #jobs == 0 and runner then runner:Hide() end
end

if runner then
    runner:Hide()
    runner:SetScript("OnUpdate", runJobs)
end

--- Starts (or restarts) a named background job.
function ns.Async(name, fn, done)
    for i = #jobs, 1, -1 do
        if jobs[i].name == name then table.remove(jobs, i) end
    end
    table.insert(jobs, { name = name, co = coroutine.create(fn), done = done })
    if runner then
        runner:Show()
    else
        -- No frame (offline tests): run to completion synchronously.
        while #jobs > 0 do runJobs() end
    end
end

function ns.IsJobRunning(name)
    for i = 1, #jobs do
        if jobs[i].name == name then return true end
    end
    return false
end

local yieldCounter = 0
--- Call inside loops of async jobs; yields every `every` iterations.
function ns.MaybeYield(every)
    yieldCounter = yieldCounter + 1
    if yieldCounter >= (every or 40) then
        yieldCounter = 0
        if coroutine.running() then coroutine.yield() end
    end
end

---------------------------------------------------------------------------
-- Debounce helper
---------------------------------------------------------------------------
local pending = {}
function ns.Debounce(key, delay, fn)
    if pending[key] then return end
    pending[key] = true
    local function fire()
        pending[key] = nil
        fn()
    end
    if C_Timer and C_Timer.After then
        C_Timer.After(delay, fire)
    else
        fire()
    end
end

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------
ns.RegisterEvent("ADDON_LOADED", function(_, name)
    if name ~= ns.ADDON then return end
    -- For /ladder diag: did the client restore our saved settings? (Forever's cold-start bug)
    ns.svRestored = type(QuestLadderDB) == "table" and next(QuestLadderDB) ~= nil
    QuestLadderDB = applyDefaults(QuestLadderDB or {}, ns.defaults)
    ns.MigrateSettings(QuestLadderDB)
    QuestLadderCharDB = applyDefaults(QuestLadderCharDB or {}, { ignored = {}, deferred = {}, frame = {} })
    ns.db = QuestLadderDB
    ns.charDB = QuestLadderCharDB
    ns.Fire("SETTINGS_LOADED")
end)

ns.RegisterEvent("PLAYER_LOGIN", function()
    ns.Fire("LOGIN")
end)

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------
local function onOff(v)
    return v and "|cff00ff00on|r" or "|cffff4444off|r"
end

local toggles = {
    auto = { "autoAccept", "autoTurnIn" },
    autopick = { "autoPickReward" },
    unstarted = { "includeUnstarted" },
    dungeons = { "skipDungeonQuests", invert = true },
    waypoints = { "waypoints" },
    hints = { "showHints" },
    flights = { "useFlights" },
    hearth = { "useHearth" },
    bind = { "suggestBind" },
    discover = { "discoverFlights" },
    highlights = { "highlights" },
    marks = { "worldMarks" },
    debug = { "debug" },
}

local function help()
    ns.Print("commands:")
    print("  /ladder                 show or hide the guide")
    print("  /ladder replan          rebuild the route now")
    print("  /ladder skip            skip the current step (unstarted quests are ignored)")
    print("  /ladder unignore        clear all ignored quests")
    print("  /ladder bags            bag planner: what to sell or destroy")
    print("  /ladder gear            gear upgrades (quest rewards + Auctionator)")
    print("  /ladder reserve <n>     bag slots to keep free (now " .. tostring(ns.db.reserveSlots) .. ")")
    print("  /ladder gold <amount>   gold to keep for training, e.g. 5g or auto")
    print("  /ladder weight <stat> <n>  override a stat weight (str agi sta int spi armor dps ap sp)")
    print("  /ladder auto|autopick|unstarted|dungeons|waypoints|hints  toggle a feature")
    print("  /ladder flights|hearth|bind|discover|highlights|marks     toggle travel / highlight features")
    print("  /ladder interacticons   turn on Blizzard's icons over interactable objects")
    print("  /ladder npcplates       show friendly NPC nameplates (so quest givers get a marker)")
    print("  /ladder diag [label]    run the in-game checks and save them (then /reload); diag clear")
end

SLASH_QUESTLADDER1 = "/ladder"
SLASH_QUESTLADDER2 = "/qladder"
SlashCmdList.QUESTLADDER = function(input)
    local cmd, rest = (input or ""):match("^%s*(%S*)%s*(.-)%s*$")
    cmd = (cmd or ""):lower()

    if cmd == "" then
        ns.db.showGuide = not ns.db.showGuide
        ns.Fire("SETTINGS_CHANGED")
    elseif cmd == "help" then
        help()
    elseif cmd == "replan" then
        ns.Fire("REQUEST_REPLAN", "manual")
    elseif cmd == "skip" then
        ns.Fire("SKIP_STEP")
    elseif cmd == "unignore" then
        for k in pairs(ns.charDB.ignored) do ns.charDB.ignored[k] = nil end
        for k in pairs(ns.charDB.deferred) do ns.charDB.deferred[k] = nil end
        ns.Print("ignored quests cleared")
        ns.Fire("REQUEST_REPLAN", "unignore")
    elseif cmd == "bags" then
        ns.Fire("SHOW_PANEL", "bags")
    elseif cmd == "gear" then
        ns.Fire("SHOW_PANEL", "gear")
    elseif cmd == "reserve" then
        local n = tonumber(rest)
        if n and n >= 0 and n <= 30 then
            ns.db.reserveSlots = math.floor(n)
            ns.Print("keeping %d bag slots free", ns.db.reserveSlots)
            ns.Fire("REQUEST_REPLAN", "settings")
        else
            ns.Print("usage: /ladder reserve <0-30>")
        end
    elseif cmd == "gold" then
        if rest:lower() == "auto" then
            ns.db.goldReserve = nil
            ns.Print("gold reserve: automatic by level")
        else
            local copper = ns.ParseMoney(rest)
            if copper then
                ns.db.goldReserve = copper
                ns.Print("keeping %s for training", ns.FormatMoney(copper))
            else
                ns.Print("usage: /ladder gold 5g  (or /ladder gold auto)")
            end
        end
        ns.Fire("SETTINGS_CHANGED")
    elseif cmd == "weight" then
        local stat, value = rest:match("^(%a+)%s*([%d%.]*)$")
        if stat and stat:lower() == "reset" then
            ns.db.weights = nil
            ns.Print("stat weights reset to class defaults")
            ns.Fire("SETTINGS_CHANGED")
        elseif stat and tonumber(value) then
            ns.db.weights = ns.db.weights or {}
            ns.db.weights[stat:lower()] = tonumber(value)
            ns.Print("weight %s = %s", stat:lower(), value)
            ns.Fire("SETTINGS_CHANGED")
        else
            ns.Print("usage: /ladder weight agi 2.5   (or /ladder weight reset)")
        end
    elseif cmd == "interacticons" or cmd == "npcplates" then
        ns.Fire("CVAR_PRESET", cmd)
    elseif cmd == "diag" then
        ns.Fire("RUN_DIAG", rest)
    elseif toggles[cmd] then
        local spec = toggles[cmd]
        local newValue = not ns.db[spec[1]]
        for i = 1, #spec do ns.db[spec[i]] = newValue end
        local shown = spec.invert and not newValue or newValue
        ns.Print("%s: %s", cmd, onOff(shown))
        ns.Fire("SETTINGS_CHANGED")
        ns.Fire("REQUEST_REPLAN", "settings")
    else
        help()
    end
end

-- Key binding labels (Bindings.xml). The names carry "Quest Ladder:" because Forever's
-- Keybindings > AddOns list doesn't always show the section heading above them.
BINDING_HEADER_QUESTLADDER = "Quest Ladder"
_G["BINDING_NAME_CLICK QuestLadderUseButton:LeftButton"] = "Quest Ladder: use the suggested quest item"
BINDING_NAME_QUESTLADDER_SKIP = "Quest Ladder: skip current step"
BINDING_NAME_QUESTLADDER_TOGGLE = "Quest Ladder: show/hide guide"

function QuestLadder_Skip() ns.Fire("SKIP_STEP") end
function QuestLadder_Toggle() SlashCmdList.QUESTLADDER("") end
