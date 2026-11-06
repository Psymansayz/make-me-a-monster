-- TEMPORARY debug window: every chat head left after the filtering, as a paged grid (like the variants window),
-- for finding the ones that should be blacklisted. Clicking a head flags it (it turns red) and logs its id; click
-- it again to take the flag off. "Log flagged" prints every flagged id in one line, ready to paste into
-- src/data/head_blacklist.lua. A search box narrows the heads by name or id, and a page box jumps to a page.
--
-- HeadFlaggingWindow.open(PrettyUI, parent, heads, nameOf, animFor, options): heads = { id... } in the order shown.
-- options (all optional) lets the same window show and flag other things than heads (the animations on Hans):
-- title; logLabel (the word the log lines start with, "blacklist" for heads); setup(model, id), which sets a cell's
-- model up in place of the NPC head and animation; tint(id), the colour { r, g, b, a } of a cell not flagged;
-- flaggedLines(ids), the lines "Log flagged" prints for the flagged ids (in place of the one line of ids);
-- logButton, that button's text; removeOnLog, the heads logged leave the window; quietClicks, no log line per click;
-- idText(id), the text under the name (in place of the id); secondLogButton and secondFlaggedLines(ids), another
-- log button beside the first, with its own lines; minWidth, the least the window can be resized to;
-- headClicked(id), given a click first, true if it used the click (no flag changes); labelNote(), text for the
-- bottom label in place of the head counts, or nil; firstLogKeeps(ids), the id of the head the first log button
-- leaves in the window (with removeOnLog).
-- HeadFlaggingWindow.tick(): every frame. HeadFlaggingWindow.close().

local HeadFlaggingWindow = {}

HeadFlaggingWindow.scaleFor = nil -- function() -> how many times larger than normal the heads are drawn (the head size setting)

local COLUMNS, ROWS = 5, 4
local PAGE_SIZE = COLUMNS * ROWS
local PAD, GAP = 8, 6
local NAV_HEIGHT = 36
local START_CELL_W, START_CELL_H = 150, 170
local MIN_CELL_W, MIN_CELL_H = 90, 110
local BORDERS, TITLE_AND_BOTTOM = 16, 40
local BASE_VIEW, BASE_SIZE = 2150, 160

local BACKGROUND = { 0.12, 0.09, 0.06, 1 }
local HOVER = { 0.30, 0.24, 0.14, 1 }
local FLAGGED = { 0.55, 0.10, 0.10, 1 }
local FLAGGED_HOVER = { 0.70, 0.20, 0.20, 1 }
local TEXT_LIGHT = 0xE9E5DDFF

local windowState = nil -- { window, logLabel, setup, tint, flaggedLines, all, shown, page, pages, flagged, cells, nav, nameOf, animFor, lowered, layoutW, layoutH }

local function say(message)
    print("[make_me_a_monster] " .. message)
end

local function toColour(colourValues) return Vector4.new(colourValues[1], colourValues[2], colourValues[3], colourValues[4]) end

local function destroyCells()
    for _, headCell in ipairs(windowState.cells) do
        pcall(function() headCell.click:Destroy() end)
        pcall(function() headCell.name:Destroy() end)
        pcall(function() headCell.idLabel:Destroy() end)
        pcall(function() headCell.model:Destroy() end)
        pcall(function() headCell.background:Destroy() end)
    end
    windowState.cells = {}
end

local function paintCell(headCell, hovered)
    local flagged = windowState.flagged[headCell.id]
    local base = windowState.tint and windowState.tint(headCell.id) or BACKGROUND
    local colourValues = flagged and (hovered and FLAGGED_HOVER or FLAGGED) or (hovered and HOVER or base)
    pcall(function() headCell.background.colour = toColour(colourValues) end)
end

local function flaggedLine()
    local variantIDs = {}
    for npcID in pairs(windowState.flagged) do variantIDs[#variantIDs + 1] = npcID end
    table.sort(variantIDs)
    return #variantIDs, table.concat(variantIDs, ", ")
end

local function updatePageLabel()
    local flaggedCount = 0
    for _ in pairs(windowState.flagged) do flaggedCount = flaggedCount + 1 end
    local note = windowState.labelNote and windowState.labelNote()
    pcall(function()
        windowState.nav.label.content = note
            and ("%s (page %d of %d)"):format(note, windowState.page, windowState.pages)
            or ("page %d of %d, %d heads%s, %d flagged"):format(windowState.page,
            windowState.pages, #windowState.shown, #windowState.shown < #windowState.all and " found" or "",
            flaggedCount)
    end)
end

local function toggle(headCell)
    local npcID = headCell.id
    if windowState.headClicked and windowState.headClicked(npcID) then
        updatePageLabel()
        return
    end
    if windowState.flagged[npcID] then
        windowState.flagged[npcID] = nil
        if not windowState.quietClicks then
            say(("%s removed: %d (%s)"):format(windowState.logLabel, npcID, windowState.nameOf(npcID) or "?"))
        end
    else
        windowState.flagged[npcID] = true
        if not windowState.quietClicks then
            say(("%s: %d (%s)"):format(windowState.logLabel, npcID, windowState.nameOf(npcID) or "?"))
        end
    end
    paintCell(headCell, true)
    updatePageLabel()
end

-- The grid for the window's content as it is now.
local function computeGeometry()
    local windowContent = windowState.window.content
    local width, height = windowContent.width, windowContent.height
    local cellW = math.max(40, math.floor((width - PAD * 2 - (COLUMNS - 1) * GAP) / COLUMNS))
    local cellH = math.max(60, math.floor((height - PAD * 2 - NAV_HEIGHT - 4 - (ROWS - 1) * GAP) / ROWS))
    local gridW = COLUMNS * cellW + (COLUMNS - 1) * GAP
    return {
        width = width, height = height, cellW = cellW, cellH = cellH,
        originX = math.max(0, math.floor((width - gridW) / 2)), originY = PAD,
        gridH = ROWS * cellH + (ROWS - 1) * GAP,
    }
end

-- The head size setting: how many times larger than normal the heads are drawn (1: normal).
local function currentHeadScale()
    local scale = HeadFlaggingWindow.scaleFor and HeadFlaggingWindow.scaleFor() or 1
    return type(scale) == "number" and scale >= 1 and scale or 1
end

local function placeCell(headCell, grid)
    local column, row = (headCell.index - 1) % COLUMNS, math.floor((headCell.index - 1) / COLUMNS)
    local x, y = grid.originX + column * (grid.cellW + GAP), grid.originY + row * (grid.cellH + GAP)
    local headSize = math.max(16, math.min(grid.cellW - 8, grid.cellH - 44))
    headCell.background:SetPos(x, y)
    headCell.background:SetSize(grid.cellW, grid.cellH)
    headCell.model:SetPos(x + math.floor((grid.cellW - headSize) / 2), y + 4)
    headCell.model:SetSize(headSize, headSize)
    headCell.model.viewDistance = math.max(1, math.floor(BASE_VIEW * BASE_SIZE / headSize / currentHeadScale()))
    headCell.name:SetPos(x, y + grid.cellH - 38)
    headCell.name:SetSize(grid.cellW, 16)
    headCell.idLabel:SetPos(x, y + grid.cellH - 20)
    headCell.idLabel:SetSize(grid.cellW, 16)
    headCell.click:SetPos(x, y)
    headCell.click:SetSize(grid.cellW, grid.cellH)
end

local function placeNavigation(grid)
    local y = grid.originY + grid.gridH + 4
    local navigation = windowState.nav
    pcall(function() navigation.previous.root:SetPos(PAD, y + 2) end)
    pcall(function() navigation.after.root:SetPos(PAD + 86, y + 2) end)
    pcall(function() navigation.search.root:SetPos(PAD + 180, y + 2) end)
    pcall(function() navigation.jump.root:SetPos(PAD + 392, y + 2) end)
    pcall(function() navigation.log.root:SetPos(grid.width - PAD - 110, y + 2) end)
    local buttonsWidth = 116
    if navigation.secondLog then
        buttonsWidth = 232
        pcall(function() navigation.secondLog.root:SetPos(grid.width - PAD - 226, y + 2) end)
    end
    pcall(function()
        navigation.label:SetPos(PAD + 470, y + 8)
        navigation.label:SetSize(math.max(1, grid.width - PAD * 2 - 470 - buttonsWidth), 20)
    end)
end

local function layoutWindow()
    local succeeded, grid = pcall(computeGeometry)
    if not succeeded then return end
    windowState.layoutW, windowState.layoutH, windowState.layoutScale = grid.width, grid.height, currentHeadScale()
    for _, headCell in ipairs(windowState.cells) do pcall(placeCell, headCell, grid) end
    placeNavigation(grid)
end

-- A cell shown or hidden (all its parts).
local function setCellHidden(headCell, hidden)
    for _, cellPart in ipairs({ headCell.background, headCell.model, headCell.name, headCell.idLabel, headCell.click }) do
        pcall(function() cellPart.hidden = hidden end)
    end
end

-- One of the window's PAGE_SIZE cells, made once and used for every page (see src/ui/all_heads_window.lua).
local function makeCell(position)
    local windowContent = windowState.window.content
    local headCell = { index = position }
    windowState.cells[#windowState.cells + 1] = headCell

    headCell.background = ui.Rectangle.new(windowContent)
    headCell.background.fill = true
    headCell.background.clickthrough = true

    headCell.model = ui.Model.new(windowContent)
    headCell.model.clickthrough = true

    local function makeTextLabel(labelText)
        local textLabel = ui.Text.new(windowContent)
        textLabel.maxLines = 1
        textLabel.font = id.Font.MUSEO_SANS_11PT_REGULAR
        textLabel.rgba = TEXT_LIGHT
        textLabel.alignHorizontal = ui.AlignMode.CENTRE
        textLabel.clickthrough = true
        textLabel.content = labelText
        return textLabel
    end
    headCell.name = makeTextLabel("")
    headCell.idLabel = makeTextLabel("")

    headCell.click = ui.Layer.new(windowContent)
    headCell.click.clickthrough = false
    headCell.click:Subscribe(ui.Hook.ONMOUSEOVER, function() paintCell(headCell, true) end)
    headCell.click:Subscribe(ui.Hook.ONMOUSELEAVE, function() paintCell(headCell, false) end)
    headCell.click:Subscribe(ui.Hook.ONCLICK, function() if headCell.id ~= nil then toggle(headCell) end end)
    setCellHidden(headCell, true)
end

local function fillCell(headCell, npcID)
    headCell.id = npcID
    if windowState.setup then
        windowState.setup(headCell.model, npcID)
    else
        headCell.model:SetModel(ui.ModelType.NPC_HEAD, npcID)
        local animationID = windowState.animFor and windowState.animFor(npcID) or nil
        if animationID ~= nil then headCell.model.animID = animationID end
    end
    headCell.name.content = windowState.nameOf(npcID) or "?"
    headCell.idLabel.content = windowState.idText and windowState.idText(npcID) or ("ID " .. npcID)
    setCellHidden(headCell, false)
    paintCell(headCell, false)
end

local function emptyCell(headCell)
    headCell.id = nil
    setCellHidden(headCell, true)
end

local function showPage()
    if not windowState.cellsMade then
        windowState.cellsMade = true
        for position = 1, PAGE_SIZE do
            local succeeded, errorMessage = pcall(makeCell, position)
            if not succeeded then say("could not make a cell: " .. tostring(errorMessage)) end
        end
    end
    windowState.page = math.max(1, math.min(windowState.pages, windowState.page))
    local firstHeadIndex = (windowState.page - 1) * PAGE_SIZE
    for _, headCell in ipairs(windowState.cells) do
        local npcID = windowState.shown[firstHeadIndex + headCell.index]
        if npcID == nil then
            emptyCell(headCell)
        else
            local succeeded, errorMessage = pcall(fillCell, headCell, npcID)
            if not succeeded then say("could not fill a cell: " .. tostring(errorMessage)) end
        end
    end
    updatePageLabel()
    layoutWindow()
    local wanted = { windowState.page > 1, windowState.page < windowState.pages }
    for position, button in ipairs({ windowState.nav.previous, windowState.nav.after }) do
        pcall(function()
            button.root.hidden = not wanted[position]
            button.root:MoveToFront()
        end)
    end
end

-- The heads whose name or id holds the search text (all of them if it is blank).
local function applySearch()
    local searchWords = {}
    for searchWord in (windowState.query or ""):lower():gmatch("%S+") do searchWords[#searchWords + 1] = searchWord end
    if #searchWords == 0 then
        windowState.shown = windowState.all
    else
        local matchingHeadIDs = {}
        for _, npcID in ipairs(windowState.all) do
            local haystack = (windowState.lowered[npcID] or "") .. " " .. npcID
            local matches = true
            for _, searchWord in ipairs(searchWords) do
                if not haystack:find(searchWord, 1, true) then matches = false break end
            end
            if matches then matchingHeadIDs[#matchingHeadIDs + 1] = npcID end
        end
        windowState.shown = matchingHeadIDs
    end
    windowState.pages = math.max(1, math.ceil(#windowState.shown / PAGE_SIZE))
    windowState.page = 1
end

-- The animation chosen changed: the cells filled again (the setup plays the one chosen now).
function HeadFlaggingWindow.updateAnimations()
    if windowState ~= nil then showPage() end
end

function HeadFlaggingWindow.isOpen()
    return windowState ~= nil
end

function HeadFlaggingWindow.open(PrettyUI, parent, heads, nameOf, animFor, options)
    options = options or {}
    if windowState ~= nil then HeadFlaggingWindow.close() end
    local width = COLUMNS * START_CELL_W + (COLUMNS - 1) * GAP + PAD * 2 + BORDERS
    local height = ROWS * START_CELL_H + (ROWS - 1) * GAP + PAD * 2 + NAV_HEIGHT + 4 + TITLE_AND_BOTTOM
    local minWidth = COLUMNS * MIN_CELL_W + (COLUMNS - 1) * GAP + PAD * 2 + BORDERS
    minWidth = math.max(minWidth, options.minWidth or 760) -- (room for the buttons and boxes in the bottom row)
    local minHeight = ROWS * MIN_CELL_H + (ROWS - 1) * GAP + PAD * 2 + NAV_HEIGHT + 4 + TITLE_AND_BOTTOM
    width = math.max(math.min(minWidth, parent.width), math.min(width, parent.width))
    height = math.max(math.min(minHeight, parent.height), math.min(height, parent.height))
    local x = math.max(0, math.floor((parent.width - width) / 2))
    local y = math.max(0, math.floor((parent.height - height) / 2))

    local lowered = {}
    for _, npcID in ipairs(heads) do lowered[npcID] = (nameOf(npcID) or ""):lower() end
    windowState = { all = heads, shown = heads, page = 1, pages = math.max(1, math.ceil(#heads / PAGE_SIZE)),
        flagged = {}, cells = {}, nav = {}, nameOf = nameOf, animFor = animFor, lowered = lowered, query = "",
        logLabel = options.logLabel or "blacklist", setup = options.setup, tint = options.tint,
        flaggedLines = options.flaggedLines, removeOnLog = options.removeOnLog, quietClicks = options.quietClicks,
        idText = options.idText, secondFlaggedLines = options.secondFlaggedLines,
        headClicked = options.headClicked, labelNote = options.labelNote,
        firstLogKeeps = options.firstLogKeeps }
    local openedState = windowState
    local succeeded, errorMessage = pcall(function()
        openedState.window = PrettyUI.Window.new(parent, {
            title = options.title or "Debug: all heads (click one to flag it for the blacklist)", x = x, y = y, width = width, height = height,
            minWidth = math.min(minWidth, width), minHeight = math.min(minHeight, height),
            resizable = true, scrollable = false, destroyOnClose = true,
            onClose = function()
                if windowState == openedState then
                    destroyCells()
                    Event.Draw.Unsubscribe("make_me_a_monster_head_flagging_window")
                    windowState = nil
                end
            end,
        })
    end)
    if not succeeded then
        windowState = nil
        say("could not open the head browser: " .. tostring(errorMessage))
        return false
    end
    local windowContent = openedState.window.content
    local okNav, errNav = pcall(function()
        local navigation = openedState.nav
        navigation.turn = 0
        navigation.previous = PrettyUI.SimpleButton.new(windowContent, "Previous", function() navigation.turn = -1 end, { width = 80 })
        navigation.after = PrettyUI.SimpleButton.new(windowContent, "Next", function() navigation.turn = 1 end, { width = 80 })
        navigation.search = PrettyUI.TextField.new(windowContent, {
            width = 204, height = 30, placeholder = "Search name or id",
            onChange = function(_, _, text)
                openedState.query, openedState.searchDirty = text, true
            end,
        })
        navigation.jump = PrettyUI.TextField.new(windowContent, {
            width = 70, height = 30, placeholder = "Page", filterMode = ui.InputFieldFilterMode.NUMERIC,
            onSubmit = function(_, text) navigation.jumpTo = tonumber(text) end,
        })
        navigation.log = PrettyUI.SimpleButton.new(windowContent, options.logButton or "Log flagged", function() navigation.logFlagged = true end, { width = 110 })
        if options.secondLogButton then
            navigation.secondLog = PrettyUI.SimpleButton.new(windowContent, options.secondLogButton, function()
                navigation.logFlagged, navigation.logSecond = true, true
            end, { width = 110 })
        end
        navigation.label = ui.Text.new(windowContent)
        navigation.label.maxLines = 1
        navigation.label.font = id.Font.MUSEO_SANS_11PT_REGULAR
        navigation.label.rgba = TEXT_LIGHT
    end)
    if not okNav then say("could not make the controls: " .. tostring(errNav)) end
    showPage()
    Event.Draw.Subscribe("make_me_a_monster_head_flagging_window", function() pcall(HeadFlaggingWindow.tick) end)
    return true
end

function HeadFlaggingWindow.close()
    if windowState == nil then return end
    local window = windowState.window
    destroyCells()
    Event.Draw.Unsubscribe("make_me_a_monster_head_flagging_window")
    windowState = nil
    pcall(function() window:Destroy() end)
end

-- Every frame while the window is open: what the buttons and boxes asked for (done here, not inside their own handlers), and the cells
-- fitted to the window's size.
function HeadFlaggingWindow.tick()
    if windowState == nil or windowState.window == nil then return end
    local navigation = windowState.nav
    if windowState.searchDirty then
        windowState.searchDirty = false
        applySearch()
        showPage()
    end
    if navigation.turn ~= nil and navigation.turn ~= 0 then
        local pageChange = navigation.turn
        navigation.turn = 0
        local page = math.max(1, math.min(windowState.pages, windowState.page + pageChange))
        if page ~= windowState.page then
            windowState.page = page
            showPage()
        end
    end
    if navigation.jumpTo ~= nil then
        windowState.page, navigation.jumpTo = navigation.jumpTo, nil
        showPage()
    end
    if navigation.logFlagged then
        navigation.logFlagged = false
        local flaggedLines, keptHeadOf = windowState.flaggedLines, windowState.firstLogKeeps
        if navigation.logSecond then
            flaggedLines, keptHeadOf, navigation.logSecond = windowState.secondFlaggedLines, nil, false
        end
        local variantIDs = {}
        for npcID in pairs(windowState.flagged) do variantIDs[#variantIDs + 1] = npcID end
        table.sort(variantIDs)
        if flaggedLines then
            for _, text in ipairs(flaggedLines(variantIDs)) do say(text) end
        else
            local count, labelText = flaggedLine()
            say(("%s ids flagged (%d): %s"):format(windowState.logLabel, count, labelText))
        end
        if windowState.removeOnLog and next(windowState.flagged) ~= nil then
            local keptHead = keptHeadOf and keptHeadOf(variantIDs)
            local remainingHeads = {}
            for _, npcID in ipairs(windowState.all) do
                if not windowState.flagged[npcID] or npcID == keptHead then
                    remainingHeads[#remainingHeads + 1] = npcID
                end
            end
            local page = windowState.page
            windowState.all, windowState.flagged = remainingHeads, {}
            applySearch()
            windowState.page = page -- (the same page, or the last if that one is gone: showPage keeps it in range)
            showPage()
        end
    end
    local succeeded, width, height = pcall(function() return windowState.window.content.width, windowState.window.content.height end)
    if succeeded and (width ~= windowState.layoutW or height ~= windowState.layoutH or currentHeadScale() ~= windowState.layoutScale) then layoutWindow() end
end

return HeadFlaggingWindow
