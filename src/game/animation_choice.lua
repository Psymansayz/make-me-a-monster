-- Which animation each kind of head plays for the chosen animation: the player's own head, old NPC heads, the newer
-- heads on the player's rig, and the heads of a set that has its own animations.

local Animations = require("src/game/animations")
local Settings = require("src/data/settings")

local AnimationChoice = {}

local npcVersionOfGameAnimation = nil

function AnimationChoice.noteGameAnimation(playerAnimationID)
    npcVersionOfGameAnimation = Animations.npcTwinOf(playerAnimationID)
end

-- Records what the NPC heads play, for use while nothing is chosen.
function AnimationChoice.noteNpcAnimation(animationID)
    Settings.lastSeenNpcAnimationID = animationID
end

function AnimationChoice.forgetGameAnimation()
    npcVersionOfGameAnimation = nil
end

function AnimationChoice.playerAnimationsInUse()
    return Settings.chosenNpcID == nil or Animations.isOnPlayerRig(Settings.chosenNpcID)
end

function AnimationChoice.setInUse()
    return Animations.setOfHead(Settings.chosenNpcID)
end

-- The human equivalent of an animation, or the last human animation chosen if there is none. Nil means the game's own.
local function humanVersionOf(animationID)
    local ownSet = Animations.setOf(animationID)
    if ownSet == nil then return animationID end
    return ownSet.toHuman[animationID] or Settings.humanAnimationID
end

function AnimationChoice.humanChoice()
    return humanVersionOf(Settings.chosenAnimationID)
end

-- The animation to keep when the head changes between the new player model heads, old NPC heads and the heads of a
-- set with its own animations (headSet). It is the same emotion if the new kind of head has one, or a default if not.
function AnimationChoice.animationForHead(animationID, forPlayerHead, headSet)
    if animationID == nil then return nil end
    -- An animation from another set is matched through its human version.
    local humanVersion = humanVersionOf(animationID)
    if headSet ~= nil then
        if Animations.setOf(animationID) == headSet then return animationID end
        humanVersion = AnimationChoice.animationForHead(humanVersion, false)
        if headSet.alsoHuman and humanVersion ~= nil then return humanVersion end
        return humanVersion and headSet.fromHuman[humanVersion] or headSet.default
    end
    animationID = humanVersion or Animations.npcFallback
    local isPlayerAnimation = Animations.isPlayerAnimation(animationID)
    if forPlayerHead then
        if isPlayerAnimation then return animationID end
        return Animations.playerTwinOf(animationID) or Animations.fallback
    end
    if not isPlayerAnimation then return animationID end
    return Animations.npcTwinOf(animationID) or Animations.npcTwinOf(Animations.fallback)
end

-- playerAnimationOfLine is the animation the game set on the player's head for this line. Heads on the player's rig
-- use it.
function AnimationChoice.npcHeadAnimation(npcID, playerAnimationOfLine)
    local headSet = Animations.setOfHead(npcID)
    if headSet ~= nil then
        local wanted = Settings.chosenAnimationID or npcVersionOfGameAnimation or Settings.lastSeenNpcAnimationID
        return AnimationChoice.animationForHead(wanted or Animations.npcFallback, false, headSet)
    end
    local chosenAnimation = AnimationChoice.humanChoice()
    if Animations.isOnPlayerRig(npcID) then
        if chosenAnimation ~= nil then return AnimationChoice.animationForHead(chosenAnimation, true) end
        if playerAnimationOfLine ~= nil and playerAnimationOfLine >= 0 then return playerAnimationOfLine end
        return Animations.neutral
    end
    if chosenAnimation ~= nil then return AnimationChoice.animationForHead(chosenAnimation, false) end
    -- The last one seen can be a set's animation, if it came from an NPC in a set.
    local gameAnimation = npcVersionOfGameAnimation or Settings.lastSeenNpcAnimationID or Animations.npcFallback
    return AnimationChoice.animationForHead(gameAnimation, false)
end

function AnimationChoice.playerHeadAnimation(withNeutral)
    local chosenAnimation = AnimationChoice.humanChoice()
    if chosenAnimation == nil then return withNeutral and Animations.neutral or nil end
    return AnimationChoice.animationForHead(chosenAnimation, true)
end

-- npcHeads: true for the version NPC heads play, or the set's own version for a head of a set.
function AnimationChoice.shown(npcHeads)
    local headSet = AnimationChoice.setInUse()
    local shownAnimation = headSet and Settings.chosenAnimationID or AnimationChoice.humanChoice()
    if not npcHeads then return shownAnimation end
    return AnimationChoice.animationForHead(shownAnimation, false, headSet)
end

-- Makes sure the chosen animation is one the head in use can play. A head of a set keeps the choice and plays its own
-- version of it. While the heads window shows NPC heads, a player animation is kept.
function AnimationChoice.fitToHead(allHeadsWindowOpen)
    local chosenBefore = Settings.chosenAnimationID
    local playerAnimations = AnimationChoice.playerAnimationsInUse()
    if chosenBefore ~= nil and AnimationChoice.setInUse() == nil and not (playerAnimations and allHeadsWindowOpen) then
        local fittedAnimation = AnimationChoice.animationForHead(AnimationChoice.humanChoice(), playerAnimations)
        if fittedAnimation ~= chosenBefore then Settings.chooseAnimation(fittedAnimation) end
    end
    return Settings.chosenAnimationID ~= chosenBefore
end

return AnimationChoice
