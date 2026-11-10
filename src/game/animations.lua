-- The animations the plugin lists (src/data/animation_list.lua) and the sets of races' own
-- (src/data/dedicated_animations.lua), their names turned into this build's ids once, at load.

local AnimationList = require("src/data/animation_list")
local DedicatedAnimations = require("src/data/dedicated_animations")
local GameIds = require("src/game/game_ids")

local Animations = {}

-- The sets name the same human animations hundreds of times: each name is looked up (and reported unknown) once,
-- while loading.
local idOfName = {}
local function seqID(name)
    if name == nil then return nil end
    if idOfName[name] == nil then idOfName[name] = GameIds.resolve("Seq", name) or false end
    return idOfName[name] or nil
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
-- An NPC head animation's player version, and the other way round (one several twins name is settled by alsoFor).
local playerTwin = idPairs(AnimationList.twin)
local npcTwin = {}
for npcAnimation, playerAnimation in pairs(playerTwin) do npcTwin[playerAnimation] = npcAnimation end
for playerAnimation, npcAnimation in pairs(idPairs(AnimationList.alsoFor)) do
    npcTwin[playerAnimation] = npcAnimation
end
Animations.neutral = seqID(AnimationList.neutral)
Animations.fallback = seqID(AnimationList.fallback)
Animations.npcFallback = seqID(AnimationList.npcFallback)

-- The NPC heads built on the player's rig: { [npc id] = true }.
Animations.headsOnPlayerRig = {}
for _, npcName in ipairs(AnimationList.headsOnPlayerRig) do
    local npcID = GameIds.resolve("NPC", npcName)
    if npcID ~= nil then Animations.headsOnPlayerRig[npcID] = true end
end

-- The sets of animations of their own that heads play in place of the human ones (alsoHuman: as well as them):
-- { options (listings), default, fromHuman = { human id -> own id }, toHuman = { own id -> human id }, alsoHuman }.
local setOfHead, setOfAnimation = {}, {}
for _, savedSet in ipairs(DedicatedAnimations) do
    local animationSet = { options = {}, fromHuman = {}, toHuman = {}, default = seqID(savedSet.default),
        alsoHuman = savedSet.alsoHuman }
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
    -- The other lengths of a listed animation: not listed, but the set's own, as the game may play them.
    for _, pair in ipairs(savedSet.sameAs or {}) do
        local variantID, listedID = seqID(pair[1]), seqID(pair[2])
        if variantID ~= nil and setOfAnimation[listedID] == animationSet then
            setOfAnimation[variantID], animationSet.toHuman[variantID] = animationSet, animationSet.toHuman[listedID]
        end
    end
    -- The human animations follow the set's own in the dropdown.
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

-- The set the NPC head with this id plays, or nil (it plays the human animations).
function Animations.setOfHead(npcID)
    return setOfHead[npcID]
end

-- The set an animation belongs to, or nil (a human animation).
function Animations.setOf(animationID)
    return setOfAnimation[animationID]
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

-- The listings in the dropdown's order: for the player's own head, for NPC heads, or for the heads of a set.
function Animations.options(forPlayerHead, headSet)
    if headSet ~= nil then return headSet.options end
    return forPlayerHead and optionsFor.player or optionsFor.npc
end

-- The player's version of an NPC head animation, or nil.
function Animations.playerTwinOf(npcAnimationID)
    return playerTwin[npcAnimationID]
end

-- The NPC head version of a player animation, or nil.
function Animations.npcTwinOf(playerAnimationID)
    return npcTwin[playerAnimationID]
end

function Animations.nameOf(animationID)
    return GameIds.nameOf("Seq", animationID)
end

function Animations.idOf(name)
    local animationID = GameIds.resolve("Seq", name)
    return Animations.isListed(animationID) and animationID or nil
end

idOfName = nil -- (the loading's cache, no longer needed)

return Animations
