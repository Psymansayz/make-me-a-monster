-- Heads drawn at a size of their own, in the dialogue boxes and the windows: a head whose model fills more of the
-- space than other heads do looks far larger than they do at the same camera distance.
-- HeadSizes.of(npcID) -> how many times the size set by the player to draw this head (1 for most).

local GameIds = require("src/game/game_ids")

local HeadSizes = {}

-- { name in the game (id.NPC) = size }.
local SIZE_OF_NPC = {
    MYARM_MAN_IN_POT = 0.5, -- (Adventurer: a man in a pot)
}

local sizeOfID = {}
for npcName, size in pairs(SIZE_OF_NPC) do
    local npcID = GameIds.resolve("NPC", npcName)
    if npcID ~= nil then sizeOfID[npcID] = size end
end

function HeadSizes.of(npcID)
    return sizeOfID[npcID] or 1
end

return HeadSizes
