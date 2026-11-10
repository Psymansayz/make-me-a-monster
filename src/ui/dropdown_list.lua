-- The game's combo field (PrettyUI's ComboBox) has a search bar of its own that matches only the start of the names
-- listed, and the plugin can't read what is typed in it: so the NPC dropdown is the game's plain dropdown list, which
-- has none, leaving the plugin's own search box (matching anywhere in a name, as the heads window does).

local DropdownList = {}

local MAX_VISIBLE_ENTRIES = 8
local PLACEHOLDER_ID = 0 -- (entries are numbered from 1)

-- Turns a ComboBox just added to a PrettyUI view into a dropdown list in its place: the view lays the box out by its
-- root, so the list becomes the root. onSelection(entryID, eventType) replaces the box's onChange; placeholder is the
-- text shown while no entry is chosen.
function DropdownList.replaceComboBox(comboBox, onSelection, placeholder)
    local field = comboBox.root
    local list = ui.List.new(field.parent)
    list.stylesheetID = id.StyleSheet.DROPDOWN_DEFAULT
    list:SetPos(field.x, field.y)
    list:SetSize(field.width, field.height)
    list.dropdownMaxVisibleEntries = MAX_VISIBLE_ENTRIES
    list.entryHeight = field.entryHeight
    list.contentMargin, list.headerMargin = field.contentMargin, field.headerMargin
    list.entryText.font, list.entryText.rgba = field.entryText.font, field.entryText.rgba
    list.entryText.isShadowed = field.entryText.isShadowed
    list:Subscribe(ui.Hook.ONSELECTIONCHANGED, function(_, entryID, eventType)
        onSelection(entryID, eventType)
        return false
    end)
    field:Destroy()
    comboBox.root, comboBox.isList = list, true
    -- A dropdown list always has an entry selected, the first if none is: that one could not be picked (no change, no
    -- event). So with none chosen, a placeholder is the one selected: shown in the closed box, hidden in the list.
    -- (the combo field's Select and selection fields are not the list's; labels may repeat, so no label map)
    comboBox.SetEntries = function(_, entries, selectedID)
        list:Clear()
        if selectedID == nil then list:Add(placeholder, PLACEHOLDER_ID) end
        for _, entry in ipairs(entries) do list:Add(entry.label, entry.id) end
        list:SetEntrySelected(selectedID or PLACEHOLDER_ID, true, false)
        if selectedID == nil then list:SetEntryVisible(PLACEHOLDER_ID, false) end
    end
    return comboBox
end

return DropdownList
