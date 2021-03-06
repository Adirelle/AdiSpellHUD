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

local _G = _G
local CreateFrame = _G.CreateFrame
local GetSpellInfo = _G.GetSpellInfo
local GetSpellLink = _G.GetSpellLink
local IsSpellOverlayed = _G.IsSpellOverlayed
local UIParent = _G.UIParent
local UnitAura = _G.UnitAura
local UnitBuff = _G.UnitBuff
local UnitClass = _G.UnitClass
local UnitDebuff = _G.UnitDebuff
local UnitFactionGroup = _G.UnitFactionGroup
local abs = _G.math. abs
local geterrorhandler = _G.geterrorhandler
local huge = _G.math.huge
local ipairs = _G.ipairs
local next = _G.next
local pairs = _G.pairs
local select = _G.select
local setmetatable = _G.setmetatable
local sqrt = _G.math.sqrt
local tinsert = _G.tinsert
local tsort = _G.table.sort
local unpack = _G.unpack
local wipe = _G.wipe

local addonName, addon = ...

local mod = addon:NewModule("Auras", "LibMovable-1.0", "LibSpellWidget-1.0")
local Spellbook = LibStub("LibSpellbook-1.0")
local LibPlayerSpells = LibStub("LibPlayerSpells-1.0")

local IsSpellKnown = addon.IsSpellKnown

local rules, spells
function mod:BuildRules()
	if rules then return end
	self:Debug('Building rules')
	rules, spells = {}, {}

	local IconLine = addon.IconLine
	local _, class = UnitClass('player')

	local function AddRule(unit, buff, provider, handler, desc)
		if not desc then
			local name, _, texture = GetSpellInfo(buff or provider)
			desc = name and addon.IconLine(texture, name) or "something"
		end
		if not rules[unit] then
			self:Debug('Has rules for', unit)
			rules[unit] = {}
		end
		tinsert(rules[unit], function(allowed)
			if provider and not IsSpellKnown(provider) then
				--@debug@
				self:Debug('Not watching for', desc, 'because', GetSpellLink(provider), 'is unknown')
				--@end-debug@
			elseif buff and not allowed[buff] then
				--@debug@
				self:Debug('Not watching for', desc, 'because it is disabled')
				--@end-debug@
			else
				--@debug@
				self:Debug('Watching for', desc)
				--@end-debug@
				return handler
			end
		end)
		if buff and desc then
			spells[buff] = desc
		end
	end

	local function AddPlayerBuff(buff, provider, important, harmful)
		local filter = "PLAYER|" .. (harmful and "HARMFUL" or "HELPFUL")
		AddRule(
			"player",
			buff,
			provider or buff,
			function(unit, callback)
				for index = 1, huge do
					local name, _, _, count, _, duration, expirationTime, _, _, _, spellId = UnitAura(unit, index, nil, filter)
					if name then
						if spellId == buff then
							callback(buff, count, duration, expirationTime, important)
							return
						end
					else
						return
					end
				end
			end
		)
	end

	if class == 'MONK' then
		-- Stagger
		local staggerLevels = {
			[124273] = GetSpellInfo(124273),
			[124274] = GetSpellInfo(124274),
			[124275] = GetSpellInfo(124275)
		}
		AddRule("player", 115069, 115069, function(unit, callback)
			for spell, name in pairs(staggerLevels) do
				if UnitDebuff(unit, name) then
					return callback(spell, select(15, UnitDebuff(unit, name)), 0, 0)
				end
			end
		end)

		local guard = GetSpellInfo(115295)
		AddRule("player", 115295, 115295, function(unit, callback)
			local name, _, _, count, _, duration, expirationTime = UnitBuff(unit, guard)
			if name then
				return callback(115295, select(15, UnitBuff(unit, guard)), duration, expirationTime)
			end
		end)
	elseif class == 'PRIEST' then
		AddPlayerBuff(123254, 109142) -- Twist of Fate
		AddPlayerBuff( 52798) -- Borrowed Time
		AddPlayerBuff(109964) -- Spirit Shell
		AddPlayerBuff( 81700) -- Archangel
	end

	-- Spells according to LibPlayerSpells
	for buff, flags, provider in LibPlayerSpells:IterateSpells('IMPORTANT SURVIVAL BURST MANA_REGEN POWER_REGEN', class..' PERSONAL AURA') do
		--@debug@
		self:Debug('LibPlayerSpells', GetSpellLink(provider), '=>', (GetSpellLink(buff)))
		--@end-debug@
		AddPlayerBuff(buff, provider)
	end

	-- Haste cooldowns
	local factionBurst = UnitFactionGroup("player") == "Horde" and 2825 or 32182
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
	AddRule("player", factionBurst, nil, function(unit, callback)
		for i, name in ipairs(hasteCooldowns) do
			local found, _, _, count, _, duration, expirationTime, _, _, _, spell = UnitBuff(unit, name)
			if found then
				return callback(spell, count, duration, expirationTime, true)
			end
		end
	end)

	-- Encounter debuffs
	AddRule("player", -1, nil, function(unit, callback)
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
	end, IconLine([[Interface\Icons\Ability_Creature_Cursed_02]], "Encounter debuffs"))

	-- Item buffs
	local LibItemBuffs = LibStub("LibItemBuffs-1.0")
	AddRule("player", -2, nil, function(unit, callback)
		for index = 1, 128 do
			local name, _, _, count, _, duration, expirationTime, _, _, _, spell = UnitBuff(unit, index)
			if name then
				if duration and duration > 0 and duration < 120 and LibItemBuffs:IsItemBuff(spell) then
					callback(spell, count, duration, expirationTime, duration <= 30)
				end
			else
				return
			end
		end
	end, IconLine([[Interface\Icons\ACHIEVEMENT_GUILDPERK_CHUG A LUG]], "Item buffs"))
end

local prefs

local DEFAULT_SETTINGS = {
	profile = {
		alpha = 0.6,
		size = 32,
		spacing = 4,
		animation = true,
		anchor = { },
		ignoreOverlayed = true,
		direction = "rightToLeft",
		maxIcons = 16,
		sortOrder = "expirationDesc",
	},
	class = {
		spells = { ['*'] = true },
		customSpells = { },
	}
}

local handlers = {}
local widgets = {}
local pool = {}
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

		local anchor = CreateFrame("Frame", nil, frame)
		anchor:SetSize(prefs.size, prefs.size)
		self.anchor = anchor

		self:RegisterMovable(frame, function() return self.db.profile.anchor end, addon.L[addonName.." Auras"], anchor)
	end

	self.frame:SetAlpha(prefs.alpha)
	Spellbook.RegisterCallback(self, "LibSpellbook_Spells_Changed")
	if self.hasSpells then
		self:UpdateSpells('OnEnable')
	end
end

function mod:OnDisable()
	self:UnregisterAllEvents()
	self.frame:Hide()
	Spellbook.UnregisterAllCallbacks(self)
end

function mod:LibSpellbook_Spells_Changed(event)
	self.hasSpells = true
	self:BuildRules()
	self:UpdateSpells(event)
end

--------------------------------------------------------------------------------
-- Bar layout
--------------------------------------------------------------------------------

local comparators = {
	startAsc = function(a, b)
		return a.expires - a.duration < b.expires - b.duration
	end,
	startDesc = function(a, b)
		return a.expires - a.duration > b.expires - b.duration
	end,
	durationDesc = function(a, b)
		return a.duration > b.duration
	end,
	durationAsc = function(a, b)
		return a.duration < b.duration
	end,
	expirationAsc = function(a, b)
		return a.expires < b.expires
	end,
	expirationDesc = function(a, b)
		return a.expires > b.expires
	end,
}

local currentComparator = comparators.newestFirst
local function CompareWidgets(a, b)
	return currentComparator(a.spell, b.spell)
end

local directions = {
	--              from,     to,       dx, dy
	rightToLeft = { "RIGHT",  "LEFT",   -1,  0 },
	leftToRight = { "LEFT",   "RIGHT",   1,  0 },
	topToBottom = { "TOP",    "BOTTOM",  0, -1 },
	bottomToTop = { "BOTTOM", "TOP",     0,  1 },
}

local order = {}
function mod:Layout()
	local maxIcons, iconSize = prefs.maxIcons, prefs.size
	local from, to, dx, dy = unpack(directions[prefs.direction])

	local span = (iconSize+prefs.spacing)*(maxIcons-1)
	local anchor = self.anchor
	anchor:ClearAllPoints()
	anchor:SetPoint(from)
	anchor:SetSize(iconSize + abs(dx)*span, iconSize + abs(dy)*span)

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
	currentComparator = comparators[prefs.sortOrder]
	tsort(order, CompareWidgets)

	dx, dy = dx*prefs.spacing, dy*prefs.spacing
	for i, widget in ipairs(order) do
		widget:ClearAllPoints()
		if i <= maxIcons then
			self:Debug('Showing', i..'th', 'icons')
			widget:SetSize(iconSize, iconSize)
			if i == 1 then
				widget:SetPoint(from, self.frame)
			else
				widget:SetPoint(from, order[i-1], to, dx, dy)
			end
			widget:Show()
		else
			self:Debug('Ignoring', i..'th', 'icons')
			widget:Hide()
		end
	end
end

--------------------------------------------------------------------------------
-- Widget handling
--------------------------------------------------------------------------------

local widgetParent = CreateFrame("Frame")
local widgetProto = setmetatable({}, { __index = widgetParent })
local widgetMeta = { __index = widgetProto }

function widgetProto:SetSize(w, h)
	widgetParent.SetSize(self, w, h)
	self.spell:SetSize(w, h)
end

function widgetProto:OnAcquire(id, spell, count, duration, expires)
	self.id = id
	local spell = mod:AcquireSpellWidget(prefs.size, spell, count, duration, expires)
	spell:SetParent(self)
	spell:SetPoint("CENTER")
	self.spell = spell
	widgets[id] = self
end

function widgetProto:Release()
	self:SetAnimation(nil)
	self.spell:Release()
	self.spell = nil
	widgets[self.id] = nil
	pool[self] = true
end

local animations = {
	["importantIn"] = {
		duration = 0.3,
		Update = function(self, progress)
			self.spell:SetScale(3-2*progress)
		end,
		Cleanup =  function(self)
			self.spell:SetScale(1)
		end,
	},
	["in"] = {
		duration = 0.3,
		Update = function(self, progress)
			self.spell:SetAlpha(progress)
		end,
		Cleanup =  function(self)
			self.spell:SetAlpha(1)
		end,
	},
	["out"] = {
		duration = 0.5,
		Update = function(self, progress)
			self.spell:SetAlpha(1-progress)
		end,
		Cleanup = function(self)
			self.spell:SetAlpha(1)
		end,
		OnFinished = widgetProto.Release,
	},
}

function widgetProto:OnUpdate(elapsed)
	local anim = animations[self.animation]
	self.timeLeft = self.timeLeft - elapsed
	if self.timeLeft < 0 then
		local prev = self:SetAnimation(nil)
		if prev and prev.OnFinished then
			prev.OnFinished(self)
		end
	else
		local progress = sqrt(1 - (self.timeLeft / anim.duration))
		anim.Update(self, progress)
	end
end

function widgetProto:SetAnimation(animation)
	if not prefs.animation then animation = nil end
	if self.animation == animation then return end

	local prev = animations[self.animation or false]
	if prev then
		prev.Cleanup(self)
	end

	self.animation = animation

	local new = animations[animation or false]
	if new then
		self.timeLeft = new.duration
		self:SetScript('OnUpdate', self.OnUpdate)
		new.Update(self, 0)
	else
		self:SetScript('OnUpdate', nil)
	end

	return prev
end

local function ReuseOrSpawnWidget(spell, count, duration, expires, important)
	if IsSpellOverlayed(spell) and prefs.ignoreOverlayed then
		return
	end
	local id = spell
	local widget = widgets[id]
	local animIn = important and "importantIn" or "in"
	if widget then
		widget.spell:SetSpell(spell)
		widget.spell:SetTimeleft(duration, expires)
		widget.spell:SetCount(count)
		if widget.animation == "out" then
			widget:SetAnimation(animIn)
		end
	else
		widget = next(pool)
		if widget then
			pool[widget] = nil
		else
			widget = setmetatable(CreateFrame("Frame", nil, mod.frame), widgetMeta)
		end
		widget:OnAcquire(id, spell, count, duration, expires)
		widget:SetAnimation(animIn)
	end
	widget.gen = gen
end

--------------------------------------------------------------------------------
-- Options
--------------------------------------------------------------------------------

function mod:Update(event, unit)
	if not handlers[unit] then return end
	self:Debug('Update', event, unit)

	gen = (gen + 1) % 10000
	for i, handler in ipairs(handlers[unit]) do
		handler(unit, ReuseOrSpawnWidget)
	end
	for spell, widget in pairs(widgets) do
		if widget.gen ~= gen then
			widget:SetAnimation("out")
		end
	end

	self:Layout()
end

function mod:UpdateAll(event)
	for unit in pairs(handlers) do
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
	local allowed = self.db.class.spells
	for unit, unitRules in pairs(rules) do
		for i, rule in ipairs(unitRules) do
			local handler = rule(allowed)
			if handler then
				if not handlers[unit] then
					self:Debug('Watching', unit, 'auras')
					handlers[unit] = { handler }
				else
					tinsert(handlers[unit], handler)
				end
			end
		end
		if handlers[unit] and not next(handlers[unit]) then
			handlers[unit] = nil
		end
	end

	if next(handlers) then
		self:RegisterEvent('UNIT_AURA', 'Update')
		self:RegisterEvent('PLAYER_ENTERING_WORLD', 'UpdateAll')
	else
		self:UnregisterEvent('UNIT_AURA')
		self:UnregisterEvent('PLAYER_ENTERING_WORLD')
	end
	if handlers.target then
		self:RegisterEvent('PLAYER_TARGET_CHANGED')
	else
		self:UnregisterEvent('PLAYER_TARGET_CHANGED')
	end
	if handlers.focus then
		self:RegisterEvent('PLAYER_FOCUS_CHANGED')
	else
		self:UnregisterEvent('PLAYER_FOCUS_CHANGED')
	end
	if handlers.pet then
		self:RegisterEvent('UNIT_PET')
	else
		self:UnregisterEvent('UNIT_PET')
	end
	if prefs.ignoreOverlayed then
		self:RegisterEvent('SPELL_ACTIVATION_OVERLAY_GLOW_SHOW', 'UpdateAll')
		self:RegisterEvent('SPELL_ACTIVATION_OVERLAY_GLOW_HIDE', 'UpdateAll')
	else
		self:UnregisterEvent('SPELL_ACTIVATION_OVERLAY_GLOW_SHOW')
		self:UnregisterEvent('SPELL_ACTIVATION_OVERLAY_GLOW_HIDE')
	end

	self:UpdateAll(event)
end

function mod:OnConfigChanged()
	local frame = self.frame
	if frame then
		frame:SetAlpha(prefs.alpha)
		self:Layout()
	end
	if self:IsEnabled() and self.hasSpells then
		self:UpdateSpells('OnConfigChanged')
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
					return spells or {}
				end,
				get = function(_, key)
					return self.db.class.spells[key]
				end,
				set = function(_, key, enable)
					self.db.class.spells[key] = enable
					self:UpdateSpells('OnConfigChanged')
				end,
				order = 10,
			},
			ignoreOverlayed = {
				name = L['Ignore flashing spells'],
				desc = L['Do not show spells that are otherwise flashing by Blizzard UI.'],
				type = 'toggle',
				order = 15,
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
			direction = {
				name = L['Direction'],
				type = 'select',
				order = 55,
				values = {
					rightToLeft = L["Right to left"],
					leftToRight = L["Left to right"],
					topToBottom = L["Top to bottom"],
					bottomToTop = L["Bottom to top"],
				},
			},
			maxIcons = {
				name = L['Maximum number of icons'],
				desc = L['Do not show more than this number of icons.'],
				type = 'range',
				order = 57,
				min = 1,
				max = 64,
				softMax = 16,
				step = 1,
			},
			sortOrder = {
				name = L['Ordering'],
				type = 'select',
				order = 58,
				values = {
					startAsc       = L["Oldest first"],
					startDesc      = L["Newest first"],
					durationDesc   = L["Longest first"],
					durationAsc    = L["Shortest first"],
					expirationAsc  = L["First to expire first"],
					expirationDesc = L["Last to expire first"],
				},
			},
			animation = {
				name = L['Animation'],
				desc = L['Animate the icons when the aura appears/disappears.'],
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
