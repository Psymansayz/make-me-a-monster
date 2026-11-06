-- The ids of the game's configs (animations, NPCs, interfaces, components, variables) from their names in the game
-- (id.Seq, id.NPC, id.Interface, id.Component, var.VarPlayer). Ids can differ between game builds and between the dev
-- worlds and the live game; the names do not, so the plugin holds names and turns them into ids here, once, at load.

local GameIds = {}

GameIds.unresolved = {} -- "<kind>.<name>" for every name the game did not know

local idByName, nameByID = {}, {} -- kind -> name -> id, kind -> id -> name

local function lookUp(kind, name)
    return id[kind][name]
end

function GameIds.resolve(kind, name)
    local known = idByName[kind]
    if known == nil then
        known = {}
        idByName[kind], nameByID[kind] = known, {}
    end
    local configID = known[name]
    if configID ~= nil then return configID end
    -- (the game's id table, outside the plugin: an unknown name reads as -1)
    local found, value = pcall(lookUp, kind, name)
    if not found or value == nil or value < 0 then
        GameIds.unresolved[#GameIds.unresolved + 1] = kind .. "." .. name
        return nil
    end
    known[name], nameByID[kind][value] = value, name
    return value
end

function GameIds.playerVariable(name)
    local variable = var.VarPlayer[name]
    if variable == nil then
        GameIds.unresolved[#GameIds.unresolved + 1] = "VarPlayer." .. name
        return nil
    end
    return variable.id
end

-- The name of a config previously resolved by GameIds.resolve
function GameIds.nameOf(kind, configID)
    return nameByID[kind] and nameByID[kind][configID]
end

return GameIds
