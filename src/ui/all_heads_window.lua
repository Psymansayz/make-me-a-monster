-- The "all heads" window: every listed chat head in a paged grid (src/ui/head_grid.lua), with a search by name or id.
-- AllHeadsWindow.open(PrettyUI, parent, heads, current, onPick, nameOf); close(); isOpen(); updateAnimations();
-- refreshHeadSize().

local Settings = require("src/data/settings")
local HeadGrid = require("src/ui/head_grid")

local AllHeadsWindow = {}

AllHeadsWindow.animationForNpcHeads = nil -- function(npcID) -> the animation id this head should play, or nil
AllHeadsWindow.onClosed = nil -- function(): called when the window has closed, however it was closed

local grid = nil -- the HeadGrid while the window is open

-- The lower case names of the heads listed, for the search box: made once for a list (the same list is given every
-- time the window opens).
local loweredNamesOfList, loweredNames = nil, nil

-- The heads whose name or id holds every word of the search text (all of them if it is blank).
local function matchingHeads(heads, text)
    local words = {}
    for word in text:lower():gmatch("%S+") do words[#words + 1] = word end
    if #words == 0 then return heads end
    local matching = {}
    for _, npcID in ipairs(heads) do
        local haystack = (loweredNames[npcID] or "") .. " " .. npcID
        local matches = true
        for _, word in ipairs(words) do
            if not haystack:find(word, 1, true) then
                matches = false
                break
            end
        end
        if matches then matching[#matching + 1] = npcID end
    end
    return matching
end

function AllHeadsWindow.isOpen()
    return grid ~= nil
end

function AllHeadsWindow.updateAnimations()
    if grid then grid:updateAnimations() end
end

function AllHeadsWindow.refreshHeadSize()
    if grid then grid:refreshHeadSize() end
end

function AllHeadsWindow.close()
    if grid then grid:close() end
end

function AllHeadsWindow.open(PrettyUI, parent, heads, current, onPick, nameOf)
    AllHeadsWindow.close()
    if loweredNamesOfList ~= heads then
        loweredNames = {}
        for _, npcID in ipairs(heads) do loweredNames[npcID] = (nameOf(npcID) or ""):lower() end
        loweredNamesOfList = heads
    end
    grid = HeadGrid.open(PrettyUI, parent, {
        title = "All heads", columns = 5, rows = 4,
        minWidth = 640, -- (room for the buttons and boxes in the bottom row)
        ids = heads, current = current,
        savedWidth = Settings.galleryWidth, savedHeight = Settings.galleryHeight,
        savedX = Settings.galleryX, savedY = Settings.galleryY,
        withSearch = true,
        nameOf = nameOf,
        animationFor = function(npcID)
            return AllHeadsWindow.animationForNpcHeads and AllHeadsWindow.animationForNpcHeads(npcID) or nil
        end,
        pageLabel = function(page, pages, shown)
            return ("Page %d of %d (%d heads%s)"):format(page, pages, shown, shown < #heads and " found" or "")
        end,
        onPick = onPick,
        onSearch = function(text) grid:setHeads(matchingHeads(heads, text), grid.current) end,
        onPlacement = function(width, height, x, y)
            Settings.galleryWidth, Settings.galleryHeight, Settings.galleryX, Settings.galleryY = width, height, x, y
        end,
        onClosed = function()
            grid = nil
            if AllHeadsWindow.onClosed then pcall(AllHeadsWindow.onClosed) end
        end,
    })
    return grid ~= nil
end

return AllHeadsWindow
