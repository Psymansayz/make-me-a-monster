-- Debug only: reads every animation in the game (config.Seq), a few hundred ids a frame, for the debug window that
-- plays them on Hans. (The plugin itself looks up only the whitelisted animations, see src/game/animations.lua.)
--
-- AnimationScan.step(): call every frame until AnimationScan.done. AnimationScan.list = { { id, name }... } in id order.

local AnimationScan = {}

AnimationScan.list = {}
AnimationScan.done = false
AnimationScan.scanned = 0 -- ids tried so far

local PER_FRAME = 400
local MAX_ID = 300000
-- Workaround: config.Seq has no length or iterator, so the scan ends after this many ids in a row that don't exist
-- (past the first MIN_ID, which may contain gaps).
local MISS_LIMIT = 3000
local MIN_ID = 5000
local misses = 0

function AnimationScan.step()
    if AnimationScan.done then return end
    for _ = 1, PER_FRAME do
        local animID = AnimationScan.scanned
        AnimationScan.scanned = animID + 1
        local succeeded, name = pcall(function() return config.Seq.FromID(animID).configName end)
        if succeeded and type(name) == "string" then
            misses = 0
            if name ~= "" then AnimationScan.list[#AnimationScan.list + 1] = { id = animID, name = name } end
        else
            misses = misses + 1
        end
        if animID >= MAX_ID or (animID >= MIN_ID and misses >= MISS_LIMIT) then
            AnimationScan.done = true
            return
        end
    end
end

return AnimationScan
