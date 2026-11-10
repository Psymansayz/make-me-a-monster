-- Where a window opens and how big: as it was left (its placement in Settings.windows), else a default size in the
-- middle; kept on the screen.

local WindowPlacement = {}

-- The size it was left at, else the default; at least the least size, unless the screen is smaller.
function WindowPlacement.size(parent, placement, defaultWidth, defaultHeight, minWidth, minHeight)
    local width, height = placement.width or defaultWidth, placement.height or defaultHeight
    width = math.max(math.min(minWidth, parent.width), math.min(width, parent.width))
    height = math.max(math.min(minHeight, parent.height), math.min(height, parent.height))
    return width, height
end

-- The top left corner on parent for a window of this size.
function WindowPlacement.position(parent, width, height, placement)
    local x, y = placement.x, placement.y
    if x == nil or y == nil then
        x, y = math.floor((parent.width - width) / 2), math.floor((parent.height - height) / 2)
    end
    return math.max(0, math.min(x, parent.width - width)), math.max(0, math.min(y, parent.height - height))
end

-- Notes where the window is and its size, for it to open there next.
function WindowPlacement.remember(window, placement)
    local root = window.root
    placement.x, placement.y = math.max(0, math.floor(root.x)), math.max(0, math.floor(root.y))
    placement.width, placement.height = math.floor(root.width), math.floor(root.height)
end

return WindowPlacement
