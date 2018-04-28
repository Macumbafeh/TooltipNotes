----------------------------------------------------------------------------------------------------
-- addon variables
----------------------------------------------------------------------------------------------------
local eventFrame = CreateFrame("frame")
eventFrame:Hide()

-- saved settings table - defaults set up in TooltipNotes_OnEventLoad
-- TooltipNotesSave.settings[setting] = value
-- TooltipNotesSave.creatures["name"].note = "custom note"
-- TooltipNotesSave.creatures["name"][1 or 2 for normal/herioc][spell id] = true
-- TooltipNotesSave.creatures["name"][1 or 2 for normal/herioc].tooltipString = "Spell, Spell 2"
-- TooltipNotesSave.creatures["name"][1 or 2 for normal/herioc].linkString = "[link] [link 2]"
TooltipNotesSave   = nil
local noteSettings = nil -- reference to TooltipNotesSave.settings
local noteList     = nil -- reference to TooltipNotesSave.creatures

-- keybinding constants
BINDING_HEADER_TOOLTIPNOTES    = "Tooltip Notes"
BINDING_NAME_TOOLTIPNOTES_SET  = "Set target's note"
BINDING_NAME_TOOLTIPNOTES_SHOW = "Show target's note to yourself"
BINDING_NAME_TOOLTIPNOTES_SAY  = "Say target's note to group"

-- local references
local tableinsert = table.insert
local tableconcat = table.concat

----------------------------------------------------------------------------------------------------
-- Helper functions
----------------------------------------------------------------------------------------------------
-- word wrap for tooltip lines - from http://rosettacode.org/wiki/Word_wrap#Lua
local function SplitTokens(text)
	local res = {}
	for word in text:gmatch("%S+") do
		res[#res+1] = word
	end
	return res
end

local function WordWrap(text, linewidth)
	if linewidth == 0 then
		return {text}
	end
	if not linewidth then
		linewidth = 60
	end

	local spaceleft = linewidth
	local res = {}
	local line = {}
	for _, word in ipairs(SplitTokens(text)) do
		if #word + 1 > spaceleft then
			tableinsert(res, tableconcat(line, ' '))
			line = {word}
			spaceleft = linewidth - #word
		else
			tableinsert(line, word)
			spaceleft = spaceleft - (#word + 1)
		end
	end
	tableinsert(res, tableconcat(line, ' '))
	return res
end

----------------------------------------------------------------------------------------------------
-- Notes popup dialog
----------------------------------------------------------------------------------------------------
--------------------------------------------------
-- add a note (or clear it if blank)
--------------------------------------------------
local function AddNote(name, note)
	if not name then return end
	name = name:lower()

	local creature = noteList[name]

	-- creature doesn't exist yet so add it
	if not creature then
		if note and note ~= "" then
			noteList[name] = {}
			noteList[name].note = note
		end
		return
	end

	-- creature already exists - add/change or remove the note
	if note and note ~= "" then
		creature.note = note
	else
		-- removing the note - also remove the whole creature if no spells are recorded for them
		creature.note = nil
		if next(creature) == nil then
			noteList[name] = nil
		end
	end
end

--------------------------------------------------
-- open popup window to edit a note
--------------------------------------------------
local function OpenNoteDialog(name)
	if not name or name == "" then return end

	-- create the dialog if it hasn't been yet
	if not StaticPopupDialogs["TOOLTIPNOTES_POPUP"] then
		StaticPopupDialogs["TOOLTIPNOTES_POPUP"] = {
			text = "",
			button1 = ACCEPT,
			button2 = CANCEL,
			timeout = 0,
			whileDead = 1,
			hideOnEscape = 1,
			hasEditBox = 1,
			hasWideEditBox = 1,
			preferredIndex = 3, -- to avoid interferring with Blizzard UI popups
			EditBoxOnEscapePressed = function()
				this:GetParent():Hide()
			end,
			EditBoxOnEnterPressed = function()
				AddNote(StaticPopupDialogs["TOOLTIPNOTES_POPUP"].text,
					_G[this:GetParent():GetName().."WideEditBox"]:GetText())
				this:GetParent():Hide()
			end,
			OnShow = function()
				local creature = noteList[StaticPopupDialogs["TOOLTIPNOTES_POPUP"].text]
				_G[this:GetName().."WideEditBox"]:SetText(creature and creature.note or "")
			end,
			OnAccept = function()
				AddNote(StaticPopupDialogs["TOOLTIPNOTES_POPUP"].text,
					_G[this:GetParent():GetName().."WideEditBox"]:GetText())
			end,
		}
	end -- end of creating static popup

	StaticPopupDialogs["TOOLTIPNOTES_POPUP"].text = name
	StaticPopup_Show("TOOLTIPNOTES_POPUP")
end

----------------------------------------------------------------------------------------------------
-- watch combat events to find spells
----------------------------------------------------------------------------------------------------
-- table of combat log actions to look for - much faster than find("^SPELL") every event
local spellActions = {
	["SPELL_DAMAGE"]=1,
	["SPELL_MISSED"]=1,
	["SPELL_HEAL"]=1,
	["SPELL_ENERGIZE"]=1,
	["SPELL_DRAIN"]=1,
	["SPELL_LEECH"]=1,
	["SPELL_INTERRUPT"]=1,
	["SPELL_EXTRA_ATTACKS"]=1,
	["SPELL_AURA_APPLIED"]=1,
	["SPELL_AURA_APPLIED_DOSE"]=1,
	["SPELL_AURA_REFRESH"]=1,
	["SPELL_CAST_START"]=1,
	["SPELL_CAST_SUCCESS"]=1,
	["SPELL_CAST_FAILED"]=1,
}

local function TooltipNotes_OnEventCombat(self, event, _, action, casterGUID, casterName,
                                          _, _, _, _, spellID, spellName)
	if not casterGUID or not spellActions[action] or casterGUID:sub(5,5) ~= "3" or not spellID then
		return
	end

	local creature = noteList[casterName:lower()]
	if not creature then
		local lowerName = casterName:lower()
		noteList[lowerName] = {}
		creature = noteList[lowerName]
	end
	local spellInfo = creature[GetInstanceDifficulty()]
	if not spellInfo then
		creature[GetInstanceDifficulty()] = {}
		spellInfo = creature[GetInstanceDifficulty()]
	end

	if not spellInfo[spellID] then
		spellInfo[spellID] = true
		if not spellInfo.tooltipString then
			spellInfo.tooltipString = spellName
			spellInfo.linkString = GetSpellLink(spellID)
		else
			-- only add the tooltip text if no other spells are using the same name
			local nameFound
			spellInfo.tooltipString:gsub("([^,]+)[,]?[ ]?", function(name)
				if name == spellName then nameFound = true end
			end)
			if not nameFound then
				spellInfo.tooltipString = spellInfo.tooltipString .. ", " .. spellName
			end
			spellInfo.linkString = spellInfo.linkString .. " " .. GetSpellLink(spellID)
		end
	end
end

----------------------------------------------------------------------------------------------------
-- loading
----------------------------------------------------------------------------------------------------
local function TooltipNotes_OnEventLoad(self, event)
	if TooltipNotesSave           == nil then TooltipNotesSave           = {} end
	if TooltipNotesSave.creatures == nil then TooltipNotesSave.creatures = {} end
	if TooltipNotesSave.settings  == nil then TooltipNotesSave.settings  = {} end

	-- set local references to the creature list and settings
	noteList     = TooltipNotesSave.creatures
	noteSettings = TooltipNotesSave.settings

	-- set default values for the settings if needed
	if noteSettings.wordWrapWidth == nil then noteSettings.wordWrapWidth = 0            end
	if noteSettings.noteColor     == nil then noteSettings.noteColor     = {.8, .8, .8} end
	if noteSettings.spellColor    == nil then noteSettings.spellColor    = {1, 0, 0}    end

	-- set tooltips to insert the notes
	local tooltipScript = GameTooltip:GetScript("OnTooltipSetUnit")
	GameTooltip:SetScript("OnTooltipSetUnit", function(self, ...)
		local name, unitid = self:GetUnit()
		if not name then return tooltipScript(self, ...) end

		local creature = UnitExists(unitid) and noteList[name:lower()]
		if creature then
		-- custom note first
		if creature.note then
			local color = noteSettings.noteColor
				if noteSettings.wordWrapWidth ~= 0 then
					local wwNote = WordWrap(creature.note, noteSettings.wordWrapWidth)
					for i=1,#wwNote do
						GameTooltip:AddLine(wwNote[i], color[1], color[2], color[3], true)
					end
				else
					GameTooltip:AddLine(creature.note, color[1], color[2], color[3], true)
				end
			end
			-- spell list
			if not UnitIsPlayer(unitid) then
				local spellInfo = creature[GetInstanceDifficulty()]
				local tooltipString = spellInfo and spellInfo.tooltipString
				if tooltipString then
					local color = noteSettings.spellColor
					if noteSettings.wordWrapWidth ~= 0 then
						local wwSpells = WordWrap("Uses: " .. tooltipString, noteSettings.wordWrapWidth)
						for i=1,#wwSpells do
							GameTooltip:AddLine(wwSpells[i], color[1], color[2], color[3], true)
						end
					else
						GameTooltip:AddLine("Uses: " .. tooltipString, color[1], color[2], color[3], true)
					end
				end
			end
		end
		GameTooltip:Show() -- to allow standard word wrapping to happen after adding lines
		return tooltipScript(self, ...)
	end)

	-- start watching combat events
	eventFrame:UnregisterEvent(event)
	eventFrame:SetScript("OnEvent", TooltipNotes_OnEventCombat)
	eventFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
end

eventFrame:SetScript("OnEvent", TooltipNotes_OnEventLoad)
eventFrame:RegisterEvent("VARIABLES_LOADED")

----------------------------------------------------------------------------------------------------
-- /tnote command
----------------------------------------------------------------------------------------------------
--------------------------------------------------
-- find a target either by input text or targeting
--------------------------------------------------
local function GetSlashTarget(input)
	local target = (input and input ~= "" and input) or UnitName("target")
	if not target then
		DEFAULT_CHAT_FRAME:AddMessage("You must either have a target selected or input a name.")
		return
	end
	return target:lower()
end

--------------------------------------------------
-- changing tooltip line colors
--------------------------------------------------
local colorPickerColor = nil -- color table for the picker - reference to one of the saved settings

-- called when the color changes or the picker is canceled
local function ColorPickerCallback(restore)
	if restore then
		colorPickerColor[1], colorPickerColor[2], colorPickerColor[3] = unpack(restore)
	else
		colorPickerColor[1], colorPickerColor[2], colorPickerColor[3] = ColorPickerFrame:GetColorRGB()
	end
end

-- open and show the color picker
local function ShowColorPicker(r, g, b)
	ColorPickerFrame:SetColorRGB(r,g,b)
	ColorPickerFrame.hasOpacity, ColorPickerFrame.opacity = nil, nil
	ColorPickerFrame.previousValues = {r,g,b}
	ColorPickerFrame.func, ColorPickerFrame.opacityFunc, ColorPickerFrame.cancelFunc =
		ColorPickerCallback, ColorPickerCallback, ColorPickerCallback
	ColorPickerFrame:Hide() -- in case it's already open, this will reopen it to update the color
	ColorPickerFrame:Show()
end

--------------------------------------------------
-- say or print the notes of a creature
--------------------------------------------------
local function SayOrPrintNotes(name, channel)
	local creature = noteList[name:lower()]
	if not creature then
		DEFAULT_CHAT_FRAME:AddMessage("There isn't any information about '" .. name .. "' to show.")
		return
	end

	-- show custom note first
	if creature.note then
		if channel then
			SendChatMessage("Note about " .. name .. ": " .. creature.note, channel)
		else
			DEFAULT_CHAT_FRAME:AddMessage(name .. ": " .. creature.note)
		end
	end

	-- spell list
	local spellInfo = creature[GetInstanceDifficulty()]
	local linkString = spellInfo and spellInfo.linkString
	if linkString then
		linkString = (creature.note and "Uses: " or (name .. " uses: ")) .. linkString
		if channel then
			if linkString:len() <= 255 then
				SendChatMessage(linkString, channel)
			else
				-- replace spaces inside links with @ so it stays together when splitting up lines
				linkString = linkString:gsub("([^]]) ", "%1@")
				local wwLinkString = WordWrap(linkString, 255)
				for i=1,#wwLinkString do
					SendChatMessage(wwLinkString[i]:gsub("@", " "), channel)
				end
			end
		else
			DEFAULT_CHAT_FRAME:AddMessage(linkString)
		end
	end
end

--------------------------------------------------
-- /tnote command
--------------------------------------------------
_G.SLASH_TNOTE1 = "/tnote"
function SlashCmdList.TNOTE(input)
	input = input or ""

	local command, value = input:match("(%w+)%s*(.*)")
	if command then command = command:lower() end

	-- /tnote set - set a note on something
	if command == "set" then
		local target = GetSlashTarget(value)
		if target then
			OpenNoteDialog(target)
		end
		return
	end

	-- /tnote clear - remove all notes from something
	if command == "clear" then
		local target = GetSlashTarget(value)
		if target then
			local creature = noteList[target]
			if creature then
				noteList[target] = nil
				DEFAULT_CHAT_FRAME:AddMessage("Information for '" .. target .. "' has been deleted.")
			else
				DEFAULT_CHAT_FRAME:AddMessage("There is nothing to clear for that target.")
			end
		end
		return
	end

	-- /tnote show - print note/immunities to yourself
	if command == "show" then
		local target = GetSlashTarget(value)
		if target then
			SayOrPrintNotes(target, nil)
		end
		return
	end

	-- /tnote say - say note/spells to the raid/party
	if command == "say" then
		local target = GetSlashTarget(value)
		if target then
			local channel = (GetNumRaidMembers() > 0 and "raid") or (GetNumPartyMembers() > 0 and "party")
			if channel then
				SayOrPrintNotes(target, channel)
			else
				DEFAULT_CHAT_FRAME:AddMessage("You aren't in a group.")
			end
		end
		return
	end

	-- /tnote notecolor
	if command == "notecolor" then
		colorPickerColor = noteSettings["noteColor"]
		ShowColorPicker(unpack(colorPickerColor))
		return
	end

	-- /tnote spellcolor
	if command == "spellcolor" then
		colorPickerColor = noteSettings["spellColor"]
		ShowColorPicker(unpack(colorPickerColor))
		return
	end

	-- /tnote wordwrap - set how long tooltip lines can be in notes and immunity lists
	if command == "wordwrap" then
		local value = value and tonumber(value) or nil
		if value and value < 0 then
			DEFAULT_CHAT_FRAME:AddMessage("The width number must be 0 (for no wrapping) or greater.")
		elseif value and value >= 0 then
			noteSettings.wordWrapWidth = value
			if noteSettings.wordWrapWidth == 0 then
				DEFAULT_CHAT_FRAME:AddMessage("Custom word wrapping has been disabled.")
			else
				DEFAULT_CHAT_FRAME:AddMessage("Custom word wrapping has been set to " ..
					noteSettings.wordWrapWidth .. " characters.")
			end
		else
			DEFAULT_CHAT_FRAME:AddMessage("Syntax: /tnote wordwrap <width or 0>")
			if noteSettings.wordWrapWidth > 0 then
				DEFAULT_CHAT_FRAME:AddMessage("Custom word wrapping is currently " ..
					noteSettings.wordWrapWidth .. " characters.")
			end
		end
		return
	end

	-- no command used - show syntax and some current settings
	DEFAULT_CHAT_FRAME:AddMessage('TooltipNotes commands:', 1, 1, 0)
	DEFAULT_CHAT_FRAME:AddMessage('/tnote set [name]')
	DEFAULT_CHAT_FRAME:AddMessage('/tnote clear [name]')
	DEFAULT_CHAT_FRAME:AddMessage('/tnote show [name]')
	DEFAULT_CHAT_FRAME:AddMessage('/tnote say [name]')
	DEFAULT_CHAT_FRAME:AddMessage('/tnote notecolor')
	DEFAULT_CHAT_FRAME:AddMessage('/tnote spellcolor')
	DEFAULT_CHAT_FRAME:AddMessage('/tnote wordwrap <width>')
	if noteSettings.wordWrapWidth > 0 then
		DEFAULT_CHAT_FRAME:AddMessage(" ")
		DEFAULT_CHAT_FRAME:AddMessage("Custom word wrapping has been set to " ..
			noteSettings.wordWrapWidth .. " characters.")
	end
end
