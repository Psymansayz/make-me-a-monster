-- Replaces the player's chat head in the game's dialogue boxes with an NPC's head.
--
-- The boxes' own head components are ui.Models, so a player head (ModelType PLAYER_HEAD) is turned into an
-- NPC head with Model:SetModel. A box is handled once, when it opens, and again when the player changes the head,
-- the animation or the size: the game does not undo the changes while a box stays open.

local Animations = require("src/game/animations")
local Settings = require("src/data/settings")

local HeadSwap = {}

-- The NPC version of the animation the game last set on the player's head, before it was swapped (nil if it has none).
local npcVersionOfGameAnimation = nil

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
local PAIR_COMPONENT_KEYS = { "1187:8", "1187:13" } -- (the keys of the per-component records below)

local PLAYER_HEAD_MODEL_TYPE = 3 -- ui.ModelType values
local NPC_HEAD_MODEL_TYPE = 2

-- The listed animation that has each player animation as its twin (the lowest id if several), made once from
-- Animations.twin and Animations.alsoFor. (The player's head animations don't play on an NPC's head, their NPC
-- versions do.)
local npcVersionOfPlayerAnimation = {}
for npcAnimation, playerAnimation in pairs(Animations.twin) do
    local lowestSoFar = npcVersionOfPlayerAnimation[playerAnimation]
    if lowestSoFar == nil or npcAnimation < lowestSoFar then npcVersionOfPlayerAnimation[playerAnimation] = npcAnimation end
end
for playerAnimation, npcAnimation in pairs(Animations.alsoFor) do
    npcVersionOfPlayerAnimation[playerAnimation] = npcAnimation
end

-- Whether an interface is open now (checked first, so a closed box costs nothing more).
local function isInterfaceOpen(interface)
    return ui.Interfaces:GetInterface(interface) ~= nil
end

-- The animation the NPC head with this id should play (in a dialogue box or a window). An NPC-rig head plays NPC
-- animations only: the choice as its NPC version, else the NPC version of the game's animation for the line, else
-- the one last seen on a real NPC, else the NPC evil laugh. A head on the player's rig plays the player's: the choice
-- as its player version, else the game's animation for the line (playerAnimationOfLine), else the neutral one.
function HeadSwap.npcHeadAnimation(npcID, playerAnimationOfLine)
    local chosenAnimation = Settings.chosenAnimationID
    if Animations.isOnPlayerRig(npcID) then
        if chosenAnimation ~= nil then return HeadSwap.animationForHead(chosenAnimation, true) end
        if playerAnimationOfLine ~= nil and playerAnimationOfLine >= 0 then return playerAnimationOfLine end
        return Animations.neutral
    end
    if chosenAnimation ~= nil then return HeadSwap.animationForHead(chosenAnimation, false) end
    return npcVersionOfGameAnimation or Settings.lastSeenNpcAnimationID or Animations.npcFallback
end

-- The animation the player's own head plays for the animation chosen (which may be one for an NPC's head): its
-- HUMAN_ACTOR twin from src/data/animation_list.lua, else evil laugh. With none chosen:
-- the neutral one if asked for (withNeutral, for a head shown outside dialogue), else nil.
function HeadSwap.playerHeadAnimation(withNeutral)
    local chosenAnimation = Settings.chosenAnimationID
    if chosenAnimation == nil then return withNeutral and Animations.neutral or nil end
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
        return Animations.twin[animationID] or Animations.fallback
    end
    if not isPlayerAnimation then return animationID end
    return npcVersionOfPlayerAnimation[animationID] or npcVersionOfPlayerAnimation[Animations.fallback]
end

-- The NPC head with this id, in this component, given the animation it should play (playerAnimationOfLine: the
-- animation the game had set on the player's head there, if known).
local function applyNpcHeadAnimation(component, npcID, playerAnimationOfLine)
    local animationID = HeadSwap.npcHeadAnimation(npcID, playerAnimationOfLine)
    if animationID ~= nil and component.animID ~= animationID then component.animID = animationID end
end

-- Notes the animation of the NPC speech box's head, for the swapped head to use. (Called while that box is open.)
local function learnNpcSpeechAnimation()
    local component = ui.Interfaces:GetComponent(NPC_SPEECH_INTERFACE, HEAD_STATIC_ID)
    if component.visibleGlobal == true and tonumber(component.modelType) == NPC_HEAD_MODEL_TYPE then
        local animationID = tonumber(component.animID)
        if animationID ~= nil and animationID >= 0 and animationID ~= Settings.lastSeenNpcAnimationID then
            Settings.lastSeenNpcAnimationID = animationID
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
-- Done when a head is put in a box, and for every head shown when the size is changed.
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
            -- "Use my own head": the player's head again, with the animation and the projection the game had set on it.
            swappedHeads[componentKey] = nil
            component:SetModel(ui.ModelType.PLAYER_HEAD, -1)
            component.orthographic = swappedHead.orthographic
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
        applyNpcHeadAnimation(component, npcID, swappedHead.gameAnimation)
        writeHeadViewDistance(component)
        return
    end
    if modelType == NPC_HEAD_MODEL_TYPE and component.modelID1 == npcID then
        -- (already ours: only the animation is kept up)
        local ownRecord = swappedHeads[componentKey]
        applyNpcHeadAnimation(component, npcID, ownRecord and ownRecord.gameAnimation or nil)
        return
    end
    if modelType ~= PLAYER_HEAD_MODEL_TYPE then return end -- an NPC's own head stays
    -- The animation the game chose for the player's head on this line (the speaker's expression).
    local gameAnimationOfLine = tonumber(component.animID)
    if gameAnimationOfLine ~= nil and gameAnimationOfLine >= 0 then
        npcVersionOfGameAnimation = npcVersionOfPlayerAnimation[gameAnimationOfLine]
    end
    swappedHeads[componentKey] = { npcID = npcID, gameAnimation = gameAnimationOfLine, orthographic = component.orthographic }
    component:SetModel(ui.ModelType.NPC_HEAD, npcID)
    -- The game draws the player's own head with an orthographic projection and NPC heads in perspective (seen in the
    -- logs); SetModel keeps the projection, so the NPC head is given the NPC one.
    component.orthographic = false
    applyNpcHeadAnimation(component, npcID, gameAnimationOfLine)
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

local handledBoxes = {} -- interface -> true while it is open and has been handled

-- A box that stays open for the next line is filled again without closing. The server sends variables 8180
-- (CHAT_V3_UPDATE_INTERFACE) and 101 (PAGEPOS) a frame before a single box is filled, 101 alone before the pair box:
-- after either, the open boxes are looked at again for a few frames (heads set again by the game are swapped again).
-- Listened to only while a box that can hold the player's head is handled.
local DIALOGUE_UPDATE_VARIABLE_IDS = { [8180] = true, [101] = true }
local FRAMES_TO_RECHECK = 5
local framesToRecheck = 0
local VARIABLE_SUBSCRIPTION = "make_me_a_monster_dialogue_update"
local RECHECK_SUBSCRIPTION = "make_me_a_monster_dialogue_recheck"
local listeningForUpdates = false

-- The rechecks run on the Draw event, which is subscribed to for just those frames: nothing of the plugin's runs every
-- frame otherwise.
local function onRecheckFrame()
    framesToRecheck = framesToRecheck - 1
    HeadSwap.refreshOpenDialogues()
    if framesToRecheck <= 0 then Event.Draw.Unsubscribe(RECHECK_SUBSCRIPTION) end
end

local function recheckForAFewFrames()
    if framesToRecheck <= 0 then Event.Draw.Subscribe(RECHECK_SUBSCRIPTION, onRecheckFrame) end
    framesToRecheck = FRAMES_TO_RECHECK
end

local function stopRechecking()
    if framesToRecheck > 0 then Event.Draw.Unsubscribe(RECHECK_SUBSCRIPTION) end
    framesToRecheck = 0
end

local function onVariableTransmitted(event)
    if DIALOGUE_UPDATE_VARIABLE_IDS[event.var.id] then recheckForAFewFrames() end
end

-- Starts listening (when a box that can hold the player's head has been handled).
local function startListeningForUpdates()
    if listeningForUpdates then return end
    Event.VarTransmit.Subscribe(VARIABLE_SUBSCRIPTION, onVariableTransmitted)
    listeningForUpdates = true
end

-- Stops listening when neither of those boxes is handled any more.
local function stopListeningIfNoBoxHandled()
    if not listeningForUpdates or handledBoxes[PLAYER_LINE_INTERFACE] or handledBoxes[PAIR_INTERFACE] then return end
    Event.VarTransmit.Unsubscribe(VARIABLE_SUBSCRIPTION)
    listeningForUpdates = false
end

-- The head components of a box that has opened, swapped once. The game may fill the box's head only after the box is
-- seen open (the check runs as the server's packet is processed), so the open boxes are looked at again for a few
-- frames as well.
local function handleBox(interface)
    npcIDToShow = Settings.chosenNpcID
    if interface == PLAYER_LINE_INTERFACE then
        startListeningForUpdates()
        visitHead(swapHeadVisit, PLAYER_LINE_INTERFACE, HEAD_STATIC_ID, "1191:8")
    elseif interface == PAIR_INTERFACE then
        startListeningForUpdates()
        visitHead(swapHeadVisit, PAIR_INTERFACE, HEAD_STATIC_ID, "1187:8")
        visitHead(swapHeadVisit, PAIR_INTERFACE, PAIR_SECOND_HEAD_STATIC_ID, "1187:13")
    elseif npcIDToShow ~= nil then
        learnNpcSpeechAnimation()
    end
    recheckForAFewFrames()
end

-- What a closed box leaves behind is let go (the game fills it again when it opens).
local function forgetBox(interface)
    handledBoxes[interface] = nil
    stopListeningIfNoBoxHandled()
    if interface == PLAYER_LINE_INTERFACE then
        writtenAnimation["1191:8"], gameAnimation["1191:8"], swappedHeads["1191:8"] = nil, nil, nil
    elseif interface == PAIR_INTERFACE then
        for _, componentKey in ipairs(PAIR_COMPONENT_KEYS) do
            writtenAnimation[componentKey], gameAnimation[componentKey], swappedHeads[componentKey] = nil, nil, nil
        end
    end
end

-- The player changed the head, the animation or the size: the boxes open now follow.
function HeadSwap.refreshOpenDialogues()
    npcIDToShow = Settings.chosenNpcID
    forEachOpenHeadComponent(swapHeadVisit)
    if npcIDToShow ~= nil and isInterfaceOpen(NPC_SPEECH_INTERFACE) then pcall(learnNpcSpeechAnimation) end
end

-- A box that has just opened is handled once; one that has closed is forgotten.
local function watchBox(interface)
    if isInterfaceOpen(interface) then
        if not handledBoxes[interface] then
            handledBoxes[interface] = true
            pcall(handleBox, interface)
        end
    elseif handledBoxes[interface] then
        forgetBox(interface)
    end
end

-- Looks for a box that has just opened or closed: two or three interface lookups. Dialogue boxes open and close only as
-- the server says, so this runs on the ServerLogic event (once per packet from the server, about every 0.6 s, as soon
-- as the packet has been processed), not every frame. (The NPC's own animation is only used with an NPC head, so that
-- box is watched only then.)
local function watchBoxes()
    watchBox(PLAYER_LINE_INTERFACE)
    watchBox(PAIR_INTERFACE)
    if Settings.chosenNpcID ~= nil then watchBox(NPC_SPEECH_INTERFACE) end
end

local WATCH_SUBSCRIPTION = "make_me_a_monster_dialogue_watch"

function HeadSwap.start()
    Event.ServerLogic.Subscribe(WATCH_SUBSCRIPTION, watchBoxes)
end

-- For the plugin shutting down.
function HeadSwap.stop()
    Event.ServerLogic.Unsubscribe(WATCH_SUBSCRIPTION)
    handledBoxes = {}
    stopListeningIfNoBoxHandled()
    stopRechecking()
end

-- Logout: the boxes are gone, and nothing is watched until the game is entered again (HeadSwap.start).
function HeadSwap.reset()
    HeadSwap.stop()
    writtenAnimation, gameAnimation, swappedHeads = {}, {}, {}
end

return HeadSwap
