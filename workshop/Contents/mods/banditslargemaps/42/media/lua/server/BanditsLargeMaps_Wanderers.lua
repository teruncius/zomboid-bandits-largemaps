-- Bandits wanderer groups travel between destinations hardcoded to the Knox
-- (Kentucky) map and only turn into real NPCs within 70 tiles of a player.
-- On other maps, like Real USA, those destinations are far away from every
-- player, so wanderers are never met and pile up against the 100 group cap.
-- This replaces the destinations with points around the online players and
-- moves groups stranded far from everyone back into reach.

if isClient() then return end

local REFRESH_MINUTES = 10

local minutesSinceRefresh = REFRESH_MINUTES

local function option(name, default)
    local group = SandboxVars and SandboxVars.BanditsLargeMaps
    local value = group and group[name]
    if type(value) ~= "number" then return default end
    return value
end

local function getPlayerPositions()
    local list
    if isServer() then
        list = getOnlinePlayers()
    else
        list = IsoPlayer.getPlayers()
    end
    local positions = {}
    if not list then return positions end
    for i = 0, list:size() - 1 do
        local player = list:get(i)
        if player and not player:isDead() then
            positions[#positions + 1] = { x = player:getX(), y = player:getY() }
        end
    end
    return positions
end

local function nearAny(x, y, positions, distance)
    local limit = distance * distance
    for _, position in ipairs(positions) do
        local dx, dy = x - position.x, y - position.y
        if dx * dx + dy * dy <= limit then return true end
    end
    return false
end

local function pointAround(origin, minDistance, maxDistance)
    local angle = ZombRandFloat(0, 2 * math.pi)
    local distance = ZombRandFloat(minDistance, maxDistance)
    return math.max(0, math.floor(origin.x + math.cos(angle) * distance)),
        math.max(0, math.floor(origin.y + math.sin(angle) * distance))
end

-- Far points are where groups start and roam, Bandits only starts groups at
-- destinations more than 150 tiles away from every player. Near points make
-- some routes pass the players, which is where groups turn into NPCs.
local function buildDestinations(positions)
    local farMin = option("FarMinDistance", 400)
    local farMax = math.max(farMin, option("FarMaxDistance", 900))
    local nearMax = option("NearMaxDistance", 50)
    local all, far = {}, {}
    for p, origin in ipairs(positions) do
        for i = 1, option("FarPoints", 4) do
            local x, y = pointAround(origin, farMin, farMax)
            local destination = { name = "Large maps far " .. p .. "." .. i, x = x, y = y, z = 0 }
            all[#all + 1] = destination
            far[#far + 1] = destination
        end
        for i = 1, option("NearPoints", 2) do
            local x, y = pointAround(origin, 0, nearMax)
            all[#all + 1] = { name = "Large maps near " .. p .. "." .. i, x = x, y = y, z = 0 }
        end
    end
    return all, far
end

local function choice(list)
    return list[ZombRand(#list) + 1]
end

local function retargetGroups(all, far, positions)
    if not GetBanditModData then return false end
    local gmd = GetBanditModData()
    local wanderers = gmd and gmd.Wanderers
    if not wanderers then return false end

    local recycleDistance = option("RecycleDistance", 3000)
    local destinationRange = math.max(option("FarMinDistance", 400), option("FarMaxDistance", 900)) + 100
    local changed = false
    for _, group in ipairs(wanderers) do
        -- dead groups expire after 14 days, groups placed by hand (marked
        -- false by YANMC) keep their route
        if group.alive and group._yanmcAutomaticAmbientPopulation ~= false
            and type(group.x) == "number" and type(group.y) == "number" then
            if #far > 0 and not nearAny(group.x, group.y, positions, recycleDistance) then
                local start = choice(far)
                group.x, group.y, group.z = start.x, start.y, 0
                changed = true
            end
            local destination = group.destination
            if type(destination) ~= "table" or type(destination.x) ~= "number" or type(destination.y) ~= "number"
                or not nearAny(destination.x, destination.y, positions, destinationRange) then
                group.destination = choice(all)
                changed = true
            end
        end
    end
    return changed
end

local function refresh()
    local wanderers = BanditServer and BanditServer.Wanderers
    if not wanderers or type(wanderers.destinations) ~= "table" then return false end

    local positions = getPlayerPositions()
    if #positions == 0 then return false end

    local all, far = buildDestinations(positions)
    if #all == 0 then return false end

    -- replaced in place, Bandits keeps references to this table
    local destinations = wanderers.destinations
    for i = #destinations, 1, -1 do destinations[i] = nil end
    for i, destination in ipairs(all) do destinations[i] = destination end

    if retargetGroups(all, far, positions) and TransmitBanditModData then
        TransmitBanditModData()
    end
    return true
end

local function everyOneMinute()
    minutesSinceRefresh = minutesSinceRefresh + 1
    if minutesSinceRefresh < REFRESH_MINUTES then return end
    if refresh() then minutesSinceRefresh = 0 end
end

Events.EveryOneMinute.Add(everyOneMinute)
