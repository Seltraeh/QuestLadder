-- Minimal fake WoW client + fake QuestieDB for offline tests of Quest Ladder.
local M = {}

---------------------------------------------------------------------------
-- Frame stub that accepts any method call (records nothing, returns sane values)
---------------------------------------------------------------------------
local frameMeta
local function newFrame(name)
    local f = { __name = name, __shown = false, __attrs = {}, __scripts = {}, __text = "" }
    return setmetatable(f, frameMeta)
end
frameMeta = {
    __index = function(t, k)
        local special = {
            Show = function(self) self.__shown = true end,
            Hide = function(self) self.__shown = false end,
            IsShown = function(self) return self.__shown end,
            SetScript = function(self, s, fn) self.__scripts[s] = fn end,
            GetScript = function(self, s) return self.__scripts[s] end,
            SetAttribute = function(self, k2, v) self.__attrs[k2] = v end,
            GetAttribute = function(self, k2) return self.__attrs[k2] end,
            SetText = function(self, v) self.__text = v end,
            GetText = function(self) return self.__text end,
            GetStringHeight = function() return 12 end,
            GetLeft = function() return 100 end,
            GetTop = function() return 500 end,
            GetEffectiveScale = function() return 1 end,
            GetPoint = function() return "CENTER", nil, "CENTER", 0, 0 end,
            CreateFontString = function() return newFrame("fs") end,
            CreateTexture = function() return newFrame("tex") end,
            RegisterEvent = function(self, e) self.__events = self.__events or {}; self.__events[e] = true end,
            IsVisible = function(self) return self.__shown end,
            GetID = function(self) return self.__id end,
            SetID = function(self, v) self.__id = v end,
            GetChildren = function(self) return unpack(self.__children or {}) end,
            GetParent = function(self) return self.__parent end,
            SetParent = function(self, p) self.__parent = p end,
            GetFrameLevel = function(self) return self.__level end,
            SetFrameLevel = function(self, v) self.__level = v end,
            IsProtected = function() return false end,
            CreateAnimationGroup = function() return newFrame("ag") end,
            CreateAnimation = function() return newFrame("anim") end,
            SetPoint = function(self, ...) self.__points = self.__points or {}; table.insert(self.__points, { ... }) end,
            ClearAllPoints = function(self) self.__points = {} end,
            EnumerateValidItems = function(self) return ipairs(self.__items or {}) end,
        }
        if special[k] then return special[k] end
        -- Unknown *methods* are no-ops; unknown *fields* (UnitFrame, QuestLadderMark, __x) are nil.
        if k == "GetBag" or k == "GetBagID" or k == "IsObjectType" then return nil end -- set explicitly on item-button mocks
        if type(k) == "string" and k:match("^%u") and (k:match("^Set") or k:match("^Get") or k:match("^Is")
            or k:match("^Create") or k:match("^Register") or k:match("^Unregister") or k:match("^Enable")
            or k:match("^Hook") or k:match("^Clear") or k:match("^Start") or k:match("^Stop")
            or k:match("^Play") or k:match("^Add") or k:match("^Raise") or k:match("^Lower")) then
            return function() end
        end
        return nil
    end,
}
M.newFrame = newFrame

---------------------------------------------------------------------------
-- Globals
---------------------------------------------------------------------------
function M.installGlobals(opts)
    opts = opts or {}
    M.time = 1000
    M.frames = {}
    _G.GetTime = function() return M.time end
    _G.debugprofilestop = function() return os.clock() * 1000 end
    _G.print = _G.print
    _G.DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg) M.lastPrint = msg end }
    _G.geterrorhandler = function() return function(err) error(err, 0) end end
    _G.SlashCmdList = {}
    _G.UISpecialFrames = {}
    _G.tinsert = table.insert
    _G.loadstring = loadstring
    _G.issecretvalue = function() return false end
    if opts.frames then
        _G.CreateFrame = function(_, name, parent)
            local f = newFrame(name)
            f.__parent = parent
            M.frames[#M.frames + 1] = f
            if name then _G[name] = f end
            return f
        end
        _G.UIParent = newFrame("UIParent")
        _G.GameTooltip = newFrame("GameTooltip")
    else
        _G.CreateFrame = nil
    end
    _G.C_Timer = nil -- Debounce runs immediately in tests
    _G.strsplit = function(sep, str)
        local out = {}
        for part in (str .. sep):gmatch("(.-)" .. sep:gsub("%-", "%%-")) do out[#out + 1] = part end
        return unpack(out)
    end
    M.guids = {}
    _G.UnitGUID = function(unit) return M.guids[unit] end
    _G.UnitName = function(unit) return M.names and M.names[unit] end
    M.taxiNodes = {}
    _G.C_TaxiMap = { GetTaxiNodesForMap = function() return M.taxiNodes end }
    _G.Enum = { UIMapType = { Continent = 2 }, FlightPathFaction = { Neutral = 0, Horde = 1, Alliance = 2 } }
    M.bindName = nil
    _G.GetBindLocation = function() return M.bindName end
    M.hearthCD = { 0, 0 }
    M.plates = {}
    _G.C_NamePlate = {
        GetNamePlateForUnit = function(unit) return M.plates[unit] end,
        GetNamePlates = function() local out = {} for _, p in pairs(M.plates) do out[#out + 1] = p end return out end,
    }
    _G.hooksecurefunc = function() end
    _G.LibStub = nil
    -- Bag windows start closed in every test (tests that open them set these themselves).
    _G.ContainerFrameCombinedBags, _G.ContainerFrameUtil_EnumerateContainerFrames = nil, nil
    _G.BagBrother, _G.Baganator, _G.MainMenuBarBackpackButton = nil, nil, nil
    _G.InCombatLockdown = function() return M.inCombat or false end
    _G.IsShiftKeyDown = function() return false end
    _G.UnitLevel = function() return M.player.level end
    _G.UnitClass = function() return M.player.className, M.player.classFile end
    _G.UnitRace = function() return "Human", "Human", 1 end
    _G.UnitFactionGroup = function() return "Alliance" end
    _G.GetMoney = function() return M.player.money end
    _G.CreateVector2D = function(x, y) return { x = x, y = y } end
    _G.NUM_BAG_SLOTS = 4

    -- Map: transforms are injected through Geo.SetTransform; player position here.
    _G.C_Map = {
        GetBestMapForUnit = function() return M.player.mapId end,
        GetPlayerMapPosition = function() return { x = M.player.x, y = M.player.y } end,
        GetMapInfo = function(id)
            if id == 1415 then return { name = "Eastern Kingdoms", mapID = id, mapType = 2 } end
            return { name = "Elwynn Forest", mapID = id, mapType = 3, parentMapID = 1415 }
        end,
        GetWorldPosFromMapPos = nil,
        SetUserWaypoint = function(p) M.waypoint = p end,
        GetUserWaypoint = function()
            local p = M.waypoint
            return p and { uiMapID = p.mapId, position = { x = p.x, y = p.y } } or nil
        end,
        CanSetUserWaypointOnMap = function() return true end,
    }
    _G.UiMapPoint = { CreateFromCoordinates = function(m, x, y) return { mapId = m, x = x, y = y } end }
    _G.C_SuperTrack = { SetSuperTrackedUserWaypoint = function() end, IsSuperTrackingUserWaypoint = function() return true end }

    -- Quest log
    _G.C_QuestLog = {
        GetNumQuestLogEntries = function() return #M.log end,
        GetInfo = function(i)
            local q = M.log[i]
            return q and { questID = q.id, title = q.title, level = q.level, isHeader = false, suggestedGroup = 0 }
        end,
        IsComplete = function(id) for _, q in ipairs(M.log) do if q.id == id then return q.complete end end return false end,
        IsFailed = function() return false end,
        GetQuestObjectives = function(id)
            for _, q in ipairs(M.log) do if q.id == id then return q.objectives end end
            return {}
        end,
        IsQuestFlaggedCompleted = function(id) return M.completed[id] or false end,
        GetMaxNumQuestsCanAccept = function() return M.logMax or 20 end,
        GetQuestsOnMap = function() return {} end,
        GetNextWaypoint = function() return nil end,
        GetTimeAllowed = function() return nil end,
        GetQuestTagInfo = function() return nil end,
        IsOnQuest = function(id) for _, q in ipairs(M.log) do if q.id == id then return true end end return false end,
        GetTrivialRange = function() return 5 end,
    }
    _G.GetNumQuestLogChoices = function(id) local r = M.rewards[id]; return r and #r or 0 end
    _G.GetQuestLogItemLink = function(kind, i, id)
        local r = M.rewards[id]
        if kind == "choice" and r and r[i] then return "|Hitem:" .. r[i] .. "|h[x]|h" end
        return nil
    end
    _G.GetQuestLogChoiceInfo = function(i, id)
        local r = M.rewards[id]
        if r and r[i] then return "x", 0, 1, 2, true, r[i] end
    end
    _G.GetNumQuestLogRewards = function() return 0 end
    _G.GetQuestLogSpecialItemInfo = function(i)
        local q = M.log[i]
        if q and q.special then return "|Hitem:" .. q.special .. "|h[x]|h", 0, 1 end
        return nil
    end
    _G.C_SkillInfo = nil

    -- Bags
    _G.C_Container = {
        GetItemCooldown = function() return M.hearthCD[1], M.hearthCD[2], 1 end,
        GetContainerNumSlots = function(bag) return (bag == 0) and 16 or 0 end,
        GetContainerNumFreeSlots = function(bag)
            if bag ~= 0 then return 0, 0 end
            return 16 - #M.bag, 0
        end,
        GetContainerItemInfo = function(bag, slot)
            if bag ~= 0 then return nil end
            local e = M.bag[slot]
            if not e then return nil end
            return { itemID = e.id, stackCount = e.count or 1, quality = M.items[e.id] and M.items[e.id].quality or 1,
                     hyperlink = "|Hitem:" .. e.id .. "|h[" .. (M.items[e.id] and M.items[e.id].name or "?") .. "]|h", isBound = e.bound }
        end,
        GetContainerItemQuestInfo = function(bag, slot)
            local e = bag == 0 and M.bag[slot]
            if e and e.startsQuest then return { isQuestItem = true, questID = e.startsQuest, isActive = false } end
            if e and e.questItem then return { isQuestItem = true } end
            return { isQuestItem = false }
        end,
    }

    -- Items
    _G.C_Item = {
        GetItemInfo = function(item)
            local id = type(item) == "number" and item or tonumber(tostring(item):match("item:(%d+)"))
            local it = M.items[id]
            if not it then return nil end
            return it.name, "|Hitem:" .. id .. "|h[" .. it.name .. "]|h", it.quality or 1, it.ilvl or 5, it.minLevel or 0,
                "", "", 1, it.equipLoc or "", 0, it.sell or 0, it.classID or 15, it.subClassID or 0, it.bind or 0
        end,
        GetItemNameByID = function(id) return M.items[id] and M.items[id].name end,
        GetItemSpell = function(id) return M.items[id] and M.items[id].spell end,
        GetItemCount = function(id)
            local n = 0
            for _, e in ipairs(M.bag) do if e.id == id then n = n + (e.count or 1) end end
            return n
        end,
        GetItemStats = function(link)
            local id = tonumber(tostring(link):match("item:(%d+)"))
            return id and M.items[id] and M.items[id].stats or nil
        end,
        GetItemIconByID = function() return 134400 end,
        RequestLoadItemDataByID = function() end,
    }
    _G.GetInventoryItemLink = function(_, slot)
        local id = M.equipped[slot]
        return id and ("|Hitem:" .. id .. "|h[x]|h") or nil
    end
    _G.C_PlayerInfo = nil
    _G.GetCoinTextureString = nil
end

---------------------------------------------------------------------------
-- Fake LibQuestieDB
---------------------------------------------------------------------------
function M.fakeDB(data)
    local function entity(rows, keys)
        local E = {}
        function E.Exists(id) return rows[id] ~= nil end
        function E.Get(id, key)
            local r = rows[id]
            if not r then return nil end
            local v = r[key]
            if v == nil and keys and keys[key] == "number" then return 0 end
            return v
        end
        function E.GetAllIds()
            local ids = {}
            for id in pairs(rows) do ids[#ids + 1] = id end
            table.sort(ids)
            return ids
        end
        return E
    end
    local numeric = {
        requiredLevel = "number", questLevel = "number", requiredRaces = "number", requiredClasses = "number",
        sourceItemId = "number", zoneOrSort = "number", nextQuestInChain = "number", specialFlags = "number",
        parentQuest = "number", breadcrumbForQuestId = "number", requiredMaxLevel = "number",
        npcFlags = "number", class = "number", startQuest = "number",
    }
    return {
        RequireContract = function() return true end,
        Quest = entity(data.quests, numeric),
        Npc = entity(data.npcs, numeric),
        Object = entity(data.objects, numeric),
        Item = entity(data.items, numeric),
        Enum = {
            raceMaskById = { [1] = 1 },
            classKeys = { WARRIOR = 1, MAGE = 128 },
            npcFlags = { VENDOR = 128, TRAINER = 16, FLIGHT_MASTER = 8, INNKEEPER = 512 },
        },
    }
end

---------------------------------------------------------------------------
-- Loading the add-on
---------------------------------------------------------------------------
function M.loadAddon(dir, files)
    local ns = {}
    for _, f in ipairs(files) do
        local chunk, err = loadfile(dir .. "/" .. f)
        if not chunk then error(err) end
        chunk("QuestLadder", ns)
    end
    return ns
end

return M
