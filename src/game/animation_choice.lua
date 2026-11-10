-- Which animation each head plays for the animation chosen: the player's own head, old NPC heads, the newer heads on
-- the player's rig, and the heads of a set with animations of its own.

local Animations = require("src/game/animations")
local Settings = require("src/data/settings")

local AnimationChoice = {}

-- The NPC version of the animation the game last set on the player's head, before it was swapped (nil if it has none).
local npcVersionOfGameAnimation = nil

-- The game set this animation on the player's head, for a dialogue line.
function AnimationChoice.noteGameAnimation(playerAnimationID)
    npcVersionOfGameAnimation = Animations.npcTwinOf(playerAnimationID)
end

-- A real NPC's head played this animation in a dialogue box: what the NPC heads play while nothing is chosen.
function AnimationChoice.noteNpcAnimation(animationID)
    Settings.lastSeenNpcAnimationID = animationID
end

-- Logout: the game's last animation no longer counts.
function AnimationChoice.forgetGameAnimation()
    npcVersionOfGameAnimation = nil
end

-- Whether the head in use plays the player's animations: the player's own head, or an NPC head on the player's rig.
function AnimationChoice.playerAnimationsInUse()
    return Settings.chosenNpcID == nil or Animations.isOnPlayerRig(Settings.chosenNpcID)
end

-- The set of animations of its own the head in use plays, or nil.
function AnimationChoice.setInUse()
    return Animations.setOfHead(Settings.chosenNpcID)
end

-- An animation as a head outside the sets plays it: a set's animation becomes its human match, else the last human
-- animation chosen (nil: the game's own).
local function humanVersionOf(animationID)
    local ownSet = Animations.setOf(animationID)
    if ownSet == nil then return animationID end
    return ownSet.toHuman[animationID] or Settings.humanAnimationID
end

-- The choice as a head outside the sets plays it.
function AnimationChoice.humanChoice()
    return humanVersionOf(Settings.chosenAnimationID)
end

-- The animation to keep when the head changes between the new player model heads, old NPC heads and the heads of a
-- set with animations of its own (headSet): the same emotion where the other kind has it, else a default.
function AnimationChoice.animationForHead(animationID, forPlayerHead, headSet)
    if animationID == nil then return nil end
    -- Another set's animation goes by its human version.
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

-- The animation the NPC head with this id should play (in a dialogue box or a window). playerAnimationOfLine: what the
-- game set on the player's head for the line, for a head on the player's rig.
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
    -- (the last seen can be a set's animation, from an NPC of a set)
    local gameAnimation = npcVersionOfGameAnimation or Settings.lastSeenNpcAnimationID or Animations.npcFallback
    return AnimationChoice.animationForHead(gameAnimation, false)
end

-- The animation the player's own head plays for the animation chosen (never an NPC animation: it becomes the player's
-- version). withNeutral: the neutral one when nothing is chosen, else nil.
function AnimationChoice.playerHeadAnimation(withNeutral)
    local chosenAnimation = AnimationChoice.humanChoice()
    if chosenAnimation == nil then return withNeutral and Animations.neutral or nil end
    return AnimationChoice.animationForHead(chosenAnimation, true)
end

-- The chosen animation as the head in use plays it (a head of a set: the set's version of it). npcHeads: as NPC heads
-- play it.
function AnimationChoice.shown(npcHeads)
    local headSet = AnimationChoice.setInUse()
    local shownAnimation = headSet and Settings.chosenAnimationID or AnimationChoice.humanChoice()
    if not npcHeads then return shownAnimation end
    return AnimationChoice.animationForHead(shownAnimation, false, headSet)
end

-- Keeps the animation chosen one the head in use can play, clearing a saved one no longer listed; whether it changed.
-- (A head of a set keeps the choice, playing its own version. While the heads window shows NPC heads, the player's
-- animation is left as it is.)
function AnimationChoice.fitToHead(allHeadsWindowOpen)
    local chosenBefore = Settings.chosenAnimationID
    local playerAnimations = AnimationChoice.playerAnimationsInUse()
    if chosenBefore ~= nil and AnimationChoice.setInUse() == nil and not (playerAnimations and allHeadsWindowOpen) then
        local fittedAnimation = AnimationChoice.animationForHead(AnimationChoice.humanChoice(), playerAnimations)
        if fittedAnimation ~= chosenBefore then Settings.chooseAnimation(fittedAnimation) end
    end
    if Settings.chosenAnimationID ~= nil and not Animations.isListed(Settings.chosenAnimationID) then
        Settings.chooseAnimation(nil)
    end
    return Settings.chosenAnimationID ~= chosenBefore
end

return AnimationChoice
