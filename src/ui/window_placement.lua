-- Where a window opens and how big it is: as it was last left (its placement in Settings.windows), or otherwise at a
-- default size in the middle, always kept on the screen.

local WindowPlacement = {}

-- At least the minimum size, unless the screen is smaller.
function WindowPlacement.size(parent, placement, defaultWidth, defaultHeight, minWidth, minHeight)
    local width, height = placement.width or defaultWidth, placement.height or defaultHeight
    width = math.max(math.min(minWidth, parent.width), math.min(width, parent.width))
    height = math.max(math.min(minHeight, parent.height), math.min(height, parent.height))
    return width, height
end

function WindowPlacement.position(parent, width, height, placement)
    local x, y = placement.x, placement.y
    if x == nil or y == nil then
        x, y = math.floor((parent.width - width) / 2), math.floor((parent.height - height) / 2)
    end
    return math.max(0, math.min(x, parent.width - width)), math.max(0, math.min(y, parent.height - height))
end

function WindowPlacement.remember(window, placement)
    local root = window.root
    placement.x, placement.y = math.max(0, math.floor(root.x)), math.max(0, math.floor(root.y))
    placement.width, placement.height = math.floor(root.width), math.floor(root.height)
end

return WindowPlacement
