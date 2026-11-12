-- Debug only: lists every animation in the game for the debug window that plays them on Hans.

local AnimationScan = {}

AnimationScan.list = {}
AnimationScan.done = false
AnimationScan.scanned = 0 -- ids tried so far

local PER_FRAME = 400
local MAX_ID = 300000
-- config.Seq has no length or iterator, so the scan stops after this many missing ids in a row. The low ids have
-- gaps, so this only applies past MIN_ID.
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
