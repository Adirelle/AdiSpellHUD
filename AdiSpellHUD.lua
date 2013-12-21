--[[
AdiSpellHUD - Spell overlay customization and spell state HUD.
Copyright 2011-2013 Adirelle (adirelle@gmail.com)
All rights reserved.

This file is part of AdiSpellHUD.

AdiSpellHUD is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

AdiSpellHUD is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with AdiSpellHUD.  If not, see <http://www.gnu.org/licenses/>.
--]]

local addonName, addon = ...
local L = addon.L

LibStub('AceAddon-3.0'):NewAddon(addon, addonName, 'AceEvent-3.0', 'AceConsole-3.0')
--@debug@
_G[addonName] = addon
--@end-debug@

--------------------------------------------------------------------------------
-- Debug stuff
--------------------------------------------------------------------------------

--@alpha@
if AdiDebug then
	AdiDebug:Embed(addon, addonName)
else
--@end-alpha@
	function addon.Debug() end
--@alpha@
end
--@end-alpha@

--------------------------------------------------------------------------------
-- Default settings
--------------------------------------------------------------------------------

local DEFAULT_SETTINGS = {
	profile = {
		modules = { ['*'] = true },
	}
}

--------------------------------------------------------------------------------
-- Upvalues and constants
--------------------------------------------------------------------------------

local prefs

--------------------------------------------------------------------------------
-- Event dispatching using CallbackHandler-1.0
--------------------------------------------------------------------------------

local events = LibStub('CallbackHandler-1.0'):New(addon, 'RegisterEvent', 'UnregisterEvent', 'UnregisterAllEvents')
local eventFrame = CreateFrame("Frame")
eventFrame:SetScript('OnEvent', function(_, ...) return events:Fire(...) end)
function events:OnUsed(_, event) return eventFrame:RegisterEvent(event) end
function events:OnUnused(_, event) return eventFrame:UnregisterEvent(event) end

--------------------------------------------------------------------------------
-- Initialization
--------------------------------------------------------------------------------

function addon:OnInitialize()
	self.db = LibStub('AceDB-3.0'):New(addonName.."DB", DEFAULT_SETTINGS, true)
	self.db.RegisterCallback(self, "OnProfileChanged", "Reconfigure")
	self.db.RegisterCallback(self, "OnProfileCopied", "Reconfigure")
	self.db.RegisterCallback(self, "OnProfileReset", "Reconfigure")

	LibStub('LibDualSpec-1.0'):EnhanceDatabase(self.db, addonName)

	prefs = self.db.profile

	LibStub('AceConfig-3.0'):RegisterOptionsTable(addonName, self.GetOptions)
	self.blizPanel = LibStub('AceConfigDialog-3.0'):AddToBlizOptions(addonName, addonName)
end

function addon:OnEnable()
	prefs = self.db.profile
	
	for name, module in self:IterateModules() do
		module:SetEnabledState(prefs.modules[module.name])
	end
end

function addon:Reconfigure()
	self:Disable()
	self:Enable()
end

function addon:OnConfigChanged()
end

function addon:ChatCommand()
	InterfaceOptionsFrame_OpenToCategory(self.blizPanel)
end

-- The slash command
_G.SLASH_ADISPELLHUD1 = "/adispellhud"
_G.SLASH_ADISPELLHUD2 = "/ash"
_G.SlashCmdList["ADISPELLHUD"] = function(args) return addon:ChatCommand(args) end

--------------------------------------------------------------------------------
-- Helper
--------------------------------------------------------------------------------

function addon.IconLine(texture, text)
	return format("|T%s:20|t %s", texture, text)
end

--------------------------------------------------------------------------------
-- Module Prototype
--------------------------------------------------------------------------------

local moduleProto = {
	Debug = addon.Debug,
	RegisterEvent = addon.RegisterEvent,
	UnregisterEvent = addon.UnregisterEvent,
	UnregisterAllEvents = addon.UnregisterAllEvents
}
addon:SetDefaultModulePrototype(moduleProto)

function moduleProto:ShouldEnable()
	return prefs.modules[self.name]
end

function moduleProto:UpdateEnabledState()
	local enable = self:ShouldEnable()
	if enable and not self:IsEnabled() then
		self:Enable()
	elseif not enable and self:IsEnabled() then
		self:Disable()
	end
end

