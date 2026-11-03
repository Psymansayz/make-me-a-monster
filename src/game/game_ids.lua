-- The ids of the game's configs (animations, NPCs) from their names in the game (id.Seq, id.NPC). Ids can differ
-- between game builds and between the dev worlds and the live game; the names do not, so the plugin's data holds
-- names and turns them into ids here, once, when the data is loaded.

local GameIds = {}

GameIds.unresolved = {} -- "<kind>.<name>" for every name the game did not know (shown on the dev branch)

local idByName, nameByID = {}, {} -- kind -> name -> id, kind -> id -> name

local function lookUp(kind, name)
    return id[kind][name]
end

-- The id of the config of this kind ("Seq" or "NPC") with this name, or nil if this game build has none by that name
-- (renamed or removed: the entry is left out).
function GameIds.resolve(kind, name)
    local known = idByName[kind]
    if known == nil then
        known = {}
        idByName[kind], nameByID[kind] = known, {}
    end
    local configID = known[name]
    if configID ~= nil then return configID end
    -- (the game's id table, outside the plugin: an unknown name reads as -1, in the dev client of 2026-11-03)
    local found, value = pcall(lookUp, kind, name)
    if not found or value == nil or value < 0 then
        GameIds.unresolved[#GameIds.unresolved + 1] = kind .. "." .. name
        return nil
    end
    known[name], nameByID[kind][value] = value, name
    return value
end

-- The name of a config resolved before (by GameIds.resolve), or nil.
function GameIds.nameOf(kind, configID)
    return nameByID[kind] and nameByID[kind][configID]
end

return GameIds
