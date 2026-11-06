-- Some heads need custom sizes. Currently only used to reduce the size of too-large heads, though
-- in the future it could be used to enlarge too-small heads too. The sizes are multipliers of the normal size.

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
