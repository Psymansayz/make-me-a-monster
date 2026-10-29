-- Replaces the player's chat head in the game's dialogue boxes with an NPC's head.
--
-- The boxes' own head components are ui.Models, so a player head (ModelType PLAYER_HEAD) is turned into an
-- NPC head with Model:SetModel. Checked every frame: the game sets the player's head again whenever it
-- fills or lays out a box, so it would otherwise flash up or come back.

local ListedAnimations = require("src/game/listed_animations")
local Settings = require("src/data/settings")
local AnimationData = require("src/data/animations")

local HeadSwap = {}

-- The NPC version of the animation the game last set on the player's head, before it was swapped (nil if it has none).
HeadSwap.npcVersionOfGameAnimation = nil

-- Interfaces with a player head: the player's line (CHAT_V2_RIGHT) and two heads at once (CHAT_V2_PAIR).
-- The ids are as seen in game; id.Interface is preferred when it has them.
local function interfaceID(interfaceName, defaultID)
    local succeeded, detectedID = pcall(function() return id.Interface[interfaceName] end)
    return succeeded and type(detectedID) == "number" and detectedID or defaultID
end
local PLAYER_HEAD_INTERFACES = {
    interfaceID("CHAT_V2_RIGHT", 1191),
    interfaceID("CHAT_V2_PAIR", 1187),
}
local MAX_COMPONENT_SCAN_ID = 40 -- the boxes' head components are among their first statics

local NPC_SPEECH_INTERFACE = interfaceID("CHAT_V2_LEFT", 1184) -- the NPC's line: its head is always the NPC's own

local PLAYER_HEAD_MODEL_TYPE = 3 -- ui.ModelType values
local NPC_HEAD_MODEL_TYPE = 2

-- The listed animation that has each player animation as its twin (the lowest id if several), made once from
-- AnimationData.twin and AnimationData.alsoFor. (The player's head animations don't play on an NPC's head, their NPC
-- versions do.)
local npcVersionOfPlayerAnimation = {}
for npcAnimation, playerAnimation in pairs(AnimationData.twin) do
    local lowestSoFar = npcVersionOfPlayerAnimation[playerAnimation]
    if lowestSoFar == nil or npcAnimation < lowestSoFar then npcVersionOfPlayerAnimation[playerAnimation] = npcAnimation end
end
for playerAnimation, npcAnimation in pairs(AnimationData.alsoFor) do
    npcVersionOfPlayerAnimation[playerAnimation] = npcAnimation
end

local modelComponentIDsOfInterface = {} -- interface id -> static ids of its model components (their type doesn't change)

-- The static ids of an interface's model components, found once it is loaded; nil while it isn't.
local function modelComponentIDs(interface)
    local componentIDs = modelComponentIDsOfInterface[interface]
    if componentIDs ~= nil then return componentIDs end
    if ui.Interfaces:GetInterface(interface) == nil then return nil end
    componentIDs = {}
    local MODEL = ui.ComponentType.MODEL
    for staticID = 0, MAX_COMPONENT_SCAN_ID do
        local succeeded, isModel = pcall(function()
            local component = ui.Interfaces:GetComponent(interface, staticID)
            return component ~= nil and component.type == MODEL
        end)
        if succeeded and isModel then componentIDs[#componentIDs + 1] = staticID end
    end
    modelComponentIDsOfInterface[interface] = componentIDs
    return componentIDs
end

-- Whether an interface is open now (a cheap check, so a closed box costs nothing each frame).
local function isInterfaceOpen(interface)
    local succeeded, isOpen = pcall(function() return ui.Interfaces:GetInterface(interface) ~= nil end)
    return succeeded and isOpen
end

-- The animation an NPC's head should play (never a player's animation: they don't play on an NPC's head): the
-- player's choice as its NPC version, else the NPC version of the animation the game set on the player's head for the
-- line (HeadSwap.npcVersionOfGameAnimation), and only if that has none, the one last seen on a real NPC's head.
-- Also what the heads in the windows play.
function HeadSwap.npcHeadAnimation()
    local chosenAnimation = Settings.chosenAnimationID
    if chosenAnimation ~= nil then return HeadSwap.animationForHead(chosenAnimation, false) end
    return HeadSwap.npcVersionOfGameAnimation or Settings.lastSeenNpcAnimationID
end

-- The animation the player's own head plays for the animation chosen (which may be one for an NPC's head): its
-- HUMAN_ACTOR twin from src/data/animations.lua, else evil laugh. With none chosen:
-- the neutral one if asked for (withNeutral, for a head shown outside dialogue), else nil.
function HeadSwap.playerHeadAnimation(withNeutral)
    local chosenAnimation = Settings.chosenAnimationID
    if chosenAnimation == nil then return withNeutral and AnimationData.neutral or nil end
    -- (never an NPC animation: it is changed to the player's version)
    return HeadSwap.animationForHead(chosenAnimation, true)
end

-- The animation to keep when the head changes between the player's own and an NPC's, which play different
-- animations: for the player's own head the twin of an NPC animation; for an NPC head the animation that has this
-- one as its twin. Where there is none, evil laugh (of the kind the head plays).
function HeadSwap.animationForHead(animationID, forPlayerHead)
    if animationID == nil then return nil end
    local isPlayerAnimation = ListedAnimations.isPlayerAnimation(animationID)
    if forPlayerHead then
        if isPlayerAnimation then return animationID end
        return AnimationData.twin[animationID] or AnimationData.fallback
    end
    if not isPlayerAnimation then return animationID end
    return npcVersionOfPlayerAnimation[animationID] or npcVersionOfPlayerAnimation[AnimationData.fallback]
end

function HeadSwap.applyNpcHeadAnimation(component)
    local animationID = HeadSwap.npcHeadAnimation()
    if animationID ~= nil and component.animID ~= animationID then component.animID = animationID end
end

-- Notes the animation of the NPC speech box's head, for the swapped head to use.
local function learnNpcSpeechAnimation()
    if not isInterfaceOpen(NPC_SPEECH_INTERFACE) then return end
    local componentIDs = modelComponentIDs(NPC_SPEECH_INTERFACE)
    if componentIDs == nil then return end
    for _, staticID in ipairs(componentIDs) do
        local component = ui.Interfaces:GetComponent(NPC_SPEECH_INTERFACE, staticID)
        if component.visibleGlobal == true and tonumber(component.modelType) == NPC_HEAD_MODEL_TYPE then
            local animationID = tonumber(component.animID)
            if animationID ~= nil and animationID >= 0 and animationID ~= Settings.lastSeenNpcAnimationID then
                Settings.setLastSeenNpcAnimation(animationID)
            end
        end
    end
end

-- Per head component, by its key (interface and static id):
local scaledViewDistance = {} -- -> { game, written }: the view distance the game set, and the one written
-- The player's own head, left in place and given the animation chosen: the animation written, and the one the game set
-- (to put back when the choice is cleared).
local writtenAnimation, gameAnimation = {}, {}
-- A player head turned into an NPC's: -> { npcID = the NPC's id, gameAnimation = the animation the game set on the
-- player's head }, to change the head when another NPC is chosen and to put the player's head back.
local swappedHeads = {}

-- The head drawn Settings.headScale times larger by moving the camera closer: the view distance is the game's divided
-- by the scale. The game sets the view distance itself when it fills a box, so a value other than the one written
-- is the game's, and becomes the new game value. (Only as large as the box's own space: more of the head than that
-- is cut off at its edge.)
-- Workaround: a component is looked up again each frame and may be a different object, so it is told apart by its
-- key (interface and static id), not itself.
local function applyHeadScale(componentKey, component)
    local currentViewDistance = component.viewDistance
    if type(currentViewDistance) ~= "number" then return end
    local record = scaledViewDistance[componentKey]
    if Settings.headScale <= 1 then
        if record ~= nil and currentViewDistance == record.written then component.viewDistance = record.game end
        scaledViewDistance[componentKey] = nil
        return
    end
    if record == nil or currentViewDistance ~= record.written then
        record = { game = currentViewDistance }
        scaledViewDistance[componentKey] = record
    end
    local scaledViewDistanceWanted = math.max(1, math.floor(record.game / Settings.headScale + 0.5))
    if currentViewDistance ~= scaledViewDistanceWanted then component.viewDistance = scaledViewDistanceWanted end
    record.written = scaledViewDistanceWanted
end

-- One model component: a shown player head becomes the NPC's head. With no NPC chosen (npcID nil), the
-- player's own head stays, playing the animation the player picked. Either way it is drawn at the size set.
local function swapComponentHead(component, npcID, componentKey)
    if component.visibleGlobal ~= true then
        scaledViewDistance[componentKey], writtenAnimation[componentKey] = nil, nil
        gameAnimation[componentKey], swappedHeads[componentKey] = nil, nil
        return
    end
    local modelType = tonumber(component.modelType)
    local swappedHead = swappedHeads[componentKey]
    if swappedHead ~= nil
        and (swappedHead.npcID == npcID or modelType ~= NPC_HEAD_MODEL_TYPE or component.modelID1 ~= swappedHead.npcID) then
        -- (still ours with the same NPC, or the game has set the head again: nothing to change)
        if swappedHead.npcID ~= npcID then swappedHeads[componentKey] = nil end
        swappedHead = nil
    end
    if npcID == nil then
        if swappedHead ~= nil then
            -- "Use my own head": the player's head again, with the animation the game had set on it.
            swappedHeads[componentKey] = nil
            component:SetModel(ui.ModelType.PLAYER_HEAD, -1)
            if swappedHead.gameAnimation ~= nil then component.animID = swappedHead.gameAnimation end
            modelType = tonumber(component.modelType)
        end
        if modelType == PLAYER_HEAD_MODEL_TYPE then
            local currentAnimation = tonumber(component.animID)
            local lastWrittenAnimation = writtenAnimation[componentKey]
            if lastWrittenAnimation == nil or currentAnimation ~= lastWrittenAnimation then
                gameAnimation[componentKey] = currentAnimation -- (the game set it)
            end
            local wantedAnimation = HeadSwap.playerHeadAnimation(false)
            if wantedAnimation ~= nil then
                if currentAnimation ~= wantedAnimation then component.animID = wantedAnimation end
                writtenAnimation[componentKey] = wantedAnimation
            elseif lastWrittenAnimation ~= nil then
                -- The choice was cleared: the game's animation again (unless the game has set another since).
                if currentAnimation == lastWrittenAnimation and gameAnimation[componentKey] ~= nil then
                    component.animID = gameAnimation[componentKey]
                end
                writtenAnimation[componentKey], gameAnimation[componentKey] = nil, nil
            end
            applyHeadScale(componentKey, component)
        end
        return
    end
    if swappedHead ~= nil then
        -- Another NPC chosen: its head in place of the one shown.
        swappedHead.npcID = npcID
        component:SetModel(ui.ModelType.NPC_HEAD, npcID)
        HeadSwap.applyNpcHeadAnimation(component)
        applyHeadScale(componentKey, component)
        return
    end
    if modelType == NPC_HEAD_MODEL_TYPE and component.modelID1 == npcID then
        HeadSwap.applyNpcHeadAnimation(component) -- (already ours: the animation kept up)
        applyHeadScale(componentKey, component)
        return
    end
    if modelType ~= PLAYER_HEAD_MODEL_TYPE then return end -- an NPC's own head stays
    -- The animation the game chose for the player's head on this line (the speaker's expression).
    local gameAnimationOfLine = tonumber(component.animID)
    if gameAnimationOfLine ~= nil and gameAnimationOfLine >= 0 then
        HeadSwap.npcVersionOfGameAnimation = npcVersionOfPlayerAnimation[gameAnimationOfLine]
    end
    swappedHeads[componentKey] = { npcID = npcID, gameAnimation = gameAnimationOfLine }
    component:SetModel(ui.ModelType.NPC_HEAD, npcID)
    HeadSwap.applyNpcHeadAnimation(component)
    applyHeadScale(componentKey, component)
end

-- Every frame.
function HeadSwap.tick()
    local npcID = Settings.chosenNpcID
    if npcID ~= nil then pcall(learnNpcSpeechAnimation) end -- (the NPC's own animation is only used with an NPC's head)
    -- (nothing to do with no NPC, no animation chosen, normal size and nothing left to put back)
    if npcID == nil and Settings.chosenAnimationID == nil and Settings.headScale <= 1 and next(scaledViewDistance) == nil
        and next(writtenAnimation) == nil and next(swappedHeads) == nil then
        return
    end
    for _, interface in ipairs(PLAYER_HEAD_INTERFACES) do
        local succeeded, componentIDs = false, nil
        if isInterfaceOpen(interface) then succeeded, componentIDs = pcall(modelComponentIDs, interface) end
        if succeeded and componentIDs ~= nil then
            for _, staticID in ipairs(componentIDs) do
                pcall(function()
                    swapComponentHead(ui.Interfaces:GetComponent(interface, staticID), npcID, interface .. ":" .. staticID)
                end)
            end
        end
    end
end

-- Logout: the boxes are gone, so what was found about them is looked up again.
function HeadSwap.reset()
    modelComponentIDsOfInterface = {}
    scaledViewDistance, writtenAnimation, gameAnimation, swappedHeads = {}, {}, {}, {}
end

return HeadSwap
