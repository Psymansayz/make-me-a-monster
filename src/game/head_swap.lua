-- Replaces the player's chat head in the game's dialogue boxes with an NPC's head.
--
-- The boxes' own head components are ui.Models, so a player head (ModelType PLAYER_HEAD) is turned into an
-- NPC head with Model:SetModel. Checked every frame: the game sets the player's head again whenever it
-- fills or lays out a box, so it would otherwise flash up or come back.

local Anims = require("src/game/anims")
local Settings = require("src/data/settings")
local Animations = require("src/data/animations")

local HeadSwap = {}

HeadSwap.rawPlayerAnim = nil -- the same, as the game set it
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


-- The animation the swapped head should play: the player's choice, else the one the game set on the player's head
-- for the line (HeadSwap.playerAnim, see npcTwinOf). Then, with an NPC's head chosen, the one last seen on a real NPC's
-- head (Settings.animID) and then the game's own animation as it is (HeadSwap.rawPlayerAnim); with the player's own
-- head, only the game's own animation (a real NPC's has nothing to do with it).
local function wantedAnim()
    local wanted = Settings.animOverride or HeadSwap.playerAnim
    if wanted ~= nil then return wanted end
    if Settings.npcID ~= nil then return Settings.animID or HeadSwap.rawPlayerAnim end
    return HeadSwap.rawPlayerAnim
end

-- The animation the player's own head plays for the animation chosen (which is one for an NPC's head): its
-- HUMAN_ACTOR twin from src/data/animations.lua, else the one chosen as it is. With none chosen:
-- the neutral one if asked for (withNeutral, for a head shown outside dialogue), else nil.
function HeadSwap.playerHeadAnim(withNeutral)
    local chosen = Settings.animOverride
    if chosen == nil then return withNeutral and Animations.neutral or nil end
    return Animations.twin[chosen] or chosen
end

-- The listed animation that has this player animation as its twin (the lowest id if several), or nil. (The player's
-- head animations don't play on an NPC's head, their NPC twins do.)
local function npcTwinOf(actorID)
    if Animations.alsoFor[actorID] ~= nil then return Animations.alsoFor[actorID] end
    local best = nil
    for npcAnim, twinID in pairs(Animations.twin) do
        if twinID == actorID and (best == nil or npcAnim < best) then best = npcAnim end
    end
    return best
end

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
    return npcTwinOf(animID) or npcTwinOf(Animations.fallback)
end

function HeadSwap.animate(component)
    local anim = wantedAnim()
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
    return wantedAnim()
end

local scaled = {} -- component key -> { original, written }: the view distance the game set, and the one written

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
        scaled[key] = nil
        return
    end
    local modelType = tonumber(component.modelType)
    if npcID == nil then
        if modelType == PLAYER_HEAD then
            local anim = HeadSwap.playerHeadAnim(false)
            if anim ~= nil and component.animID ~= anim then component.animID = anim end
            applyScale(key, component)
        end
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
        HeadSwap.rawPlayerAnim, HeadSwap.playerAnim = playerAnim, npcTwinOf(playerAnim)
    end
    component:SetModel(ui.ModelType.NPC_HEAD, npcID)
    HeadSwap.animate(component)
    applyScale(key, component)
end

-- Every frame.
function HeadSwap.tick()
    local npcID = Settings.npcID
    if npcID ~= nil then pcall(learn) end -- (the NPC's own animation is only used with an NPC's head)
    -- (nothing to do with no NPC, no animation chosen, normal size and no size left to put back)
    if npcID == nil and Settings.animOverride == nil and Settings.headScale <= 1 and next(scaled) == nil then return end
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
end

return HeadSwap
