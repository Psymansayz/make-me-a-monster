-- The "all heads" window: every listed chat head in a paged grid, with a search by name or id and a check box for one
-- head of each group or every head.

local Settings = require("src/data/settings")
local NpcDirectory = require("src/game/npc_directory")
local AnimationChoice = require("src/game/animation_choice")
local HeadGrid = require("src/ui/head_grid")

local AllHeadsWindow = {}

AllHeadsWindow.onClosed = nil -- function(): called when the window has closed, however it was closed

local grid = nil -- the HeadGrid while the window is open
HeadGrid.addWindowFunctions(AllHeadsWindow, function() return grid end)

-- { id -> name } of the heads a search chose with one head per group, each as what the search matched.
local searchedNames = nil

-- The heads for the search text, and their names if the search chose them. With one head per group, a head goes by
-- every member of its group.
local function matchingHeads(heads, text)
    searchedNames = nil
    local words = NpcDirectory.wordsOfQuery(text)
    if words.blank then return heads end
    if #words == 0 then return {} end -- (symbols only)
    if Settings.oneHeadPerGroup then
        local matching, names = NpcDirectory.headsMatching(heads, words)
        searchedNames = names
        return matching
    end
    return NpcDirectory.headsHolding(heads, words)
end

-- Opening it again brings it to the front.
function AllHeadsWindow.open(PrettyUI, parent, current, onPick)
    if AllHeadsWindow.isOpen() then
        grid.window:Show()
        return
    end
    local searchText = ""
    searchedNames = nil
    -- Fetched each time, not kept here: the every-head list is only made while "One per group" is unticked. Its count
    -- is kept for the page label.
    local listedCount = 0
    local function headsListed()
        local heads = Settings.oneHeadPerGroup and NpcDirectory.headsOfEachGroup() or NpcDirectory.headsInNameOrder()
        listedCount = #heads
        return heads
    end
    local function nameShown(npcID)
        if searchedNames then return searchedNames[npcID] end
        return (Settings.oneHeadPerGroup and NpcDirectory.nameForGroupOfNpc or NpcDirectory.nameOfNpc)(npcID)
    end
    grid = HeadGrid.open(PrettyUI, parent, {
        title = "All heads", columns = 5, rows = 4,
        minWidth = 770, -- (room for the buttons and boxes in the bottom row)
        ids = headsListed(), current = current,
        placement = Settings.windows.allHeads,
        withSearch = true,
        toggle = {
            text = "One per group", selected = Settings.oneHeadPerGroup,
            onChange = function(selected)
                Settings.oneHeadPerGroup = selected
                grid:setHeads(matchingHeads(headsListed(), searchText), grid.current, nil, grid.page)
            end,
        },
        nameOf = nameShown,
        -- (NPC heads: the NPC version of the animation chosen, whichever head is in use)
        animationFor = function(npcID) return AnimationChoice.npcHeadAnimation(npcID) end,
        pageLabel = function(page, pages, shown)
            local counted = Settings.oneHeadPerGroup and "groups" or "heads"
            return ("Page %d of %d (%d %s%s)"):format(page, pages, shown, counted,
                shown < listedCount and " found" or "")
        end,
        onPick = function(npcID) onPick(npcID, nameShown(npcID)) end, -- (with the name it was picked under)
        -- (Enter sends the text again)
        onSearch = function(text)
            if text == searchText then return end
            searchText = text
            grid:setHeads(matchingHeads(headsListed(), text), grid.current)
        end,
        onClosed = function()
            grid = nil
            AllHeadsWindow.onClosed()
        end,
    })
end

return AllHeadsWindow
