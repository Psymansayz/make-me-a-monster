-- The animations the plugin lists: those in src/data/animation_whitelist.lua (for NPC heads) and
-- src/data/player_head_animations.lua (for the player's own head), each with the label src/data/animation_labels.lua
-- gives it. Nothing is looked up in the game and no animation name is read.

local Whitelist = require("src/data/animation_whitelist")
local PlayerAnims = require("src/data/player_head_animations")
local Labels = require("src/data/animation_labels")

local Anims = {}

-- Whether the animation with this id is listed.
function Anims.find(animID)
    return Labels[animID] ~= nil
end

-- The label of the animation with this id, or nil if it isn't listed.
function Anims.displayName(animID)
    return Labels[animID]
end

-- The animations for the player's head if `own`, else those for NPC heads: { id, label }, in label order.
function Anims.options(own)
    local found = {}
    for _, animID in ipairs(own and PlayerAnims.actors or Whitelist.ids) do
        found[#found + 1] = { id = animID, label = Labels[animID] }
    end
    table.sort(found, function(a, b)
        if a.label ~= b.label then return a.label < b.label end
        return a.id < b.id
    end)
    return found
end

return Anims
