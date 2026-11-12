-- A window of chat heads in a paged grid. Its cells are made once and reused for every page.
--
-- Models aren't clipped by a scroll area, so the grid uses pages instead of scrolling.
-- Models in two parts of the UI tree, such as a window and a dialogue box, flicker along their top and right edges,
-- so the heads are drawn in two layers next to the window and overlaid on it. This relies on PrettyUI internals (its
-- overlays, drag bounds, resize controller and SetSize), so check them after a PrettyUI update.
-- Closing the window destroys its cell backgrounds and controls with it; release() destroys the two layers.

local Settings = require("src/data/settings")
local HeadSizes = require("src/game/head_sizes")
local WindowPlacement = require("src/ui/window_placement")

local HeadGrid = {}
HeadGrid.__index = HeadGrid

local PAD, GAP = 8, 6
local NAV_HEIGHT = 36
local NAV_BUTTON = 80
local NAV_TOGGLE = 130
local NAV_NUMBER = 70
local LABELS_HEIGHT = 40 -- the name and id lines under a head
local START_CELL_W, START_CELL_H = 150, 170 -- the cell size when a window opens without a saved size
local MIN_CELL_W, MIN_CELL_H = 90, 110      -- the smallest cell size a window can be resized to
local BORDERS, TITLE_AND_BOTTOM = 16, 40     -- PrettyUI's 8-pixel side borders; 32-pixel title bar plus bottom border
local BASE_SIZE = 160                        -- the size of a chat head drawn at the view distance for its head size
local WINDOW_HEAD_SCALE = 1.5                -- how much larger heads are in the windows than in the dialogue boxes

local BACKGROUND = Vector4.new(0.12, 0.09, 0.06, 1)
local HOVER = Vector4.new(0.30, 0.24, 0.14, 1)
local CURRENT = Vector4.new(0.55, 0.42, 0.14, 1)
local TEXT_LIGHT = 0xE9E5DDFF
local CELL_PARTS = { "model", "name", "idLabel", "background", "click" }
local raiseCount = 0

local function frameSize(columns, rows, cellW, cellH)
    return columns * cellW + (columns - 1) * GAP + PAD * 2 + BORDERS,
        rows * cellH + (rows - 1) * GAP + PAD * 2 + NAV_HEIGHT + 4 + TITLE_AND_BOTTOM
end

local WIDTH_SHARE, HEIGHT_SHARE = 0.45, 0.75

local function defaultSize(parent)
    local width, height = frameSize(5, 4, START_CELL_W, START_CELL_H)
    local scale = math.min(parent.width * WIDTH_SHARE / width, parent.height * HEIGHT_SHARE / height)
    return math.floor(width * scale), math.floor(height * scale)
end

local function contentSizeOf(windowWidth, windowHeight)
    return windowWidth - BORDERS, windowHeight - TITLE_AND_BOTTOM
end

local function pageOf(ids, current, pageSize)
    for position, npcID in ipairs(ids) do
        if npcID == current then return math.ceil(position / pageSize) end
    end
    return 1
end

function HeadGrid:geometry()
    local width, height = self.contentWidth, self.contentHeight
    local cellW = math.max(40, math.floor((width - PAD * 2 - (self.columns - 1) * GAP) / self.columns))
    local cellH = math.max(60, math.floor((height - PAD * 2 - NAV_HEIGHT - 4 - (self.rows - 1) * GAP) / self.rows))
    local gridW = self.columns * cellW + (self.columns - 1) * GAP
    return { width = width, height = height, cellW = cellW, cellH = cellH,
        originX = math.max(0, math.floor((width - gridW) / 2)), originY = PAD,
        gridH = self.rows * cellH + (self.rows - 1) * GAP }
end

local function cellOrigin(self, cell, g)
    local column, row = (cell.index - 1) % self.columns, math.floor((cell.index - 1) / self.columns)
    return g.originX + column * (g.cellW + GAP), g.originY + row * (g.cellH + GAP)
end

function HeadGrid:placeCellFrame(cell, g)
    local x, y = cellOrigin(self, cell, g)
    cell.background:SetPos(x, y)
    cell.background:SetSize(g.cellW, g.cellH)
    cell.click:SetPos(x, y)
    cell.click:SetSize(g.cellW, g.cellH)
    cell.name:SetSize(g.cellW, 16)
    cell.idLabel:SetSize(g.cellW, 16)
    -- Resizing a model redraws it from scratch, so it is only resized when the size changes.
    local headSize = math.max(16, math.min(g.cellW, g.cellH - LABELS_HEIGHT))
    if cell.headSize ~= headSize then
        cell.headSize = headSize
        cell.model:SetSize(headSize, headSize)
    end
end

function HeadGrid:placeCellOverlay(cell, g)
    local x, y = cellOrigin(self, cell, g)
    cell.model:SetPos(g.offsetX + x + math.floor((g.cellW - cell.headSize) / 2), g.offsetY + y)
    cell.name:SetPos(g.offsetX + x, g.offsetY + y + g.cellH - 38)
    cell.idLabel:SetPos(g.offsetX + x, g.offsetY + y + g.cellH - 20)
end

-- A head is drawn larger by moving the camera closer.
function HeadGrid:placeViewDistance(cell)
    if cell.id == nil or cell.headSize == nil then return end
    local viewDistance = math.max(1, math.floor(Settings.headViewDistance * BASE_SIZE / cell.headSize
        / WINDOW_HEAD_SCALE / HeadSizes.of(cell.id)))
    if cell.viewDistance ~= viewDistance then
        cell.viewDistance = viewDistance
        cell.model.viewDistance = viewDistance
    end
end

function HeadGrid:placeNavigation(g)
    local y = g.originY + g.gridH + 4
    local nav = self.nav
    nav.previous.root:SetPos(PAD, y + 2)
    nav.after.root:SetPos(PAD + NAV_BUTTON + 6, y + 2)
    if nav.search then
        nav.search.root:SetPos(PAD + 180, y + 2)
        nav.jump.root:SetPos(PAD + 392, y + 2)
        local labelX = 470
        if nav.toggle then
            nav.toggle.root:SetPos(PAD + labelX, y + 6)
            labelX = labelX + NAV_TOGGLE
        end
        nav.label:SetPos(PAD + labelX, y + 8)
        nav.label:SetSize(math.max(1, g.width - PAD * 2 - labelX), 20)
    else
        local labelX, labelEnd = PAD + (NAV_BUTTON + 6) * 2, g.width - PAD
        if nav.number then
            nav.number.root:SetPos(labelX, y + 2)
            labelX = labelX + NAV_NUMBER + 6
        end
        if nav.extra and not nav.extra.root.hidden then
            labelEnd = labelEnd - self.extraWidth
            nav.extra.root:SetPos(labelEnd, y + 2)
            labelEnd = labelEnd - 6
        end
        nav.label:SetPos(labelX, y + 8)
        nav.label:SetSize(math.max(1, labelEnd - labelX), 20)
    end
end

-- Places only what changed: everything after a resize, the heads and labels after a move, and otherwise just the
-- view distances. Setting self.placed to nil places everything.
function HeadGrid:place()
    local g = self:geometry()
    -- The layers cover the parent, so the heads and labels are placed relative to where the content sits on it.
    local root = self.window.root
    g.offsetX, g.offsetY = root.x + BORDERS / 2, root.y + TITLE_AND_BOTTOM - BORDERS / 2
    local placed = self.placed
    local resized = placed == nil or placed.width ~= g.width or placed.height ~= g.height
    local moved = resized or placed.offsetX ~= g.offsetX or placed.offsetY ~= g.offsetY
    for _, cell in ipairs(self.cells) do
        if resized then self:placeCellFrame(cell, g) end
        if moved then self:placeCellOverlay(cell, g) end
        self:placeViewDistance(cell)
    end
    if resized then self:placeNavigation(g) end
    self.placed = { width = g.width, height = g.height, offsetX = g.offsetX, offsetY = g.offsetY }
end

-- Called only when the window is laid out or moved. Raising the layers on a page or head size change too would put
-- them over any window in front of this one.
function HeadGrid:layout()
    self:place()
    self.headsLayer:MoveToFront()
    self.labelsLayer:MoveToFront()
end

local function setCellHidden(cell, hidden)
    if cell.hidden == hidden then return end
    cell.hidden = hidden
    for _, part in ipairs(CELL_PARTS) do cell[part].hidden = hidden end
end

local function setCellTexts(cell, nameText, idText)
    if cell.nameText ~= nameText then
        cell.nameText = nameText
        cell.name.content = nameText
    end
    if cell.idText ~= idText then
        cell.idText = idText
        cell.idLabel.content = idText
    end
end

function HeadGrid:paintCell(cell, hovered)
    local colour = hovered and HOVER or (cell.id == self.current and CURRENT or BACKGROUND)
    if cell.colour ~= colour then
        cell.colour = colour
        cell.background.colour = colour
    end
end

function HeadGrid:pick(pickedCell)
    if self.marksPick then self.current = pickedCell.id end
    self.onPick(pickedCell.id)
    for _, cell in ipairs(self.cells) do self:paintCell(cell, cell == pickedCell) end
end

function HeadGrid:makeCell(position)
    local content = self.window.content
    local cell = { index = position }
    self.cells[#self.cells + 1] = cell
    cell.background = ui.Rectangle.new(content)
    cell.background.fill = true
    cell.background.clickthrough = true
    cell.model = ui.Model.new(self.headsLayer)
    cell.model.clickthrough = true
    local function makeTextLabel()
        local text = ui.Text.new(self.labelsLayer)
        text.maxLines = 1
        text.font = id.Font.MUSEO_SANS_11PT_REGULAR
        text.rgba = TEXT_LIGHT
        text.alignHorizontal = ui.AlignMode.CENTRE
        text.clickthrough = true
        return text
    end
    cell.name = makeTextLabel()
    cell.idLabel = makeTextLabel()
    -- Sits on top of the cell and takes its clicks.
    cell.click = ui.Layer.new(content)
    cell.click.clickthrough = false
    cell.click:Subscribe(ui.Hook.ONMOUSEOVER, function() self:paintCell(cell, true) end)
    cell.click:Subscribe(ui.Hook.ONMOUSELEAVE, function() self:paintCell(cell, false) end)
    cell.click:Subscribe(ui.Hook.ONCLICK, function() if cell.id ~= nil then self:pick(cell) end end)
    setCellHidden(cell, true)
end

local function modelTypeFor(self, npcID)
    return self.isPlayerHead(npcID) and ui.ModelType.PLAYER_HEAD or ui.ModelType.NPC_HEAD
end

-- Setting a model again redraws it from scratch, so a cell whose head hasn't changed keeps its model.
function HeadGrid:fillCell(cell, npcID, position)
    cell.position = position
    if cell.id ~= npcID then
        cell.id = npcID
        cell.model:SetModel(modelTypeFor(self, npcID), npcID)
        cell.viewDistance = nil -- SetModel resets the view distance; place() sets it again
        cell.animationID = self.animationFor(npcID, position)
        if cell.animationID ~= nil then cell.model.animID = cell.animationID end
    end
    local isPlayer = self.isPlayerHead(npcID)
    local name = not isPlayer and self.nameOf(npcID, position) or nil
    setCellTexts(cell, isPlayer and "My head" or name or ("ID " .. npcID), name and ("ID " .. npcID) or "")
    setCellHidden(cell, false)
    self:paintCell(cell, false)
end

-- The model is released rather than just hidden, so a page with few heads keeps few models loaded.
local function emptyCell(cell)
    if cell.id == nil then return end
    cell.id, cell.animationID = nil, nil
    cell.model:SetModel(ui.ModelType.NONE, -1)
    setCellTexts(cell, "", "")
    setCellHidden(cell, true)
end

function HeadGrid:showPage()
    if #self.cells == 0 then
        for position = 1, self.pageSize do self:makeCell(position) end
    end
    self.page = math.max(1, math.min(self.pages, self.page))
    local first = (self.page - 1) * self.pageSize
    for _, cell in ipairs(self.cells) do
        local npcID = self.ids[first + cell.index]
        if npcID == nil then emptyCell(cell) else self:fillCell(cell, npcID, first + cell.index) end
    end
    local label = self.pageLabel(self.page, self.pages, #self.ids)
    if label ~= self.labelText then
        self.labelText = label
        self.nav.label.content = label
    end
    self:place()
    local firstPage, lastPage = self.page <= 1, self.page >= self.pages
    if firstPage ~= self.onFirstPage then
        self.onFirstPage = firstPage
        self.nav.previous.root.hidden = firstPage
    end
    if lastPage ~= self.onLastPage then
        self.onLastPage = lastPage
        self.nav.after.root.hidden = lastPage
    end
end

-- page: the page to show; nil shows the page holding the head in use.
function HeadGrid:setHeads(ids, current, title, page)
    self.ids, self.current = ids, current
    self.pages = math.max(1, math.ceil(#ids / self.pageSize))
    self.page = page or pageOf(ids, current, self.pageSize)
    if title ~= nil then self.window:SetTitle(title) end
    self:showPage()
end

function HeadGrid:setExtraButton(text)
    local button = self.nav.extra
    if button == nil or (text == self.extraText and self.placed ~= nil) then return end
    self.extraText = text
    button.root.hidden = text == nil
    if text ~= nil then
        button.content.content = text
        self.extraWidth = self.simpleButton.getSize(text)
        button.root:SetSize(self.extraWidth, button.root.height)
    end
    self.placed = nil
    if #self.cells > 0 then self:place() end -- otherwise showing the first page places it
end

function HeadGrid:changePage(pageChange)
    local page = math.max(1, math.min(self.pages, self.page + pageChange))
    if page ~= self.page then
        self.page = page
        self:showPage()
    end
end

function HeadGrid:updateAnimations()
    for _, cell in ipairs(self.cells) do
        if cell.id ~= nil then
            local animationID = self.animationFor(cell.id, cell.position)
            if animationID ~= cell.animationID then
                cell.animationID = animationID
                if animationID ~= nil then
                    cell.model.animID = animationID
                else
                    cell.model:SetModel(modelTypeFor(self, cell.id), cell.id) -- no animation, so the starting pose
                    cell.model.viewDistance = cell.viewDistance
                end
            end
        end
    end
end

function HeadGrid:refreshHeadSize()
    for _, cell in ipairs(self.cells) do self:placeViewDistance(cell) end
end

-- Called however the window is closed.
function HeadGrid:release()
    if self.closed then return end
    self.closed = true
    WindowPlacement.remember(self.window, self.placement)
    Event.Draw.Unsubscribe(self.raiseSubscription)
    self.window:_UnregisterOverlay(self.labelsLayer)
    self.cells = {}
    self.nav = {}
    self.headsLayer:Destroy()
    self.labelsLayer:Destroy()
    self.onClosed()
end

function HeadGrid:close()
    if self.closed then return end
    self:release()
    self.window:Destroy()
end

-- The window's interface can unload without any close handler running; if it has, the grid is forgotten.
function HeadGrid:stillLoaded()
    if self.closed then return false end
    if ui.Interfaces:GetInterface(self.window.interfaceID) ~= nil then return true end
    self.closed = true
    Event.Draw.Unsubscribe(self.raiseSubscription)
    self.onClosed()
    return false
end

-- Returns nil if the window can't be made. The options that need explaining:
-- placement: a Settings.windows entry, read when the window opens and updated when it closes;
-- page: the page to show first; nil shows the page holding the head in use;
-- toggle = { text, selected, onChange(selected) }: a check box, used only with withSearch;
-- extraButton = { text, onClick() }: a button at the end of the bottom row, used only without withSearch and hidden
-- while it has no text;
-- numberBox = { placeholder, onSubmit(number) }: a number field after Next, used only without withSearch;
-- marksPick = false: clicking a head doesn't mark it as the one in use;
-- nameOf(id, position), animationFor(id, position): position is the head's index in ids, in case a head is listed
-- twice.
function HeadGrid.open(PrettyUI, parent, options)
    local self = setmetatable({
        columns = options.columns, rows = options.rows, pageSize = options.columns * options.rows,
        nameOf = options.nameOf or function() return nil end,
        isPlayerHead = options.isPlayerHead or function() return false end,
        animationFor = options.animationFor or function() return nil end,
        pageLabel = options.pageLabel,
        onPick = options.onPick or function() end,
        onSearch = options.onSearch,
        onClosed = options.onClosed or function() end,
        placement = options.placement,
        marksPick = options.marksPick ~= false,
        cells = {}, nav = {}, closed = false, page = options.page, simpleButton = PrettyUI.SimpleButton,
    }, HeadGrid)
    local minWidth, minHeight = frameSize(self.columns, self.rows, MIN_CELL_W, MIN_CELL_H)
    minWidth = math.max(minWidth, options.minWidth or 0)
    local defaultWidth, defaultHeight = defaultSize(parent)
    local width, height = WindowPlacement.size(parent, self.placement, defaultWidth, defaultHeight, minWidth, minHeight)
    local x, y = WindowPlacement.position(parent, width, height, self.placement)
    self.contentWidth, self.contentHeight = contentSizeOf(width, height)
    local made = pcall(function()
        self.window = PrettyUI.Window.new(parent, {
            title = options.title, x = x, y = y, width = width, height = height,
            minWidth = math.min(minWidth, width), minHeight = math.min(minHeight, height),
            resizable = true, scrollable = false, destroyOnClose = true,
            onClose = function() self:release() end, -- closed with its X button, so the window destroys itself
        })
    end)
    if not made then return nil end
    local window, content = self.window, self.window.content
    -- Layers next to the window; see the top of this file.
    for _, layerName in ipairs({ "headsLayer", "labelsLayer" }) do
        local layer = ui.Layer.new(parent)
        layer.clickthrough = true
        layer:SetPos(0, 0)
        layer:SetSize(0, 0, 1.0, 1.0)
        self[layerName] = layer
    end
    -- Lays the grid out when the window is shown, resized or dropped. The labels layer is the registered overlay, so
    -- PrettyUI raises it after layout() raises the heads, and the labels end up on top.
    window:_RegisterOverlay(self.labelsLayer, nil, function() if not self.closed then self:layout() end end)
    -- A title-bar drag records each step through the drag bounds, so the layers follow the drag from there. Resizing
    -- records its steps there too, but then the overlay lays the layers out instead.
    local dragBounds = window.dragBounds
    local rememberPosition = dragBounds.RememberPosition
    dragBounds.RememberPosition = function(...)
        rememberPosition(...)
        if not self.closed and not self.sizing then self:layout() end
    end
    -- Clicking the title bar raises the window over the layers, and its hook stops later listeners from running. So the
    -- layers are raised again one frame after that handler disables the resize controller.
    raiseCount = raiseCount + 1
    self.raiseSubscription = "make_me_a_monster_grid_raise_" .. raiseCount
    local resize = window.resize
    local setResizeEnabled = resize.SetEnabled
    resize.SetEnabled = function(controller, enabled)
        setResizeEnabled(controller, enabled)
        if enabled or self.closed then return end
        Event.Draw.Subscribe(self.raiseSubscription, function()
            Event.Draw.Unsubscribe(self.raiseSubscription)
            if not self.closed then
                self.headsLayer:MoveToFront()
                self.labelsLayer:MoveToFront()
            end
        end)
    end
    -- The buttons say "Previous" and "Next" rather than showing arrows, because the game reads "<" in a button's text
    -- as the start of a markup tag.
    local nav = self.nav
    local buttonOptions = { width = NAV_BUTTON }
    nav.previous = PrettyUI.SimpleButton.new(content, "Previous", function() self:changePage(-1) end, buttonOptions)
    nav.after = PrettyUI.SimpleButton.new(content, "Next", function() self:changePage(1) end, buttonOptions)
    local function numberField(placeholder, onNumber)
        return PrettyUI.TextField.new(content, {
            width = NAV_NUMBER, height = 30, placeholder = placeholder, filterMode = ui.InputFieldFilterMode.NUMERIC,
            onSubmit = function(_, text)
                local number = tonumber(text)
                if number ~= nil and not self.closed then onNumber(math.floor(number)) end
            end,
        })
    end
    if options.withSearch then
        nav.search = PrettyUI.TextField.new(content, {
            width = 204, height = 30, placeholder = "Search name or id",
            onChange = function(_, _, text) if not self.closed then self.onSearch(text) end end,
        })
        nav.jump = numberField("Page", function(page) self:changePage(page - self.page) end)
    end
    if options.numberBox then nav.number = numberField(options.numberBox.placeholder, options.numberBox.onSubmit) end
    if options.extraButton then
        nav.extra = PrettyUI.SimpleButton.new(content, "", function()
            if not self.closed then options.extraButton.onClick() end
        end)
        nav.extra.root.hidden = true -- hidden until it has text to size it by
    end
    if options.toggle then
        nav.toggle = PrettyUI.CheckboxButton.new(content,
            { { text = options.toggle.text, value = true, selected = options.toggle.selected } }, {
                width = NAV_TOGGLE,
                onChange = function(_, _, _, selected)
                    if not self.closed then options.toggle.onChange(selected) end
                end,
            })
    end
    nav.label = ui.Text.new(content)
    nav.label.maxLines = 1
    nav.label.font = id.Font.MUSEO_SANS_11PT_REGULAR
    nav.label.rgba = TEXT_LIGHT
    if options.extraButton then self:setExtraButton(options.extraButton.text) end
    self:setHeads(options.ids, options.current, nil, options.page)
    -- The content only takes its new size a moment later, so the new content size is worked out here, within
    -- PrettyUI's limits, before PrettyUI lays out the overlay.
    local setWindowSize = self.window.SetSize
    self.window.SetSize = function(window, newWidth, newHeight)
        if not self.closed then
            newWidth = math.max(window.minWidth, math.min(window.maxWidth or newWidth, math.floor(newWidth)))
            newHeight = math.max(window.minHeight, math.min(window.maxHeight or newHeight, math.floor(newHeight)))
            self.contentWidth, self.contentHeight = contentSizeOf(newWidth, newHeight)
        end
        self.sizing = true
        setWindowSize(window, newWidth, newHeight)
        self.sizing = false
    end
    return self
end

-- Adds isOpen, updateAnimations, refreshHeadSize and close to a window module. currentGrid() returns the module's
-- grid, or nil.
function HeadGrid.addWindowFunctions(windowModule, currentGrid)
    local function liveGrid()
        local grid = currentGrid()
        return grid ~= nil and grid:stillLoaded() and grid or nil
    end
    function windowModule.isOpen() return liveGrid() ~= nil end
    function windowModule.updateAnimations() if liveGrid() then liveGrid():updateAnimations() end end
    function windowModule.refreshHeadSize() if liveGrid() then liveGrid():refreshHeadSize() end end
    function windowModule.close() if liveGrid() then liveGrid():close() end end
end

return HeadGrid
