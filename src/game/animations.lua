-- The animations the plugin lists, from src/data/animation_list.lua (already in the dropdown's order). Nothing is looked
-- up in the game and no animation name is read.

local AnimationList = require("src/data/animation_list")

local Animations = {}

-- animation id -> { listing = the entry { id, label }, isPlayerAnimation = whether it is one for the player's own head }
local listedAnimationByID = {}
for _, isPlayerList in ipairs({ false, true }) do
    for _, listing in ipairs(isPlayerList and AnimationList.player or AnimationList.npc) do
        listedAnimationByID[listing.id] = { listing = listing, isPlayerAnimation = isPlayerList }
    end
end

-- Whether the animation with this id is listed.
function Animations.isListed(animationID)
    return listedAnimationByID[animationID] ~= nil
end

-- The label of the animation with this id, or nil if it isn't listed.
function Animations.labelOf(animationID)
    local listed = listedAnimationByID[animationID]
    return listed and listed.listing.label or nil
end

-- Whether the animation with this id is one for the player's own head.
function Animations.isPlayerAnimation(animationID)
    local listed = listedAnimationByID[animationID]
    return listed ~= nil and listed.isPlayerAnimation
end

-- Whether the NPC head with this id plays the player's animations (it is built on the player's rig).
function Animations.isOnPlayerRig(npcID)
    return AnimationList.headsOnPlayerRig[npcID] == true
end

-- The animations for the player's own head if `forPlayerHead`, else those for NPC heads: { id, label }, in the order
-- shown.
function Animations.options(forPlayerHead)
    return forPlayerHead and AnimationList.player or AnimationList.npc
end

return Animations
