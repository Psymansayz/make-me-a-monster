-- Replaces the player's chat head in the game's dialogue boxes with an NPC's head.
--
-- The boxes' own head components are ui.Models, so a player head (ModelType PLAYER_HEAD) is turned into an
-- NPC head with Model:SetModel. Checked every frame: the game sets the player's head again whenever it
-- fills or lays out a box, so it would otherwise flash up or come back.

local Animations = require("src/game/animations")
local Settings = require("src/data/settings")
local AnimationList = require("src/data/animation_list")

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
-- AnimationList.twin and AnimationList.alsoFor. (The player's head animations don't play on an NPC's head, their NPC
-- versions do.)
local npcVersionOfPlayerAnimation = {}
for npcAnimation, playerAnimation in pairs(AnimationList.twin) do
    local lowestSoFar = npcVersionOfPlayerAnimation[playerAnimation]
    if lowestSoFar == nil or npcAnimation < lowestSoFar then npcVersionOfPlayerAnimation[playerAnimation] = npcAnimation end
end
for playerAnimation, npcAnimation in pairs(AnimationList.alsoFor) do
    npcVersionOfPlayerAnimation[playerAnimation] = npcAnimation
end

-- interface id -> { ids = static ids of its model components (their type doesn't change), keys = their keys }
local modelComponentsOfInterface = {}

-- The model components of an interface, found once it is loaded; nil while it isn't.
local function modelComponents(interface)
    local components = modelComponentsOfInterface[interface]
    if components ~= nil then return components end
    local fetched, interfaceObject = pcall(ui.Interfaces.GetInterface, ui.Interfaces, interface)
    if not fetched or interfaceObject == nil then return nil end
    components = { ids = {}, keys = {} }
    local MODEL = ui.ComponentType.MODEL
    for staticID = 0, MAX_COMPONENT_SCAN_ID do
        local succeeded, isModel = pcall(function()
            local component = ui.Interfaces:GetComponent(interface, staticID)
            return component ~= nil and component.type == MODEL
        end)
        if succeeded and isModel then
            components.ids[#components.ids + 1] = staticID
            components.keys[#components.keys + 1] = interface .. ":" .. staticID
        end
    end
    modelComponentsOfInterface[interface] = components
    return components
end

-- Whether an interface is open now. (Checked first each frame, so a closed box costs nothing more.)
local function isInterfaceOpen(interface)
    local fetched, interfaceObject = pcall(ui.Interfaces.GetInterface, ui.Interfaces, interface)
    return fetched and interfaceObject ~= nil
end

-- The animation an NPC's head should play (never a player's animation: they don't play on an NPC's head): the
-- player's choice as its NPC version, else the NPC version of the animation the game set on the player's head for the
-- line (HeadSwap.npcVersionOfGameAnimation), and only if that has none, the one last seen on a real NPC's head. If
-- there is none of those either, the NPC evil laugh: an NPC's head always has an animation. Also what the heads in the
-- windows play.
function HeadSwap.npcHeadAnimation()
    local chosenAnimation = Settings.chosenAnimationID
    if chosenAnimation ~= nil then return HeadSwap.animationForHead(chosenAnimation, false) end
    return HeadSwap.npcVersionOfGameAnimation or Settings.lastSeenNpcAnimationID or AnimationList.npcFallback
end

-- The animation the player's own head plays for the animation chosen (which may be one for an NPC's head): its
-- HUMAN_ACTOR twin from src/data/animation_list.lua, else evil laugh. With none chosen:
-- the neutral one if asked for (withNeutral, for a head shown outside dialogue), else nil.
function HeadSwap.playerHeadAnimation(withNeutral)
    local chosenAnimation = Settings.chosenAnimationID
    if chosenAnimation == nil then return withNeutral and AnimationList.neutral or nil end
    -- (never an NPC animation: it is changed to the player's version)
    return HeadSwap.animationForHead(chosenAnimation, true)
end

-- The animation to keep when the head changes between the player's own and an NPC's, which play different
-- animations: for the player's own head the twin of an NPC animation; for an NPC head the animation that has this
-- one as its twin. Where there is none, evil laugh (of the kind the head plays).
function HeadSwap.animationForHead(animationID, forPlayerHead)
    if animationID == nil then return nil end
    local isPlayerAnimation = Animations.isPlayerAnimation(animationID)
    if forPlayerHead then
        if isPlayerAnimation then return animationID end
        return AnimationList.twin[animationID] or AnimationList.fallback
    end
    if not isPlayerAnimation then return animationID end
    return npcVersionOfPlayerAnimation[animationID] or npcVersionOfPlayerAnimation[AnimationList.fallback]
end

function HeadSwap.applyNpcHeadAnimation(component)
    local animationID = HeadSwap.npcHeadAnimation()
    if animationID ~= nil and component.animID ~= animationID then component.animID = animationID end
end

-- Notes the animation of the NPC speech box's head, for the swapped head to use. (Called while that box is open.)
local function learnNpcSpeechAnimation()
    local components = modelComponents(NPC_SPEECH_INTERFACE)
    if components == nil then return end
    for _, staticID in ipairs(components.ids) do
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

-- The player's own head, left in place and given the animation chosen: the animation written, and the one the game set
-- (to put back when the choice is cleared).
local writtenAnimation, gameAnimation = {}, {}

-- A player head turned into an NPC's: -> { npcID = the NPC's id, gameAnimation = the animation the game set on the
-- player's head }, to change the head when another NPC is chosen and to put the player's head back.
local swappedHeads = {}

-- The head is drawn larger by moving the camera closer: Settings.headViewDistance is the view distance to give it (the
-- game's own is Settings.DEFAULT_HEAD_VIEW_DISTANCE). Only as large as the box's own space: more of the head than that
-- is cut off at its edge.
-- Done when a head is put in a box, for a player head left in place every frame, and for every head shown when the
-- size is changed.
local function writeHeadViewDistance(component)
    if component.viewDistance ~= Settings.headViewDistance then component.viewDistance = Settings.headViewDistance end
end

-- One model component: a shown player head becomes the NPC's head. With no NPC chosen (npcID nil), the
-- player's own head stays, playing the animation the player picked. Either way it is drawn at the size set.
local function swapComponentHead(component, npcID, componentKey)
    if component.visibleGlobal ~= true then
        writtenAnimation[componentKey] = nil
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
            writeHeadViewDistance(component)
        end
        return
    end
    if swappedHead ~= nil then
        -- Another NPC chosen: its head in place of the one shown.
        swappedHead.npcID = npcID
        component:SetModel(ui.ModelType.NPC_HEAD, npcID)
        HeadSwap.applyNpcHeadAnimation(component)
        writeHeadViewDistance(component)
        return
    end
    if modelType == NPC_HEAD_MODEL_TYPE and component.modelID1 == npcID then
        HeadSwap.applyNpcHeadAnimation(component) -- (already ours: only the animation is kept up)
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
    writeHeadViewDistance(component)
end

-- Calls visit(component, componentKey) for each model component of the open dialogue boxes that can show the player's head.
local function forEachOpenHeadComponent(visit)
    for _, interface in ipairs(PLAYER_HEAD_INTERFACES) do
        if isInterfaceOpen(interface) then
            local components = modelComponents(interface)
            if components ~= nil then
                for position, staticID in ipairs(components.ids) do
                    local fetched, component = pcall(ui.Interfaces.GetComponent, ui.Interfaces, interface, staticID)
                    if fetched and component ~= nil then pcall(visit, component, components.keys[position]) end
                end
            end
        end
    end
end

local npcIDToShow = nil -- (set by the frame function for swapHeadVisit)
local function swapHeadVisit(component, componentKey)
    swapComponentHead(component, npcIDToShow, componentKey)
end

local function scaleHeadVisit(component, componentKey)
    if component.visibleGlobal == true
        and (swappedHeads[componentKey] ~= nil or tonumber(component.modelType) == PLAYER_HEAD_MODEL_TYPE) then
        writeHeadViewDistance(component)
    end
end

-- The head size was changed (the slider): the heads shown now are drawn at the new size.
function HeadSwap.refreshHeadViewDistance()
    forEachOpenHeadComponent(scaleHeadVisit)
end

-- Every frame (a Draw event: the game sets the player's head again whenever it fills or lays out a box). Does nothing
-- until a dialogue box is open, and leaves out what isn't needed (the NPC's own animation is only used with an NPC head).
function HeadSwap.tick()
    local npcID = Settings.chosenNpcID
    if npcID ~= nil and isInterfaceOpen(NPC_SPEECH_INTERFACE) then pcall(learnNpcSpeechAnimation) end
    -- (nothing to do with no NPC, no animation chosen and normal size)
    if npcID == nil and Settings.chosenAnimationID == nil and Settings.headViewDistance == Settings.DEFAULT_HEAD_VIEW_DISTANCE
        and next(writtenAnimation) == nil and next(swappedHeads) == nil then
        return
    end
    npcIDToShow = npcID
    forEachOpenHeadComponent(swapHeadVisit)
end

-- Logout: the boxes are gone, so what was found about them is looked up again.
function HeadSwap.reset()
    modelComponentsOfInterface = {}
    writtenAnimation, gameAnimation, swappedHeads = {}, {}, {}
end

return HeadSwap
