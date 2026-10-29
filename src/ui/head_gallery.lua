-- The "all heads" window: every chat head the plugin lists, as a paged grid with their names. Clicking one makes it
-- the head used in dialogue (the window stays open, the head in use highlighted, so another can be tried). A search
-- box narrows the heads by name or id, and a page box jumps to a page; the window can be resized, the cells and
-- heads in them growing and shrinking with it, and its size is remembered.
--
-- Workaround: pages instead of scrolling: models in a scroll area aren't clipped by it, so they would draw
-- outside it.
-- Workaround: the page is changed from the next frame, not from the button or box that asked: a component isn't
-- destroyed inside its own handler.
-- Workaround: a window's content size changes a moment after it is resized, so it is read every frame and the cells
-- are placed again when it differs.
--
-- HeadGallery.open(PrettyUI, parent, heads, current, onPick, nameOf): heads = { id... } in the order shown;
-- current = the id used now (highlighted, and its page shown first); onPick(id) is called when a head is clicked
-- (the highlight then moves to it);
-- nameOf(id) is the name shown under each head. HeadGallery.tick(): every frame. HeadGallery.close().

local Settings = require("src/data/settings")

local HeadGallery = {}

HeadGallery.animFor = nil -- function() -> the animation id the heads should play, or nil
HeadGallery.onClosed = nil -- function(): called when the window has closed, however it was closed

local COLUMNS, ROWS = 5, 4
local PAGE_SIZE = COLUMNS * ROWS
local PAD, GAP = 8, 6
local NAV_HEIGHT = 36
local START_CELL_W, START_CELL_H = 150, 170
local MIN_CELL_W, MIN_CELL_H = 90, 110
local MIN_WIDTH = 640 -- room for the buttons and boxes in the bottom row
local BORDERS, TITLE_AND_BOTTOM = 16, 40
local BASE_VIEW, BASE_SIZE = 2150, 160

local BACKGROUND = { 0.12, 0.09, 0.06, 1 }
local HOVER = { 0.30, 0.24, 0.14, 1 }
local CURRENT = { 0.55, 0.42, 0.14, 1 }
local TEXT_LIGHT = 0xE9E5DDFF

local state = nil -- { window, current, onPick, nameOf, all, shown, page, pages, cells, nav, lowered, query, layoutW, ... }

local function colour(c) return Vector4.new(c[1], c[2], c[3], c[4]) end

-- The head size setting: how many times larger than normal the heads are drawn (1: normal).
local function headScale()
    return Settings.headScale
end

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

-- The window's size, handed to the settings (to be remembered), if it can be read.
local function reportSize(shown)
    if shown == nil or shown.window == nil then return end
    local ok, width, height = pcall(function() return shown.window.root.width, shown.window.root.height end)
    if ok and type(width) == "number" and type(height) == "number" and width > 0 and height > 0 then
        Settings.setGallerySize(math.floor(width), math.floor(height))
    end
end

-- A cell's background: the head in use gold, the others dark (lighter under the mouse).
local function paint(cell, hovered)
    local c = hovered and HOVER or (cell.id == state.current and CURRENT or BACKGROUND)
    pcall(function() cell.background.colour = colour(c) end)
end

-- A head clicked: it becomes the one in use, and the cells show which.
local function pick(npcID)
    if state == nil then return end
    state.current = npcID
    pcall(state.onPick, npcID)
    for _, cell in ipairs(state.cells) do paint(cell, cell.id == npcID) end
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
    pcall(function()
        nav.label:SetPos(PAD + 470, y + 8)
        nav.label:SetSize(math.max(1, g.width - PAD * 2 - 470), 20)
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

-- One of the window's PAGE_SIZE cells, made once when the window opens and used for every page (a page change
-- gives the cells other heads, it doesn't make and destroy components: that built up while paging, and the
-- client was slow to let go of them). Empty until fillCell.
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

    -- Over the rest, taking the click. (One handler per hook: a second default Subscribe replaces the first.)
    cell.click = ui.Layer.new(content)
    cell.click.clickthrough = false
    cell.click:Subscribe(ui.Hook.ONMOUSEOVER, function() paint(cell, true) end)
    cell.click:Subscribe(ui.Hook.ONMOUSELEAVE, function() paint(cell, false) end)
    cell.click:Subscribe(ui.Hook.ONCLICK, function() if cell.id ~= nil then pick(cell.id) end end)
    setHidden(cell, true)
end

-- The cell showing this head.
local function fillCell(cell, npcID)
    cell.id = npcID
    cell.model:SetModel(ui.ModelType.NPC_HEAD, npcID)
    local anim = HeadGallery.animFor and HeadGallery.animFor() or nil
    if anim ~= nil then cell.model.animID = anim end
    cell.name.content = state.nameOf(npcID) or "?"
    cell.idLabel.content = "ID " .. npcID
    setHidden(cell, false)
    paint(cell, false)
end

-- The cell with nothing in it (past the last head of the last page).
local function emptyCell(cell)
    cell.id = nil
    setHidden(cell, true)
end

local function showPage()
    if not state.cellsMade then
        state.cellsMade = true
        for index = 1, PAGE_SIZE do
            local ok, err = pcall(makeCell, index)
            if not ok then print("[make_me_a_monster] could not make a head cell: " .. tostring(err)) end
        end
    end
    state.page = math.max(1, math.min(state.pages, state.page))
    local first = (state.page - 1) * PAGE_SIZE
    for index, cell in ipairs(state.cells) do
        local npcID = state.shown[first + cell.index]
        if npcID == nil then
            emptyCell(cell)
        else
            local ok, err = pcall(fillCell, cell, npcID)
            if not ok then print("[make_me_a_monster] could not fill a head cell: " .. tostring(err)) end
        end
    end
    pcall(function()
        state.nav.label.content = ("Page %d of %d (%d heads%s)"):format(
            state.page, state.pages, #state.shown, #state.shown < #state.all and " found" or "")
    end)
    layout()
    -- Previous and Next only where there is a page to go to; they stay above the heads.
    local wanted = { state.page > 1, state.page < state.pages }
    for index, button in ipairs({ state.nav.previous, state.nav.after }) do
        pcall(function()
            button.root.hidden = not wanted[index]
            button.root:MoveToFront()
        end)
    end
end

-- The heads whose name or id holds every word of the search text (all of them if it is blank).
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
                if not haystack:find(word, 1, true) then
                    matches = false
                    break
                end
            end
            if matches then found[#found + 1] = npcID end
        end
        state.shown = found
    end
    state.pages = math.max(1, math.ceil(#state.shown / PAGE_SIZE))
    state.page = 1
end

-- The size the window opens at when it has no saved size: five cells across and four down, at their starting size.
-- The window's size scales with the game window (`parent`): that cell size, made larger or smaller to take up about
-- WIDTH_SHARE of its width or HEIGHT_SHARE of its height, whichever comes first.
local WIDTH_SHARE, HEIGHT_SHARE = 0.45, 0.75

function HeadGallery.defaultSize(parent)
    local width = COLUMNS * START_CELL_W + (COLUMNS - 1) * GAP + PAD * 2 + BORDERS
    local height = ROWS * START_CELL_H + (ROWS - 1) * GAP + PAD * 2 + NAV_HEIGHT + 4 + TITLE_AND_BOTTOM
    local scale = math.min(parent.width * WIDTH_SHARE / width, parent.height * HEIGHT_SHARE / height)
    return math.floor(width * scale), math.floor(height * scale)
end

-- The heads shown play the animation now wanted (it was changed while the window is open).
function HeadGallery.updateAnimations()
    if state == nil then return end
    local anim = HeadGallery.animFor and HeadGallery.animFor() or nil
    for _, cell in ipairs(state.cells) do
        if cell.id ~= nil then
            pcall(function()
                if anim ~= nil then
                    cell.model.animID = anim
                else
                    cell.model:SetModel(ui.ModelType.NPC_HEAD, cell.id) -- (no animation: the head as it starts)
                end
            end)
        end
    end
end

function HeadGallery.isOpen()
    return state ~= nil
end

function HeadGallery.open(PrettyUI, parent, heads, current, onPick, nameOf)
    if state ~= nil then HeadGallery.close() end
    local width, height = HeadGallery.defaultSize(parent)
    local minWidth = math.max(MIN_WIDTH, COLUMNS * MIN_CELL_W + (COLUMNS - 1) * GAP + PAD * 2 + BORDERS)
    local minHeight = ROWS * MIN_CELL_H + (ROWS - 1) * GAP + PAD * 2 + NAV_HEIGHT + 4 + TITLE_AND_BOTTOM
    -- As it was left, if it was.
    if Settings.galleryWidth ~= nil then width, height = Settings.galleryWidth, Settings.galleryHeight end
    -- (kept on the screen, and no smaller than it can be resized to)
    width = math.max(math.min(minWidth, parent.width), math.min(width, parent.width))
    height = math.max(math.min(minHeight, parent.height), math.min(height, parent.height))
    local x = math.max(0, math.floor((parent.width - width) / 2))
    local y = math.max(0, math.floor((parent.height - height) / 2))

    local lowered = {}
    local currentIndex = nil
    for index, npcID in ipairs(heads) do
        lowered[npcID] = (nameOf(npcID) or ""):lower()
        if npcID == current then currentIndex = index end
    end
    state = { all = heads, shown = heads, page = 1, pages = math.max(1, math.ceil(#heads / PAGE_SIZE)),
        current = current, onPick = onPick, nameOf = nameOf, cells = {}, nav = {}, lowered = lowered, query = "" }
    if currentIndex ~= nil then state.page = math.ceil(currentIndex / PAGE_SIZE) end -- (the head used now first)
    local mine = state
    local ok, err = pcall(function()
        mine.window = PrettyUI.Window.new(parent, {
            title = "All heads", x = x, y = y, width = width, height = height,
            minWidth = math.min(minWidth, width), minHeight = math.min(minHeight, height),
            resizable = true, scrollable = false, destroyOnClose = true,
            -- Closed with its X: the window destroys itself; the heads (models) in it are destroyed here, and what
            -- the window held is let go.
            onClose = function()
                if state == mine then
                    reportSize(mine)
                    destroyCells()
                    state = nil
                    if HeadGallery.onClosed then pcall(HeadGallery.onClosed) end
                end
            end,
        })
    end)
    if not ok then
        state = nil
        print("[make_me_a_monster] could not open the heads window: " .. tostring(err))
        return false
    end
    local content = mine.window.content
    local okNav, errNav = pcall(function()
        local nav = mine.nav
        nav.turn = 0
        -- (no angle brackets in the button text: the game reads "<" as the start of a markup tag)
        nav.previous = PrettyUI.SimpleButton.new(content, "Previous", function() nav.turn = -1 end, { width = 80 })
        nav.after = PrettyUI.SimpleButton.new(content, "Next", function() nav.turn = 1 end, { width = 80 })
        nav.search = PrettyUI.TextField.new(content, {
            width = 204, height = 30, placeholder = "Search name or id",
            onChange = function(_, _, text) mine.query, mine.searchDirty = text, true end,
        })
        nav.jump = PrettyUI.TextField.new(content, {
            width = 70, height = 30, placeholder = "Page", filterMode = ui.InputFieldFilterMode.NUMERIC,
            onSubmit = function(_, text) nav.jumpTo = tonumber(text) end,
        })
        nav.label = ui.Text.new(content)
        nav.label.maxLines = 1
        nav.label.font = id.Font.MUSEO_SANS_11PT_REGULAR
        nav.label.rgba = TEXT_LIGHT
    end)
    if not okNav then print("[make_me_a_monster] could not make the heads window's controls: " .. tostring(errNav)) end
    showPage()
    return true
end

function HeadGallery.close()
    if state == nil then return end
    local window = state.window
    reportSize(state)
    destroyCells()
    state = nil
    pcall(function() window:Destroy() end)
    if HeadGallery.onClosed then pcall(HeadGallery.onClosed) end
end

-- Every frame: does what the buttons and boxes asked for (not inside their own handlers), and fits the cells to the
-- window's size.
function HeadGallery.tick()
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
    local ok, width, height = pcall(function() return state.window.content.width, state.window.content.height end)
    if ok and (width ~= state.layoutW or height ~= state.layoutH or headScale() ~= state.layoutScale) then layout() end
end

return HeadGallery
