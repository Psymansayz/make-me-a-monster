-- The animations the plugin lists, from src/data/animation_list.lua, their names turned into this build's ids once,
-- at load.

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

function Animations.isListed(animationID)
    return listedAnimationByID[animationID] ~= nil
end

function Animations.labelOf(animationID)
    local listed = listedAnimationByID[animationID]
    return listed and listed.listing.label or nil
end

function Animations.isPlayerAnimation(animationID)
    local listed = listedAnimationByID[animationID]
    return listed ~= nil and listed.isPlayerAnimation
end

-- Whether the NPC head with this id plays the player's animations (it is built on the player's rig).
function Animations.isOnPlayerRig(npcID)
    return Animations.headsOnPlayerRig[npcID] == true
end

-- { id, label } in the dropdown's order, for the player's own head or for NPC heads.
function Animations.options(forPlayerHead)
    return forPlayerHead and optionsFor.player or optionsFor.npc
end

function Animations.nameOf(animationID)
    return GameIds.nameOf("Seq", animationID)
end

function Animations.idOf(name)
    local animationID = seqID(name)
    return Animations.isListed(animationID) and animationID or nil
end

return Animations
