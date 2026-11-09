-- The ids of the game's configs (animations, NPCs, interfaces, components, variables) from their names in the game
-- (id.Seq, id.NPC, id.Interface, id.Component, var.VarPlayer). Ids can differ between game builds and between the dev
-- worlds and the live game; the names do not, so the plugin holds names and turns them into ids here, once, at load.

local GameIds = {}

GameIds.unresolved = {} -- "<kind>.<name>" for every name the game did not know

-- An unknown name reads as -1 in the game's table.
function GameIds.resolve(kind, name)
    local configID = id[kind][name]
    if configID >= 0 then return configID end
    GameIds.unresolved[#GameIds.unresolved + 1] = kind .. "." .. name
    return nil
end

function GameIds.playerVariable(name)
    local variable = var.VarPlayer[name]
    if variable == nil then
        GameIds.unresolved[#GameIds.unresolved + 1] = "VarPlayer." .. name
        return nil
    end
    return variable.id
end

-- The name in the game of a config resolved by GameIds.resolve.
function GameIds.nameOf(kind, configID)
    return id[kind].FromID(configID)
end

return GameIds
