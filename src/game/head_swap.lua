-- Replaces the player's chat head in the game's dialogue boxes with an NPC's head.
--
-- The boxes' own head components are ui.Models, so a player head (ModelType PLAYER_HEAD) is turned into an
-- NPC head with Model:SetModel. Checked every frame: the game sets the player's head again whenever it
-- fills or lays out a box, so it would otherwise flash up or come back.

local Anims = require("src/game/anims")
local Settings = require("src/data/settings")
local Animations = require("src/data/animations")

local HeadSwap = {}

HeadSwap.playerAnim = nil   -- the animation the game last set on the player's head, before it was swapped

-- Interfaces with a player head: the player's line (CHAT_V2_RIGHT) and two heads at once (CHAT_V2_PAIR).
-- The ids are as seen in game; id.Interface is preferred when it has them.
local function interfaceID(name, fallback)
    local ok, value = pcall(function() return id.Interface[name] end)
    return ok and type(value) == "number" and value or fallback
end
local INTERFACES = {
    interfaceID("CHAT_V2_RIGHT", 1191),
    interfaceID("CHAT_V2_PAIR", 1187),
}
local MAX_SCAN_ID = 40 -- the boxes' head components are among their first statics

local NPC_BOX = interfaceID("CHAT_V2_LEFT", 1184) -- the NPC's line: its head is always the NPC's own

local PLAYER_HEAD = 3 -- ui.ModelType values
local NPC_HEAD = 2

local headStatics = {} -- interfaceID -> static ids of its model components (their type doesn't change)

-- The static ids of an interface's model components, found once it is loaded; nil while it isn't.
local function modelStatics(interface)
    local statics = headStatics[interface]
    if statics ~= nil then return statics end
    if ui.Interfaces:GetInterface(interface) == nil then return nil end
    statics = {}
    local MODEL = ui.ComponentType.MODEL
    for staticID = 0, MAX_SCAN_ID do
        local ok, isModel = pcall(function()
            local component = ui.Interfaces:GetComponent(interface, staticID)
            return component ~= nil and component.type == MODEL
        end)
        if ok and isModel then statics[#statics + 1] = staticID end
    end
    headStatics[interface] = statics
    return statics
end


-- The animation an NPC's head should play (never a player's animation: they don't play on an NPC's head): the
-- player's choice as its NPC version, else the NPC version of the animation the game set on the player's head for the
-- line (HeadSwap.playerAnim, see npcTwin), and only if that has none, the one last seen on a real NPC's head.
local function npcHeadAnim()
    local chosen = Settings.animOverride
    if chosen ~= nil then return HeadSwap.animForHead(chosen, false) end
    return HeadSwap.playerAnim or Settings.animID
end

-- The animation the player's own head plays for the animation chosen (which is one for an NPC's head): its
-- HUMAN_ACTOR twin from src/data/animations.lua, else evil laugh. With none chosen:
-- the neutral one if asked for (withNeutral, for a head shown outside dialogue), else nil.
function HeadSwap.playerHeadAnim(withNeutral)
    local chosen = Settings.animOverride
    if chosen == nil then return withNeutral and Animations.neutral or nil end
    return HeadSwap.animForHead(chosen, true) -- (never an NPC animation: it is changed to the player's version)
end

-- The listed animation that has each player animation as its twin (the lowest id if several), made once from
-- Animations.twin and Animations.alsoFor. (The player's head animations don't play on an NPC's head, their NPC twins do.)
local npcTwin = {}
for npcAnim, playerAnim in pairs(Animations.twin) do
    if npcTwin[playerAnim] == nil or npcAnim < npcTwin[playerAnim] then npcTwin[playerAnim] = npcAnim end
end
for playerAnim, npcAnim in pairs(Animations.alsoFor) do npcTwin[playerAnim] = npcAnim end

-- The animation to keep when the head changes between the player's own and an NPC's, which play different
-- animations: for the player's own head the twin of an NPC animation; for an NPC head the animation that has this
-- one as its twin. Where there is none, evil laugh (of the kind the head plays).
function HeadSwap.animForHead(animID, playerHead)
    if animID == nil then return nil end
    local isPlayers = Anims.isPlayer(animID)
    if playerHead then
        if isPlayers then return animID end
        return Animations.twin[animID] or Animations.fallback
    end
    if not isPlayers then return animID end
    return npcTwin[animID] or npcTwin[Animations.fallback]
end

function HeadSwap.animate(component)
    local anim = npcHeadAnim()
    if anim ~= nil and component.animID ~= anim then component.animID = anim end
end

-- Whether an interface is open now (a cheap check, so a closed box costs nothing each frame).
local function isOpen(interface)
    local ok, opened = pcall(function() return ui.Interfaces:GetInterface(interface) ~= nil end)
    return ok and opened
end

-- Notes the animation of the NPC speech box's head, for the swapped head to use.
local function learn()
    if not isOpen(NPC_BOX) then return end
    local statics = modelStatics(NPC_BOX)
    if statics == nil then return end
    for _, staticID in ipairs(statics) do
        local component = ui.Interfaces:GetComponent(NPC_BOX, staticID)
        if component.visibleGlobal == true and tonumber(component.modelType) == NPC_HEAD then
            local anim = tonumber(component.animID)
            if anim ~= nil and anim >= 0 and anim ~= Settings.animID then
                Settings.setAnim(anim)
            end
        end
    end
end

-- The animation id the swapped head plays (or nil), for other windows showing NPC heads.
function HeadSwap.currentAnim()
    return npcHeadAnim()
end

local scaled = {} -- component key -> { original, written }: the view distance the game set, and the one written
-- The player's own head, left in place and given the animation chosen: component key -> the animation written, and
-- the one the game set (to put back when the choice is cleared).
local written, gameAnim = {}, {}
-- A player head turned into an NPC's: component key -> { npc = the NPC's id, anim = the animation the game set on the
-- player's head }, to change the head when another NPC is chosen and to put the player's head back.
local swapped = {}

-- The head drawn Settings.headScale times larger by moving the camera closer: the view distance is the game's divided
-- by the scale. The game sets the view distance itself when it fills a box, so a value other than the one written
-- is the game's, and becomes the new original. (Only as large as the box's own space: more of the head than that
-- is cut off at its edge.)
-- Workaround: a component is looked up again each frame and may be a different object, so it is told apart by its
-- key (interface and static id), not itself.
local function applyScale(key, component)
    local current = component.viewDistance
    if type(current) ~= "number" then return end
    local record = scaled[key]
    if Settings.headScale <= 1 then
        if record ~= nil and current == record.written then component.viewDistance = record.original end
        scaled[key] = nil
        return
    end
    if record == nil or current ~= record.written then
        record = { original = current }
        scaled[key] = record
    end
    local wanted = math.max(1, math.floor(record.original / Settings.headScale + 0.5))
    if current ~= wanted then component.viewDistance = wanted end
    record.written = wanted
end

-- One model component: a shown player head becomes the NPC's head. With no NPC chosen (npcID nil), the
-- player's own head stays, playing the animation the player picked. Either way it is drawn at the size set.
local function swap(component, npcID, key)
    if component.visibleGlobal ~= true then
        scaled[key], written[key], gameAnim[key], swapped[key] = nil, nil, nil, nil
        return
    end
    local modelType = tonumber(component.modelType)
    local ours = swapped[key]
    if ours ~= nil and (ours.npc == npcID or modelType ~= NPC_HEAD or component.modelID1 ~= ours.npc) then
        -- (still ours with the same NPC, or the game has set the head again: nothing to change)
        if ours.npc ~= npcID then swapped[key] = nil end
        ours = nil
    end
    if npcID == nil then
        if ours ~= nil then
            -- "Use my own head": the player's head again, with the animation the game had set on it.
            swapped[key] = nil
            component:SetModel(ui.ModelType.PLAYER_HEAD, -1)
            if ours.anim ~= nil then component.animID = ours.anim end
            modelType = tonumber(component.modelType)
        end
        if modelType == PLAYER_HEAD then
            local current = tonumber(component.animID)
            local mine = written[key]
            if mine == nil or current ~= mine then gameAnim[key] = current end -- (the game set it)
            local anim = HeadSwap.playerHeadAnim(false)
            if anim ~= nil then
                if current ~= anim then component.animID = anim end
                written[key] = anim
            elseif mine ~= nil then
                -- The choice was cleared: the game's animation again (unless the game has set another since).
                if current == mine and gameAnim[key] ~= nil then component.animID = gameAnim[key] end
                written[key], gameAnim[key] = nil, nil
            end
            applyScale(key, component)
        end
        return
    end
    if ours ~= nil then
        -- Another NPC chosen: its head in place of the one shown.
        ours.npc = npcID
        component:SetModel(ui.ModelType.NPC_HEAD, npcID)
        HeadSwap.animate(component)
        applyScale(key, component)
        return
    end
    if modelType == NPC_HEAD and component.modelID1 == npcID then
        HeadSwap.animate(component) -- (already ours: the animation kept up)
        applyScale(key, component)
        return
    end
    if modelType ~= PLAYER_HEAD then return end -- an NPC's own head stays
    local anim = component.animID
    -- The animation the game chose for the player's head on this line (the speaker's expression).
    local playerAnim = tonumber(anim)
    if playerAnim ~= nil and playerAnim >= 0 then
        HeadSwap.playerAnim = npcTwin[playerAnim]
    end
    swapped[key] = { npc = npcID, anim = playerAnim }
    component:SetModel(ui.ModelType.NPC_HEAD, npcID)
    HeadSwap.animate(component)
    applyScale(key, component)
end

-- Every frame.
function HeadSwap.tick()
    local npcID = Settings.npcID
    if npcID ~= nil then pcall(learn) end -- (the NPC's own animation is only used with an NPC's head)
    -- (nothing to do with no NPC, no animation chosen, normal size and no size left to put back)
    if npcID == nil and Settings.animOverride == nil and Settings.headScale <= 1 and next(scaled) == nil and next(written) == nil
        and next(swapped) == nil then return end
    for _, interface in ipairs(INTERFACES) do
        local ok, statics = false, nil
        if isOpen(interface) then ok, statics = pcall(modelStatics, interface) end
        if ok and statics ~= nil then
            for _, staticID in ipairs(statics) do
                pcall(function()
                    swap(ui.Interfaces:GetComponent(interface, staticID), npcID, interface .. ":" .. staticID)
                end)
            end
        end
    end
end

-- Logout: the boxes are gone, so what was found about them is looked up again.
function HeadSwap.reset()
    headStatics = {}
    scaled, written, gameAnim, swapped = {}, {}, {}, {}
end

return HeadSwap
