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

-- The dialogue boxes and the model components in them that hold a head. These are fixed in the game (seen in its logs):
--   1184 (CHAT_V2_LEFT): the NPC's line, one head, component 8, always the NPC's own.
--   1191 (CHAT_V2_RIGHT): the player's line, one head, component 8.
--   1187 (CHAT_V2_PAIR): two heads, components 8 and 13; each can hold the player, an NPC, or in a dialogue without the
--   player, two NPCs. Only a component holding the player's head is changed.
local NPC_SPEECH_INTERFACE = 1184
local PLAYER_LINE_INTERFACE = 1191
local PAIR_INTERFACE = 1187
local HEAD_STATIC_ID = 8
local PAIR_SECOND_HEAD_STATIC_ID = 13

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
    local component = ui.Interfaces:GetComponent(NPC_SPEECH_INTERFACE, HEAD_STATIC_ID)
    if component.visibleGlobal == true and tonumber(component.modelType) == NPC_HEAD_MODEL_TYPE then
        local animationID = tonumber(component.animID)
        if animationID ~= nil and animationID >= 0 and animationID ~= Settings.lastSeenNpcAnimationID then
            Settings.setLastSeenNpcAnimation(animationID)
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
    if swappedHead ~= nil then
        -- The record is kept only while the component still shows the NPC we put there (the game may have set it again).
        local stillOurs = modelType == NPC_HEAD_MODEL_TYPE and component.modelID1 == swappedHead.npcID
        if not stillOurs then swappedHeads[componentKey] = nil end
        -- (nothing to change if it is the NPC chosen now, or if it is no longer ours)
        if not stillOurs or swappedHead.npcID == npcID then swappedHead = nil end
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

-- Calls visit(component, componentKey) for the head component with this id, if it can be fetched.
local function visitHead(visit, interface, staticID, componentKey)
    local fetched, component = pcall(ui.Interfaces.GetComponent, ui.Interfaces, interface, staticID)
    if fetched and component ~= nil then pcall(visit, component, componentKey) end
end

-- Calls visit(component, componentKey) for each head component of the open dialogue boxes that can show the player's head.
local function forEachOpenHeadComponent(visit)
    if isInterfaceOpen(PLAYER_LINE_INTERFACE) then
        visitHead(visit, PLAYER_LINE_INTERFACE, HEAD_STATIC_ID, "1191:8")
    end
    if isInterfaceOpen(PAIR_INTERFACE) then
        visitHead(visit, PAIR_INTERFACE, HEAD_STATIC_ID, "1187:8")
        visitHead(visit, PAIR_INTERFACE, PAIR_SECOND_HEAD_STATIC_ID, "1187:13")
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

-- EXPERIMENT (dev only): a box is handled once, when it opens (and when the player changes the head, the animation or the
-- size), instead of every frame. Whether the game clears the changes while a box stays open is what is being tried.
local handledBoxes = {} -- interface -> true while it is open and has been handled

-- The head components of a box that has opened, swapped once.
local function handleBox(interface)
    npcIDToShow = Settings.chosenNpcID
    if interface == PLAYER_LINE_INTERFACE then
        visitHead(swapHeadVisit, PLAYER_LINE_INTERFACE, HEAD_STATIC_ID, "1191:8")
    elseif interface == PAIR_INTERFACE then
        visitHead(swapHeadVisit, PAIR_INTERFACE, HEAD_STATIC_ID, "1187:8")
        visitHead(swapHeadVisit, PAIR_INTERFACE, PAIR_SECOND_HEAD_STATIC_ID, "1187:13")
    elseif npcIDToShow ~= nil then
        learnNpcSpeechAnimation()
    end
end

-- What a closed box leaves behind is let go (the game fills it again when it opens).
local function forgetBox(interface)
    handledBoxes[interface] = nil
    if interface == PLAYER_LINE_INTERFACE then
        writtenAnimation["1191:8"], gameAnimation["1191:8"], swappedHeads["1191:8"] = nil, nil, nil
    elseif interface == PAIR_INTERFACE then
        for _, componentKey in ipairs({ "1187:8", "1187:13" }) do
            writtenAnimation[componentKey], gameAnimation[componentKey], swappedHeads[componentKey] = nil, nil, nil
        end
    end
end

-- The player changed the head or the animation: the boxes open now follow.
function HeadSwap.refreshOpenBoxes()
    npcIDToShow = Settings.chosenNpcID
    forEachOpenHeadComponent(swapHeadVisit)
    if npcIDToShow ~= nil and isInterfaceOpen(NPC_SPEECH_INTERFACE) then pcall(learnNpcSpeechAnimation) end
end

-- Every frame (a Draw event): looks for a box that has just opened and handles it once.
function HeadSwap.tick()
    if isInterfaceOpen(PLAYER_LINE_INTERFACE) then
        if not handledBoxes[PLAYER_LINE_INTERFACE] then
            handledBoxes[PLAYER_LINE_INTERFACE] = true
            pcall(handleBox, PLAYER_LINE_INTERFACE)
        end
    elseif handledBoxes[PLAYER_LINE_INTERFACE] then
        forgetBox(PLAYER_LINE_INTERFACE)
    end
    if isInterfaceOpen(PAIR_INTERFACE) then
        if not handledBoxes[PAIR_INTERFACE] then
            handledBoxes[PAIR_INTERFACE] = true
            pcall(handleBox, PAIR_INTERFACE)
        end
    elseif handledBoxes[PAIR_INTERFACE] then
        forgetBox(PAIR_INTERFACE)
    end
    if Settings.chosenNpcID ~= nil then
        if isInterfaceOpen(NPC_SPEECH_INTERFACE) then
            if not handledBoxes[NPC_SPEECH_INTERFACE] then
                handledBoxes[NPC_SPEECH_INTERFACE] = true
                pcall(handleBox, NPC_SPEECH_INTERFACE)
            end
        else
            handledBoxes[NPC_SPEECH_INTERFACE] = nil
        end
    end
end

-- Logout: the boxes are gone, so what was found about them is looked up again.
function HeadSwap.reset()
    writtenAnimation, gameAnimation, swappedHeads, handledBoxes = {}, {}, {}, {}
end

return HeadSwap
