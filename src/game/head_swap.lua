-- Replaces the player's chat head in the game's dialogue boxes with an NPC's head.
--
-- The boxes' own head components are ui.Models, so a player head (ModelType PLAYER_HEAD) is turned into an
-- NPC head with Model:SetModel. Checked every frame: the game sets the player's head again whenever it
-- fills or lays out a box, so it would otherwise flash up or come back.

local Anims = require("src/game/anims")
local PlayerAnims = require("src/data/player_head_animations")

local HeadSwap = {}

HeadSwap.npcID = nil   -- the NPC whose head is shown, or nil to leave the boxes alone
HeadSwap.scale = 1 -- how many times larger than the game draws it the player's head is drawn (1: as the game does)
HeadSwap.animOverride = nil -- an animation id chosen by the player, used for the swapped head
HeadSwap.rawPlayerAnim = nil -- the same, as the game set it
HeadSwap.playerAnim = nil   -- the animation the game last set on the player's head, before it was swapped
HeadSwap.learnedAnim = nil  -- the animation last seen on a real NPC's head in the NPC speech box
HeadSwap.onLearned = nil    -- function(animID): called when a new one is seen

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


-- The animation the swapped head should play: the player's choice, else the one the game set on the player's
-- head for the line (HeadSwap.playerAnim, see npcVersion), else the one seen on a real NPC's head, else the
-- game's own animation as it is (HeadSwap.rawPlayerAnim).
local function wantedAnim()
    return HeadSwap.animOverride or HeadSwap.playerAnim or HeadSwap.learnedAnim or HeadSwap.rawPlayerAnim
end

-- The name of an animation, for the log.
local function animName(animID)
    local ok, name = pcall(function() return config.Seq.FromID(animID).configName end)
    return ok and tostring(name) or "?"
end

-- Workaround: the player's head animations named HUMAN_ACTOR_... don't play on an NPC's head, but the
-- HUMAN_UPDATE_... one for the same expression does. Chat head animations are matched by Anims.matching
-- (the names differ: ACTOR SHOCK_STANDARD is UPDATE SURPRISED_NORMAL_LEN1); others by the same name with
-- HUMAN_UPDATE for HUMAN_ACTOR. The id of that one if it exists; the id given if it isn't a HUMAN_ACTOR
-- one; else nil (the last NPC's animation is used instead).
local function npcVersion(animID)
    local name = animName(animID)
    if Anims.prefixOf(name) == Anims.PREFIX_OWN then
        local match = Anims.matching(Anims.PREFIX_NPC, Anims.keyOf(name))
        return match and match.id or nil
    end
    local rest = name:match("^HUMAN_ACTOR(.*)$")
    if rest == nil then return animID end
    local ok, other = pcall(function() return config.Seq["HUMAN_UPDATE" .. rest] end)
    local otherID = ok and other ~= nil and tonumber(other.id) or nil
    return otherID
end

-- The animation the player's own head plays for the animation chosen (which is one for an NPC's head): its
-- HUMAN_ACTOR twin from src/data/player_head_animations.lua, else the one chosen as it is. With none chosen:
-- the neutral one if asked for (withNeutral, for a head shown outside dialogue), else nil.
function HeadSwap.ownHeadAnim(withNeutral)
    local chosen = HeadSwap.animOverride
    if chosen == nil then return withNeutral and PlayerAnims.neutral or nil end
    return PlayerAnims.twin[chosen] or chosen
end

-- The animation to keep when the head changes between the player's own and an NPC's, which play different
-- animations: for the player's own head the twin of an NPC animation, or evil laugh if it has none (an animation
-- for the player's head stays); for an NPC head the animation that has this one as its twin, or nil if none.
function HeadSwap.animForHead(animID, ownHead)
    if animID == nil then return nil end
    local isPlayers = false
    for _, actorID in ipairs(PlayerAnims.actors) do
        if actorID == animID then isPlayers = true break end
    end
    if ownHead then
        if isPlayers then return animID end
        return PlayerAnims.twin[animID] or PlayerAnims.fallback
    end
    if not isPlayers then return animID end
    if PlayerAnims.alsoFor[animID] ~= nil then return PlayerAnims.alsoFor[animID] end
    local best = nil
    for npcAnim, actorID in pairs(PlayerAnims.twin) do
        if actorID == animID and (best == nil or npcAnim < best) then best = npcAnim end
    end
    return best
end

function HeadSwap.animate(component)
    local anim = wantedAnim()
    if anim ~= nil and component.animID ~= anim then component.animID = anim end
end

-- Notes the animation of the NPC speech box's head, for the swapped head to use.
local function learn()
    local statics = modelStatics(NPC_BOX)
    if statics == nil then return end
    for _, staticID in ipairs(statics) do
        local component = ui.Interfaces:GetComponent(NPC_BOX, staticID)
        if component.visibleGlobal == true and tonumber(component.modelType) == NPC_HEAD then
            local anim = tonumber(component.animID)
            if anim ~= nil and anim >= 0 and anim ~= HeadSwap.learnedAnim then
                HeadSwap.learnedAnim = anim
                if HeadSwap.onLearned then HeadSwap.onLearned(anim) end
            end
        end
    end
end

-- The animation id the swapped head plays (or nil), for other windows showing NPC heads.
function HeadSwap.currentAnim()
    return wantedAnim()
end

local scaled = {} -- component key -> { original, written }: the view distance the game set, and the one written

-- The head drawn HeadSwap.scale times larger by moving the camera closer: the view distance is the game's divided
-- by the scale. The game sets the view distance itself when it fills a box, so a value other than the one written
-- is the game's, and becomes the new original. (Only as large as the box's own space: more of the head than that
-- is cut off at its edge.)
-- Workaround: a component is looked up again each frame and may be a different object, so it is told apart by its
-- key (interface and static id), not itself.
local function applyScale(key, component)
    local current = component.viewDistance
    if type(current) ~= "number" then return end
    local record = scaled[key]
    if HeadSwap.scale <= 1 then
        if record ~= nil and current == record.written then component.viewDistance = record.original end
        scaled[key] = nil
        return
    end
    if record == nil or current ~= record.written then
        record = { original = current }
        scaled[key] = record
    end
    local wanted = math.max(1, math.floor(record.original / HeadSwap.scale + 0.5))
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
            local anim = HeadSwap.ownHeadAnim(false)
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
        HeadSwap.rawPlayerAnim, HeadSwap.playerAnim = playerAnim, npcVersion(playerAnim)
    end
    component:SetModel(ui.ModelType.NPC_HEAD, npcID)
    HeadSwap.animate(component)
    applyScale(key, component)
end

-- Every frame.
function HeadSwap.tick()
    pcall(learn)
    local npcID = HeadSwap.npcID
    -- (nothing to do with no NPC, no animation chosen, normal size and no size left to put back)
    if npcID == nil and HeadSwap.animOverride == nil and HeadSwap.scale <= 1 and next(scaled) == nil then return end
    for _, interface in ipairs(INTERFACES) do
        local ok, statics = pcall(modelStatics, interface)
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
