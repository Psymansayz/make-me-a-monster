-- The animations the plugin lists: those in src/data/animation_whitelist.lua (for NPC heads) and
-- src/data/player_head_animations.lua (for the player's own head), each with the label src/data/animation_labels.lua
-- gives it. Nothing is looked up in the game and no animation name is read.

local Whitelist = require("src/data/animation_whitelist")
local PlayerAnims = require("src/data/player_head_animations")
local Labels = require("src/data/animation_labels")

local Anims = {}

-- { id, label, own }, own being true for the player's head animations.
Anims.list = {}
local byID = {}

local function add(ids, own)
    for _, animID in ipairs(ids or {}) do
        local anim = { id = animID, label = Labels[animID] or tostring(animID), own = own }
        Anims.list[#Anims.list + 1] = anim
        byID[animID] = anim
    end
end
add(Whitelist.ids, false)
add(PlayerAnims.actors, true)

-- The listed animation with this id, or nil.
function Anims.find(animID)
    return byID[animID]
end

-- The label of the animation with this id, or nil if it isn't listed.
function Anims.displayName(animID)
    local anim = byID[animID]
    return anim and anim.label or nil
end

-- The animations for the player's head if `own`, else those for NPC heads: { id, label }, in label order.
function Anims.options(own)
    local found = {}
    for _, anim in ipairs(Anims.list) do
        if anim.own == own then found[#found + 1] = anim end
    end
    table.sort(found, function(a, b)
        if a.label ~= b.label then return a.label < b.label end
        return a.id < b.id
    end)
    return found
end

return Anims
