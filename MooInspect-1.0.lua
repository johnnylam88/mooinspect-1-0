--[[--------------------------------------------------------------------
    Copyright (C) 2018 Johnny C. Lam.
    See the file LICENSE.txt for copying permission.
--]]--------------------------------------------------------------------

-- GLOBALS: assert
-- GLOBALS: LibStub

local MAJOR, MINOR = "MooInspect-1.0", 1
assert(LibStub, MAJOR .. " requires LibStub")
assert(LibStub("CallbackHandler-1.0", true), MAJOR .. " requires CallbackHandler-1.0")
assert(LibStub("MooUnit-1.0", true), MAJOR .. " requires MooUnit-1.0")
local lib, oldminor = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then return end

------------------------------------------------------------------------

local format = string.format
local ipairs = ipairs
local next = next
local pairs = pairs
local setmetatable = setmetatable
local strfind = string.find
local strjoin = strjoin
local strmatch = string.match
local tinsert = table.insert
local tonumber = tonumber
local tostring = tostring
local tostringall = tostringall
local tremove = table.remove
local type = type
local wipe = wipe
-- GLOBALS: _G
-- GLOBALS: GetAddOnMetadata
local FONT_COLOR_CODE_CLOSE = FONT_COLOR_CODE_CLOSE
local GREEN_FONT_COLOR_CODE = GREEN_FONT_COLOR_CODE
local NORMAL_FONT_COLOR_CODE = NORMAL_FONT_COLOR_CODE

local MooUnit = LibStub("MooUnit-1.0")

--[[--------------------------------------------------------------------
    Debugging code from LibResInfo-1.0 by Phanx.
    https://github.com/Phanx/LibResInfo
--]]--------------------------------------------------------------------

local isAddon = GetAddOnMetadata(MAJOR, "Version")

local DEBUG_LEVEL = isAddon and 2 or 0
local DEBUG_FRAME = ChatFrame3

local function debug(level, text, ...)
	if level <= DEBUG_LEVEL then
		if ... then
			if type(text) == "string" and strfind(text, "%%[dfqsx%d%.]") then
				text = format(text, ...)
			else
				text = strjoin(" ", tostringall(text, ...))
			end
		else
			text = tostring(text)
		end
		DEBUG_FRAME:AddMessage(GREEN_FONT_COLOR_CODE .. MAJOR .. FONT_COLOR_CODE_CLOSE .. " " .. text)
	end
end

if isAddon then
	-- GLOBALS: SLASH_MOOINSPECT1
	-- GLOBALS: SlashCmdList
	SLASH_MOOINSPECT1 = "/mooinspect"
	SlashCmdList.MOOINSPECT = function(input)
		input = tostring(input or "")

		local CURRENT_CHAT_FRAME
		for i = 1, 10 do
			local cf = _G["ChatFrame"..i]
			if cf and cf:IsVisible() then
				CURRENT_CHAT_FRAME = cf
				break
			end
		end

		local of = DEBUG_FRAME
		DEBUG_FRAME = CURRENT_CHAT_FRAME

		if strmatch(input, "^%s*[0-9]%s*$") then
			local v = tonumber(input)
			debug(0, "Debug level set to", input)
			DEBUG_LEVEL = v
			DEBUG_FRAME = of
			return
		end

		local f = _G[input]
		if type(f) == "table" and type(f.AddMessage) == "function" then
			debug(0, "Debug frame set to", input)
			DEBUG_FRAME = f
			return
		end

		debug(0, "Version " .. MINOR .. " loaded. Usage:")
		debug(0, format("%s%s %s%s - change debug verbosity, valid range is 0-6",
			NORMAL_FONT_COLOR_CODE, SLASH_MOOINSPECT1, DEBUG_LEVEL, FONT_COLOR_CODE_CLOSE))
		debug(0, format("%s%s %s%s -- change debug output frame",
			NORMAL_FONT_COLOR_CODE, SLASH_MOOINSPECT1, of:GetName(), FONT_COLOR_CODE_CLOSE))

		DEBUG_FRAME = of
	end
end

------------------------------------------------------------------------

lib.callbacks = lib.callbacks or LibStub("CallbackHandler-1.0"):New(lib)
lib.callbacksInUse = lib.callbacksInUse or {}

local eventFrame = lib.eventFrame or CreateFrame("Frame")
lib.eventFrame = eventFrame
eventFrame:UnregisterAllEvents()

local function OnEvent(frame, event, ...)
	return frame[event] and frame[event](frame, event, ...)
end

eventFrame:SetScript("OnEvent", OnEvent)

function lib.callbacks:OnUsed(lib, callback)
	if not next(lib.callbacksInUse) then
		debug(1, "Callbacks in use! Starting up...")
		eventFrame:RegisterEvent("INSPECT_READY")
		eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
		eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
		eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
		eventFrame:RegisterEvent("UNIT_CONNECTION")
		-- Register a callback so MooUnit will track GUID-to-unit mappings.
		MooUnit.RegisterCallback(eventFrame, "MooUnit_RosterUpdated")
	end
	lib.callbacksInUse[callback] = true
end

function lib.callbacks:OnUnused(lib, callback)
	lib.callbacksInUse[callback] = nil
	if not next(lib.callbacksInUse) then
		debug(1, "No callbacks in use. Shutting down...")
		eventFrame:UnregisterAllEvents()
		MooUnit.UnregisterCallback(eventFrame, "MooUnit_RosterUpdated")
	end
end

--[[--------------------------------------------------------------------
	Throttle calls to NotifyInspect() to avoid hitting the limit where
	the servers drop all inspection requests originating from the
	account for a period of time.
--]]--------------------------------------------------------------------

-- GLOBALS: CanInspect
-- GLOBALS: CheckInteractDistance
-- GLOBALS: GetTime
-- GLOBALS: InCombatLockdown
-- GLOBALS: NotifyInspect
-- GLOBALS: UnitGUID
-- GLOBALS: UnitIsConnected
-- GLOBALS: hooksecurefunc

-- Preserve inspection status across library upgrades.
lib.sent = lib.sent or {}
lib.timestamp = lib.timestamp or {} -- timestamp[guid] = time that data was last received
lib.lastInspectTime = lib.lastInspectTime or 0

local INSPECT_INTERVAL = 2 -- number of seconds between inspections
local INSPECT_TIMEOUT = 10 -- number of seconds before timing out and failing an inspection request

local inCombat

-- pending and failed are special FIFO objects that allow checking for
-- the presence of an item in O(1) time.
do
	-- Preserve FIFOs across library upgrades.
	lib.pending = lib.pending or {}
	lib.pending.queue = lib.pending.queue or {}
	lib.pending.set = lib.pending.set or {}

	lib.failed = lib.failed or {}
	lib.failed.queue = lib.failed.queue or {}
	lib.failed.set = lib.failed.set or {}

	local fifo = {
		--queue = {},
		--set = {},
	}

	function fifo:has(item)
		return self.set[item]
	end

	function fifo:empty()
		return #self.queue == 0
	end

	function fifo:push(item)
		tinsert(self.queue, item)
		self.set[item] = true
	end

	function fifo:pop()
		local item = tremove(self.queue, 1)
		self.set[item] = nil
		return item
	end

	function fifo:delete(item)
		for i, queuedItem in ipairs(self.queue) do
			if item == queuedItem then
				tremove(self.queue, i)
				break
			end
		end
		self.set[item] = nil
	end

	function fifo:embed(t)
		for key, value in pairs(self) do
			if key ~= "embed" then
				t[key] = value
			end
		end
	end

	fifo:embed(lib.pending)
	fifo:embed(lib.failed)
end

-- Hook NotifyInspect() to catch inspects from other addons.
local function NotifyInspectHook(unit)
	local now = GetTime()
	lib.lastInspectTime = now
	local guid = UnitGUID(unit)
	if guid then
		lib.pending:delete(guid)
		lib.failed:delete(guid)
		lib.sent[guid] = now
	end
end

hooksecurefunc("NotifyInspect", NotifyInspectHook)

local inspectFrames = {
	"Examiner", -- https://wow.curseforge.com/projects/examiner
	"InspectFrame", -- Blizzard_InspectUI
}

local function IsInspectFrameOpen()
	for _, name in pairs(inspectFrames) do
		local frame = _G[name]
		if frame and type(frame.IsShown) == "function" and frame:IsShown() then
			return true
		end
	end
	return false
end

local function HasInspect(guid)
	if guid then
		return lib.pending:has(guid) or lib.failed:has(guid) or lib.sent[guid]
	else
		return not lib.pending:empty() or not lib.failed:empty() or next(lib.sent)
	end
end

function lib:QueueInspect(guid)
	if not HasInspect(guid) then
		debug(2, "QueueInspect", guid)
		self.pending:push(guid)
		eventFrame:InspectStart()
	end
end

function lib:CancelInspect(guid)
	self.pending:delete(guid)
	self.failed:delete(guid)
	self.sent[guid] = nil
end

function lib:GetInspectAge(guid)
	local now = GetTime()
	local timestamp = self.timestamp[guid]
	if timestamp then
		return now - timestamp
	end
	return nil
end

function eventFrame:InspectStop()
	if self:IsShown() and HasInspect() then
		debug(3, "Pausing inspections.")
		self:Hide()
	end
end

function eventFrame:InspectStart()
	if not inCombat and not self:IsShown() and HasInspect() then
		debug(3, "Starting inspections.")
		self:Show()
	end
end

local function OnUpdate(frame, elapsed)
	local now = GetTime()
	if now - lib.lastInspectTime > INSPECT_INTERVAL then
		for guid, timeSent in pairs(lib.sent) do
			if now - timeSent > INSPECT_TIMEOUT then
				lib.failed[guid] = true
			end
		end
		if lib.pending:empty() and not lib.failed:empty() then
			-- Re-inspect for failed units.
			lib.pending, lib.failed = lib.failed, lib.pending
		end
		while not lib.pending:empty() do
			local guid = lib.pending:pop()
			local unit = MooUnit:GetUnitByGUID(guid)
			if unit then
				if UnitIsConnected(unit) and CanInspect(unit) and CheckInteractDistance(unit, 1) and not IsInspectFrameOpen() then
					NotifyInspect(unit)
					-- NotifyInspectHook() is a secure hook and is called automatically
					-- after NotifyInspect() to set the inspection times.
					break
				else
					lib.failed:push(guid)
				end
			else
				-- GUID no longer maps to a usable unit ID, so further inspections are
				-- no longer possible.
				lib.failed:delete(guid)
				debug(2, guid, "no unit ID, inspection not possible.")
			end
		end
		if not HasInspect() then
			debug(2, "No more inspections, pausing OnUpdate...")
			frame:Hide()
		end
	end
end

eventFrame:SetScript("OnUpdate", OnUpdate)

function eventFrame:INSPECT_READY(event, guid)
	if HasInspect(guid) then
		debug(3, event, guid)
		lib:CancelInspect(guid)
		lib.timestamp[guid] = GetTime()
		debug(2, "MooInspect_InspectReady", guid)
		lib.callbacks:Fire("MooInspect_InspectReady", guid)
	end
end

function eventFrame:PLAYER_ENTERING_WORLD(event)
	inCombat = InCombatLockdown()
end

function eventFrame:PLAYER_REGEN_DISABLED(event)
	inCombat = true
	self:InspectStop()
end

function eventFrame:PLAYER_REGEN_ENABLED(event)
	inCombat = false
	self:InspectStart()
end

function eventFrame:UNIT_CONNECTION(event, unit, isConnected)
	debug(3, event, unit, isConnected)
	if not isConnected then
		local guid = UnitGUID(unit)
		if guid then
			-- Fail the inspection for disconnected units.
			if lib.pending:has(guid) then
				lib.pending:delete(guid)
				lib.failed:push(guid)
			end
		end
	end
end

function eventFrame:MooUnit_RosterUpdated(event)
	-- do nothing
end