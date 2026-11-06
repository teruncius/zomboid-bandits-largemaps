-- YANMC Bandits Core tells towns from countryside by outlines of the Knox
-- (Kentucky) towns (YANMCFreshTownBoundaries). On Real USA nearly every point
-- lies outside them, so everything counts as rural. This replaces the outlines
-- with the town boxes Real USA ships for its town maps (RealUSA.TOWN_MAPS),
-- which YANMC's spawn zoning, Week One events and battle audio then use.

local applied = false

local function inRealUSA()
    local RUSA = RealUSA
    if not RUSA or type(RUSA.TOWN_MAPS) ~= "table" then return false end
    if RUSA.isCountryList and RUSA.mapList then
        return RUSA.isCountryList(RUSA.mapList())
    end
    return RUSA.inCountryWorld ~= nil and RUSA.inCountryWorld()
end

local function apply()
    if applied then return end
    local towns = YANMCFreshTownBoundaries
    if type(towns) ~= "table" or not inRealUSA() then return end

    local boundaries = {}
    for _, row in ipairs(RealUSA.TOWN_MAPS) do
        -- name, state, x1, y1, x2, y2 in world tiles (inclusive)
        local x1, y1, x2, y2 = tonumber(row[3]), tonumber(row[4]), tonumber(row[5]), tonumber(row[6])
        if x1 and y1 and x2 and y2 then
            local minX, maxX = math.min(x1, x2), math.max(x1, x2)
            local minY, maxY = math.min(y1, y2), math.max(y1, y2)
            boundaries[#boundaries + 1] = {
                name = tostring(row[1]) .. ", " .. tostring(row[2]),
                minX = minX, minY = minY, maxX = maxX, maxY = maxY,
                points = { { minX, minY }, { maxX, minY }, { maxX, maxY }, { minX, maxY } },
            }
        end
    end
    if #boundaries == 0 then return end

    -- replaced in place, YANMC keeps references to this table
    for i = #towns, 1, -1 do towns[i] = nil end
    for i, town in ipairs(boundaries) do towns[i] = town end
    if YANMCFreshSpawnZoning then
        YANMCFreshSpawnZoning.CLASSIFIER_VERSION = "banditslargemaps-realusa-town-maps"
    end
    applied = true
    print("[BanditsLargeMaps] urban areas: " .. #boundaries .. " Real USA town boxes")
end

-- All mods' Lua is loaded and the map list is known by then. OnLoadMapZones
-- fires in single player, on the server and on the clients; the others are
-- fallbacks, apply() runs only once.
Events.OnLoadMapZones.Add(apply)
Events.OnGameStart.Add(apply)
Events.OnServerStarted.Add(apply)
