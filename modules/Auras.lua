--[[
AdiSpellHUD - Spell overlay customization and spell state HUD.
Copyright 2013 Adirelle (adirelle@gmail.com)
All rights reserved.
--]]

local addonName, addon = ...

local GetWatchers
do
	local _, class = UnitClass('player')
	
	local function OwnAuraGetter(spell, harmful)
		local name = GetSpellInfo(spell)
		if not name then
			geterrorhandler()("Unknown spell id", spell)
			return function() end
		end
		local filter = "PLAYER|" .. (harmful and "HARMFUL" or "HELPFUL")
		return function(unit)
			local name, _, _, count, _, duration, expirationTime = UnitAura(unit, name, nil, filter)
			addon.Debug("OwnAuraGetter", name, spell, count, duration, expirationTime)
			if name then
				return spell, count, duration, expirationTime
			end
		end
	end
	
	-- Callback signature : spell, count, duration, expires = callback(unit, id)
	if class == 'HUNTER' then
		GetWatchers = function()
			return {
				player = {
					[ 19263] = OwnAuraGetter( 19263), -- Deterrence
					[ 34477] = OwnAuraGetter( 34477), -- Misdirection
					[ 56343] = OwnAuraGetter( 56343), -- Lock and Load
					[ 53224] = OwnAuraGetter( 53224), -- Improved Steady Shot
					[  3045] = OwnAuraGetter(  3045), -- Rapid Fire
				},
			}
		end
	elseif class == 'DRUID' then
		GetWatchers = function()
			return {
				player = {
					[113043] = OwnAuraGetter( 16870), -- Omen of Clarity => Clearcasting
					[ 77495] = OwnAuraGetter(100977), -- Mastery: Harmony => Harmony
					[ 33886] = OwnAuraGetter( 96206), -- Swift Rejuvenation
				},
			}
		end
	end
end
if not GetWatchers then return end

local mod = addon:NewModule("Auras", "AceEvent-3.0", "LibMovable-1.0", "LibSpellWidget-1.0")

local prefs

local DEFAULT_SETTINGS = {
	profile = {
		alpha = 0.6,
		size = 32,
		spacing = 4,
		anchor = { }
	},
	class = {
		spells = { ['*'] = true },
	}
}

local watchers = {}
local widgets = {}

function mod:OnInitialize()
	self.db = addon.db:RegisterNamespace(self.moduleName, DEFAULT_SETTINGS)
	prefs = self.db.profile
end

function mod:OnEnable()
	prefs = self.db.profile
	
	if not self.frame then
		local frame = CreateFrame("Frame", nil, UIParent)
		frame:SetPoint("RIGHT", UIParent, "CENTER", -400, 0)
		frame:SetClampedToScreen(true)
		frame:SetSize(prefs.size, prefs.size)
		self.frame = frame
		self:RegisterMovable(frame, function() return self.db.profile.anchor end, addon.L[addonName.." Auras"])
	end

	self.frame:SetAlpha(prefs.alpha)
	self:RegisterEvent('SPELLS_CHANGED', 'UpdateSpells')
	self:RegisterEvent('PLAYER_ENTERING_WORLD', 'UpdateAll')

	self:UpdateSpells('OnEnable')
end

function mod:OnDisable()
	self.frame:Hide()
end

local function CompareWidgets(a, b)
	if a.expires == b.expires then
		if a.duration == b.duration then
			return GetSpellInfo(a.spell) < GetSpellInfo(b.spell)
		else
			return b.duration < a.duration
		end
	else
		return b.expires < a.expires
	end
end

local order = {}
function mod:Layout()
	local iconSize = prefs.size
	if next(widgets) then
		self.frame:Show()
	else
		self.frame:Hide()
		return
	end

	wipe(order)
	for id, widget in pairs(widgets) do
		tinsert(order, widget)
	end
	table.sort(order, CompareWidgets)
	
	for i, widget in ipairs(order) do
		widget:ClearAllPoints()
		widget:SetSize(iconSize, iconSize)
		if i == 1 then
			widget:SetPoint('RIGHT', self.frame)
		else
			widget:SetPoint('RIGHT', order[i-1], 'LEFT', -prefs.spacing, 0)
		end
	end
end

function mod.OnWidgetReleased(widget)
	widgets[widget.id] = nil
	mod:Layout()
end

function mod:Update(event, unit)
	if not watchers[unit] then return end
	local allowed = self.db.class.spells
	self:Debug('Update', event, unit)
	local needLayout = false
	for id, callback in pairs(watchers[unit]) do
		local spell, count, duration, expires = callback(unit, id)
		if spell and allowed[id] then
			local widget = widgets[id]
			if widget then
				self:Debug(spell, 'Update widget', spell, count, duration, expires)
				widget:SetSpell(spell)
				widget:SetTimeleft(duration, expires)
				widget:SetCount(count)
				needLayout = true
			else
				self:Debug(spell, 'New widget', spell, count, duration, expires)
				widget = self:AcquireSpellWidget(prefs.size, spell, count, duration, expires)
				widget:SetParent(self.frame)
				widget.OnCooldownEnd = widgets.Release
				widget.OnRelease = self.OnWidgetReleased
				widget.id = id
				widgets[id] = widget
				needLayout = true
			end
		elseif widgets[id] then
			widgets[id]:Release()
			needLayout = true
		end
	end
	if needLayout then
		self:Layout()
	end
end

function mod:UpdateAll(event)
	for unit in pairs(watchers) do
		self:Update(event, unit)
	end
end

function mod:PLAYER_TARGET_CHANGED(event)
	self:Update(event, 'target')
end

function mod:PLAYER_FOCUS_CHANGED(event)
	self:Update(event, 'focus')
end

function mod:PLAYER_FOCUS_CHANGED(event)
	self:Update(event, 'focus')
end

function mod:UNIT_PET(event, unit)
	if unit == 'player' then
		self:Update(event, 'pet')
	end
end

function mod:UpdateSpells(event)
	for unit, spells in pairs(GetWatchers()) do
		for id, callback in pairs(spells) do
			if IsPlayerSpell(id) then
				if not watchers[unit] then
					self:Debug('Watching', unit, 'auras')
					watchers[unit] = { [id] = callback }
				else
					watchers[unit][id] = callback
				end
				self:Debug('Watching for', GetSpellInfo(id), 'on', unit)
			elseif watchers[unit] then
				watchers[unit][id] = nil
			end
		end
		if watchers[unit] and not next(watchers[unit]) then
			watchers[unit] = nil
		end
	end

	if next(watchers) then
		self:RegisterEvent('UNIT_AURA', 'Update')
	else
		self:UnregisterEvent('UNIT_AURA', 'Update')
	end
	if watchers.target then
		self:RegisterEvent('PLAYER_TARGET_CHANGED')
	else
		self:UnregisterEvent('PLAYER_TARGET_CHANGED')
	end
	if watchers.focus then
		self:RegisterEvent('PLAYER_FOCUS_CHANGED')
	else
		self:UnregisterEvent('PLAYER_FOCUS_CHANGED')
	end
	if watchers.pet then
		self:RegisterEvent('UNIT_PET')
	else
		self:UnregisterEvent('UNIT_PET')
	end

	self:UpdateAll(event)
end

function mod:OnConfigChanged()
	local frame = self.frame
	if frame then
		frame:SetAlpha(prefs.alpha)
		self:Layout()
	end
	if self:IsEnabled() then
		self:Update('OnConfigChanged')
	end
end

--------------------------------------------------------------------------------
-- Options
--------------------------------------------------------------------------------

function mod:GetOptions()
	local L = addon.L
	local spellList = {}
	return {
		args = {
			spells = {
				name = L['Spells'],
				type = 'multiselect',
				values = function()
					wipe(spellList)
					for unit, spells in pairs(GetWatchers()) do
						for id, callback in pairs(spells) do
							local name, _, texture = GetSpellInfo(id)
							spellList[id] = format("|T%s:24|t %s", texture, name)
						end
					end
					return spellList
				end,
				get = function(_, id)
					return self.db.class.spells[id]
				end,
				set = function(_, id, enable)
					self.db.class.spells[id] = enable
					self:UpdateAll('OnConfigChanged')
				end,
				order = 10,
			},
			size = {
				name = L['Size'],
				type = 'range',
				order = 40,
				min = 16,
				max = 256,
				step = 1,
				bigStep = 8,
			},
			alpha = {
				name = L['Opacity'],
				type = 'range',
				order = 50,
				isPercent = true,
				min = 0.01,
				max = 1.0,
				step = 0.01,
				bigStep = 0.1,
			},
			unlock = {
				name = function()
					return self:AreMovablesLocked() and L["Unlock"] or L["Lock"]
				end,
				type = 'execute',
				order = 70,
				func = function()
					if self:AreMovablesLocked() then
						self:UnlockMovables()
					else
						self:LockMovables()
					end
				end,
			}
		}
	}
end
