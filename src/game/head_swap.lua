-- Replaces the player's chat head in the game's dialogue boxes with an NPC's head. A box is handled once, when it
-- opens, and again when the player changes the head, the animation or the size.

local AnimationChoice = require("src/game/animation_choice")
local Settings = require("src/data/settings")
local GameIds = require("src/game/game_ids")
local HeadSizes = require("src/game/head_sizes")

local HeadSwap = {}

-- The dialogue boxes and the model components in them that hold a head:
--   CHAT_V2_LEFT: the NPC's line, one head, always the NPC's own.
--   CHAT_V2_RIGHT: the player's line, one head.
--   CHAT_V2_PAIR: two heads; each can hold the player, an NPC, or in a dialogue without the player, two NPCs. Only a
--   component holding the player's head is changed.
local NPC_SPEECH_INTERFACE = GameIds.resolve("Interface", "CHAT_V2_LEFT")
local PLAYER_LINE_INTERFACE = GameIds.resolve("Interface", "CHAT_V2_RIGHT")
local PAIR_INTERFACE = GameIds.resolve("Interface", "CHAT_V2_PAIR")

-- The combined ids of the components with these names.
local function headComponents(...)
    local components = {}
    for _, name in ipairs({ ... }) do components[#components + 1] = GameIds.resolve("Component", name) end
    return components
end

local NPC_SPEECH_HEADS = headComponents("CHAT_V2_LEFT__CHATHEAD_1")
local PLAYER_LINE_HEADS = headComponents("CHAT_V2_RIGHT__CHATHEAD_1")
local PAIR_HEADS = headComponents("CHAT_V2_PAIR__CHATHEAD_LEFT", "CHAT_V2_PAIR__CHATHEAD_RIGHT")

local PLAYER_HEAD_MODEL_TYPE = ui.ModelType.PLAYER_HEAD
local NPC_HEAD_MODEL_TYPE = ui.ModelType.NPC_HEAD

local function isInterfaceOpen(interface)
    return interface ~= nil and ui.Interfaces:GetInterface(interface) ~= nil
end

local function applyNpcHeadAnimation(component, npcID, playerAnimationOfLine)
    local animationID = AnimationChoice.npcHeadAnimation(npcID, playerAnimationOfLine)
    if animationID ~= nil and component.animID ~= animationID then component.animID = animationID end
end

-- Notes the animation of the NPC speech box's head, for the swapped head to use.
local function learnNpcSpeechAnimation(component)
    if component.visibleGlobal == true and tonumber(component.modelType) == NPC_HEAD_MODEL_TYPE then
        local animationID = tonumber(component.animID)
        if animationID ~= nil and animationID >= 0 then AnimationChoice.noteNpcAnimation(animationID) end
    end
end

-- By head component: what the plugin wrote and what the game had set, to put the player's head back.
local writtenAnimation, gameAnimation = {}, {}
local swappedHeads = {} -- a player head turned into an NPC's: { npcID, gameAnimation, orthographic }

-- The player's head back, with the animation and the projection the game had set.
local function putPlayerHeadBack(component, swappedHead)
    component:SetModel(PLAYER_HEAD_MODEL_TYPE, -1)
    component.orthographic = swappedHead.orthographic
    if swappedHead.gameAnimation ~= nil then component.animID = swappedHead.gameAnimation end
end

-- A head is drawn larger by moving the camera closer.
local function writeHeadViewDistance(component, npcID)
    local viewDistance = math.max(1, math.floor(Settings.headViewDistance / HeadSizes.of(npcID)))
    if component.viewDistance ~= viewDistance then component.viewDistance = viewDistance end
end

-- Turns a shown player head into the NPC's head, or with no NPC chosen keeps it, playing the animation picked.
local function swapComponentHead(component, npcID, componentKey)
    if component.visibleGlobal ~= true then return end
    local modelType = tonumber(component.modelType)
    local swappedHead = swappedHeads[componentKey]
    if swappedHead ~= nil then
        -- The game may have set the head again: the record holds only while it still shows our NPC.
        local stillOurs = modelType == NPC_HEAD_MODEL_TYPE and component.modelID1 == swappedHead.npcID
        if not stillOurs then swappedHeads[componentKey] = nil end
        if not stillOurs or swappedHead.npcID == npcID then swappedHead = nil end
    end
    if npcID == nil then
        if swappedHead ~= nil then
            swappedHeads[componentKey] = nil
            putPlayerHeadBack(component, swappedHead)
            modelType = tonumber(component.modelType)
        end
        if modelType == PLAYER_HEAD_MODEL_TYPE then
            local currentAnimation = tonumber(component.animID)
            local lastWrittenAnimation = writtenAnimation[componentKey]
            if lastWrittenAnimation == nil or currentAnimation ~= lastWrittenAnimation then
                gameAnimation[componentKey] = currentAnimation -- (the game set it)
            end
            local wantedAnimation = AnimationChoice.playerHeadAnimation(false)
            if wantedAnimation ~= nil then
                if currentAnimation ~= wantedAnimation then component.animID = wantedAnimation end
                writtenAnimation[componentKey] = wantedAnimation
            elseif lastWrittenAnimation ~= nil then
                -- The choice was cleared: back to the game's animation.
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
        swappedHead.npcID = npcID
        component:SetModel(NPC_HEAD_MODEL_TYPE, npcID)
        applyNpcHeadAnimation(component, npcID, swappedHead.gameAnimation)
        writeHeadViewDistance(component, npcID)
        return
    end
    if modelType == NPC_HEAD_MODEL_TYPE and component.modelID1 == npcID then
        local ownRecord = swappedHeads[componentKey]
        applyNpcHeadAnimation(component, npcID, ownRecord and ownRecord.gameAnimation or nil)
        -- The game can reset the view distance for the next line, and a head with custom size needs it set again.
        if ownRecord ~= nil then writeHeadViewDistance(component, npcID) end
        return
    end
    if modelType ~= PLAYER_HEAD_MODEL_TYPE then return end -- an NPC's own head stays
    local gameAnimationOfLine = tonumber(component.animID)
    if gameAnimationOfLine ~= nil and gameAnimationOfLine >= 0 then
        AnimationChoice.noteGameAnimation(gameAnimationOfLine)
    end
    swappedHeads[componentKey] = {
        npcID = npcID, gameAnimation = gameAnimationOfLine, orthographic = component.orthographic,
    }
    component:SetModel(NPC_HEAD_MODEL_TYPE, npcID)
    -- The player's head is orthographic and NPC heads are not, but SetModel keeps the projection.
    component.orthographic = false
    applyNpcHeadAnimation(component, npcID, gameAnimationOfLine)
    writeHeadViewDistance(component, npcID)
end

-- Puts the player's head back as the game had set it, in place of the NPC's head or the animation chosen.
local function restoreComponentHead(component, componentKey)
    local modelType = tonumber(component.modelType)
    local swappedHead = swappedHeads[componentKey]
    if swappedHead ~= nil and modelType == NPC_HEAD_MODEL_TYPE and component.modelID1 == swappedHead.npcID then
        putPlayerHeadBack(component, swappedHead)
    elseif modelType ~= PLAYER_HEAD_MODEL_TYPE then
        return -- an NPC's own head
    elseif tonumber(component.animID) == writtenAnimation[componentKey] and gameAnimation[componentKey] ~= nil then
        component.animID = gameAnimation[componentKey]
    end
    component.viewDistance = Settings.DEFAULT_HEAD_VIEW_DISTANCE
end

-- The head components of each box that can hold the player's head.
local HEADS_OF_BOX = {}
if PLAYER_LINE_INTERFACE ~= nil then HEADS_OF_BOX[PLAYER_LINE_INTERFACE] = PLAYER_LINE_HEADS end
if PAIR_INTERFACE ~= nil then HEADS_OF_BOX[PAIR_INTERFACE] = PAIR_HEADS end

-- The pcalls are for the game's own components, outside the plugin.
local function visitHeads(visit, headComponentIDs)
    for _, componentKey in ipairs(headComponentIDs) do
        local fetched, component = pcall(ui.Interfaces.GetComponent, ui.Interfaces, componentKey)
        if fetched and component ~= nil then pcall(visit, component, componentKey) end
    end
end

-- Visits the interfaces that could contain a player's head.
local function forEachOpenHeadComponent(visit)
    if isInterfaceOpen(PLAYER_LINE_INTERFACE) then visitHeads(visit, PLAYER_LINE_HEADS) end
    if isInterfaceOpen(PAIR_INTERFACE) then visitHeads(visit, PAIR_HEADS) end
end

local function swapHeadVisit(component, componentKey)
    swapComponentHead(component, Settings.chosenNpcID, componentKey)
end

local handledBoxes = {} -- interface -> true while it is open and has been handled

-- A box staying open for the next line is filled again without closing, and the game sets its head again. These
-- variables arrive a frame before that (the pair box: PAGEPOS only), so the boxes are checked for a few frames after.
local DIALOGUE_UPDATE_VARIABLE_IDS = {}
for _, name in ipairs({ "CHAT_V3_UPDATE_INTERFACE", "PAGEPOS" }) do
    local variableID = GameIds.playerVariable(name)
    if variableID ~= nil then DIALOGUE_UPDATE_VARIABLE_IDS[variableID] = true end
end
local FRAMES_TO_RECHECK = 5
local framesToRecheck = 0
local VARIABLE_SUBSCRIPTION = "make_me_a_monster_dialogue_update"
local RECHECK_SUBSCRIPTION = "make_me_a_monster_dialogue_recheck"
local listeningForUpdates = false

-- Draw is subscribed to for just these frames.
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

local function startListeningForUpdates()
    if listeningForUpdates then return end
    Event.VarTransmit.Subscribe(VARIABLE_SUBSCRIPTION, onVariableTransmitted)
    listeningForUpdates = true
end

local function stopListeningIfNoBoxHandled()
    if not listeningForUpdates or handledBoxes[PLAYER_LINE_INTERFACE] or handledBoxes[PAIR_INTERFACE] then return end
    Event.VarTransmit.Unsubscribe(VARIABLE_SUBSCRIPTION)
    listeningForUpdates = false
end

-- A box just opened: its player heads swapped, or the NPC's animation noted. The game may fill a box's head only after
-- the box is seen open: so the boxes are checked again for a few frames.
local function handleBox(interface)
    local heads = HEADS_OF_BOX[interface]
    if heads ~= nil then
        startListeningForUpdates()
        visitHeads(swapHeadVisit, heads)
    elseif Settings.chosenNpcID ~= nil then
        visitHeads(learnNpcSpeechAnimation, NPC_SPEECH_HEADS)
    end
    recheckForAFewFrames()
end

local function forgetBox(interface)
    handledBoxes[interface] = nil
    stopListeningIfNoBoxHandled()
    for _, componentKey in ipairs(HEADS_OF_BOX[interface] or {}) do
        writtenAnimation[componentKey], gameAnimation[componentKey], swappedHeads[componentKey] = nil, nil, nil
    end
end

-- The open boxes follow a new head, animation or size.
function HeadSwap.refreshOpenDialogues()
    forEachOpenHeadComponent(swapHeadVisit)
    if Settings.chosenNpcID ~= nil and isInterfaceOpen(NPC_SPEECH_INTERFACE) then
        visitHeads(learnNpcSpeechAnimation, NPC_SPEECH_HEADS)
    end
end

local function watchBox(interface)
    if isInterfaceOpen(interface) then
        if not handledBoxes[interface] then
            handledBoxes[interface] = true
            handleBox(interface)
        end
    elseif handledBoxes[interface] then
        forgetBox(interface)
    end
end

-- Dialogue boxes open and close only as the server says: so this runs on ServerLogic, not every frame.
-- The NPC's own animation is only used with an NPC head, so that box is watched only then.
local function watchBoxes()
    watchBox(PLAYER_LINE_INTERFACE)
    watchBox(PAIR_INTERFACE)
    if Settings.chosenNpcID ~= nil then
        watchBox(NPC_SPEECH_INTERFACE)
    elseif handledBoxes[NPC_SPEECH_INTERFACE] then
        forgetBox(NPC_SPEECH_INTERFACE)
    end
end

local WATCH_SUBSCRIPTION = "make_me_a_monster_dialogue_watch"

function HeadSwap.start()
    Event.ServerLogic.Subscribe(WATCH_SUBSCRIPTION, watchBoxes)
end

-- The open boxes get the player's head back: the game would only set it again for the next line.
function HeadSwap.stop()
    Event.ServerLogic.Unsubscribe(WATCH_SUBSCRIPTION)
    forEachOpenHeadComponent(restoreComponentHead)
    handledBoxes = {}
    stopListeningIfNoBoxHandled()
    stopRechecking()
end

-- Logout: nothing is watched until the game is entered again.
function HeadSwap.reset()
    HeadSwap.stop()
    writtenAnimation, gameAnimation, swappedHeads = {}, {}, {}
    AnimationChoice.forgetGameAnimation()
end

return HeadSwap
