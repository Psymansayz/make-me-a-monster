-- The animations the plugin lists, from src/data/animation_list.lua, their names turned into this build's ids once,
-- at load.

local AnimationList = require("src/data/animation_list")
local DedicatedAnimations = require("src/data/dedicated_animations")
local GameIds = require("src/game/game_ids")

local Animations = {}

local function seqID(name)
    return GameIds.resolve("Seq", name)
end

-- The listed animations as { id, label, isPlayerAnimation }: for NPC heads and for the player's own head.
local optionsFor = { npc = {}, player = {} }

local listingByID = {} -- animation id -> its listing
for _, listKind in ipairs({ "npc", "player" }) do
    for _, entry in ipairs(AnimationList[listKind]) do
        local animationID = seqID(entry.name)
        if animationID ~= nil then
            local listing = { id = animationID, label = entry.label, isPlayerAnimation = listKind == "player" }
            optionsFor[listKind][#optionsFor[listKind] + 1] = listing
            listingByID[animationID] = listing
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

-- The races and characters with animations of their own (src/data/dedicated_animations.lua), which their heads play
-- in place of the human ones: { name, options, default, fromHuman = { human id -> own id }, toHuman = { own id ->
-- human id }, alsoHuman }. options are listings, as for the human animations.
local setOfHead, setOfAnimation = {}, {}
for _, savedSet in ipairs(DedicatedAnimations) do
    local animationSet = { name = savedSet.name, options = {}, fromHuman = {}, toHuman = {},
        default = seqID(savedSet.default), alsoHuman = savedSet.alsoHuman == true }
    for _, entry in ipairs(savedSet.animations) do
        local animationID = seqID(entry[1])
        if animationID ~= nil then
            local listing = { id = animationID, label = entry[2], isPlayerAnimation = false }
            animationSet.options[#animationSet.options + 1] = listing
            listingByID[animationID], setOfAnimation[animationID] = listing, animationSet
            animationSet.toHuman[animationID] = entry[3] and seqID(entry[3])
        end
    end
    for _, pair in ipairs(savedSet.fromHuman) do
        local humanID, ownID = seqID(pair[1]), seqID(pair[2])
        if humanID ~= nil and ownID ~= nil then animationSet.fromHuman[humanID] = ownID end
    end
    -- The other lengths of a listed animation: not listed, but the set's own (as the game may play them).
    for _, pair in ipairs(savedSet.sameAs or {}) do
        local variantID, listedID = seqID(pair[1]), seqID(pair[2])
        if variantID ~= nil and setOfAnimation[listedID] == animationSet then
            setOfAnimation[variantID], animationSet.toHuman[variantID] = animationSet, animationSet.toHuman[listedID]
        end
    end
    -- With the human animations too, they follow its own in the dropdown.
    if animationSet.alsoHuman then
        for _, listing in ipairs(optionsFor.npc) do animationSet.options[#animationSet.options + 1] = listing end
    end
    if animationSet.default ~= nil then
        for _, npcName in ipairs(savedSet.heads) do
            local npcID = GameIds.resolve("NPC", npcName)
            if npcID ~= nil and setOfHead[npcID] == nil then setOfHead[npcID] = animationSet end
        end
    end
end

-- The set of animations of its own the NPC head with this id plays, or nil (it plays the human ones).
function Animations.setOfHead(npcID)
    return npcID and setOfHead[npcID]
end

-- The set an animation of its own belongs to, or nil (a human animation).
function Animations.setOf(animationID)
    return animationID and setOfAnimation[animationID]
end

function Animations.isListed(animationID)
    return listingByID[animationID] ~= nil
end

function Animations.labelOf(animationID)
    local listing = listingByID[animationID]
    return listing and listing.label or nil
end

function Animations.isPlayerAnimation(animationID)
    local listing = listingByID[animationID]
    return listing ~= nil and listing.isPlayerAnimation
end

-- Whether the NPC head with this id plays the player's animations (it is built on the player's rig).
function Animations.isOnPlayerRig(npcID)
    return Animations.headsOnPlayerRig[npcID] ~= nil
end

-- { id, label } in the dropdown's order: for the player's own head, for NPC heads, or for the heads of a set.
function Animations.options(forPlayerHead, headSet)
    if headSet ~= nil then return headSet.options end
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
