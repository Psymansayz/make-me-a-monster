-- Make Me A Monster: choose an NPC in the settings, and its head replaces yours in the game's dialogue boxes.
-- This file holds the plugin's page, the settings window, and what choosing a head sets going.

-- Development: the names in the plugin's data that this game build does not know, noted from the first lookup on.
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

-- Debug windows: a button for each is added to the settings (dev only).
local DEBUG_HEAD_BROWSER = true
local HeadFlaggingWindow = require("src/debug/head_flagging_window")
local HeadGroupingWindow = require("src/debug/head_grouping_window")
local DedicatedAnimationsWindow = require("src/debug/dedicated_animations_window")

-- The settings are read once, here, and written at shutdown.
Settings.load()
HeadSwap.start()

-- Development: names in the plugin's data that this game build does not know.
if #GameIds.unresolved > 0 then
    print("[make_me_a_monster] UNRESOLVED|" .. table.concat(GameIds.unresolved, " "))
end

-- (On dev the data files are kept: the debug windows read them again.)

local pluginPageLayer = nil -- the layer the client gives the plugin's page
local pluginPageToggle = nil -- the page's button switching the settings between the page and their own window
local pluginPageView = nil -- what the page holds under that button
local pageNoticeText = nil -- says on the page why the window did not open

-- The open dialogue boxes, the windows' heads and the status texts follow the animation chosen.
local function animationChanged()
    HeadSwap.refreshOpenDialogues()
    AllHeadsWindow.updateAnimations()
    VariantsWindow.updateAnimations()
    SettingsView.refreshStatusTexts()
end

-- The animation chosen fitted to the head in use, and the animation dropdown and status texts to both; whether the
-- animation changed (then everything following it was refreshed too).
local function refitAnimation()
    local changed = AnimationChoice.fitToHead(AllHeadsWindow.isOpen())
    SettingsView.refreshAnimationDropdown()
    if changed then animationChanged() else SettingsView.refreshStatusTexts() end
    return changed
end

-- A head can be in several groups: the one the head chosen was picked from, kept for this session.
local pickedGroup = nil

local function groupOfChosenNpc()
    local npcID = Settings.chosenNpcID
    if npcID == nil then return nil end
    if pickedGroup ~= nil and NpcDirectory.memberOfNpc(npcID, pickedGroup) ~= nil then return pickedGroup end
    return NpcDirectory.groupOfNpc(npcID)
end

-- Defined below.
local openVariantsWindow
local openAllHeadsWindow
local switchSettings

-- chosenFrom: "dropdown" or "variants" if that already shows the choice. selectedGroup: the group the head was selected
-- under, if its label named one. What follows the head in use is refreshed once.
local function chooseNpc(npcID, chosenFrom, selectedGroup)
    Settings.chosenNpcID = npcID
    if chosenFrom == nil then pickedGroup = selectedGroup end
    if selectedGroup ~= nil then VariantsWindow.selectGroup(npcID, selectedGroup) end
    local animationRefitted = refitAnimation()
    if chosenFrom ~= "dropdown" then SettingsView.refreshNpcDropdown() end
    if chosenFrom ~= "variants" and VariantsWindow.isOpen() then openVariantsWindow() end
    if not animationRefitted then HeadSwap.refreshOpenDialogues() end -- (else refreshed with the animation)
end

-- The layer plugin windows go on; nil while the game screen isn't ready, which setNotice is told.
local function windowLayer(setNotice)
    local succeeded, pluginLayer = pcall(function()
        return ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__PLUGIN_BUILD_LAYER_TOP)
    end)
    pluginLayer = succeeded and pluginLayer or nil
    setNotice(pluginLayer and "" or "The game screen isn't ready.")
    return pluginLayer
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

-- The heads window closed: the animation and its dropdown go back to the head in use.
AllHeadsWindow.onClosed = function() refitAnimation() end

openAllHeadsWindow = function()
    if not NpcDirectory.isLoaded then return SettingsView.setNotice("The NPCs are still being read.") end
    local pluginLayer = windowLayer(SettingsView.setNotice)
    if pluginLayer == nil then return end
    AllHeadsWindow.open(PrettyUI, pluginLayer, Settings.chosenNpcID, function(npcID, label)
        SettingsView.clearSearch() -- (so the NPC dropdown lists, and shows, the head picked)
        chooseNpc(npcID, nil, NpcDirectory.groupLabelled(npcID, label))
    end)
    refitAnimation()
end

-- A saved NPC the list no longer has (taken out as a bad head) is forgotten.
local function forgetUnlistedNpcs()
    if Settings.chosenNpcID ~= nil and NpcDirectory.groupOfNpc(Settings.chosenNpcID) == nil then
        Settings.chosenNpcID = nil
    end
    if Settings.variantsNpcID ~= nil and NpcDirectory.groupOfNpc(Settings.variantsNpcID) == nil then
        Settings.variantsNpcID = nil
    end
end

-- Development --------------------------------------------------------------------------------------------------------

-- An NPC's name in the game (what the plugin's data holds), or "?".
local function configNameOf(npcID)
    local named, configName = pcall(function() return config.NPC.FromID(npcID).configName end)
    return named and configName or "?"
end

-- How many times larger than normal the heads are drawn: the flagging window's scale.
local function headScale()
    return Settings.DEFAULT_HEAD_VIEW_DISTANCE / Settings.headViewDistance
end

-- What the debug windows' heads play: the player's version of the animation chosen, worked out at every fill.
local function playerVersionOfChosenAnimation()
    return AnimationChoice.animationForHead(AnimationChoice.humanChoice() or Animations.fallback, true)
end

-- The NPC scan and the animation browser read a few configs a frame: Draw is subscribed to only while one runs.
local DRAW_SUBSCRIPTION = "make_me_a_monster_dev_frames"
local drawing = false
local scanWanted, animationBrowserWanted = false, false
local onFrame -- (below)

local function watchFrames()
    if drawing then return end
    Event.Draw.Subscribe(DRAW_SUBSCRIPTION, function() onFrame() end)
    drawing = true
end

local function stopFrames()
    if drawing then Event.Draw.Unsubscribe(DRAW_SUBSCRIPTION) end
    drawing = false
end

-- The scan: every NPC read (NpcDirectory.step), then each name's heads worth showing found (HeadFilter, a few a
-- frame), then the names merged into groups and logged as the lines src/data/listed_heads.lua is made from.
local CHECK_PER_FRAME = 200
local visibleOf, nextEntryToCheck = {}, 1
local logListedHeadNames -- (below)

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
            forgetUnlistedNpcs()
            SettingsView.setNotice("")
            SettingsView.refreshNpcDropdown()
            SettingsView.refreshStatusTexts()
            return
        end
        visibleOf[entry] = HeadFilter.variants(entry.ids)
        nextEntryToCheck = nextEntryToCheck + 1
    end
end

-- Every animation in the game played on Hans, for choosing the whitelist (src/data/animation_whitelist.lua).
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

-- Reads every animation a few a frame, then opens the window.
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

-- The NPCs must be read before a window of them opens.
local function headsWindowLayer()
    if not NpcDirectory.isLoaded then
        SettingsView.setNotice("The NPCs are still being read.")
        return nil
    end
    return windowLayer(SettingsView.setNotice)
end

-- Every listed head, to flag heads for the blacklist.
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

-- The blacklisted heads with the player's animations, to find heads built on the player's rig: a head that was blank
-- with NPC animations but moves here belongs in Animations.headsOnPlayerRig.
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
    -- For telling look-alikes apart: the heads on the player's rig, and the listed heads sharing a name with one.
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

-- The listed heads, newest models first, with the player's animations, to find newer heads on the player's rig.
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

-- Each set of animations of its own beside the human ones (src/debug/dedicated_animations_window.lua).
local function openDedicatedAnimationsWindow()
    local pluginLayer = windowLayer(SettingsView.setNotice)
    if pluginLayer ~= nil and not DedicatedAnimationsWindow.open(PrettyUI, pluginLayer) then
        SettingsView.setNotice("No set of animations could be read.")
    end
end

-- Every listed head sorted by its models, for grouping them by hand (src/debug/head_grouping_window.lua).
local function openHeadGroupingWindow()
    local pluginLayer = headsWindowLayer()
    if pluginLayer == nil then return end
    HeadFlaggingWindow.scaleFor = headScale
    HeadGroupingWindow.open(PrettyUI, pluginLayer, NpcDirectory.headsInNameOrder(), NpcDirectory.nameOfNpc,
        function(npcID) return AnimationChoice.npcHeadAnimation(npcID) end)
end

-- The listed heads with exactly the same customisation logged as duplicates, for tools/apply_grouping_log.py.
local function logExactDuplicates()
    if not NpcDirectory.isLoaded then return SettingsView.setNotice("The NPCs are still being read.") end
    local logged, total = HeadGroupingWindow.logExactDuplicates(NpcDirectory.headsInNameOrder(), NpcDirectory.nameOfNpc)
    SettingsView.setNotice(logged >= total and ("All %d batches logged"):format(total)
        or ("Logged %d of %d batches: paste them, then press again"):format(logged, total))
end

-- Every listed head's name and models, several to a line (the console keeps about a thousand lines), for
-- tools/make_heads_models.py.
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

-- Every listed head's constant (id=!NAME if it does not give its id back), and the animation names id.Seq did not
-- know, for tools/name_listed_heads.py.
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

-- Every blacklisted head's constant, for tools/make_blacklist_constants.py. There are more than the console keeps
-- (about a thousand lines): so each press logs the next page.
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

-- The debug buttons, under the settings' own (SettingsView's extraControls).
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

-- The saved heads are not loaded until the settings are first built: dialogue needs only the saved NPC id. Without the
-- saved list (dev), the game's NPCs are scanned instead.
local function loadHeads()
    if NpcDirectory.isLoaded or scanWanted then return end
    local hasList, listedHeads = pcall(require, "src/data/listed_heads")
    if not hasList then return startScan() end
    NpcDirectory.loadListedHeads(listedHeads)
    forgetUnlistedNpcs()
end

local settingsActions = {
    useOwnHead = function()
        SettingsView.clearSearch() -- (so the NPC dropdown shows it)
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

-- The settings window's size when first opened, and the least it can be resized to (its content scrolls).
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
            -- Closed with its X: the window destroys itself, and the settings go back to the page.
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
        buildSettings(pageView)
    end
end

local function emptyPage()
    if pluginPageView == nil then return end
    if SettingsView.isBuilt() and SettingsView.window() == nil then SettingsView.release() end
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

-- Dialogue boxes are only watched in the game.
Event.GameStateChanged.Subscribe("make_me_a_monster_state", function(event)
    if event.newState == GameState.GAME then
        HeadSwap.start()
    elseif event.oldState == GameState.GAME then
        HeadSwap.reset()
        DedicatedAnimationsWindow.close() -- (it plays on server ticks)
    end
end)

-- Closing the heads window refits the animation and refreshes the boxes: so the settings close first, and the player's
-- head goes back last.
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
