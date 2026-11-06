-- Make Me A Monster: choose an NPC in the settings, and its head replaces yours in the game's
-- dialogue boxes.

local Settings = require("src/data/settings")
local NpcDirectory = require("src/game/npc_directory")
local HeadSwap = require("src/game/head_swap")
local VariantsWindow = require("src/ui/variants_window")
local AllHeadsWindow = require("src/ui/all_heads_window")
local Animations = require("src/game/animations")

local PrettyUI = prettyui

local RESULTS_SHOWN = 40 -- NPCs listed in the dropdown at once

local function updateOpenWindows()
    HeadSwap.refreshOpenDialogues()
    AllHeadsWindow.updateAnimations()
    VariantsWindow.updateAnimations()
end

Settings.load()
HeadSwap.start()
VariantsWindow.animationForNpcHeads = function(npcID) return HeadSwap.npcHeadAnimation(npcID) end
-- The window shows NPC heads: they play the NPC version of the animation chosen, whichever head is in use.
AllHeadsWindow.animationForNpcHeads = VariantsWindow.animationForNpcHeads
VariantsWindow.animationForPlayerHead = function() return HeadSwap.playerHeadAnimation(true) end

-- The saved heads are not loaded until the settings are first built: dialogue needs only the saved NPC id.
local engaged = false

local pluginPageLayer = nil -- the layer the client gives the plugin's page
local pluginPageToggle = nil -- the page's button switching the settings between the page and their own window
local pluginPageView = nil -- what the page holds under that button
local pageNoticeText = nil -- says on the page why the window did not open
local settingsControls = nil -- the controls while they are built; .window is the window holding them, if one is
local matchedMembersByEntryID = {} -- entry id -> the member of the group that matched the search, or nil
local groupsByEntryID = {} -- entry id -> the group
local listingsByEntryID = {} -- entry id -> the animation
local isRefreshingNpcDropdown = false
local isRefreshingAnimationDropdown = false

-- A dropdown's text doesn't follow a selection made from code: so its text is hidden and a label of ours laid over it.
-- Clicking it open puts it back. (Not on its change events: SetEntries sends those too.)
local coverStates = {} -- dropdown -> { colours, covered, label }

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
            if not coverState.covered then
                coverState.colours = { dropdownRoot.entryText.rgba, dropdownRoot.selectedForegroundRGBA, dropdownRoot.mouseoverForegroundRGBA,
                    alpha = dropdownRoot.entryText.alpha, isShadowed = dropdownRoot.entryText.isShadowed }
                coverState.covered = true
                dropdownRoot.entryText.rgba, dropdownRoot.selectedForegroundRGBA, dropdownRoot.mouseoverForegroundRGBA = 0, 0, 0
                dropdownRoot.entryText.alpha, dropdownRoot.entryText.isShadowed = 0, false
            end
            if overlayText == nil then
                if coverState.label ~= nil then coverState.label.hidden = true end
                return
            end
            local overlayLabel = coverState.label
            if overlayLabel == nil then
                overlayLabel = ui.Text.new(dropdownRoot.parent)
                overlayLabel.clickthrough = true
                overlayLabel.maxLines = 1
                overlayLabel.alignHorizontal = ui.AlignMode.TOPLEFT
                overlayLabel.alignVertical = ui.AlignMode.CENTRE
                coverState.label = overlayLabel
            end
            -- Where the box's own text goes: inset 8, clear of its arrow button (as wide as the box is high).
            overlayLabel:SetPos(dropdownRoot.x + 8, dropdownRoot.y)
            overlayLabel:SetSize(math.max(1, dropdownRoot.width - 8 - dropdownRoot.height), dropdownRoot.height)
            overlayLabel.font = dropdownRoot.entryText.font
            overlayLabel.rgba = coverState.colours[1]
            overlayLabel.isShadowed = coverState.colours.isShadowed
            overlayLabel.content = overlayText
            overlayLabel.hidden = false
            overlayLabel:MoveToFront()
        elseif coverState.covered then
            local savedColours = coverState.colours
            coverState.covered = false
            if coverState.label ~= nil then coverState.label.hidden = true end
            dropdownRoot.entryText.rgba, dropdownRoot.selectedForegroundRGBA, dropdownRoot.mouseoverForegroundRGBA = savedColours[1], savedColours[2], savedColours[3]
            dropdownRoot.entryText.alpha, dropdownRoot.entryText.isShadowed = savedColours.alpha, savedColours.isShadowed
        end
    end)
end

local function showTextWhenClicked(dropdown)
    pcall(function()
        dropdown.root:Subscribe(ui.Hook.ONCLICK, function()
            coverDropdownText(dropdown, false)
            return false
        end)
    end)
end

local function findSelectedEntryID(shownItems, isChosen)
    for entryID, shownItem in pairs(shownItems) do
        if isChosen(shownItem) then return entryID end
    end
    return nil
end

local function chatheadStatusMessage()
    local npcID = Settings.chosenNpcID
    if npcID == nil then return "Current chathead: my own head" end
    local npcName = NpcDirectory.nameOfNpc(npcID)
    local npcGroup = NpcDirectory.groupOfNpc(npcID)
    local variantSuffix = npcGroup and #npcGroup.ids > 1 and (" (variant ID " .. npcID .. ")") or ""
    return "Current chathead: " .. (npcName or ("NPC " .. npcID)) .. variantSuffix
end

local function animationStatusText()
    local chosenAnimation = Settings.chosenAnimationID
    if chosenAnimation ~= nil then
        return "Animation: " .. (Animations.labelOf(chosenAnimation) or ("ID " .. chosenAnimation))
    end
    return ""
end

local function refreshStatusTexts()
    if settingsControls then
        settingsControls.chatheadStatusText.content = chatheadStatusMessage()
        settingsControls.animationStatusText.content = animationStatusText()
    end
end

-- Whether the head in use plays the player's animations: the player's own head, or an NPC head on the player's rig.
local function playerAnimationsInUse()
    return Settings.chosenNpcID == nil or Animations.isOnPlayerRig(Settings.chosenNpcID)
end

-- Keeps the chosen animation one that the head in use can play.
local function fitAnimationToHead()
    if Settings.chosenAnimationID == nil then return end
    -- The heads window shows NPC heads: the animation stays as it is until it closes.
    if playerAnimationsInUse() and AllHeadsWindow.isOpen() then return end
    local fittedAnimation = HeadSwap.animationForHead(Settings.chosenAnimationID, playerAnimationsInUse())
    if fittedAnimation ~= Settings.chosenAnimationID then
        Settings.chosenAnimationID = fittedAnimation
        updateOpenWindows()
    end
end

-- Fills the animation dropdown for the head in use. A choice saved earlier that is no longer listed is cleared.
local function refreshAnimationDropdown()
    if not engaged then return end
    -- (also with the settings closed: a heads window can stay open and change the head in use)
    fitAnimationToHead()
    if Settings.chosenAnimationID ~= nil and not Animations.isListed(Settings.chosenAnimationID) then
        Settings.chosenAnimationID = nil
        updateOpenWindows()
        refreshStatusTexts()
    end
    if settingsControls == nil then return end
    -- The heads window shows NPC heads, whatever head is in use.
    local npcHeads = not playerAnimationsInUse() or AllHeadsWindow.isOpen()
    local listedAnimations = Animations.options(not npcHeads)
    local entries = {}
    listingsByEntryID = {}
    for entryID, listing in ipairs(listedAnimations) do
        entries[#entries + 1] = { label = listing.label, id = entryID }
        listingsByEntryID[entryID] = listing
    end
    local shownChoiceID = Settings.chosenAnimationID
    if npcHeads then shownChoiceID = HeadSwap.animationForHead(shownChoiceID, false) end
    local selected = findSelectedEntryID(listingsByEntryID, function(listing) return listing.id == shownChoiceID end)
    isRefreshingAnimationDropdown = true
    pcall(function() settingsControls.animationDropdown:SetEntries(entries, selected) end)
    isRefreshingAnimationDropdown = false
    coverDropdownText(settingsControls.animationDropdown, true, selected ~= nil and listingsByEntryID[selected].label or nil)
end

-- A head can be in several groups: the one the head chosen was picked from, kept for this session.
local pickedGroup = nil

local function groupOfChosenNpc()
    local npcID = Settings.chosenNpcID
    if npcID == nil then return nil end
    for _, groupNpcID in ipairs(pickedGroup and pickedGroup.ids or {}) do
        if groupNpcID == npcID then return pickedGroup end
    end
    return NpcDirectory.groupOfNpc(npcID)
end

-- A name equal to its group's stands for the whole group (Fairy holds Jukat too): so it counts the group's heads.
local function labelOfEntry(npcGroup, member, memberNpcCount)
    if member == nil or NpcDirectory.lowerCaseAscii(member.name) == NpcDirectory.lowerCaseAscii(npcGroup.name) then
        return NpcDirectory.labelOfGroup(npcGroup, #npcGroup.ids)
    end
    return NpcDirectory.labelOfMember(member, memberNpcCount)
end

local function refreshNpcDropdown()
    if settingsControls == nil then return end
    local query = ""
    pcall(function() query = settingsControls.npcSearchBox:GetText() end)
    local matchingGroups = NpcDirectory.searchGroups(query, RESULTS_SHOWN)
    local matchCount = #matchingGroups
    local chosenGroup = groupOfChosenNpc()
    local chosenMember = Settings.chosenNpcID and NpcDirectory.memberOfNpc(Settings.chosenNpcID, chosenGroup) or nil
    -- With nothing typed the NPC chosen stays listed, so the dropdown can show it after a restart.
    if chosenGroup ~= nil and query:find("^%s*$") then
        local alreadyListed = false
        for _, npcGroup in ipairs(matchingGroups) do
            if npcGroup == chosenGroup then alreadyListed = true end
        end
        if not alreadyListed then table.insert(matchingGroups, 1, chosenGroup) end
    end
    local entries = {}
    groupsByEntryID, matchedMembersByEntryID = {}, {}
    for entryID, npcGroup in ipairs(matchingGroups) do
        -- An entry shows the name that matched the search; the chosen NPC's group shows that NPC's name instead.
        local matchedMember, matchedNpcCount = NpcDirectory.memberMatching(npcGroup, query)
        if npcGroup == chosenGroup and chosenMember ~= nil then matchedMember, matchedNpcCount = chosenMember, nil end
        entries[#entries + 1] = { label = labelOfEntry(npcGroup, matchedMember, matchedNpcCount), id = entryID }
        groupsByEntryID[entryID] = npcGroup
        matchedMembersByEntryID[entryID] = matchedMember
    end
    local selected = findSelectedEntryID(groupsByEntryID, function(npcGroup) return npcGroup == chosenGroup end)
    isRefreshingNpcDropdown = true
    pcall(function() settingsControls.npcDropdown:SetEntries(entries, selected) end)
    isRefreshingNpcDropdown = false
    -- The closed box shows the NPC's name, or nothing if it isn't in the list.
    if selected ~= nil and chosenMember ~= nil then
        coverDropdownText(settingsControls.npcDropdown, true, labelOfEntry(chosenGroup, chosenMember))
    else
        coverDropdownText(settingsControls.npcDropdown, selected == nil)
    end
    pcall(function()
        settingsControls.matchCountText.content = matchCount == RESULTS_SHOWN and ("Showing the first " .. RESULTS_SHOWN .. " matches.")
            or (matchCount .. " matches.")
    end)
end

-- Defined below.
local openVariantsWindow
local closeSettingsWindow
local switchSettings
local openAllHeadsWindow

-- chosenFrom: "dropdown" or "variants" if that already shows the choice. selectedGroup: the group the head was selected
-- under, if its label named one.
local function chooseNpc(npcID, chosenFrom, selectedGroup)
    Settings.chosenNpcID = npcID
    if chosenFrom == nil then pickedGroup = selectedGroup end
    if selectedGroup ~= nil then VariantsWindow.selectGroup(npcID, selectedGroup) end
    refreshAnimationDropdown()
    HeadSwap.refreshOpenDialogues()
    if chosenFrom ~= "dropdown" then refreshNpcDropdown() end
    if chosenFrom ~= "variants" and VariantsWindow.isOpen() then openVariantsWindow() end
    refreshStatusTexts()
end

local function isSelectionEvent(eventType)
    local succeeded, selected = pcall(function() return eventType == ui.SelectionChangeEvent.SELECTED end)
    return not succeeded or selected or eventType == nil
end

-- The variants window's button text for the NPC chosen, or nil if it is in no other group.
local function nextGroupButtonText(npcGroup)
    local nextGroup = NpcDirectory.nextGroupOfNpc(Settings.chosenNpcID, npcGroup)
    return nextGroup and ("View " .. nextGroup.name .. " variants") or nil
end

-- page: the page to show, else that of the head chosen.
local function showVariantsOf(npcGroup, page)
    pickedGroup = npcGroup -- (a variant picked in the window stays in this group)
    local showPlayerHeadOnly = Settings.chosenNpcID == nil
    local noticeText = ""
    if npcGroup == nil and not showPlayerHeadOnly then
        noticeText = "Choose an NPC first."
    else
        local succeeded, pluginLayer = pcall(function()
            return ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__PLUGIN_BUILD_LAYER_TOP)
        end)
        if succeeded and pluginLayer ~= nil then
            local function chooseFromVariants(npcID)
                chooseNpc(npcID ~= VariantsWindow.PLAYER_HEAD_ID and npcID or nil, "variants")
                if Settings.chosenNpcID ~= nil then
                    VariantsWindow.remember(Settings.chosenNpcID, pickedGroup)
                    VariantsWindow.setButton(nextGroupButtonText(pickedGroup))
                end
            end
            if showPlayerHeadOnly then
                VariantsWindow.open(PrettyUI, pluginLayer, "My head", { VariantsWindow.PLAYER_HEAD_ID }, VariantsWindow.PLAYER_HEAD_ID, chooseFromVariants)
            else
                VariantsWindow.remember(Settings.chosenNpcID, npcGroup)
                VariantsWindow.open(PrettyUI, pluginLayer, npcGroup.name .. " variants", npcGroup.ids,
                    Settings.chosenNpcID, chooseFromVariants, NpcDirectory.nameOfNpc, {
                        page = page,
                        buttonText = nextGroupButtonText(npcGroup),
                        onButton = function()
                            showVariantsOf(NpcDirectory.nextGroupOfNpc(Settings.chosenNpcID, pickedGroup))
                            refreshNpcDropdown()
                        end,
                    })
            end
        else
            noticeText = "The game screen isn't ready."
        end
    end
    if settingsControls then settingsControls.noticeText.content = noticeText end
end

openVariantsWindow = function()
    local npcID = Settings.chosenNpcID
    if npcID == nil then return showVariantsOf(nil) end
    showVariantsOf(VariantsWindow.firstView(npcID, NpcDirectory.groupsOfNpc(npcID)))
end

-- The settings window's size, unless the screen is smaller.
local SETTINGS_WIDTH, SETTINGS_HEIGHT = 420, 560

local function buildSettingsControls(view, window)
    view:AddText("Pick an NPC: its head replaces yours in dialogue boxes.")
    local controls = { window = window }
    controls.chatheadStatusText = view:AddText(chatheadStatusMessage())
    controls.npcSearchBox = view:AddTextField({
        placeholder = "Search NPCs by name or id",
        onChange = function() refreshNpcDropdown() end,
    })
    controls.matchCountText = view:AddText("")
    controls.npcDropdown = view:AddComboBox({
        entries = {},
        onChange = function(_, entryID, _, eventType)
            local npcGroup = groupsByEntryID[entryID]
            if isRefreshingNpcDropdown or not isSelectionEvent(eventType) or npcGroup == nil then return end
            coverDropdownText(controls.npcDropdown, false)
            -- The first NPC of the name that matched the search, else of the group.
            local matchedMember = matchedMembersByEntryID[entryID]
            pickedGroup = npcGroup
            local npcID = (matchedMember or npcGroup).ids[1]
            -- A member's name can be another group's.
            local label = matchedMember and matchedMember.name or npcGroup.name
            chooseNpc(npcID, "dropdown",
                label == npcGroup.name and npcGroup or NpcDirectory.groupLabelled(npcID, label))
        end,
    })
    showTextWhenClicked(controls.npcDropdown)
    view:AddSimpleButton("View variants", function() openVariantsWindow() end)
    view:AddSimpleButton("Browse all heads", function() openAllHeadsWindow() end)
    view:AddSimpleButton("Use my own head", function() chooseNpc(nil) end)
    controls.noticeText = view:AddText("")
    controls.headSizeText = view:AddText("Head size: " .. Settings.headSizePercent() .. "%")
    view:AddSlider({
        min = 50,
        max = 300,
        step = 5,
        value = Settings.headSizePercent(),
        onChange = function(_, sliderValue)
            local percent = math.max(50, math.min(300, math.floor(sliderValue / 5 + 0.5) * 5))
            Settings.setHeadSizePercent(percent)
            HeadSwap.refreshHeadViewDistance()
            AllHeadsWindow.refreshHeadSize()
            VariantsWindow.refreshHeadSize()
            controls.headSizeText.content = "Head size: " .. percent .. "%"
        end,
    })
    view:AddText("Animation for the head:")
    controls.animationStatusText = view:AddText(animationStatusText())
    controls.animationDropdown = view:AddComboBox({
        entries = {},
        onChange = function(_, entryID, _, eventType)
            local selectedListing = listingsByEntryID[entryID]
            if isRefreshingAnimationDropdown or not isSelectionEvent(eventType) or selectedListing == nil then
                return
            end
            Settings.chosenAnimationID = selectedListing.id
            coverDropdownText(controls.animationDropdown, false)
            updateOpenWindows()
            refreshStatusTexts()
        end,
    })
    showTextWhenClicked(controls.animationDropdown)
    view:AddSimpleButton("Use default animation", function()
        Settings.chosenAnimationID = nil
        updateOpenWindows()
        refreshAnimationDropdown()
        refreshStatusTexts()
    end)
    settingsControls = controls
    refreshNpcDropdown()
    refreshAnimationDropdown()
end

-- A page's layer can be gone by now, its interface unloading silently: so the dropdowns' labels go under pcall.
local function releaseSettingsControls()
    if settingsControls.window ~= nil then
        local windowRoot = settingsControls.window.root
        Settings.settingsX, Settings.settingsY = math.floor(windowRoot.x), math.floor(windowRoot.y)
    end
    for _, coverState in pairs(coverStates) do
        if coverState.label ~= nil then pcall(function() coverState.label:Destroy() end) end
    end
    coverStates = {}
    settingsControls = nil
end

closeSettingsWindow = function()
    if settingsControls == nil or settingsControls.window == nil then return end
    local window = settingsControls.window
    releaseSettingsControls()
    window:Destroy()
end

local function engage()
    engaged = true
    if not NpcDirectory.isLoaded then NpcDirectory.loadListedHeads(require("src/data/listed_heads")) end
end

-- Opening it again brings it to the front.
local function openSettingsWindow()
    if settingsControls ~= nil then return settingsControls.window:Show() end
    local succeeded, pluginLayer = pcall(function()
        return ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__PLUGIN_BUILD_LAYER_TOP)
    end)
    if not succeeded or pluginLayer == nil then
        pageNoticeText.content = "The game screen isn't ready."
        return
    end
    pageNoticeText.content = ""
    engage()
    local width = math.min(SETTINGS_WIDTH, pluginLayer.width)
    local height = math.min(SETTINGS_HEIGHT, pluginLayer.height)
    -- Where it was left, else the middle (kept on the screen).
    local x = Settings.settingsX or math.floor((pluginLayer.width - width) / 2)
    local y = Settings.settingsY or math.floor((pluginLayer.height - height) / 2)
    local window = nil
    local opened = pcall(function()
        window = PrettyUI.Window.new(pluginLayer, {
            title = "Make Me A Monster", width = width, height = height, destroyOnClose = true,
            x = math.max(0, math.min(x, pluginLayer.width - width)),
            y = math.max(0, math.min(y, pluginLayer.height - height)),
            -- Closed with its X: the window destroys itself, and the settings go back to the page.
            onClose = function()
                releaseSettingsControls()
                switchSettings(false)
            end,
        })
        buildSettingsControls(window, window)
    end)
    if not opened then
        pageNoticeText.content = "The settings window could not open."
        settingsControls = nil
        if window ~= nil then pcall(function() window:Destroy() end) end
    end
end

-- The page's top row holds the button switching the settings between the page and their own window.
local TOGGLE_SIZE, TOGGLE_INSET = 20, 4 -- (as PrettyUI's panels draw this button)
local TOGGLE_ROW_HEIGHT = TOGGLE_SIZE + TOGGLE_INSET * 2

-- Under the button: the controls, or with the settings in their window, a way to open it.
local function fillPage(pluginLayer)
    local pageView = PrettyUI.SimpleView.new(pluginLayer, {
        y = TOGGLE_ROW_HEIGHT, width = pluginLayer.width, height = pluginLayer.height - TOGGLE_ROW_HEIGHT,
    })
    pluginPageView = pageView
    pageView:AddTitle("Make Me A Monster")
    if Settings.settingsPoppedOut then
        pageView:AddText("The settings are in their own window.")
        pageView:AddSimpleButton("Open settings", function() openSettingsWindow() end)
        pageNoticeText = pageView:AddText("")
    else
        engage()
        buildSettingsControls(pageView)
    end
end

local function emptyPage()
    if pluginPageView == nil then return end
    if settingsControls ~= nil and settingsControls.window == nil then releaseSettingsControls() end
    pcall(function() pluginPageView:Destroy() end)
    pluginPageView = nil
end

local showPageToggleState = nil -- (set by buildPageToggle)

switchSettings = function(poppedOut)
    closeSettingsWindow()
    emptyPage()
    Settings.settingsPoppedOut = poppedOut
    -- The window can outlive the page, which unloads silently: it is built when the client next gives a layer.
    if ui.Interfaces:GetInterface(pluginPageLayer.interfaceID) == nil then return end
    showPageToggleState()
    local succeeded = pcall(fillPage, pluginPageLayer)
    if succeeded and poppedOut then openSettingsWindow() end
end

-- Components can't be destroyed in their own click handler, and switching replaces the view: so the button is a sprite
-- of the page's own, not one of the view's controls.
local function buildPageToggle(pluginLayer)
    local button = ui.Sprite.new(pluginLayer)
    button:SetPos(-TOGGLE_SIZE - TOGGLE_INSET, TOGGLE_INSET, 1.0) -- (from the page's right edge)
    button:SetSize(TOGGLE_SIZE, TOGGLE_SIZE)
    button.clickthrough = false
    local hovered, pressed = false, false
    local function showState()
        local states = Settings.settingsPoppedOut and PrettyUI.Sprites.PANEL_DOCK_BUTTON
            or PrettyUI.Sprites.PANEL_POPOUT_BUTTON
        button.spriteID = pressed and states.mousedown or hovered and states.hovered or states.neutral
    end
    button:Subscribe(ui.Hook.ONMOUSEOVER, function()
        hovered = true
        showState()
        return true
    end)
    button:Subscribe(ui.Hook.ONMOUSELEAVE, function()
        hovered, pressed = false, false
        showState()
        return true
    end)
    button:Subscribe(ui.Hook.ONCLICK, function()
        pressed = true
        showState()
        return false
    end)
    button:Subscribe(ui.Hook.ONRELEASE, function()
        local activated = pressed
        pressed = false
        if activated then switchSettings(not Settings.settingsPoppedOut) end
        showState()
        return false
    end)
    showPageToggleState = showState
    showState()
    return button
end

local function closePage()
    emptyPage()
    if pluginPageToggle ~= nil then pcall(function() pluginPageToggle:Destroy() end) pluginPageToggle = nil end
end

local function buildPage(pluginLayer)
    pluginPageLayer = pluginLayer
    pluginPageToggle = buildPageToggle(pluginLayer)
    fillPage(pluginLayer)
end

Event.ContentLayerReady.Subscribe("make_me_a_monster_content", function(event)
    closePage()
    pcall(buildPage, event.component)
end)

-- The heads window closed: the dropdown goes back to the animations of the head in use.
AllHeadsWindow.onClosed = function()
    refreshAnimationDropdown()
    refreshStatusTexts()
end

openAllHeadsWindow = function()
    local noticeText = ""
    do
        local succeeded, pluginLayer = pcall(function()
            return ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__PLUGIN_BUILD_LAYER_TOP)
        end)
        if succeeded and pluginLayer ~= nil then
            AllHeadsWindow.open(PrettyUI, pluginLayer, NpcDirectory.headsInNameOrder(),
                NpcDirectory.headsOfEachGroup(), Settings.chosenNpcID, function(npcID, label)
                    chooseNpc(npcID, nil, NpcDirectory.groupLabelled(npcID, label))
                end,
                NpcDirectory.nameOfNpc, NpcDirectory.nameForGroupOfNpc, NpcDirectory.headsMatching)
            refreshAnimationDropdown()
        else
            noticeText = "The game screen isn't ready."
        end
    end
    if settingsControls then settingsControls.noticeText.content = noticeText end
end

Event.GameStateChanged.Subscribe("make_me_a_monster_state", function(event)
    if event.newState == GameState.GAME then
        Settings.load()
        HeadSwap.start()
        refreshAnimationDropdown()
        refreshStatusTexts()
    elseif event.oldState == GameState.GAME then
        HeadSwap.reset()
    end
end)

function PluginShutdown()
    Event.ContentLayerReady.Unsubscribe("make_me_a_monster_content")
    closeSettingsWindow()
    Event.GameStateChanged.Unsubscribe("make_me_a_monster_state")
    HeadSwap.stop()
    VariantsWindow.close()
    AllHeadsWindow.close()
    Settings.save()
    closePage()
end
