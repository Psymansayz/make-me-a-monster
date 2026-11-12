-- Ids can differ between game builds and between the dev worlds and the live game, but names don't. So the plugin uses
-- the game's config names (id.Seq, id.NPC, id.Interface, id.Component, var.VarPlayer) and turns them into ids here.

local GameIds = {}

-- A "<kind>.<name>" entry for each name the game didn't know. It is only filled in if it was set to a list before any
-- lookup, which the dev branch does for its reports.
GameIds.unresolved = nil

local function noteUnresolved(text)
    if GameIds.unresolved ~= nil then GameIds.unresolved[#GameIds.unresolved + 1] = text end
end

-- The game's table gives -1 for an unknown name.
function GameIds.resolve(kind, name)
    local configID = id[kind][name]
    if configID >= 0 then return configID end
    noteUnresolved(kind .. "." .. name)
    return nil
end

function GameIds.playerVariable(name)
    local variable = var.VarPlayer[name]
    if variable == nil then
        noteUnresolved("VarPlayer." .. name)
        return nil
    end
    return variable.id
end

function GameIds.nameOf(kind, configID)
    return id[kind].FromID(configID)
end

return GameIds
