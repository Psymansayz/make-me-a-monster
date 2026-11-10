-- The settings' controls, on the plugin's page or in their own window: the NPC search and dropdown, the buttons, the
-- head size slider and the animation dropdown, with the status texts.

local Settings = require("src/data/settings")
local NpcDirectory = require("src/game/npc_directory")
local Animations = require("src/game/animations")
local AnimationChoice = require("src/game/animation_choice")
local AllHeadsWindow = require("src/ui/all_heads_window")
local WindowPlacement = require("src/ui/window_placement")

local SettingsView = {}

local RESULTS_SHOWN = 40 -- NPCs listed in the dropdown at once
local NPC_PLACEHOLDER = "Pick one of the matches"
local OWN_HEAD_TEXT = "My own head" -- (the closed box with no NPC chosen)

local controls = nil -- the controls while they are built; .window is the window holding them, if one is
-- What the controls ask of the rest of the plugin (given to build): useOwnHead(), npcPicked(npcID, npcGroup,
-- selectedGroup), groupOfChosenNpc(), openVariants(), openAllHeads(), headSizeChanged(), animationChanged(); and
-- optionally extraControls(view), adding controls under the buttons (dev's debug ones).
local actions = nil
local npcEntries = nil -- the NPC dropdown's: { query, groups, members (the one that matched), labels, selected }
local animationEntries = nil -- the animation dropdown's: { options (the listings), selected }
local isRefreshingDropdown = false -- (SetEntries sends selection events too)

-- A dropdown's text doesn't follow a selection made from code: so its text is hidden and a label of ours laid over it.
-- Clicking it open puts it back. (Not on its change events: SetEntries sends those too.)
local coverStates = {} -- dropdown -> { colours, covered, label, shownText }

local function forgetControls()
    controls, coverStates, npcEntries, animationEntries = nil, {}, nil, nil
end

-- The controls, or nil. Their page or window can unload silently (no close runs): then they are forgotten, as they
-- went with it.
local function liveControls()
    if controls ~= nil and ui.Interfaces:GetInterface(controls.interfaceID) == nil then forgetControls() end
    return controls
end

local function isCovered(dropdown)
    return coverStates[dropdown] ~= nil and coverStates[dropdown].covered
end

-- The label laid over a dropdown's own text: inset 8, clear of its arrow button (as wide as the box is high); its
-- width follows the view's.
local function makeCoverLabel(dropdownRoot, colours)
    local label = ui.Text.new(dropdownRoot.parent)
    label.clickthrough = true
    label.maxLines = 1
    label.alignHorizontal = ui.AlignMode.TOPLEFT
    label.alignVertical = ui.AlignMode.CENTRE
    label:SetPos(dropdownRoot.x + 8, dropdownRoot.y)
    label:SetSize(dropdownRoot.width - 8 - dropdownRoot.height - dropdownRoot.parent.width, dropdownRoot.height, 1.0, 0)
    label.font = dropdownRoot.entryText.font
    label.rgba, label.isShadowed = colours[1], colours.isShadowed
    return label
end

-- overlayText: what the covered box shows, or nil for a blank one.
local function coverDropdownText(dropdown, hideText, overlayText)
    pcall(function()
        local dropdownRoot = dropdown.root
        local coverState = coverStates[dropdown]
        if coverState == nil then
            coverState = { covered = false }
            coverStates[dropdown] = coverState
        end
        if hideText then
            if coverState.covered and coverState.shownText == overlayText then return end
            if not coverState.covered then
                coverState.colours = {
                    dropdownRoot.entryText.rgba, dropdownRoot.selectedForegroundRGBA,
                    dropdownRoot.mouseoverForegroundRGBA,
                    alpha = dropdownRoot.entryText.alpha, isShadowed = dropdownRoot.entryText.isShadowed,
                }
                coverState.covered = true
                dropdownRoot.entryText.rgba = 0
                dropdownRoot.selectedForegroundRGBA, dropdownRoot.mouseoverForegroundRGBA = 0, 0
                dropdownRoot.entryText.alpha, dropdownRoot.entryText.isShadowed = 0, false
            end
            coverState.shownText = overlayText
            if overlayText == nil then
                if coverState.label ~= nil then coverState.label.hidden = true end
                return
            end
            coverState.label = coverState.label or makeCoverLabel(dropdownRoot, coverState.colours)
            coverState.label.content = overlayText
            coverState.label.hidden = false
            coverState.label:MoveToFront()
        elseif coverState.covered then
            local savedColours = coverState.colours
            coverState.covered, coverState.shownText = false, nil
            if coverState.label ~= nil then coverState.label.hidden = true end
            dropdownRoot.entryText.rgba = savedColours[1]
            dropdownRoot.selectedForegroundRGBA, dropdownRoot.mouseoverForegroundRGBA = savedColours[2], savedColours[3]
            dropdownRoot.entryText.alpha = savedColours.alpha
            dropdownRoot.entryText.isShadowed = savedColours.isShadowed
        end
    end)
end

local function showTextWhenClicked(dropdown)
    dropdown.root:Subscribe(ui.Hook.ONCLICK, function()
        coverDropdownText(dropdown, false)
        return false
    end)
end

-- Fills a dropdown and covers its closed box with closedText (nil: blank).
local function fillDropdown(dropdown, entries, selected, closedText)
    isRefreshingDropdown = true
    pcall(function() dropdown:SetEntries(entries, selected) end)
    isRefreshingDropdown = false
    coverDropdownText(dropdown, true, closedText)
end

local function isSelectionEvent(eventType)
    return eventType == nil or eventType == ui.SelectionChangeEvent.SELECTED
end

-- A text written only when it changes.
local function setText(textName, content)
    if controls[textName .. "Shown"] ~= content then
        controls[textName .. "Shown"] = content
        controls[textName].content = content
    end
end

local function chatheadStatusMessage()
    local npcID = Settings.chosenNpcID
    if npcID == nil then return "Current chathead: my own head" end
    local npcName = NpcDirectory.nameOfNpc(npcID)
    local npcGroup = NpcDirectory.groupOfNpc(npcID)
    local variantSuffix = npcGroup and npcGroup.idCount > 1 and (" (variant ID " .. npcID .. ")") or ""
    return "Current chathead: " .. (npcName or ("NPC " .. npcID)) .. variantSuffix
end

-- The heads window shows NPC heads, whatever head is in use.
local function npcAnimationsShown()
    return not AnimationChoice.playerAnimationsInUse() or AllHeadsWindow.isOpen()
end

local function animationStatusText()
    local shownAnimation = AnimationChoice.shown(npcAnimationsShown())
    if shownAnimation == nil then return "" end
    return "Animation: " .. (Animations.labelOf(shownAnimation) or ("ID " .. shownAnimation))
end

function SettingsView.refreshStatusTexts()
    if liveControls() == nil then return end
    setText("chatheadStatusText", chatheadStatusMessage())
    setText("animationStatusText", animationStatusText())
end

-- Fills the animation dropdown for the head in use: a head of a set lists the set's animations. (Not again while it
-- shows the same.)
function SettingsView.refreshAnimationDropdown()
    if liveControls() == nil then return end
    local npcHeads = npcAnimationsShown()
    local options = Animations.options(not npcHeads, AnimationChoice.setInUse())
    local shownAnimation = AnimationChoice.shown(npcHeads)
    local selected = nil
    for entryID, listing in ipairs(options) do
        if listing.id == shownAnimation then
            selected = entryID
            break
        end
    end
    local dropdown = controls.animationDropdown
    if animationEntries ~= nil and animationEntries.options == options and animationEntries.selected == selected
        and isCovered(dropdown) then
        return
    end
    animationEntries = { options = options, selected = selected }
    local entries = {}
    for entryID, listing in ipairs(options) do entries[entryID] = { label = listing.label, id = entryID } end
    fillDropdown(dropdown, entries, selected, selected and options[selected].label or nil)
end

-- A name equal to its group's stands for the whole group (Fairy holds Jukat too): so it counts the group's heads.
local function labelOfEntry(npcGroup, member, memberNpcCount)
    if member == nil or NpcDirectory.lowerCaseAscii(member.name) == NpcDirectory.lowerCaseAscii(npcGroup.name) then
        return NpcDirectory.labelOf(npcGroup.name, npcGroup.idCount)
    end
    return NpcDirectory.labelOf(member.name, memberNpcCount or #member)
end

-- Fills the NPC dropdown with the groups matching the search. With nothing typed the NPC chosen stays listed, so the
-- dropdown can show it after a restart. (Not again while it shows the same.)
function SettingsView.refreshNpcDropdown()
    if liveControls() == nil then return end
    local query = controls.npcSearchBox:GetText()
    local queryWords = NpcDirectory.wordsOfQuery(query)
    local matchingGroups = NpcDirectory.searchGroups(queryWords, RESULTS_SHOWN)
    local matchCount = #matchingGroups
    local chosenGroup = actions.groupOfChosenNpc()
    local chosenMember = chosenGroup and NpcDirectory.memberOfNpc(Settings.chosenNpcID, chosenGroup)
    if chosenGroup ~= nil and queryWords.blank then
        local alreadyListed = false
        for _, npcGroup in ipairs(matchingGroups) do
            if npcGroup == chosenGroup then
                alreadyListed = true
                break
            end
        end
        if not alreadyListed then table.insert(matchingGroups, 1, chosenGroup) end
    end
    local labels, members, selected = {}, {}, nil
    for entryID, npcGroup in ipairs(matchingGroups) do
        -- An entry shows the name that matched the search; the chosen NPC's group shows that NPC's name instead.
        local matchedMember, matchedNpcCount = NpcDirectory.memberMatching(npcGroup, queryWords)
        if npcGroup == chosenGroup then
            selected = entryID
            if chosenMember ~= nil then matchedMember, matchedNpcCount = chosenMember, nil end
        end
        labels[entryID] = labelOfEntry(npcGroup, matchedMember, matchedNpcCount)
        members[entryID] = matchedMember
    end
    local joinedLabels = table.concat(labels, "\n")
    local dropdown = controls.npcDropdown
    local unchanged = npcEntries ~= nil and npcEntries.labels == joinedLabels and npcEntries.selected == selected
        and isCovered(dropdown)
    npcEntries = {
        query = query, groups = matchingGroups, members = members, labels = joinedLabels, selected = selected,
    }
    if not unchanged then
        local entries = {}
        for entryID, label in ipairs(labels) do entries[entryID] = { label = label, id = entryID } end
        fillDropdown(dropdown, entries, selected, selected and labels[selected]
            or (Settings.chosenNpcID == nil and OWN_HEAD_TEXT) or NPC_PLACEHOLDER)
    end
    setText("matchCountText", matchCount == RESULTS_SHOWN and ("Showing the first " .. RESULTS_SHOWN .. " matches.")
        or (matchCount .. " matches."))
end

-- Builds the controls in a PrettyUI view (window: the window holding it, else nil) and fills the NPC dropdown; the
-- caller fills the animation dropdown, once the animation is fitted to the head in use.
function SettingsView.build(view, window, givenActions)
    actions = givenActions
    local built = { window = window, interfaceID = view.interfaceID }
    view:AddText("Pick an NPC: its head replaces yours in dialogue boxes.")
    built.chatheadStatusText = view:AddText(chatheadStatusMessage())
    built.npcSearchBox = view:AddTextField({
        placeholder = "Search NPCs by name or id",
        -- (Enter sends the text again: no new search for it)
        onChange = function(_, _, text)
            if npcEntries == nil or text ~= npcEntries.query then SettingsView.refreshNpcDropdown() end
        end,
    })
    built.matchCountText = view:AddText("")
    local function onNpcSelection(entryID, eventType)
        local npcGroup = npcEntries and npcEntries.groups[entryID]
        if isRefreshingDropdown or not isSelectionEvent(eventType) or npcGroup == nil then return end
        coverDropdownText(built.npcDropdown, false)
        -- The first NPC of the name that matched the search, else of the group.
        local matchedMember = npcEntries.members[entryID]
        local npcID = matchedMember and matchedMember[1] or npcGroup.shownID
        -- A member's name can be another group's.
        local label = matchedMember and matchedMember.name or npcGroup.name
        actions.npcPicked(npcID, npcGroup,
            label == npcGroup.name and npcGroup or NpcDirectory.groupLabelled(npcID, label))
    end
    built.npcDropdown = view:AddComboBox({
        entries = {},
        onChange = function(_, entryID, _, eventType) onNpcSelection(entryID, eventType) end,
    })
    showTextWhenClicked(built.npcDropdown)
    view:AddSimpleButton("View variants", function() actions.openVariants() end)
    view:AddSimpleButton("Browse all heads", function() actions.openAllHeads() end)
    view:AddSimpleButton("Use my own head", function() actions.useOwnHead() end)
    if actions.extraControls ~= nil then actions.extraControls(view) end
    built.noticeText = view:AddText("")
    built.headSizeText = view:AddText("Head size: " .. Settings.headSizePercent() .. "%")
    local limits = Settings.HEAD_SIZE_PERCENT
    view:AddSlider({
        min = limits.min, max = limits.max, step = limits.step, value = Settings.headSizePercent(),
        -- (a drag sends many values that round to the same size: only a new size is shown)
        onChange = function(_, sliderValue)
            local before = Settings.headSizePercent()
            local percent = Settings.setHeadSizePercent(sliderValue)
            if percent == before then return end
            actions.headSizeChanged()
            built.headSizeText.content = "Head size: " .. percent .. "%"
        end,
    })
    view:AddText("Animation for the head:")
    built.animationStatusText = view:AddText(animationStatusText())
    built.animationDropdown = view:AddComboBox({
        entries = {},
        onChange = function(_, entryID, _, eventType)
            local listing = animationEntries and animationEntries.options[entryID]
            if isRefreshingDropdown or not isSelectionEvent(eventType) or listing == nil then return end
            Settings.chooseAnimation(listing.id)
            coverDropdownText(built.animationDropdown, false)
            actions.animationChanged()
        end,
    })
    showTextWhenClicked(built.animationDropdown)
    view:AddSimpleButton("Use default animation", function()
        Settings.chooseAnimation(nil)
        actions.animationChanged()
        SettingsView.refreshAnimationDropdown()
    end)
    controls = built
    SettingsView.refreshNpcDropdown()
end

-- Forgets the controls, which go with their view; a window's place is noted for next time.
function SettingsView.release()
    if liveControls() == nil then return end
    if controls.window ~= nil then WindowPlacement.remember(controls.window, Settings.windows.settings) end
    forgetControls()
end

function SettingsView.isBuilt()
    return liveControls() ~= nil
end

-- The window holding the controls, or nil (on the page, or not built).
function SettingsView.window()
    return liveControls() and controls.window
end

function SettingsView.setNotice(text)
    if liveControls() ~= nil then setText("noticeText", text) end
end

-- Empties the search box, without a search: the caller refreshes the dropdown.
function SettingsView.clearSearch()
    if liveControls() ~= nil then controls.npcSearchBox:SetText("") end
end

return SettingsView
