-- Quest Ladder: coordinates. Converts QuestieDB spawn points (AreaID + 0-100 coords) and
-- UiMap positions into world coordinates so distances are real yards, and clusters spawns.

local _, ns = ...
local Geo = {}
ns.Geo = Geo

Geo.CONTINENT_SECONDS = 900  -- travel cost (seconds) for changing continent: boats, zeppelins

---------------------------------------------------------------------------
-- AreaID -> UiMapID (from QuestieDB's Forever support data)
---------------------------------------------------------------------------
local areaToUiMap, subZoneToParent

local function loadSupportTable(value)
    if type(value) == "table" then return value end
    if type(value) == "string" and loadstring then
        local chunk = loadstring(value)
        if chunk then
            local ok, result = pcall(chunk)
            if ok and type(result) == "table" then return result end
        end
    end
    return nil
end

local function buildZoneMaps()
    areaToUiMap, subZoneToParent = {}, {}
    local lib = LibQuestieDB
    if not (lib and lib.Support and lib.Support.Get) then return end
    local ok, zoneDB = pcall(lib.Support.Get, "ZoneDB")
    if not ok or type(zoneDB) ~= "table" then return end
    local private = zoneDB.private or {}
    local base = loadSupportTable(private.areaIdToUiMapId) or {}
    local override = loadSupportTable(private.areaIdToUiMapIdOverride) or {}
    for k, v in pairs(base) do areaToUiMap[k] = v end
    for k, v in pairs(override) do areaToUiMap[k] = v end
    local parents = loadSupportTable(private.subZoneToParentZone) or {}
    local parentOverride = loadSupportTable(private.subZoneToParentZoneOverride) or {}
    for k, v in pairs(parents) do subZoneToParent[k] = v end
    for k, v in pairs(parentOverride) do subZoneToParent[k] = v end
end

--- Test hook: inject mapping tables directly.
function Geo.SetZoneMaps(areaMap, parentMap)
    areaToUiMap, subZoneToParent = areaMap or {}, parentMap or {}
end

--- Diagnostics: how many AreaID->UiMap and subzone->zone entries were loaded from QuestieDB.
function Geo.ZoneMapStats()
    if not areaToUiMap then buildZoneMaps() end
    local areas, subZones = 0, 0
    for _ in pairs(areaToUiMap) do areas = areas + 1 end
    for _ in pairs(subZoneToParent) do subZones = subZones + 1 end
    return areas, subZones
end

function Geo.AreaToUiMap(areaId)
    if not areaToUiMap then buildZoneMaps() end
    local id, guard = areaId, 0
    while id and guard < 4 do
        local mapId = areaToUiMap[id]
        if mapId then return mapId ~= 0 and mapId or nil end
        id = subZoneToParent[id]
        guard = guard + 1
    end
    return nil
end

---------------------------------------------------------------------------
-- UiMap (0-1) -> world position, via an affine transform per map.
---------------------------------------------------------------------------
local transforms = {}

local function worldPos(mapId, x, y)
    local ok, cont, pos = pcall(C_Map.GetWorldPosFromMapPos, mapId, CreateVector2D(x, y))
    if not ok or ns.AnySecret(cont, pos) or not cont or not pos then return nil end
    local wx, wy
    if pos.GetXY then wx, wy = pos:GetXY() else wx, wy = pos.x, pos.y end
    if ns.AnySecret(wx, wy) or not wx or not wy then return nil end
    return cont, wx, wy
end

local function getTransform(mapId)
    local t = transforms[mapId]
    if t ~= nil then return t end
    t = false
    if C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D and mapId then
        -- Three corners give the full affine map, whatever the axis orientation.
        local c0, x00, y00 = worldPos(mapId, 0, 0)
        local c1, x10, y10 = worldPos(mapId, 1, 0)
        local c2, x01, y01 = worldPos(mapId, 0, 1)
        if c0 and c1 and c2 then
            t = {
                cont = c0,
                ox = x00, oy = y00,
                ax = x10 - x00, ay = y10 - y00,   -- per unit map-x
                bx = x01 - x00, by = y01 - y00,   -- per unit map-y
            }
        end
    end
    transforms[mapId] = t
    return t
end

--- Test hook: provide a transform for a map without the client API.
function Geo.SetTransform(mapId, t)
    transforms[mapId] = t
end

--- Builds a point: { cont, wx, wy, mapId, x, y } with x/y in 0-1 (for waypoints).
function Geo.Point(mapId, x, y)
    if not mapId or not x or not y then return nil end
    local t = getTransform(mapId)
    if not t then return nil end
    return {
        cont = t.cont,
        wx = t.ox + t.ax * x + t.bx * y,
        wy = t.oy + t.ay * x + t.by * y,
        mapId = mapId, x = x, y = y,
    }
end

--- Point from QuestieDB spawn data (AreaID and 0-100 coordinates).
function Geo.PointFromArea(areaId, x100, y100)
    if x100 == -1 or y100 == -1 then return nil, true end -- instance sentinel
    local mapId = Geo.AreaToUiMap(areaId)
    if not mapId then return nil end
    return Geo.Point(mapId, x100 / 100, y100 / 100)
end

--- Converts a QuestieDB spawns table { [areaId] = { {x, y}, ... } } to points.
--- Returns points, inInstance (true when some spawns are dungeon-only sentinels).
function Geo.PointsFromSpawns(spawns, limit)
    local points, inInstance = {}, false
    if type(spawns) ~= "table" then return points, false end
    limit = limit or 60
    for areaId, list in pairs(spawns) do
        if type(list) == "table" then
            for i = 1, #list do
                local s = list[i]
                local p, instance = Geo.PointFromArea(areaId, s[1], s[2])
                if instance then inInstance = true end
                if p then
                    points[#points + 1] = p
                    if #points >= limit then return points, inInstance end
                end
            end
        end
    end
    return points, inInstance
end

---------------------------------------------------------------------------
-- Player position
---------------------------------------------------------------------------
function Geo.PlayerPoint()
    if not (C_Map and C_Map.GetBestMapForUnit) then return nil end
    local okMap, mapId = pcall(C_Map.GetBestMapForUnit, "player")
    if not okMap or ns.IsSecret(mapId) or not mapId then return nil end
    local ok, pos = pcall(C_Map.GetPlayerMapPosition, mapId, "player")
    if not ok or ns.IsSecret(pos) or not pos then return nil end
    local x, y
    if pos.GetXY then x, y = pos:GetXY() else x, y = pos.x, pos.y end
    if ns.AnySecret(x, y) or not x or not y then return nil end
    return Geo.Point(mapId, x, y)
end

---------------------------------------------------------------------------
-- Distance and travel time
---------------------------------------------------------------------------
function Geo.Distance(a, b)
    if not a or not b then return nil end
    if a.cont ~= b.cont then return math.huge end
    local dx, dy = a.wx - b.wx, a.wy - b.wy
    return math.sqrt(dx * dx + dy * dy)
end

Geo.RUN_SPEED = 7 -- yards per second on foot

function Geo.TravelSeconds(a, b, speed)
    if not a or not b then return 0 end
    if a.cont ~= b.cont then return Geo.CONTINENT_SECONDS end
    local dx, dy = a.wx - b.wx, a.wy - b.wy
    return math.sqrt(dx * dx + dy * dy) / (speed or Geo.RUN_SPEED)
end

---------------------------------------------------------------------------
-- Clustering: pick the best "camp" among many spawn points.
-- Score favours dense groups that are close to the reference point.
---------------------------------------------------------------------------
function Geo.BestCluster(points, ref, radius)
    if not points or #points == 0 then return nil end
    radius = radius or 90
    local n = #points
    if n == 1 then
        local p = points[1]
        return { cont = p.cont, wx = p.wx, wy = p.wy, mapId = p.mapId, x = p.x, y = p.y, count = 1, radius = 0 }
    end
    -- Seed clustering: every spawn is a candidate camp centre; members are spawns within
    -- `radius`. O(n^2) but n is capped at 80 spawns per entity.
    local r2 = radius * radius
    local best, bestScore
    for i = 1, n do
        local seed = points[i]
        local sx, sy, count, members = 0, 0, 0, {}
        for j = 1, n do
            local p = points[j]
            if p.cont == seed.cont then
                local dx, dy = p.wx - seed.wx, p.wy - seed.wy
                if dx * dx + dy * dy <= r2 then
                    sx, sy, count = sx + p.wx, sy + p.wy, count + 1
                    members[#members + 1] = p
                end
            end
        end
        local cx, cy = sx / count, sy / count
        local dist = 0
        if ref then
            if ref.cont ~= seed.cont then
                dist = 20000
            else
                local dx, dy = ref.wx - cx, ref.wy - cy
                dist = math.sqrt(dx * dx + dy * dy)
            end
        end
        local score = count / (1 + dist / 400)
        if not bestScore or score > bestScore + 1e-9 then
            best, bestScore = { cont = seed.cont, cx = cx, cy = cy, n = count, members = members }, score
        end
    end
    -- Waypoint at the real spawn nearest the cluster centre (centres can sit inside walls).
    local anchor, anchorD
    for i = 1, #best.members do
        local p = best.members[i]
        local dx, dy = p.wx - best.cx, p.wy - best.cy
        local d = dx * dx + dy * dy
        if not anchorD or d < anchorD then anchor, anchorD = p, d end
    end
    return {
        cont = best.cont, wx = best.cx, wy = best.cy,
        mapId = anchor.mapId, x = anchor.x, y = anchor.y,
        count = best.n, radius = radius,
        members = best.members,
    }
end

--- Nearest point in a list to ref.
function Geo.Nearest(points, ref)
    if not points or #points == 0 then return nil end
    if not ref then return points[1] end
    local best, bestD
    for i = 1, #points do
        local d = Geo.Distance(points[i], ref)
        if d and (not bestD or d < bestD) then best, bestD = points[i], d end
    end
    return best, bestD
end
