-- Scales the spawn chance of the regular Bandits clans (assault, defenders,
-- campers, roadblocks, companions), leaving wanderer clans to the wanderer
-- script. The Bandits group size multiplier would also shrink the groups.
--
-- Only the spawn schedulers of Bandits and YANMC read clans through
-- ClanGetAll, the clan editor uses ClanGet and ClanGetAllSorted. The clan
-- data itself is never changed, so it can't be saved to clans.txt scaled.

if isClient() then return end
if not BanditCustom or type(BanditCustom.ClanGetAll) ~= "function" then return end

local function scale()
    local group = SandboxVars and SandboxVars.BanditsLargeMaps
    local value = group and group.RegularSpawnChance
    if type(value) ~= "number" then return 1 end
    return math.max(0, value) / 100
end

local function copy(source)
    local result = {}
    for key, value in pairs(source) do result[key] = value end
    return result
end

-- kept across Lua reloads, so the wrapper never wraps itself
BanditCustom._banditsLargeMapsClanGetAll = BanditCustom._banditsLargeMapsClanGetAll or BanditCustom.ClanGetAll
local upstream = BanditCustom._banditsLargeMapsClanGetAll

BanditCustom.ClanGetAll = function(...)
    local clans = upstream(...)
    local factor = scale()
    if factor == 1 or type(clans) ~= "table" then return clans end
    local view = {}
    for cid, clan in pairs(clans) do
        local spawn = type(clan) == "table" and clan.spawn
        local chance = type(spawn) == "table" and tonumber(spawn.spawnChance)
        if chance and spawn.wanderer ~= true and spawn.wanderer ~= "true" then
            local scaled = copy(clan)
            scaled.spawn = copy(spawn)
            scaled.spawn.spawnChance = chance * factor
            view[cid] = scaled
        else
            view[cid] = clan
        end
    end
    return view
end
