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

local mod = addon:NewModule("Auras", "AceEvent-3.0", "LibMovable-1.0", "LibSpellWidget-1.0")
local Spellbook = LibStub("LibSpellbook-1.0")

local GetWatchers
GetWatchers = function()
	local aurasToWatch = {}

	-- Initialize once
	GetWatchers = function() return aurasToWatch end

	local _, class = UnitClass('player')

	-- Helper
	local function OwnAuraGetter(spell, important, harmful)
		local name = GetSpellInfo(spell)
		if not name then
			geterrorhandler()("Unknown spell id", spell)
			return function() end
		end
		local filter = "PLAYER|" .. (harmful and "HARMFUL" or "HELPFUL")
		return function(unit, id, callback)
			local name, _, _, count, _, duration, expirationTime = UnitAura(unit, name, nil, filter)
			if name then
				return callback(spell, count, duration, expirationTime, important)
			end
		end
	end

	-- Callback signature : spell, count, duration, expires = callback(unit, id)
	if class == 'HUNTER' then
		aurasToWatch.player = {
			[ 19263] = OwnAuraGetter( 19263), -- Deterrence
			[ 34477] = OwnAuraGetter( 34477), -- Misdirection
			[ 53224] = OwnAuraGetter( 53224), -- Improved Steady Shot
			[  3045] = OwnAuraGetter(  3045), -- Rapid Fire
		}
	elseif class == 'DRUID' then
		aurasToWatch.player = {
			[ 22812] = OwnAuraGetter( 22812), -- Barkskin
			[ 29166] = OwnAuraGetter( 29166), -- Innervate
			[ 33886] = OwnAuraGetter( 96206), -- Swift Rejuvenation
			[ 77495] = OwnAuraGetter(100977), -- Mastery: Harmony => Harmony
			[106922] = OwnAuraGetter(106922), -- Might of Ursoc
			[114107] = OwnAuraGetter(114107), -- Soul of the Forest
			[124974] = OwnAuraGetter(124974), -- Nature's Vigil
		}
	elseif class == 'WARLOCK' then
		aurasToWatch.player = {
			[113858] = OwnAuraGetter(113858), -- Dark Soul: Instability
			[113860] = OwnAuraGetter(113860), -- Dark Soul: Misery
			[113861] = OwnAuraGetter(113861), -- Dark Soul: Knowledge
			[ 80240] = OwnAuraGetter( 80240), -- Havoc
			[104773] = OwnAuraGetter(104773), -- Unending Resolve
			[119839] = OwnAuraGetter(119839), -- Fury Ward (Dark Apotheosis)
			[132413] = OwnAuraGetter(132413), -- Shadow Bulwark (Grimoire of Sacrifice)
		}
	elseif class == 'MONK' then
		local staggerLevels = {
			[124273] = GetSpellInfo(124273),
			[124274] = GetSpellInfo(124274),
			[124275] = GetSpellInfo(124275)
		}
		local guard = GetSpellInfo(115295)
		aurasToWatch.player = {
			-- Stagger is provided by the Stance of the Sturdy Ox
			[115069] = function(unit, id, callback)
				for spell, name in pairs(staggerLevels) do
					if UnitDebuff(unit, name) then
						return callback(spell, select(15, UnitDebuff(unit, name)), 0, 0)
					end
				end
			end,
			[115203] = OwnAuraGetter(115203), -- Fortifying Brew
			[115295] = function(unit, id, callback) -- Guard
				local name, _, _, count, _, duration, expirationTime = UnitBuff(unit, guard)
				if name then
					return callback(115295, select(15, UnitBuff(unit, guard)), duration, expirationTime)
				end
			end,
		}
	else
		aurasToWatch.player = {}
	end

	-- Haste cooldowns
	local hasteCooldowns = {}
	for i, id in ipairs {
		  2825, -- Bloodlust
		 32182, -- Heroism
		 80353, -- Time Wrap
		 90355, -- Ancient Hysteria
		146555, -- Drums of Rage
	} do
		local name = GetSpellInfo(id)
		if name then
			tinsert(hasteCooldowns, name)
		else
			geterrorhandler()("Spell not found: "..id)
		end
	end
	aurasToWatch.player[-1] = function(unit, id, callback)
		for i, name in ipairs(hasteCooldowns) do
			local found, _, _, count, _, duration, expirationTime, _, _, _, spell = UnitBuff(unit, name)
			if found then
				return callback(spell, count, duration, expirationTime, true)
			end
		end
	end

	-- Encounter debuffs
	aurasToWatch.player[-2] = function(unit, id, callback)
		for index = 1, 128 do
			local name, _, _, count, _, duration, expirationTime, _, _, _, spell, _, isBossDebuff = UnitDebuff(unit, index)
			if name then
				if isBossDebuff then
					callback(spell, count, duration, expirationTime)
				end
			else
				return
			end
		end
	end

	-- Item buffs
	local LibItemBuffs = LibStub("LibItemBuffs-1.0")
	aurasToWatch.player[-3] = function(unit, id, callback)
		for index = 1, 128 do
			local name, _, _, count, _, duration, expirationTime, _, _, _, spell = UnitBuff(unit, index)
			if name then
				if LibItemBuffs:IsItemBuff(spell) then
					callback(spell, count, duration, expirationTime, true)
				end
			else
				return
			end
		end
	end

	return aurasToWatch
end

local prefs

local DEFAULT_SETTINGS = {
	profile = {
		alpha = 0.6,
		size = 32,
		spacing = 4,
		animation = true,
		anchor = { }
	},
	class = {
		spells = { ['*'] = true },
	}
}

local watchers = {}
local widgets = {}
local gen = 0
local needLayout = false

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
	self:RegisterEvent('PLAYER_ENTERING_WORLD', 'UpdateAll')
	Spellbook.RegisterCallback(self, "LibSpellbook_Spells_Changed", "UpdateSpells")

	self:UpdateSpells('OnEnable')
end

function mod:OnDisable()
	self.frame:Hide()
	Spellbook.UnregisterAllCallbacks(self)
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

	local iconSize = prefs.size
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

local function ScaleIn_OnPlay(anim)
	anim.widget.Cooldown:Hide()
	anim.widget.Icon:ClearAllPoints()
	anim.widget.Icon:SetPoint("CENTER", anim.widget)
end

local function ScaleIn_OnUpdate(anim)
	local f = 3 - 2 * anim:GetSmoothProgress()
	local w, h = anim.widget:GetSize()
	anim.widget.Icon:SetSize(f * w, f * h)
end

local function ScaleIn_OnFinished(anim)
	anim.widget.Cooldown:Show()
	anim.widget.Icon:SetAllPoints(anim.widget)
end

local function SpawnAnimation(widget)
	local anim = widget:CreateAnimationGroup()

	local scaleIn = anim:CreateAnimation("Animation")
	scaleIn.widget = widget
	scaleIn:SetOrder(1)
	scaleIn:SetDuration(0.3)
	scaleIn:SetScript('OnPlay', ScaleIn_OnPlay)
	scaleIn:SetScript('OnUpdate', ScaleIn_OnUpdate)
	scaleIn:SetScript('OnFinished', ScaleIn_OnFinished)

	return anim
end

function mod.OnWidgetReleased(widget)
	if widget.animIn and widget.animIn:IsPlaying() then
		widget.animIn:Stop()
	end
	widgets[widget.id] = nil
end

function mod:SpawnWidget(id, spell, count, duration, expires)
	widget = self:AcquireSpellWidget(prefs.size, spell, count, duration, expires)
	widget:SetParent(self.frame)
	widget.OnCooldownEnd = widget.Release
	widget.OnRelease = self.OnWidgetReleased
	widget.id = id
	widgets[id] = widget
	return widget
end


local function ReuseOrSpawnWidget(spell, count, duration, expires, important)
	local id = spell
	local widget = widgets[id]
	if widget then
		mod:Debug(id, 'Update widget', spell, count, duration, expires)
		widget:SetSpell(spell)
		widget:SetTimeleft(duration, expires)
		widget:SetCount(count)
	else
		mod:Debug(id, 'New widget', spell, count, duration, expires)
		widget = mod:SpawnWidget(id, spell, count, duration, expires)
		if important and prefs.animation then
			if not widget.animIn then
				mod:Debug('Spawning animation')
				widget.animIn = SpawnAnimation(widget)
			end
			if not widget.animIn:IsPlaying() then
				mod:Debug('Launching animation')
				widget.animIn:Play()
			end
		end
	end
	widget.gen = gen
end

function mod:Update(event, unit)
	if not watchers[unit] then return end
	local allowed = self.db.class.spells
	self:Debug('Update', event, unit)

	gen = (gen + 1) % 10000
	for id, callback in pairs(watchers[unit]) do
		if allowed[id] then
			callback(unit, id, ReuseOrSpawnWidget)
		end
	end
	for spell, widget in pairs(widgets) do
		if widget.gen ~= gen then
			widget:Release()
		end
	end

	self:Layout()
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
			if id < 0 or Spellbook:IsKnown(id) then
				if not watchers[unit] then
					self:Debug('Watching', unit, 'auras')
					watchers[unit] = { [id] = callback }
				else
					watchers[unit][id] = callback
				end
				self:Debug('Watching for', GetSpellInfo(id), '(#'..id..')', 'on', unit)
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
							local realId = id
							if id == -1 then
								realId = UnitFactionGroup("player") == "Horde" and 2825 or 32182
							end
							if realId > 0 then
								local name, _, texture = GetSpellInfo(realId)
								spellList[id] = format("|T%s:24|t %s", texture, name)
							end
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
			animation = {
				name = L['Animation'],
				desc = L['Play an animation for important buffs (trinket/enchant procs and encounter spells).'],
				type = 'toggle',
				order = 60,
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
