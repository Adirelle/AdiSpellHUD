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
local mod = addon:NewModule("Cooldowns", "AceEvent-3.0", "LibMovable-1.0")
local Spellbook = LibStub("LibSpellbook-1.0")
local LibPlayerSpells = LibStub("LibPlayerSpells-1.0")

--------------------------------------------------------------------------------
-- Consts and upvalues
--------------------------------------------------------------------------------

local COOLDOWNS

local DEFAULT_SETTINGS = {
	profile = {
		minDuration = 2,
		size = 96,
		alpha = 0.75,
		spells = { ['*'] = true },
		items = { ['*'] = true },
		anchor = { }
	}
}

local MODELS = {
	spells = {
		GetInfo = function(id)
			local name, _, texture = GetSpellInfo(id)
			if mod.petSpells[id] then
				return format("%s (%s)", name, UnitName("pet")), texture
			else
				return name, texture
			end
		end,
		GetCooldown = GetSpellCooldown,
		GetTexture = function(id) return select(3, GetSpellInfo(id)) end,
		IsMuted = GetSpellAutocast,
	},
	items = {
		GetInfo = function(id)
			local name, _, _, _, _, _, _, _, _, texture = GetItemInfo(id)
			return name, texture
		end,
		GetCooldown = GetItemCooldown,
		GetTexture = function(id) return select(10, GetItemInfo(id)) end,
		IsMuted = function() return false end,
	},
}

local prefs

--------------------------------------------------------------------------------
-- Initialization
--------------------------------------------------------------------------------

function mod:OnInitialize()
	self.db = addon.db:RegisterNamespace(self.moduleName, DEFAULT_SETTINGS)
	prefs = self.db.profile

	self.runningCooldowns = {}
	self.cooldownsToWatch = {}
	self.petSpells = {}

	self.RegisterEvent(self.name, "ACTIVE_TALENT_GROUP_CHANGED", self.UpdateEnabledState, self)
	self.RegisterEvent(self.name, "PLAYER_TALENT_UPDATE", self.UpdateEnabledState, self)
	self.RegisterEvent(self.name, "UNIT_INVENTORY_CHANGED", self.UNIT_INVENTORY_CHANGED, self)
	Spellbook.RegisterCallback(self, "LibSpellbook_Spells_Changed", "UpdateEnabledState")
	self:UpdateEnabledState("OnInitialize")

	self.unusedOverlays = {}
	self.overlaysInUse = {}
end

--------------------------------------------------------------------------------
-- Testing enable state
--------------------------------------------------------------------------------

local function MergeSpells(spells, key)
	if not COOLDOWNS[key] then
		return mod:Debug('Empty spell list', key)
	end
	for spellID, cond in pairs(COOLDOWNS[key]) do
		local name = GetSpellLink(spellID)
		if not cond then
			mod:Debug('Not watching for', name)
			spells[spellID] = nil
		elseif Spellbook:IsKnown(spellID) then
			mod:Debug('Watching for', name)
			spells[spellID] = true
		else
			mod:Debug('Unknown spell', name)
		end
	end
end

local _, playerClass = UnitClass("player")
function mod:UpdateEnabledState(event)
	self:Debug('UpdateEnabledState', event)
	local cooldownsToWatch = self.cooldownsToWatch
	local spells = wipe(cooldownsToWatch.spells or {})
	local items = wipe(cooldownsToWatch.items or {})
	local petSpells = wipe(self.petSpells)

	if addon.db.profile.modules[self.name] then
		for spellID in LibPlayerSpells:IterateSpells(playerClass..' RACIAL TRADESKILL', 'COOLDOWN') do
			if Spellbook:IsKnown(spellID) then
				self:Debug('Watching ', GetSpellLink(spellID), 'according to LibPlayerSpells')
				spells[spellID] = true
			end
		end
		MergeSpells(spells, 'COMMON')
		MergeSpells(spells, playerClass)
		for id, name in Spellbook:IterateSpells(BOOKTYPE_PET) do
			self:Debug("pet spell:", id, name)
			if not IsPassiveSpell(id) then
				self:Debug('Watch for pet spell', name)
				spells[id] = true
				petSpells[id] = index
			end
		end
		for index = 1, 18 do
			local id = GetInventoryItemID("player", index)
			if id and GetItemSpell(id) then -- Only return values for items with on-use effects
				self:Debug('Watch for item', (GetItemInfo(id)))
				items[id] = true
			end
		end
	end
	cooldownsToWatch.spells = next(spells) and spells
	cooldownsToWatch.items = next(items) and items

	local enable = (cooldownsToWatch.spells or cooldownsToWatch.items) ~= nil
	if event == "OnInitialize" then
		self:SetEnabledState(enable)
	elseif enable then
		if not self:IsEnabled() then
			self:Debug('Enabling')
			self:Enable()
		else
			self:Update(true)
		end
	elseif self:IsEnabled() then
		self:Debug('Disabling')
		self:Disable()
	end
end

function mod:UNIT_INVENTORY_CHANGED(event, unit)
	self:Debug(event, unit)
	if unit == "player" then
		self:UpdateEnabledState(event)
	end
end

--------------------------------------------------------------------------------
-- Enabling/disabling
--------------------------------------------------------------------------------

function mod:OnEnable()
	prefs = self.db.profile
	wipe(self.runningCooldowns)

	if not self.timer then
		local timer = CreateFrame("Frame")
		timer:Hide()
		timer:SetScript('OnUpdate', function(_, elapsed)
			self.delay = self.delay - elapsed
			if self.delay <= 0 or self.needUpdate then
				timer:Hide()
				self:Update()
			end
		end)
		self.delay = 0
		self.timer = timer
	end

	if not self.frame then
		local frame = CreateFrame("Frame", nil, UIParent)
		frame:SetPoint("CENTER")
		frame:SetSize(prefs.size, prefs.size)
		frame:SetAlpha(prefs.alpha)
		frame:SetClampedToScreen(true)
		self.frame = frame
		self:RegisterMovable(frame, function() return self.db.profile.anchor end, addon.L[addonName.." Cooldown Icon"])
	end

	self:RegisterEvent("SPELL_UPDATE_COOLDOWN")
	self:Debug('Enabled')
	self:Update(true)
end

function mod:OnDisable()
	self.timer:Hide()
	self.frame:Hide()
end

function mod:OnConfigChanged()
	local frame = self.frame
	if frame then
		frame:SetSize(prefs.size, prefs.size)
		frame:SetAlpha(prefs.alpha)
	end
	if self:IsEnabled() then
		self:Update(true)
	end
end

--------------------------------------------------------------------------------
-- Monitoring and feedback
--------------------------------------------------------------------------------

function mod:Update(silent)
	if not self.timer then return end
	--self:Debug("Update", silent)
	self.needUpdate = nil
	local nextCheck = math.huge
	local now = GetTime()
	local minDuration = prefs.minDuration
	local running = self.runningCooldowns
	for model, ids in pairs(self.cooldownsToWatch) do
		local modelProto = MODELS[model]
		local GetCooldown, GetTexture, IsMuted, enabled = modelProto.GetCooldown, modelProto.GetTexture, modelProto.IsMuted, prefs[model]
		for id in pairs(ids) do
			local start, duration = GetCooldown(id)
			local timeLeft = max(0, (start and duration and duration >= minDuration and start+duration or 0) - now)
			if timeLeft > 0 then
				nextCheck = min(nextCheck, timeLeft)
				running[id] = timeLeft
			elseif running[id] then
				running[id] = nil
				if not silent and enabled[id] and not IsMuted(id) then
					self:ShowCooldownReset(id, GetTexture(id))
				end
			end
		end
	end
	if nextCheck > 0 and nextCheck < math.huge then
		self.delay = nextCheck + 0.1
		self:Debug('Next update in', self.delay)
		self.timer:Show()
	else
		self.timer:Hide()
	end
end

function mod:SPELL_UPDATE_COOLDOWN()
	self.needUpdate = true
	self.timer:Show()
end

function mod:ShowCooldownReset(id, icon)
	local overlay = self:GetOverlay(id)
	overlay.texture:SetTexture(icon)
	overlay:Show()
end

--------------------------------------------------------------------------------
-- Widget handling
--------------------------------------------------------------------------------

local function Overlay_OnShow(overlay)
	mod:Debug('Overlay_OnShow', overlay)
	overlay.animation:Stop()
	overlay.animation:Play()
end

local function Animation_OnFinished(animation)
	mod:Debug('Animation_OnFinished', animation)
	local overlay = animation:GetParent()
	overlay:Hide()
	mod.overlaysInUse[overlay.id] = nil
	mod.unusedOverlays[overlay] = true
end

function mod:CreateOverlay()
	local overlay = CreateFrame("Frame", nil, self.frame)
	overlay:SetAllPoints(self.frame)
	overlay:SetAlpha(0)
	overlay:Hide()

	overlay:SetScript('OnShow', Overlay_OnShow)

	local texture = overlay:CreateTexture(nil, "OVERLAY")
	texture:SetAllPoints(overlay)
	texture:SetTexCoord(5/64, 59/64, 5/64, 59/64)
	overlay.texture = texture

	local animation = overlay:CreateAnimationGroup()
	animation:SetIgnoreFramerateThrottle(true)
	animation:SetScript('OnFinished', Animation_OnFinished)
	overlay.animation = animation

	local fadeIn = animation:CreateAnimation("Alpha")
	fadeIn:SetOrder(1)
	fadeIn:SetDuration(0.5)
	fadeIn:SetChange(1)
	fadeIn:SetSmoothing("OUT")

	local scale = animation:CreateAnimation("Scale")
	scale:SetOrder(1)
	scale:SetDuration(1)
	scale:SetScale(4, 4)
	scale:SetSmoothing("IN_OUT")

	local fadeOut = animation:CreateAnimation("Alpha")
	fadeOut:SetOrder(1)
	fadeOut:SetDuration(0.5)
	fadeOut:SetStartDelay(0.5)
	fadeOut:SetChange(-1)
	fadeOut:SetSmoothing("IN")

	return overlay
end

function mod:GetOverlay(id)
	local overlay = self.overlaysInUse[id]
	if not overlay then
		overlay = next(self.unusedOverlays)
		if overlay then
			self.unusedOverlays[overlay] = nil
		else
			overlay = self:CreateOverlay()
		end
	end
	self.overlaysInUse[id] = overlay
	overlay.id = id
	return overlay
end

--------------------------------------------------------------------------------
-- Options
--------------------------------------------------------------------------------

function mod:GetOptions()
	local L = addon.L

	local function HasNoValue(info)
		return not self.cooldownsToWatch[info[#info]]
	end

	local values = {}
	local function ListValues(info)
		local model = info[#info]
		local GetInfo = MODELS[model].GetInfo
		wipe(values)
		for id in pairs(self.cooldownsToWatch[model]) do
			local name, texture = GetInfo(id)
			values[id] = addon.IconLine(texture, name)
		end
		return values
	end

	return {
		args = {
			minDuration = {
				name = L['Minimum duration (sec.)'],
				desc = L['Any cooldown with a duration lower than that value is ignored, whether it is enabled or not.'],
				order = 10,
				type = 'range',
				min = 2,
				max = 60,
				step = 0.5,
				bigStep = 1,
			},
			spells = {
				name = L['Monitored spells'],
				desc = L['Select which spells should be monitored.'],
				order = 20,
				type = 'multiselect',
				values = ListValues,
				hidden = HasNoValue,
			},
			items = {
				name = L['Monitored items'],
				desc = L['Select which equipped items should be monitored.'],
				order = 30,
				type = 'multiselect',
				values = ListValues,
				hidden = HasNoValue,
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
			test = {
				name = L['Test'],
				type = 'execute',
				order = 60,
				func = function()
					local i = math.random(1, 8)
					mod:ShowCooldownReset(-i, format([[Interface\Icons\INV_Misc_Gear_%02d]], i))
				end,
				disabled = function() return not mod:IsEnabled() end,
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

--------------------------------------------------------------------------------
-- The database of spells to monitor
--------------------------------------------------------------------------------

COOLDOWNS = {
	WARLOCK = {
		[   755] = true, -- Glyphed Health Funnel
		[  1122] = true, -- Summon Infernal
		[  5484] = true, -- Howl of Terror
		[  6229] = true, -- Twilight Ward
		[  6789] = true, -- Mortal Coil
		[ 18540] = true, -- Summon Doomguard
		[ 20707] = true, -- Soulstone
		[ 29858] = true, -- Soulshatter
		[ 30283] = true, -- Shadowfury
		[ 47897] = true, -- Demonic Breath
		[ 48020] = true, -- Demonic Circle: Teleport
		[104773] = true, -- Unending Resolve
		[108359] = true, -- Dark Regeneration
		[108416] = true, -- Sacrificial Pact
		[108482] = true, -- Unbound Will
		[108501] = true, -- Grimore of Service
		[110913] = true, -- Dark Bargain
		[111397] = true, -- Blood Horror
		[132411] = true, -- Singe Magic (sacrified Imp)
		-- Affliction
		-- Demonology
		[119839] = true, -- Fury Ward (Dark Apotheosis)
		[116198] = true, -- Aura of Enfeeblement (Metamorphosis/Dark Apotheosis)
		[104025] = true, -- Immolation Aura (Metamorphosis/Dark Apotheosis)
		[132413] = true, -- Shadow Bulwark (Grimoire of Sacrifice)
		[113861] = true, -- Dark Soul: Knowledge
		[114175] = true, -- Demonic Slash (Dark Apotheosis)
		[105174] = true, -- Hand of Gul'dan
		-- Destruction
		[ 17962] = true, -- Conflagrate
		[ 80240] = true, -- Havoc
		[113858] = true, -- Dark Soul: Instability
		[120451] = true, -- Flames of Xororth
	},
	PRIEST = {
		[   527] = true, -- Purify
		[  8122] = true, -- Psychic Scream
		[ 10060] = true, -- Power Infusion
		[ 19236] = true, -- Desperate Prayer
		[ 32375] = true, -- Mass Dispel
		[ 34433] = true, -- Shadowfiend
		[ 64843] = true, -- Divine Hymn
		[ 64901] = true, -- Hymn of Hope
		[ 73325] = true, -- Leap of Faith
		[ 89485] = true, -- Inner Focus
		[108920] = true, -- Void Tendrils
		[108921] = true, -- Psyfiend
		[108968] = true, -- Void Shift
		-- Discipline
		[ 33206] = true, -- Pain Suppression
		[ 62618] = true, -- Power Word: Barrier
		[109964] = true, -- Spirit Shell
		-- Holy
		[ 47788] = true, -- Guardian Spirit
		[126135] = true, -- Lightwell
		-- Shadow
		[ 15286] = true, -- Vampiric Embrace
		[ 47585] = true, -- Dispersion
		[142723] = true, -- Void Shift
	},
	SHAMAN = {
		[ 77130] = true, -- Purify Spirit
		[ 51886] = true, -- Cleanse Spirit
		-- See https://github.com/Adirelle/AdiSpellHUD/issues/1
		[  2062] = true, -- Earth Elemental
		[  2894] = true, -- Fire Elemental
		[ 30823] = true, -- Shamanistic Rage
		[ 51490] = true, -- Thunderstorm
		[ 79206] = true, -- Spiritwalker's Grace
		[108270] = true, -- Stone Bullwark Totem
		[108281] = true, -- Ancestral Guidance
		[114049] = true, -- Ascendence
	},
}
