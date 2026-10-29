-- The animations the plugin lists, from src/data/animations.lua (already in the dropdown's order). Nothing is looked
-- up in the game and no animation name is read.

local Data = require("src/data/animations")

local Anims = {}

local byID = {} -- id -> the entry { id, label } and whether it is one for the player's own head
for _, player in ipairs({ false, true }) do
    for _, entry in ipairs(player and Data.player or Data.npc) do byID[entry.id] = { entry = entry, player = player } end
end

-- Whether the animation with this id is listed.
function Anims.find(animID)
    return byID[animID] ~= nil
end

-- The label of the animation with this id, or nil if it isn't listed.
function Anims.displayName(animID)
    local found = byID[animID]
    return found and found.entry.label or nil
end

-- Whether the animation with this id is one for the player's own head.
function Anims.isPlayer(animID)
    local found = byID[animID]
    return found ~= nil and found.player
end

-- The animations for the player's own head if `player`, else those for NPC heads: { id, label }, in the order shown.
function Anims.options(player)
    return player and Data.player or Data.npc
end

return Anims
