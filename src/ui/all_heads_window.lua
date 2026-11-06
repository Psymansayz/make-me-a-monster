-- The "all heads" window: every listed chat head in a paged grid (src/ui/head_grid.lua), with a search by name or id
-- and a check box for one head of each group or every head.
-- AllHeadsWindow.open(PrettyUI, parent, heads, headsOfEachGroup, current, onPick, nameOf, nameForGroupOf,
-- headsMatching); close(); isOpen(); updateAnimations(); refreshHeadSize().

local Settings = require("src/data/settings")
local HeadGrid = require("src/ui/head_grid")

local AllHeadsWindow = {}

AllHeadsWindow.animationForNpcHeads = nil -- function(npcID) -> the animation id this head should play, or nil
AllHeadsWindow.onClosed = nil -- function(): called when the window has closed, however it was closed

local grid = nil -- the HeadGrid while the window is open

-- The lower case names of the heads listed, for the search box: made once for a list (the same list is given every
-- time the window opens).
local loweredNamesOfList, loweredNames = nil, nil

-- { id -> name } of the heads a search chose with one head per group, each as what the search matched.
local searchedNames = nil

-- The heads for the search text (all of them if it is blank), and their names if the search chose them. Every head goes
-- by its name or id; with one head per group, by every member of its group: headsMatching(heads, words).
local function matchingHeads(heads, text, headsMatching)
    searchedNames = nil
    local words = {}
    for word in text:lower():gmatch("%S+") do words[#words + 1] = word end
    if #words == 0 then return heads end
    if Settings.oneHeadPerGroup then
        local matching, names = headsMatching(heads, words)
        searchedNames = names
        return matching
    end
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

function AllHeadsWindow.open(PrettyUI, parent, heads, headsOfEachGroup, current, onPick, nameOf, nameForGroupOf,
    headsMatching)
    AllHeadsWindow.close()
    local searchText = ""
    searchedNames = nil
    local function headsListed() return Settings.oneHeadPerGroup and headsOfEachGroup or heads end
    local function nameShown(npcID)
        if searchedNames then return searchedNames[npcID] end
        return (Settings.oneHeadPerGroup and nameForGroupOf or nameOf)(npcID)
    end
    if loweredNamesOfList ~= heads then
        loweredNames = {}
        for _, npcID in ipairs(heads) do loweredNames[npcID] = (nameOf(npcID) or ""):lower() end
        loweredNamesOfList = heads
    end
    grid = HeadGrid.open(PrettyUI, parent, {
        title = "All heads", columns = 5, rows = 4,
        minWidth = 770, -- (room for the buttons and boxes in the bottom row)
        ids = headsListed(), current = current,
        savedWidth = Settings.galleryWidth, savedHeight = Settings.galleryHeight,
        savedX = Settings.galleryX, savedY = Settings.galleryY,
        withSearch = true,
        toggle = {
            text = "One per group", selected = Settings.oneHeadPerGroup,
            onChange = function(selected)
                Settings.oneHeadPerGroup = selected
                grid:setHeads(matchingHeads(headsListed(), searchText, headsMatching), grid.current, nil, true)
            end,
        },
        nameOf = nameShown,
        animationFor = function(npcID)
            return AllHeadsWindow.animationForNpcHeads and AllHeadsWindow.animationForNpcHeads(npcID) or nil
        end,
        pageLabel = function(page, pages, shown)
            local counted = Settings.oneHeadPerGroup and "groups" or "heads"
            return ("Page %d of %d (%d %s%s)"):format(page, pages, shown, counted,
                shown < #headsListed() and " found" or "")
        end,
        onPick = function(npcID) onPick(npcID, nameShown(npcID)) end, -- (with the name it was picked under)
        onSearch = function(text)
            searchText = text
            grid:setHeads(matchingHeads(headsListed(), text, headsMatching), grid.current)
        end,
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
