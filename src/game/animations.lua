-- The animations the plugin lists, from src/data/animation_list.lua (already in the dropdown's order), their names
-- turned into this game build's ids once, at load. An animation the game does not know by its name is left out.

local AnimationList = require("src/data/animation_list")
local GameIds = require("src/game/game_ids")

local Animations = {}

local function seqID(name)
    return GameIds.resolve("Seq", name)
end

-- The listed animations as { id, label }: for NPC heads and for the player's own head.
local optionsFor = { npc = {}, player = {} }

-- animation id -> { listing = the entry { id, label }, isPlayerAnimation = whether it is one for the player's own head }
local listedAnimationByID = {}
for _, listKind in ipairs({ "npc", "player" }) do
    for _, entry in ipairs(AnimationList[listKind]) do
        local animationID = seqID(entry.name)
        if animationID ~= nil then
            local listing = { id = animationID, label = entry.label }
            optionsFor[listKind][#optionsFor[listKind] + 1] = listing
            listedAnimationByID[animationID] = { listing = listing, isPlayerAnimation = listKind == "player" }
        end
    end
end

-- How the two kinds of animation go with each other (see src/data/animation_list.lua), as ids.
local function idPairs(namePairs)
    local idTable = {}
    for fromName, toName in pairs(namePairs) do
        local fromID, toID = seqID(fromName), seqID(toName)
        if fromID ~= nil and toID ~= nil then idTable[fromID] = toID end
    end
    return idTable
end
Animations.twin = idPairs(AnimationList.twin)
Animations.alsoFor = idPairs(AnimationList.alsoFor)
Animations.neutral = seqID(AnimationList.neutral)
Animations.fallback = seqID(AnimationList.fallback)
Animations.npcFallback = seqID(AnimationList.npcFallback)

-- The NPC heads built on the player's rig: { [npc id] = true }.
Animations.headsOnPlayerRig = {}
for _, npcName in ipairs(AnimationList.headsOnPlayerRig) do
    local npcID = GameIds.resolve("NPC", npcName)
    if npcID ~= nil then Animations.headsOnPlayerRig[npcID] = true end
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
    return Animations.headsOnPlayerRig[npcID] == true
end

-- The animations for the player's own head if `forPlayerHead`, else those for NPC heads: { id, label }, in the order
-- shown.
function Animations.options(forPlayerHead)
    return forPlayerHead and optionsFor.player or optionsFor.npc
end

-- The name of a listed animation (to save a choice by), or nil.
function Animations.nameOf(animationID)
    return GameIds.nameOf("Seq", animationID)
end

-- The id of the listed animation with this name (a saved choice), or nil.
function Animations.idOf(name)
    local animationID = seqID(name)
    return Animations.isListed(animationID) and animationID or nil
end

return Animations
