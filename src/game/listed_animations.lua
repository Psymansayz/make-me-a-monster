-- The animations the plugin lists, from src/data/animations.lua (already in the dropdown's order). Nothing is looked
-- up in the game and no animation name is read.

local AnimationData = require("src/data/animations")

local ListedAnimations = {}

-- animation id -> { listing = the entry { id, label }, isPlayerAnimation = whether it is one for the player's own head }
local listedAnimationByID = {}
for _, isPlayerList in ipairs({ false, true }) do
    for _, listing in ipairs(isPlayerList and AnimationData.player or AnimationData.npc) do
        listedAnimationByID[listing.id] = { listing = listing, isPlayerAnimation = isPlayerList }
    end
end

-- Whether the animation with this id is listed.
function ListedAnimations.isListed(animationID)
    return listedAnimationByID[animationID] ~= nil
end

-- The label of the animation with this id, or nil if it isn't listed.
function ListedAnimations.labelOf(animationID)
    local listed = listedAnimationByID[animationID]
    return listed and listed.listing.label or nil
end

-- Whether the animation with this id is one for the player's own head.
function ListedAnimations.isPlayerAnimation(animationID)
    local listed = listedAnimationByID[animationID]
    return listed ~= nil and listed.isPlayerAnimation
end

-- The animations for the player's own head if `forPlayerHead`, else those for NPC heads: { id, label }, in the order
-- shown.
function ListedAnimations.options(forPlayerHead)
    return forPlayerHead and AnimationData.player or AnimationData.npc
end

return ListedAnimations
