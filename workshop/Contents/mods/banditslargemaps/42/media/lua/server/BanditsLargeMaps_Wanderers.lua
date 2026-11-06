-- Bandits wanderer groups travel between destinations hardcoded to the Knox
-- (Kentucky) map and only turn into real NPCs within 70 tiles of a player.
-- On other maps, like Real USA, those destinations are far away from every
-- player, so wanderers are never met and pile up against the 100 group cap.
--
-- This replaces the destinations with points far around the online players
-- and keeps every group away from them. Players close to each other form an
-- area, and each area gets one group sent to it every few days of play.

if isClient() then return end

local REFRESH_MINUTES = 10
-- Bandits turns groups into NPCs within 70 tiles of a player, YANMC only
-- 48 to 82 tiles away. Sent groups wait at this distance from their player.
local APPROACH_DISTANCE = 64
local MIN_APPROACH_DISTANCE = 40
-- a waiting group that has not turned into NPCs after this many minutes
-- tries another side, a bit closer
local STUCK_MINUTES = 30
-- sent groups start this far from their player and walk the rest
local DISPATCH_DISTANCE = 200
-- sent groups farther than this from every player start over
local LEASH_DISTANCE = 600
-- a group that disappears or shrinks this close to a player was met
local MET_DISTANCE = 100
-- other groups are kept this far from sent groups, so they do not fight
-- (groups fight within 70 tiles)
local GUARD_DISTANCE = 150

local minutesSinceRefresh = REFRESH_MINUTES
-- far points around the players, and those of them not close to a sent group
local allFar = {}
local far = {}
local previous = {}

local function option(name, default)
    local group = SandboxVars and SandboxVars.BanditsLargeMaps
    local value = group and group[name]
    if type(value) ~= "number" then return default end
    return value
end

local function keepAwayDistance()
    return option("KeepAwayDistance", 250)
end

local function farMinDistance()
    return math.max(option("FarMinDistance", 400), keepAwayDistance() + 100)
end

local function farMaxDistance()
    return math.max(farMinDistance(), option("FarMaxDistance", 900))
end

local function encounterGap()
    local minDays = option("EncounterMinDays", 1.8)
    local maxDays = math.max(minDays, option("EncounterMaxDays", 3))
    return ZombRandFloat(minDays, maxDays)
end

local function timers()
    local data = ModData.getOrCreate("BanditsLargeMaps")
    data.timers = data.timers or {}
    return data.timers
end

-- Bandits ignores admins in ghost mode, groups sent to them would wait forever
local function isGhost(player)
    if not GetBanditModDataPlayers or not BanditUtils or not BanditUtils.GetCharacterID then return false end
    local gmd = GetBanditModDataPlayers()
    local online = gmd and gmd.OnlinePlayers
    local entry = online and online[BanditUtils.GetCharacterID(player)]
    return entry and entry.isGhost or false
end

local function getPlayers()
    local list
    if isServer() then
        list = getOnlinePlayers()
    else
        list = IsoPlayer.getPlayers()
    end
    local players = {}
    if not list then return players end
    for i = 0, list:size() - 1 do
        local player = list:get(i)
        if player and not player:isDead() and not isGhost(player) then
            local key
            if isServer() then
                key = player:getUsername()
            else
                key = "local" .. player:getPlayerNum()
            end
            players[#players + 1] = { key = key, x = player:getX(), y = player:getY() }
        end
    end
    return players
end

local function distance2(ax, ay, bx, by)
    local dx, dy = ax - bx, ay - by
    return dx * dx + dy * dy
end

local function nearAny(x, y, players, distance)
    local limit = distance * distance
    for _, player in ipairs(players) do
        if distance2(x, y, player.x, player.y) <= limit then return true end
    end
    return false
end

local function nearest(x, y, players)
    local best, bestDistance2
    for _, player in ipairs(players) do
        local d2 = distance2(x, y, player.x, player.y)
        if not bestDistance2 or d2 < bestDistance2 then
            best, bestDistance2 = player, d2
        end
    end
    return best, bestDistance2 and math.sqrt(bestDistance2)
end

local function choice(list)
    return list[ZombRand(#list) + 1]
end

-- Players within AreaDistance of each other, also through other players,
-- share an area. Every player gets an `area` field.
local function buildAreas(players)
    local limit = option("AreaDistance", 300)
    limit = limit * limit
    local areas = {}
    for _, player in ipairs(players) do
        if not player.area then
            local area = { player }
            player.area = area
            local k = 1
            while k <= #area do
                local member = area[k]
                for _, other in ipairs(players) do
                    if not other.area and distance2(member.x, member.y, other.x, other.y) <= limit then
                        other.area = area
                        area[#area + 1] = other
                    end
                end
                k = k + 1
            end
            areas[#areas + 1] = area
        end
    end
    return areas
end

local function pointAround(origin, minDistance, maxDistance)
    local angle = ZombRandFloat(0, 2 * math.pi)
    local distance = ZombRandFloat(minDistance, maxDistance)
    return math.max(0, math.floor(origin.x + math.cos(angle) * distance)),
        math.max(0, math.floor(origin.y + math.sin(angle) * distance))
end

-- Far points are where groups start and roam, Bandits only starts groups at
-- destinations more than 150 tiles away from every player. They are kept away
-- from every player, not only the one they were made for.
local function buildDestinations(players)
    local farMin, farMax = farMinDistance(), farMaxDistance()
    local points = {}
    for p, origin in ipairs(players) do
        local count = option("FarPoints", 4)
        local made = 0
        for _ = 1, count * 4 do
            if made >= count then break end
            local x, y = pointAround(origin, farMin, farMax)
            if not nearAny(x, y, players, farMin) then
                made = made + 1
                points[#points + 1] = { name = "Large maps far " .. p .. "." .. made, x = x, y = y, z = 0 }
            end
        end
    end
    return points
end

local function isAutomatic(group)
    -- groups placed by hand (marked false by YANMC) keep their route
    return group._yanmcAutomaticAmbientPopulation ~= false
        and type(group.x) == "number" and type(group.y) == "number"
end

local function moveToFarPoint(group)
    local start = choice(far)
    group.x, group.y, group.z = start.x, start.y, 0
    group.destination = choice(far)
end

-- a side of the player where the waiting point is on loaded land
local function bearingFor(player, distance)
    local cell = getCell()
    for _ = 1, 8 do
        local angle = ZombRandFloat(0, 2 * math.pi)
        local square = cell and cell:getGridSquare(math.floor(player.x + math.cos(angle) * distance),
            math.floor(player.y + math.sin(angle) * distance), 0)
        if square and not square:isWaterSquare() then return angle end
    end
    return ZombRandFloat(0, 2 * math.pi)
end

local function placeForApproach(group, player, players)
    local angle
    for _ = 1, 8 do
        angle = bearingFor(player, APPROACH_DISTANCE)
        local x = player.x + math.cos(angle) * DISPATCH_DISTANCE
        local y = player.y + math.sin(angle) * DISPATCH_DISTANCE
        if not nearAny(x, y, players, DISPATCH_DISTANCE - 50) then break end
    end
    group.x = math.max(0, player.x + math.cos(angle) * DISPATCH_DISTANCE)
    group.y = math.max(0, player.y + math.sin(angle) * DISPATCH_DISTANCE)
    group.z = 0
    group._blmBearing = angle
    group._blmApproach = APPROACH_DISTANCE
    group._blmWaiting = 0
end

-- Groups that are gone or smaller than a minute ago, while alive and close to
-- a player, turned into NPCs (YANMC can do that in several steps). The area
-- of that player starts waiting for its next group.
local function detectEncounters(wanderers, players, waits)
    local current = {}
    -- a group that wins a fight also shrinks, its dead are added as a new group
    local fought = {}
    for _, group in ipairs(wanderers) do
        current[group] = true
        if not previous[group] and not group.alive and group.cid then fought[group.cid] = true end
    end
    for group, last in pairs(previous) do
        if last.alive and not last.met then
            local gone = not current[group]
            local shrunk = not gone and group.alive and type(group.size) == "number" and group.size < last.size
                and not fought[group.cid]
            if gone or shrunk then
                local player, distance = nearest(last.x, last.y, players)
                if player and distance <= MET_DISTANCE then
                    local gap = encounterGap()
                    for _, member in ipairs(player.area) do waits[member.key] = gap end
                    group._blmMet = true
                end
            end
        end
    end
    previous = {}
    for _, group in ipairs(wanderers) do
        previous[group] = {
            x = group.x, y = group.y, alive = group.alive, met = group._blmMet,
            size = type(group.size) == "number" and group.size or 0,
        }
    end
end

local function steer(group, players)
    local player, distance = nearest(group.x, group.y, players)
    if distance > LEASH_DISTANCE then
        placeForApproach(group, player, players)
        player, distance = nearest(group.x, group.y, players)
    end
    local angle = group._blmBearing or bearingFor(player, APPROACH_DISTANCE)
    local approach = group._blmApproach or APPROACH_DISTANCE
    local x, y = player.x + math.cos(angle) * approach, player.y + math.sin(angle) * approach
    if distance2(group.x, group.y, x, y) <= 25 then
        group._blmWaiting = (group._blmWaiting or 0) + 1
        if group._blmWaiting >= STUCK_MINUTES then
            approach = approach - 12
            if approach < MIN_APPROACH_DISTANCE then approach = APPROACH_DISTANCE end
            angle = bearingFor(player, approach)
            group._blmWaiting = 0
            x, y = player.x + math.cos(angle) * approach, player.y + math.sin(angle) * approach
        end
    end
    group._blmBearing, group._blmApproach = angle, approach
    group.destination = { name = "Large maps encounter", x = math.max(0, x), y = math.max(0, y), z = 0 }
end

local function replaceDestinations(points)
    -- replaced in place, Bandits keeps references to this table
    local destinations = BanditServer.Wanderers.destinations
    for i = #destinations, 1, -1 do destinations[i] = nil end
    for i, destination in ipairs(points) do destinations[i] = destination end
end

-- Bandits starts new groups at far points, and they would fight sent groups
-- close by before they can be moved away
local function publishFarPoints(wanderers)
    local guarded = {}
    for _, group in ipairs(wanderers) do
        if group._blmDispatched and group.alive then guarded[#guarded + 1] = group end
    end
    local usable = {}
    for _, point in ipairs(allFar) do
        if not nearAny(point.x, point.y, guarded, GUARD_DISTANCE) then usable[#usable + 1] = point end
    end
    if #usable == 0 then usable = allFar end
    far = usable
    replaceDestinations(far)
end

local function update(players, refreshNow)
    local gmd = GetBanditModData and GetBanditModData()
    local wanderers = gmd and gmd.Wanderers
    if not wanderers then return false end

    local waits = timers()
    local areas = buildAreas(players)
    for _, player in ipairs(players) do
        if waits[player.key] == nil then waits[player.key] = encounterGap() end
        waits[player.key] = waits[player.key] - 1 / 1440
    end

    detectEncounters(wanderers, players, waits)
    publishFarPoints(wanderers)

    local keepAway = keepAwayDistance()
    local recycle = option("RecycleDistance", 3000)
    local destinationRange = farMaxDistance() + 100
    local sent = {}
    local idle = {}
    local guarded = {}
    for _, group in ipairs(wanderers) do
        if group._blmDispatched and not group.alive then group._blmDispatched = nil end
        if group._blmDispatched then guarded[#guarded + 1] = group end
    end
    for _, group in ipairs(wanderers) do
        if not group.alive then
            -- dead groups turn into bodies near players, keep them away as well
            if #far > 0 and isAutomatic(group) and nearAny(group.x, group.y, players, keepAway) then
                local spot = choice(far)
                group.x, group.y = spot.x, spot.y
            end
        elseif isAutomatic(group) then
            if group._blmDispatched and group._blmMet then
                -- YANMC turns groups into NPCs bit by bit, give the rest some
                -- time before sending it away
                group._blmMetMinutes = (group._blmMetMinutes or 0) + 1
                if group._blmMetMinutes > STUCK_MINUTES then group._blmDispatched = nil end
            end
            if group._blmDispatched then
                steer(group, players)
                local player = nearest(group.x, group.y, players)
                sent[player.area] = true
            elseif #far > 0 then
                if nearAny(group.x, group.y, players, keepAway)
                    or nearAny(group.x, group.y, guarded, GUARD_DISTANCE)
                    or (refreshNow and not nearAny(group.x, group.y, players, recycle)) then
                    moveToFarPoint(group)
                elseif refreshNow then
                    local destination = group.destination
                    if type(destination) ~= "table" or type(destination.x) ~= "number"
                        or type(destination.y) ~= "number"
                        or not nearAny(destination.x, destination.y, players, destinationRange)
                        or nearAny(destination.x, destination.y, players, keepAway) then
                        group.destination = choice(far)
                    end
                end
                if not group._blmMet then idle[#idle + 1] = group end
            end
        end
    end

    -- an area is due once every player in it waited long enough
    for _, area in ipairs(areas) do
        if not sent[area] and #idle > 0 then
            local due = true
            for _, member in ipairs(area) do
                if waits[member.key] > 0 then due = false break end
            end
            if due then
                local index = ZombRand(#idle) + 1
                local group = table.remove(idle, index)
                group._blmDispatched = true
                placeForApproach(group, choice(area), players)
                steer(group, players)
                sent[area] = true
                for _, other in ipairs(wanderers) do
                    if other ~= group and other.alive and not other._blmDispatched and isAutomatic(other)
                        and nearAny(other.x, other.y, { group }, GUARD_DISTANCE) then
                        moveToFarPoint(other)
                    end
                end
            end
        end
    end
    publishFarPoints(wanderers)
    return true
end

local function everyOneMinute()
    local wanderers = BanditServer and BanditServer.Wanderers
    if not wanderers or type(wanderers.destinations) ~= "table" then return end

    local players = getPlayers()
    if #players == 0 then return end

    minutesSinceRefresh = minutesSinceRefresh + 1
    local refreshNow = minutesSinceRefresh >= REFRESH_MINUTES
    if refreshNow then
        local points = buildDestinations(players)
        if #points > 0 then
            allFar, far = points, points
            replaceDestinations(points)
            minutesSinceRefresh = 0
        end
    end

    if update(players, refreshNow) and TransmitBanditModData then
        TransmitBanditModData()
    end
end

Events.EveryOneMinute.Add(everyOneMinute)
