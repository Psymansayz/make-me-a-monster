-- Make Me A Monster: choose an NPC in the settings, and its head replaces yours in the game's dialogue boxes.
-- This file holds the plugin's page, the settings window, and what happens when a head is chosen.

-- Development: collects the names in the plugin's data that this game build does not know.
require("src/game/game_ids").unresolved = {}

local Settings = require("src/data/settings")
local NpcDirectory = require("src/game/npc_directory")
local AnimationChoice = require("src/game/animation_choice")
local HeadSwap = require("src/game/head_swap")
local VariantsWindow = require("src/ui/variants_window")
local AllHeadsWindow = require("src/ui/all_heads_window")
local SettingsView = require("src/ui/settings_view")
local WindowPlacement = require("src/ui/window_placement")
local GameIds = require("src/game/game_ids")
local Animations = require("src/game/animations")

local PrettyUI = prettyui

-- Debug windows, each with a button in the settings.
local DEBUG_HEAD_BROWSER = true
local HeadFlaggingWindow = require("src/debug/head_flagging_window")
local HeadGroupingWindow = require("src/debug/head_grouping_window")
local DedicatedAnimationsWindow = require("src/debug/dedicated_animations_window")

-- The settings are read once, here, and written at shutdown.
Settings.load()
HeadSwap.start()

if #GameIds.unresolved > 0 then
    print("[make_me_a_monster] UNRESOLVED|" .. table.concat(GameIds.unresolved, " "))
end

-- The data files are not emptied, because the debug windows read them again.

local pluginPageLayer = nil
local pluginPageToggle = nil
local pluginPageView = nil
local pageNoticeText = nil -- the page's text saying why the window did not open

local function animationChanged()
    HeadSwap.refreshOpenDialogues()
    AllHeadsWindow.updateAnimations()
    VariantsWindow.updateAnimations()
    SettingsView.refreshStatusTexts()
end

local function refitAnimation()
    local changed = AnimationChoice.fitToHead(AllHeadsWindow.isOpen())
    SettingsView.refreshAnimationDropdown()
    if changed then animationChanged() else SettingsView.refreshStatusTexts() end
    return changed
end

-- The group the chosen head was picked from, remembered for this session, since a head can be in several groups.
local pickedGroup = nil

local function groupOfChosenNpc()
    local npcID = Settings.chosenNpcID
    if npcID == nil then return nil end
    if pickedGroup ~= nil and NpcDirectory.memberOfNpc(npcID, pickedGroup) ~= nil then return pickedGroup end
    return NpcDirectory.groupOfNpc(npcID)
end

local openVariantsWindow
local openAllHeadsWindow
local switchSettings

-- chosenFrom is "dropdown" or "variants" when that control already shows the choice. selectedGroup is the group the
-- head was selected under, if its label named one.
local function chooseNpc(npcID, chosenFrom, selectedGroup)
    Settings.chosenNpcID = npcID
    if chosenFrom == nil then pickedGroup = selectedGroup end
    if selectedGroup ~= nil then VariantsWindow.selectGroup(npcID, selectedGroup) end
    local animationRefitted = refitAnimation()
    if chosenFrom ~= "dropdown" then SettingsView.refreshNpcDropdown() end
    if chosenFrom ~= "variants" and VariantsWindow.isOpen() then openVariantsWindow() end
    if not animationRefitted then HeadSwap.refreshOpenDialogues() end -- if it was, animationChanged refreshed them
end

-- The layer that plugin windows go on, or nil while the game screen isn't ready, in which case setNotice says so.
local function windowLayer(setNotice)
    local succeeded, pluginLayer = pcall(function()
        return ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__PLUGIN_BUILD_LAYER_TOP)
    end)
    pluginLayer = succeeded and pluginLayer or nil
    setNotice(pluginLayer and "" or "The game screen isn't ready.")
    return pluginLayer
end

local function nextGroupButtonText(npcGroup)
    local nextGroup = NpcDirectory.nextGroupOfNpc(Settings.chosenNpcID, npcGroup)
    return nextGroup and ("View " .. nextGroup.name .. " variants") or nil
end

-- page is the page to show, or nil for the page with the chosen head.
local function showVariantsOf(npcGroup, page)
    pickedGroup = npcGroup -- a variant picked in the window stays in this group
    local showPlayerHeadOnly = Settings.chosenNpcID == nil
    if npcGroup == nil and not showPlayerHeadOnly then return SettingsView.setNotice("Choose an NPC first.") end
    local pluginLayer = windowLayer(SettingsView.setNotice)
    if pluginLayer == nil then return end
    local function chooseFromVariants(npcID)
        chooseNpc(npcID ~= VariantsWindow.PLAYER_HEAD_ID and npcID or nil, "variants")
        if Settings.chosenNpcID ~= nil then
            VariantsWindow.remember(Settings.chosenNpcID, pickedGroup)
            VariantsWindow.setButton(nextGroupButtonText(pickedGroup))
        end
    end
    if showPlayerHeadOnly then
        VariantsWindow.open(PrettyUI, pluginLayer, {
            title = "My head", ids = { VariantsWindow.PLAYER_HEAD_ID }, current = VariantsWindow.PLAYER_HEAD_ID,
            onPick = chooseFromVariants,
        })
        return
    end
    VariantsWindow.remember(Settings.chosenNpcID, npcGroup)
    VariantsWindow.open(PrettyUI, pluginLayer, {
        title = npcGroup.name .. " variants", ids = NpcDirectory.idsOf(npcGroup), current = Settings.chosenNpcID,
        onPick = chooseFromVariants, nameOf = NpcDirectory.nameOfNpc, page = page,
        buttonText = nextGroupButtonText(npcGroup),
        onButton = function()
            showVariantsOf(NpcDirectory.nextGroupOfNpc(Settings.chosenNpcID, pickedGroup))
            SettingsView.refreshNpcDropdown()
        end,
    })
end

openVariantsWindow = function()
    local npcID = Settings.chosenNpcID
    if npcID == nil then return showVariantsOf(nil) end
    showVariantsOf(VariantsWindow.firstView(npcID, NpcDirectory.groupsOfNpc(npcID)))
end

-- When the heads window closes, the animation and its dropdown are fitted back to the head in use.
AllHeadsWindow.onClosed = function() refitAnimation() end

openAllHeadsWindow = function()
    if not NpcDirectory.isLoaded then return SettingsView.setNotice("The NPCs are still being read.") end
    local pluginLayer = windowLayer(SettingsView.setNotice)
    if pluginLayer == nil then return end
    AllHeadsWindow.open(PrettyUI, pluginLayer, Settings.chosenNpcID, function(npcID, label)
        SettingsView.clearSearch() -- so the NPC dropdown lists the picked head
        chooseNpc(npcID, nil, NpcDirectory.groupLabelled(npcID, label))
    end)
    refitAnimation()
end

-- Development --------------------------------------------------------------------------------------------------------

local function configNameOf(npcID)
    local named, configName = pcall(function() return config.NPC.FromID(npcID).configName end)
    return named and configName or "?"
end

local function headScale()
    return Settings.DEFAULT_HEAD_VIEW_DISTANCE / Settings.headViewDistance
end

local function playerVersionOfChosenAnimation()
    return AnimationChoice.animationForHead(AnimationChoice.humanChoice() or Animations.fallback, true)
end

-- The NPC scan and the animation browser read a few configs each frame, so Draw is subscribed to only while one runs.
local DRAW_SUBSCRIPTION = "make_me_a_monster_dev_frames"
local drawing = false
local scanWanted, animationBrowserWanted = false, false
local onFrame -- defined below

local function watchFrames()
    if drawing then return end
    Event.Draw.Subscribe(DRAW_SUBSCRIPTION, function() onFrame() end)
    drawing = true
end

local function stopFrames()
    if drawing then Event.Draw.Unsubscribe(DRAW_SUBSCRIPTION) end
    drawing = false
end

-- The scan logs the HEADS lines that tools/make_heads_list.py turns into src/data/listed_heads.lua.
local CHECK_PER_FRAME = 200
local visibleOf, nextEntryToCheck = {}, 1
local logListedHeadNames -- defined below

local function startScan()
    scanWanted = true
    watchFrames()
end

local function scanFrame()
    if not NpcDirectory.done then
        local succeeded, errorMessage = pcall(NpcDirectory.step)
        if not succeeded then
            print("[make_me_a_monster] NPC scan error: " .. tostring(errorMessage))
            NpcDirectory.done = true
        end
        SettingsView.setNotice("Reading the game's NPCs: " .. #NpcDirectory.list .. " found so far...")
        return
    end
    local HeadFilter = require("src/game/head_filter")
    local entries = NpcDirectory.scannedEntries()
    for _ = 1, CHECK_PER_FRAME do
        local entry = entries[nextEntryToCheck]
        if entry == nil then
            scanWanted = false
            NpcDirectory.regroup(function(scanned) return visibleOf[scanned] end)
            local lines, heads = NpcDirectory.exportLines()
            print(("[make_me_a_monster] HEADS|begin|%d entries, %d heads, %d lines"):format(#NpcDirectory.groups,
                heads, #lines))
            for _, line in ipairs(lines) do print(line) end
            print("[make_me_a_monster] HEADS|end")
            logListedHeadNames()
            Settings.forgetUnlistedNpcs(NpcDirectory.groupOfNpc)
            SettingsView.setNotice("")
            SettingsView.refreshNpcDropdown()
            SettingsView.refreshStatusTexts()
            return
        end
        visibleOf[entry] = HeadFilter.variants(entry.ids)
        nextEntryToCheck = nextEntryToCheck + 1
    end
end

-- Plays every animation in the game on Hans, for choosing the whitelist (src/data/animation_whitelist.lua).
local ANIMATION_HEAD = id.NPC.HANS
local ANIMATION_ENTRIES_PER_LINE = 12
local AnimationScan = require("src/debug/animation_scan")
local Whitelist = require("src/data/animation_whitelist")

local TINT_LISTED = { 0.10, 0.28, 0.12, 1 }     -- on the whitelist, listed in the dropdown
local TINT_DUPLICATE = { 0.10, 0.17, 0.34, 1 }  -- on the whitelist as a duplicate

local function showAnimationBrowser()
    local pluginLayer = windowLayer(SettingsView.setNotice)
    if pluginLayer == nil then return end
    local variantIDs, names, listed, duplicates = {}, {}, {}, {}
    for _, entry in ipairs(Animations.options(false)) do listed[entry.id] = true end
    for _, animID in ipairs(Whitelist.duplicates or {}) do duplicates[animID] = true end
    for _, anim in ipairs(AnimationScan.list) do
        variantIDs[#variantIDs + 1] = anim.id
        names[anim.id] = anim.name
    end
    HeadFlaggingWindow.scaleFor = headScale
    HeadFlaggingWindow.open(PrettyUI, pluginLayer, variantIDs, function(animID) return names[animID] end, nil, {
        title = "Debug: all animations on Hans (green: whitelisted, blue: duplicate; click to select)",
        logLabel = "animation selected",
        setup = function(model, animID)
            model:SetModel(ui.ModelType.NPC_HEAD, ANIMATION_HEAD)
            model.animID = animID
        end,
        tint = function(animID)
            return listed[animID] and TINT_LISTED or duplicates[animID] and TINT_DUPLICATE or nil
        end,
        flaggedLines = function(selected)
            local lines = { ("animations selected: %d (id=name)"):format(#selected) }
            for first = 1, #selected, ANIMATION_ENTRIES_PER_LINE do
                local parts = {}
                for entryID = first, math.min(#selected, first + ANIMATION_ENTRIES_PER_LINE - 1) do
                    parts[#parts + 1] = selected[entryID] .. "=" .. (names[selected[entryID]] or "?")
                end
                lines[#lines + 1] = ("animations selected #%d: %s"):format(
                    math.floor((first - 1) / ANIMATION_ENTRIES_PER_LINE) + 1, table.concat(parts, " | "))
            end
            return lines
        end,
    })
end

local function openAnimationFlaggingWindow()
    animationBrowserWanted = true
    SettingsView.setNotice(AnimationScan.done and "" or "Reading the game's animations...")
    watchFrames()
end

local function animationBrowserFrame()
    if not AnimationScan.done then
        AnimationScan.step()
        SettingsView.setNotice("Reading the game's animations: " .. #AnimationScan.list .. " so far...")
        return
    end
    animationBrowserWanted = false
    showAnimationBrowser()
end

onFrame = function()
    if scanWanted then scanFrame() end
    if animationBrowserWanted then pcall(animationBrowserFrame) end
    if not scanWanted and not animationBrowserWanted then stopFrames() end
end

local function headsWindowLayer()
    if not NpcDirectory.isLoaded then
        SettingsView.setNotice("The NPCs are still being read.")
        return nil
    end
    return windowLayer(SettingsView.setNotice)
end

local function openHeadFlaggingWindow()
    local pluginLayer = headsWindowLayer()
    if pluginLayer == nil then return end
    local heads = {}
    for _, npcID in ipairs(NpcDirectory.headsInNameOrder()) do heads[#heads + 1] = npcID end
    table.sort(heads)
    HeadFlaggingWindow.scaleFor = headScale
    HeadFlaggingWindow.open(PrettyUI, pluginLayer, heads, NpcDirectory.nameOfNpc,
        function(npcID) return AnimationChoice.npcHeadAnimation(npcID) end)
end

-- Shows the blacklisted heads with the player's animations, to find heads built on the player's rig. A head that was
-- blank with NPC animations but moves here belongs in Animations.headsOnPlayerRig.
local function openBlacklistedHeadsWindow()
    local pluginLayer = windowLayer(SettingsView.setNotice)
    if pluginLayer == nil then return end
    local Blacklist = require("src/data/head_blacklist")
    local BlacklistNames = require("src/data/head_blacklist_names")
    local HeadFilter = require("src/game/head_filter")
    -- The blank heads have no model to show.
    local heads, names = {}, {}
    for _, groupName in ipairs({ "identical", "manual" }) do
        local groupNames = BlacklistNames[groupName] or {}
        for _, npcID in ipairs(Blacklist[groupName] or {}) do
            heads[#heads + 1] = npcID
            names[npcID] = groupNames[npcID]
        end
    end
    local playerRigIDs = {}
    for npcID in pairs(Animations.headsOnPlayerRig) do
        heads[#heads + 1] = npcID
        playerRigIDs[#playerRigIDs + 1] = npcID
    end
    table.sort(heads)
    table.sort(playerRigIDs)
    local function nameOf(npcID)
        if names[npcID] == nil then
            local fetched, name = pcall(function() return config.NPC.FromID(npcID).name end)
            names[npcID] = NpcDirectory.nameOfNpc(npcID) or (fetched and name) or "?"
        end
        return names[npcID]
    end
    -- To help tell look-alikes apart, logs the heads on the player's rig and the listed heads sharing a name with one.
    local playerRigNames = {}
    for _, npcID in ipairs(playerRigIDs) do
        playerRigNames[nameOf(npcID)] = true
        print(("[make_me_a_monster] HEADDATA|%d|%s|%s"):format(npcID, nameOf(npcID), HeadFilter.describeHead(npcID)))
    end
    for _, npcGroup in ipairs(NpcDirectory.groups) do
        for _, member in ipairs(npcGroup.members) do
            if playerRigNames[member.name] then
                for _, npcID in ipairs(member) do
                    if not Animations.headsOnPlayerRig[npcID] then
                        print(("[make_me_a_monster] HEADDATA|%d|%s (listed)|%s"):format(npcID, member.name,
                            HeadFilter.describeHead(npcID)))
                    end
                end
            end
        end
    end
    HeadFlaggingWindow.scaleFor = headScale
    HeadFlaggingWindow.open(PrettyUI, pluginLayer, heads, nameOf, nil, {
        title = "Debug: blacklisted heads and heads on the player's rig (green), with the player's animations",
        logLabel = "player rig",
        setup = function(model, npcID)
            model:SetModel(ui.ModelType.NPC_HEAD, npcID)
            model.animID = playerVersionOfChosenAnimation()
        end,
        tint = function(npcID) return Animations.headsOnPlayerRig[npcID] and TINT_LISTED or nil end,
        flaggedLines = function(selected)
            local lines = {
                ("heads on the player's rig: %d (lines for Animations.headsOnPlayerRig)"):format(#selected),
            }
            for _, npcID in ipairs(selected) do
                lines[#lines + 1] = ("        \"%s\", -- %d %s"):format(configNameOf(npcID), npcID, names[npcID] or "?")
            end
            for _, npcID in ipairs(selected) do
                lines[#lines + 1] = ("HEADDATA|%d|%s|%s"):format(npcID, nameOf(npcID), HeadFilter.describeHead(npcID))
            end
            return lines
        end,
    })
end

-- For finding newer heads built on the player's rig.
local function openNewestHeadsWindow()
    local pluginLayer = headsWindowLayer()
    if pluginLayer == nil then return end
    local HeadFilter = require("src/game/head_filter")
    local heads, newestModel = {}, {}
    for _, npcID in ipairs(NpcDirectory.headsInNameOrder()) do
        heads[#heads + 1] = npcID
        newestModel[npcID] = HeadFilter.newestModel(npcID)
    end
    table.sort(heads, function(a, b)
        if newestModel[a] ~= newestModel[b] then return newestModel[a] > newestModel[b] end
        return a < b
    end)
    HeadFlaggingWindow.scaleFor = headScale
    local function nameWithModel(npcID)
        return (NpcDirectory.nameOfNpc(npcID) or "?") .. " (model " .. newestModel[npcID] .. ")"
    end
    HeadFlaggingWindow.open(PrettyUI, pluginLayer, heads, nameWithModel, nil, {
        title = "Debug: listed heads, newest models first, with the player's animations (green: on the player's rig)",
        logLabel = "player rig",
        setup = function(model, npcID)
            model:SetModel(ui.ModelType.NPC_HEAD, npcID)
            model.animID = playerVersionOfChosenAnimation()
        end,
        tint = function(npcID) return Animations.headsOnPlayerRig[npcID] and TINT_LISTED or nil end,
        flaggedLines = function(selected)
            local lines = {
                ("heads on the player's rig: %d (lines for Animations.headsOnPlayerRig)"):format(#selected),
            }
            for _, npcID in ipairs(selected) do
                lines[#lines + 1] = ("        \"%s\", -- %d %s"):format(configNameOf(npcID), npcID,
                    NpcDirectory.nameOfNpc(npcID) or "?")
            end
            return lines
        end,
    })
end

local function openDedicatedAnimationsWindow()
    local pluginLayer = windowLayer(SettingsView.setNotice)
    if pluginLayer ~= nil and not DedicatedAnimationsWindow.open(PrettyUI, pluginLayer) then
        SettingsView.setNotice("No set of animations could be read.")
    end
end

local function openHeadGroupingWindow()
    local pluginLayer = headsWindowLayer()
    if pluginLayer == nil then return end
    HeadFlaggingWindow.scaleFor = headScale
    HeadGroupingWindow.open(PrettyUI, pluginLayer, NpcDirectory.headsInNameOrder(), NpcDirectory.nameOfNpc,
        function(npcID) return AnimationChoice.npcHeadAnimation(npcID) end)
end

-- The log is for tools/apply_grouping_log.py.
local function logExactDuplicates()
    if not NpcDirectory.isLoaded then return SettingsView.setNotice("The NPCs are still being read.") end
    local logged, total = HeadGroupingWindow.logExactDuplicates(NpcDirectory.headsInNameOrder(), NpcDirectory.nameOfNpc)
    SettingsView.setNotice(logged >= total and ("All %d batches logged"):format(total)
        or ("Logged %d of %d batches: paste them, then press again"):format(logged, total))
end

-- For tools/make_heads_models.py. Several heads go on each line, because the console keeps only about 1000 lines.
local MODELS_PER_LINE = 10

local function logListedHeadModels()
    if not NpcDirectory.isLoaded then return SettingsView.setNotice("The NPCs are still being read.") end
    local HeadFilter = require("src/game/head_filter")
    local records = {}
    for _, npcID in ipairs(NpcDirectory.headsInNameOrder()) do
        records[#records + 1] = ("%d=%s:%s@%s"):format(npcID, NpcDirectory.nameOfNpc(npcID) or "?",
            table.concat(HeadFilter.headModels(npcID), ","), configNameOf(npcID))
    end
    local lineCount = math.ceil(#records / MODELS_PER_LINE)
    print(("[make_me_a_monster] MODELS|begin|%d heads, %d lines"):format(#records, lineCount))
    for index = 1, lineCount do
        local first = (index - 1) * MODELS_PER_LINE
        print(("[make_me_a_monster] MODELS|%d/%d|%s"):format(index, lineCount,
            table.concat(records, "~", first + 1, math.min(#records, first + MODELS_PER_LINE))))
    end
    print("[make_me_a_monster] MODELS|end")
    SettingsView.setNotice("Logged: paste the console and run tools/make_heads_models.py")
end

-- For tools/name_listed_heads.py. id=!NAME marks a constant that does not give its id back.
local NAMES_PER_LINE = 20

logListedHeadNames = function()
    if not NpcDirectory.isLoaded then return SettingsView.setNotice("The NPCs are still being read.") end
    local npcIDs, isLogged = {}, {}
    for _, npcID in ipairs(NpcDirectory.headsInNameOrder()) do
        npcIDs[#npcIDs + 1], isLogged[npcID] = npcID, true
    end
    for npcID in pairs(Animations.headsOnPlayerRig) do
        if not isLogged[npcID] then npcIDs[#npcIDs + 1] = npcID end
    end
    local records, problems = {}, 0
    for _, npcID in ipairs(npcIDs) do
        local named, configName = pcall(function() return config.NPC.FromID(npcID).configName end)
        configName = named and configName or ""
        local givesID, idBack = pcall(function() return id.NPC[configName] end)
        local good = configName ~= "" and givesID and idBack == npcID
        if not good then problems = problems + 1 end
        records[#records + 1] = ("%d=%s%s"):format(npcID, good and "" or "!", configName)
    end
    local unknownRead, unknownValue = pcall(function() return id.NPC.MAKE_ME_A_MONSTER_NO_SUCH_NPC end)
    print(("[make_me_a_monster] NPCNAMES|unknown name check: %s, %s"):format(tostring(unknownRead),
        tostring(unknownValue)))
    print(("[make_me_a_monster] NPCNAMES|animation names id.Seq did not know: %d %s"):format(#GameIds.unresolved,
        table.concat(GameIds.unresolved, " ")))
    local lineCount = math.ceil(#records / NAMES_PER_LINE)
    print(("[make_me_a_monster] NPCNAMES|begin|%d heads, %d lines"):format(#records, lineCount))
    for index = 1, lineCount do
        local first = (index - 1) * NAMES_PER_LINE
        print(("[make_me_a_monster] NPCNAMES|%d/%d|%s"):format(index, lineCount,
            table.concat(records, "~", first + 1, math.min(#records, first + NAMES_PER_LINE))))
    end
    print(("[make_me_a_monster] NPCNAMES|end|%d problems"):format(problems))
    SettingsView.setNotice(("Logged (%d problems): paste the console and run tools/name_listed_heads.py"):format(
        problems))
end

-- For tools/make_blacklist_constants.py. The console keeps only about a thousand lines, so each press logs one page.
local BLACKLIST_LINE_LENGTH, BLACKLIST_LINES_PER_PAGE = 860, 700
local blacklistLines, blacklistNextLine = nil, 1

local function logBlacklistConstants()
    if blacklistLines == nil then
        local Blacklist = require("src/data/head_blacklist")
        local npcIDs = {}
        for _, groupName in ipairs({ "blank", "identical", "manual" }) do
            for _, npcID in ipairs(Blacklist[groupName]) do npcIDs[#npcIDs + 1] = npcID end
        end
        table.sort(npcIDs)
        blacklistLines = {}
        local current, length = {}, 0
        for _, npcID in ipairs(npcIDs) do
            local constant = configNameOf(npcID)
            local givesID, idBack = pcall(function() return id.NPC[constant] end)
            local record = ("%d=%s%s"):format(npcID, (givesID and idBack == npcID) and "" or "!", constant)
            if length + #record + 1 > BLACKLIST_LINE_LENGTH then
                blacklistLines[#blacklistLines + 1] = table.concat(current, "~")
                current, length = {}, 0
            end
            current[#current + 1], length = record, length + #record + 1
        end
        if #current > 0 then blacklistLines[#blacklistLines + 1] = table.concat(current, "~") end
    end
    local lastLine = math.min(#blacklistLines, blacklistNextLine + BLACKLIST_LINES_PER_PAGE - 1)
    for index = blacklistNextLine, lastLine do
        print(("[make_me_a_monster] BLACKCONST|%d/%d|%s"):format(index, #blacklistLines, blacklistLines[index]))
    end
    local finished = lastLine >= #blacklistLines
    SettingsView.setNotice(finished and "All logged: run tools/make_blacklist_constants.py"
        or ("Logged lines up to %d of %d: paste them, then press again"):format(lastLine, #blacklistLines))
    blacklistNextLine = finished and 1 or lastLine + 1
end

local function addDebugButtons(view)
    view:AddSimpleButton("Debug: flag heads for the blacklist", function() openHeadFlaggingWindow() end)
    view:AddSimpleButton("Debug: all animations on Hans", function() openAnimationFlaggingWindow() end)
    view:AddSimpleButton("Debug: human vs dedicated animations", function() openDedicatedAnimationsWindow() end)
    view:AddSimpleButton("Debug: blacklisted heads with the player's animations", function()
        openBlacklistedHeadsWindow()
    end)
    view:AddSimpleButton("Debug: listed heads, newest models first", function() openNewestHeadsWindow() end)
    view:AddSimpleButton("Debug: group heads by hand (by model)", function() openHeadGroupingWindow() end)
    view:AddSimpleButton("Debug: log exact duplicate heads (next page)", function() logExactDuplicates() end)
    view:AddSimpleButton("Debug: log the listed heads' names and models", function() logListedHeadModels() end)
    view:AddSimpleButton("Debug: log the listed heads' game names (id.NPC)", function() logListedHeadNames() end)
    view:AddSimpleButton("Debug: log the blacklisted heads' constants (next page)", function()
        logBlacklistConstants()
    end)
end

-- The saved heads aren't loaded until the settings are first built, because dialogue only needs the saved NPC id.
-- If there is no saved list, the game's NPCs are scanned instead.
local function loadHeads()
    if NpcDirectory.isLoaded or scanWanted then return end
    local hasList, listedHeads = pcall(require, "src/data/listed_heads")
    if not hasList then return startScan() end
    NpcDirectory.loadListedHeads(listedHeads)
    Settings.forgetUnlistedNpcs(NpcDirectory.groupOfNpc)
end

local settingsActions = {
    useOwnHead = function()
        SettingsView.clearSearch() -- so the NPC dropdown shows it
        chooseNpc(nil)
    end,
    npcPicked = function(npcID, npcGroup, selectedGroup)
        pickedGroup = npcGroup
        chooseNpc(npcID, "dropdown", selectedGroup)
    end,
    groupOfChosenNpc = groupOfChosenNpc,
    openVariants = function() openVariantsWindow() end,
    openAllHeads = function() openAllHeadsWindow() end,
    headSizeChanged = function()
        HeadSwap.refreshOpenDialogues()
        AllHeadsWindow.refreshHeadSize()
        VariantsWindow.refreshHeadSize()
    end,
    animationChanged = animationChanged,
    extraControls = DEBUG_HEAD_BROWSER and function(view) addDebugButtons(view) end or nil,
}

local function buildSettings(view, window)
    loadHeads()
    SettingsView.build(view, window, settingsActions)
    refitAnimation()
end

-- The settings window's size when first opened, and the smallest it can be resized to. Its content scrolls.
local SETTINGS_WIDTH, SETTINGS_HEIGHT = 420, 560
local SETTINGS_MIN_WIDTH, SETTINGS_MIN_HEIGHT = 320, 240

local function setPageNotice(text)
    pageNoticeText.content = text
end

-- Opening it again brings it to the front.
local function openSettingsWindow()
    if SettingsView.isBuilt() then
        local openWindow = SettingsView.window()
        if openWindow ~= nil then openWindow:Show() end
        return
    end
    local pluginLayer = windowLayer(setPageNotice)
    if pluginLayer == nil then return end
    local placement = Settings.windows.settings
    local width, height = WindowPlacement.size(pluginLayer, placement, SETTINGS_WIDTH, SETTINGS_HEIGHT,
        SETTINGS_MIN_WIDTH, SETTINGS_MIN_HEIGHT)
    local x, y = WindowPlacement.position(pluginLayer, width, height, placement)
    local window = nil
    local opened = pcall(function()
        window = PrettyUI.Window.new(pluginLayer, {
            title = "Make Me A Monster", width = width, height = height, x = x, y = y, destroyOnClose = true,
            resizable = true, minWidth = math.min(SETTINGS_MIN_WIDTH, width),
            minHeight = math.min(SETTINGS_MIN_HEIGHT, height),
            -- Called when its X is clicked. The window destroys itself, and the settings move back to the page.
            onClose = function()
                SettingsView.release()
                switchSettings(false)
            end,
        })
        buildSettings(window, window)
    end)
    if not opened then
        setPageNotice("The settings window could not open.")
        SettingsView.release()
        if window ~= nil then pcall(function() window:Destroy() end) end
    end
end

local function closeSettingsWindow()
    local window = SettingsView.window()
    if window == nil then return end
    SettingsView.release()
    window:Destroy()
end

-- The page's top row holds the button that switches the settings between the page and their own window.
local TOGGLE_SIZE, TOGGLE_INSET = 20, 4 -- matching how PrettyUI's panels draw this button
local TOGGLE_ROW_HEIGHT = TOGGLE_SIZE + TOGGLE_INSET * 2

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
        buildSettings(pageView)
    end
end

local function emptyPage()
    if pluginPageView == nil then return end
    if SettingsView.isBuilt() and SettingsView.window() == nil then SettingsView.release() end
    pcall(function() pluginPageView:Destroy() end)
    pluginPageView = nil
end

local showPageToggleState = nil -- set by buildPageToggle

switchSettings = function(poppedOut)
    closeSettingsWindow()
    emptyPage()
    Settings.settingsPoppedOut = poppedOut
    -- The window can outlive the page, which unloads without notice. If it has, the page is built when the client next
    -- provides a layer.
    if ui.Interfaces:GetInterface(pluginPageLayer.interfaceID) == nil then return end
    showPageToggleState()
    local succeeded = pcall(fillPage, pluginPageLayer)
    if succeeded and poppedOut then openSettingsWindow() end
end

-- Components can't be destroyed in their own click handler, and switching replaces the view, so the button is a sprite
-- on the page itself rather than one of the view's controls.
local function buildPageToggle(pluginLayer)
    local button = ui.Sprite.new(pluginLayer)
    button:SetPos(-TOGGLE_SIZE - TOGGLE_INSET, TOGGLE_INSET, 1.0) -- from the page's right edge
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

Event.GameStateChanged.Subscribe("make_me_a_monster_state", function(event)
    if event.newState == GameState.GAME then
        HeadSwap.start()
    elseif event.oldState == GameState.GAME then
        HeadSwap.reset()
        DedicatedAnimationsWindow.close() -- it plays on server ticks
    end
end)

-- Closing the heads window refits the animation and refreshes the boxes, so the settings close first and the player's
-- head is put back last.
function PluginShutdown()
    Event.ContentLayerReady.Unsubscribe("make_me_a_monster_content")
    Event.GameStateChanged.Unsubscribe("make_me_a_monster_state")
    stopFrames()
    closeSettingsWindow()
    closePage()
    VariantsWindow.close()
    AllHeadsWindow.close()
    HeadFlaggingWindow.close()
    DedicatedAnimationsWindow.close()
    NpcDirectory.forgetCaches()
    HeadSwap.stop()
    Settings.save()
end
