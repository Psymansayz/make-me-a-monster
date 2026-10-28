-- TEMPORARY debug window: every chat head left after the filtering, as a paged grid (like the variants window),
-- for finding the ones that should be blacklisted. Clicking a head flags it (it turns red) and logs its id; click
-- it again to take the flag off. "Log flagged" prints every flagged id in one line, ready to paste into
-- src/data/head_blacklist.lua. A search box narrows the heads by name or id, and a page box jumps to a page.
--
-- HeadBrowser.open(PrettyUI, parent, heads, nameOf, animFor, options): heads = { id... } in the order shown.
-- options (all optional) lets the same window show and flag other things than heads (the animations on Hans):
-- title; logLabel (the word the log lines start with, "blacklist" for heads); setup(model, id), which sets a cell's
-- model up in place of the NPC head and animation; tint(id), the colour { r, g, b, a } of a cell not flagged;
-- flaggedLines(ids), the lines "Log flagged" prints for the flagged ids (in place of the one line of ids).
-- HeadBrowser.tick(): every frame. HeadBrowser.close().

local HeadBrowser = {}

HeadBrowser.scaleFor = nil -- function() -> how many times larger than normal the heads are drawn (the head size setting)

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

local state = nil -- { window, logLabel, setup, tint, flaggedLines, all, shown, page, pages, flagged, cells, nav, nameOf, animFor, lowered, layoutW, layoutH }

local function say(message)
    print("[make_me_a_monster] " .. message)
end

local function colour(c) return Vector4.new(c[1], c[2], c[3], c[4]) end

local function destroyCells()
    for _, cell in ipairs(state.cells) do
        pcall(function() cell.click:Destroy() end)
        pcall(function() cell.name:Destroy() end)
        pcall(function() cell.idLabel:Destroy() end)
        pcall(function() cell.model:Destroy() end)
        pcall(function() cell.background:Destroy() end)
    end
    state.cells = {}
end

local function paint(cell, hovered)
    local flagged = state.flagged[cell.id]
    local base = state.tint and state.tint(cell.id) or BACKGROUND
    local c = flagged and (hovered and FLAGGED_HOVER or FLAGGED) or (hovered and HOVER or base)
    pcall(function() cell.background.colour = colour(c) end)
end

local function flaggedLine()
    local ids = {}
    for npcID in pairs(state.flagged) do ids[#ids + 1] = npcID end
    table.sort(ids)
    return #ids, table.concat(ids, ", ")
end

local function toggle(cell)
    local npcID = cell.id
    if state.flagged[npcID] then
        state.flagged[npcID] = nil
        say(("%s removed: %d (%s)"):format(state.logLabel, npcID, state.nameOf(npcID) or "?"))
    else
        state.flagged[npcID] = true
        say(("%s: %d (%s)"):format(state.logLabel, npcID, state.nameOf(npcID) or "?"))
    end
    paint(cell, true)
end

-- The grid for the window's content as it is now.
local function geometry()
    local content = state.window.content
    local width, height = content.width, content.height
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
local function headScale()
    local scale = HeadBrowser.scaleFor and HeadBrowser.scaleFor() or 1
    return type(scale) == "number" and scale >= 1 and scale or 1
end

local function placeCell(cell, g)
    local col, row = (cell.index - 1) % COLUMNS, math.floor((cell.index - 1) / COLUMNS)
    local x, y = g.originX + col * (g.cellW + GAP), g.originY + row * (g.cellH + GAP)
    local head = math.max(16, math.min(g.cellW - 8, g.cellH - 44))
    cell.background:SetPos(x, y)
    cell.background:SetSize(g.cellW, g.cellH)
    cell.model:SetPos(x + math.floor((g.cellW - head) / 2), y + 4)
    cell.model:SetSize(head, head)
    cell.model.viewDistance = math.max(1, math.floor(BASE_VIEW * BASE_SIZE / head / headScale()))
    cell.name:SetPos(x, y + g.cellH - 38)
    cell.name:SetSize(g.cellW, 16)
    cell.idLabel:SetPos(x, y + g.cellH - 20)
    cell.idLabel:SetSize(g.cellW, 16)
    cell.click:SetPos(x, y)
    cell.click:SetSize(g.cellW, g.cellH)
end

local function placeNav(g)
    local y = g.originY + g.gridH + 4
    local nav = state.nav
    pcall(function() nav.previous.root:SetPos(PAD, y + 2) end)
    pcall(function() nav.after.root:SetPos(PAD + 86, y + 2) end)
    pcall(function() nav.search.root:SetPos(PAD + 180, y + 2) end)
    pcall(function() nav.jump.root:SetPos(PAD + 392, y + 2) end)
    pcall(function() nav.log.root:SetPos(g.width - PAD - 110, y + 2) end)
    pcall(function()
        nav.label:SetPos(PAD + 470, y + 8)
        nav.label:SetSize(math.max(1, g.width - PAD * 2 - 470 - 116), 20)
    end)
end

local function layout()
    local ok, g = pcall(geometry)
    if not ok then return end
    state.layoutW, state.layoutH, state.layoutScale = g.width, g.height, headScale()
    for _, cell in ipairs(state.cells) do pcall(placeCell, cell, g) end
    placeNav(g)
end

-- A cell shown or hidden (all its parts).
local function setHidden(cell, hidden)
    for _, part in ipairs({ cell.background, cell.model, cell.name, cell.idLabel, cell.click }) do
        pcall(function() part.hidden = hidden end)
    end
end

-- One of the window's PAGE_SIZE cells, made once and used for every page (see src/ui/head_gallery.lua).
local function makeCell(index)
    local content = state.window.content
    local cell = { index = index }
    state.cells[#state.cells + 1] = cell

    cell.background = ui.Rectangle.new(content)
    cell.background.fill = true
    cell.background.clickthrough = true

    cell.model = ui.Model.new(content)
    cell.model.clickthrough = true

    local function text(line)
        local label = ui.Text.new(content)
        label.maxLines = 1
        label.font = id.Font.MUSEO_SANS_11PT_REGULAR
        label.rgba = TEXT_LIGHT
        label.alignHorizontal = ui.AlignMode.CENTRE
        label.clickthrough = true
        label.content = line
        return label
    end
    cell.name = text("")
    cell.idLabel = text("")

    cell.click = ui.Layer.new(content)
    cell.click.clickthrough = false
    cell.click:Subscribe(ui.Hook.ONMOUSEOVER, function() paint(cell, true) end)
    cell.click:Subscribe(ui.Hook.ONMOUSELEAVE, function() paint(cell, false) end)
    cell.click:Subscribe(ui.Hook.ONCLICK, function() if cell.id ~= nil then toggle(cell) end end)
    setHidden(cell, true)
end

local function fillCell(cell, npcID)
    cell.id = npcID
    if state.setup then
        state.setup(cell.model, npcID)
    else
        cell.model:SetModel(ui.ModelType.NPC_HEAD, npcID)
        local anim = state.animFor and state.animFor() or nil
        if anim ~= nil then cell.model.animID = anim end
    end
    cell.name.content = state.nameOf(npcID) or "?"
    cell.idLabel.content = "ID " .. npcID
    setHidden(cell, false)
    paint(cell, false)
end

local function emptyCell(cell)
    cell.id = nil
    setHidden(cell, true)
end

local function showPage()
    if not state.cellsMade then
        state.cellsMade = true
        for index = 1, PAGE_SIZE do
            local ok, err = pcall(makeCell, index)
            if not ok then say("could not make a cell: " .. tostring(err)) end
        end
    end
    state.page = math.max(1, math.min(state.pages, state.page))
    local first = (state.page - 1) * PAGE_SIZE
    for _, cell in ipairs(state.cells) do
        local npcID = state.shown[first + cell.index]
        if npcID == nil then
            emptyCell(cell)
        else
            local ok, err = pcall(fillCell, cell, npcID)
            if not ok then say("could not fill a cell: " .. tostring(err)) end
        end
    end
    pcall(function()
        state.nav.label.content = ("page %d of %d, %d heads%s, %d flagged"):format(
            state.page, state.pages, #state.shown, #state.shown < #state.all and " found" or "", (function()
                local n = 0
                for _ in pairs(state.flagged) do n = n + 1 end
                return n
            end)())
    end)
    layout()
    local wanted = { state.page > 1, state.page < state.pages }
    for index, button in ipairs({ state.nav.previous, state.nav.after }) do
        pcall(function()
            button.root.hidden = not wanted[index]
            button.root:MoveToFront()
        end)
    end
end

-- The heads whose name or id holds the search text (all of them if it is blank).
local function applySearch()
    local words = {}
    for word in (state.query or ""):lower():gmatch("%S+") do words[#words + 1] = word end
    if #words == 0 then
        state.shown = state.all
    else
        local found = {}
        for _, npcID in ipairs(state.all) do
            local haystack = (state.lowered[npcID] or "") .. " " .. npcID
            local matches = true
            for _, word in ipairs(words) do
                if not haystack:find(word, 1, true) then matches = false break end
            end
            if matches then found[#found + 1] = npcID end
        end
        state.shown = found
    end
    state.pages = math.max(1, math.ceil(#state.shown / PAGE_SIZE))
    state.page = 1
end

function HeadBrowser.isOpen()
    return state ~= nil
end

function HeadBrowser.open(PrettyUI, parent, heads, nameOf, animFor, options)
    options = options or {}
    if state ~= nil then HeadBrowser.close() end
    local width = COLUMNS * START_CELL_W + (COLUMNS - 1) * GAP + PAD * 2 + BORDERS
    local height = ROWS * START_CELL_H + (ROWS - 1) * GAP + PAD * 2 + NAV_HEIGHT + 4 + TITLE_AND_BOTTOM
    local minWidth = COLUMNS * MIN_CELL_W + (COLUMNS - 1) * GAP + PAD * 2 + BORDERS
    minWidth = math.max(minWidth, 760) -- (room for the buttons and boxes in the bottom row)
    local minHeight = ROWS * MIN_CELL_H + (ROWS - 1) * GAP + PAD * 2 + NAV_HEIGHT + 4 + TITLE_AND_BOTTOM
    width = math.max(math.min(minWidth, parent.width), math.min(width, parent.width))
    height = math.max(math.min(minHeight, parent.height), math.min(height, parent.height))
    local x = math.max(0, math.floor((parent.width - width) / 2))
    local y = math.max(0, math.floor((parent.height - height) / 2))

    local lowered = {}
    for _, npcID in ipairs(heads) do lowered[npcID] = (nameOf(npcID) or ""):lower() end
    state = { all = heads, shown = heads, page = 1, pages = math.max(1, math.ceil(#heads / PAGE_SIZE)),
        flagged = {}, cells = {}, nav = {}, nameOf = nameOf, animFor = animFor, lowered = lowered, query = "",
        logLabel = options.logLabel or "blacklist", setup = options.setup, tint = options.tint,
        flaggedLines = options.flaggedLines }
    local mine = state
    local ok, err = pcall(function()
        mine.window = PrettyUI.Window.new(parent, {
            title = options.title or "Debug: all heads (click one to flag it for the blacklist)", x = x, y = y, width = width, height = height,
            minWidth = math.min(minWidth, width), minHeight = math.min(minHeight, height),
            resizable = true, scrollable = false, destroyOnClose = true,
            onClose = function()
                if state == mine then
                    destroyCells()
                    state = nil
                end
            end,
        })
    end)
    if not ok then
        state = nil
        say("could not open the head browser: " .. tostring(err))
        return false
    end
    local content = mine.window.content
    local okNav, errNav = pcall(function()
        local nav = mine.nav
        nav.turn = 0
        nav.previous = PrettyUI.SimpleButton.new(content, "Previous", function() nav.turn = -1 end, { width = 80 })
        nav.after = PrettyUI.SimpleButton.new(content, "Next", function() nav.turn = 1 end, { width = 80 })
        nav.search = PrettyUI.TextField.new(content, {
            width = 204, height = 30, placeholder = "Search name or id",
            onChange = function(_, _, text)
                mine.query, mine.searchDirty = text, true
            end,
        })
        nav.jump = PrettyUI.TextField.new(content, {
            width = 70, height = 30, placeholder = "Page", filterMode = ui.InputFieldFilterMode.NUMERIC,
            onSubmit = function(_, text) nav.jumpTo = tonumber(text) end,
        })
        nav.log = PrettyUI.SimpleButton.new(content, "Log flagged", function() nav.logFlagged = true end, { width = 110 })
        nav.label = ui.Text.new(content)
        nav.label.maxLines = 1
        nav.label.font = id.Font.MUSEO_SANS_11PT_REGULAR
        nav.label.rgba = TEXT_LIGHT
    end)
    if not okNav then say("could not make the controls: " .. tostring(errNav)) end
    showPage()
    return true
end

function HeadBrowser.close()
    if state == nil then return end
    local window = state.window
    destroyCells()
    state = nil
    pcall(function() window:Destroy() end)
end

-- Every frame: what the buttons and boxes asked for (done here, not inside their own handlers), and the cells
-- fitted to the window's size.
function HeadBrowser.tick()
    if state == nil or state.window == nil then return end
    local nav = state.nav
    if state.searchDirty then
        state.searchDirty = false
        applySearch()
        showPage()
    end
    if nav.turn ~= nil and nav.turn ~= 0 then
        local delta = nav.turn
        nav.turn = 0
        local page = math.max(1, math.min(state.pages, state.page + delta))
        if page ~= state.page then
            state.page = page
            showPage()
        end
    end
    if nav.jumpTo ~= nil then
        state.page, nav.jumpTo = nav.jumpTo, nil
        showPage()
    end
    if nav.logFlagged then
        nav.logFlagged = false
        if state.flaggedLines then
            local ids = {}
            for npcID in pairs(state.flagged) do ids[#ids + 1] = npcID end
            table.sort(ids)
            for _, text in ipairs(state.flaggedLines(ids)) do say(text) end
        else
            local count, line = flaggedLine()
            say(("%s ids flagged (%d): %s"):format(state.logLabel, count, line))
        end
    end
    local ok, width, height = pcall(function() return state.window.content.width, state.window.content.height end)
    if ok and (width ~= state.layoutW or height ~= state.layoutH or headScale() ~= state.layoutScale) then layout() end
end

return HeadBrowser
