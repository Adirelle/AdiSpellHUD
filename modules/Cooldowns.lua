--[[
AdiSpellHUD - Spell overlay customization and spell state HUD.
Copyright 2011 Adirelle (adirelle@tagada-team.net)
All rights reserved.
--]]

local addonName, addon = ...
local mod = addon:NewModule("Cooldowns", "AceEvent-3.0")

--------------------------------------------------------------------------------
-- Consts and upvalues
--------------------------------------------------------------------------------

local COOLDOWNS

local DEFAULT_SETTINGS = {
	profile = {
		spells = { ['*'] = true },
		items = { ['*'] = true },
	}
}

local MODELS = {
	spells = {
		GetInfo = function(id)
			local name, _, texture = GetSpellInfo(id)
			return name, texture
		end,
		GetCooldown = GetSpellCooldown,
		GetTexture = function(id) return select(3, GetItemInfo(id)) end,
	},
	items = {
		GetInfo = function(id)
			local name, _, _, _, _, _, _, _, _, texture = GetItemInfo(id)
			return name, texture
		end,
		GetCooldown = GetItemCooldown,
		GetTexture = function(id) return select(10, GetItemInfo(id)) end,
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
	self.RegisterEvent(self.name, "ACTIVE_TALENT_GROUP_CHANGED", self.UpdateEnabledState, self)
	self.RegisterEvent(self.name, "SPELLS_CHANGED", self.UpdateEnabledState, self)
	self.RegisterEvent(self.name, "UNIT_INVENTORY_CHANGED", self.UNIT_INVENTORY_CHANGED, self)
	self:CheckActivation("OnInitialize")

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

	SpellActivationOverlayFrame.HideOverlays = SpellActivationOverlay_HideOverlays
end

--------------------------------------------------------------------------------
-- Testing enable state
--------------------------------------------------------------------------------

local function MergeSpells(dst, src)
	if src then
		for spellID, cond in pairs(src) do
			if not cond then
				dst[spellID] = nil
				mod:Debug('Do not watch for', GetSpellInfo(spellID))
			elseif IsSpellKnown(spellID) then
				mod:Debug('Watch for', (GetSpellInfo(spellID)))
				dst[spellID] = true
			end
		end
	end
end

function mod:UpdateEnabledState(event)
	self:Debug('CheckActivation', event)
	local primaryTree = GetPrimaryTalentTree()
	if not primaryTree then
		if event == "OnInitialize" then
			self.RegisterEvent(self.name, "PLAYER_ALIVE", self.UpdateEnabledState, self)
		end
		return
	end
	local _, class = UnitClass("player")
	self:Debug('CheckActivation:', class, primaryTree)

	local cooldownsToWatch = self.cooldownsToWatch
	local spells = wipe(cooldownsToWatch.spells or {})
	local items = wipe(cooldownsToWatch.items or {})

	if prefs.enabled then
		MergeSpells(spells, COOLDOWNS.COMMON)
		if COOLDOWNS[class] then
			MergeSpells(spells, COOLDOWNS[class]['*'])
			MergeSpells(spells, COOLDOWNS[class][primaryTree])
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
	self:RegisterEvent("SPELL_UPDATE_COOLDOWN")
	self:Debug('Enabled')
	self:Update(true)
end

function mod:OnDisable()
	self.timer:Hide()
end

--------------------------------------------------------------------------------
-- Monitoring and feedback
--------------------------------------------------------------------------------

function mod:Update(silent)
	self:Debug("Update", silent)
	self.needUpdate = nil
	local nextCheck = math.huge
	local now = GetTime()
	local running = self.runningCooldowns
	for model, ids in pairs(self.cooldownsToWatch) do
		local GetCooldown, GetTexture = MODELS[model].GetCooldown, MODELS[model].GetTexture
		for id in pairs(ids) do
			local start, duration = GetCooldown(id)
			local timeLeft = max(0, (start and duration and duration > 1.5 and start+duration or 0) - now)
			if timeLeft > 0 then
				nextCheck = min(nextCheck, timeLeft)
				running[id] = timeLeft
			elseif running[id] then
				running[id] = nil
				if not silent then
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

local AceTimer = LibStub("AceTimer-3.0")
function mod:ShowCooldownReset(id, icon)
	SpellActivationOverlay_ShowOverlay(SpellActivationOverlayFrame, id, icon, "CENTER", 0.5, 255, 255, 255, false, false)
	AceTimer.ScheduleTimer(SpellActivationOverlayFrame, "HideOverlays", 0.5, id)
end

--------------------------------------------------------------------------------
-- Options
--------------------------------------------------------------------------------

function mod:GetOptions()
	local L = addon.L

	local function HasNoValue(info)
		return not next(self.cooldownsToWatch[info[#info]])
	end

	local values = {}
	local function ListValues(info)
		local GetInfo = MODELS[info[#info]].GetInfo
		wipe(values)
		for id in pairs(self.cooldownsToWatch[model]) do
			local name, texture = GetInfo(id)
			values[id] = format("|T%s:24|t %s", texture, name)
		end
		return values
	end

	return {
		args = {
			spells = {
				name = L['Spells'],
				type = 'multiselect',
				values = ListValues,
				hidden = HasNoValue,
				order = 10,
			},
			items = {
				name = L['Items'],
				type = 'multiselect',
				values = ListValues,
				hidden = HasNoValue,
				order = 20,
			}
		}
	}
end

--------------------------------------------------------------------------------
-- The database of spells to monitor
--------------------------------------------------------------------------------

COOLDOWNS = {
	COMMON = {
		-- Lifeblood (8 ranks)
		[81780] = true,
		[55428] = true,
		[55480] = true,
		[55500] = true,
		[55501] = true,
		[55502] = true,
		[55503] = true,
		[74497] = true,
		-- Racial traits
		[28730] = true, -- Arcane Torrent (mana)
		[50613] = true, -- Arcane Torrent (runic power)
		[80483] = true, -- Arcane Torrent (focus)
		[25046] = true, -- Arcane Torrent (energy)
		[69179] = true, -- Arcane Torrent (rage)
		[26297] = true, -- Berseking
		[20542] = true, -- Blood Fury (attack power)
		[33702] = true, -- Blood Fury (spell power)
		[33697] = true, -- Blood Fury (both)
		[68992] = true, -- Darkflight
		[20589] = true, -- Escape Artist
		[59752] = true, -- Every Man for Himself
		[69041] = true, -- Rocket Barrage
		[69070] = true, -- Rocket Jump
		[58984] = true, -- Shadowmeld
		[20594] = true, -- Stoneform
		[20549] = true, -- War Stomp
		[ 7744] = true, -- Will of the Forsaken
		[59545] = true, -- Gift of the Naaru
		[59543] = true, -- Gift of the Naaru
		[59548] = true, -- Gift of the Naaru
		[59542] = true, -- Gift of the Naaru
		[59544] = true, -- Gift of the Naaru
		[59547] = true, -- Gift of the Naaru
		[28880] = true, -- Gift of the Naaru
	},
	DRUID = {
		['*'] = {
			[29166] = true, -- Innervate
			[22812] = true, -- Barkskin
			[20484] = true, -- Rebirth
			[  740] = true, -- Tranquility
			[  467] = true, -- Thorns
			[ 1850] = true, -- Dash
			--[80964] = true, -- Skull Bash (bear)
			[80965] = true, -- Skull Bash (cat)
			--[77761] = true, -- Stampeding Roar (bear)
			[77764] = true, -- Stampeding Roar (cat)
			[22842] = true, -- Frenzied Regeneration
		},
		-- Balance
		[1] = {
			[48505] = true, -- Starfall
			[78675] = true, -- Solar Beam
		},
		-- Feral
		[2] = {
			[61336] = true, -- Survival Instincts
		},
		-- Restoration
		[3] = {
			[33891] = true, -- Tree of Life
			[18562] = true, -- Swiftmend
			[17116] = true, -- Nature's Swiftness
			[48438] = true, -- Wild Growth
		},
	},
	HUNTER = {
		['*'] = {
			[ 5384] = true, -- Feign Death
			[  781] = true, -- Disengage
			[34477] = true, -- Misdirection
			[ 3045] = true, -- Rapid Fire
			[ 1499] = true, -- Freezing Trap
			[13813] = true, -- Explosive Trap
			[19503] = true, -- Scatter Shot
			[19263] = true, -- Deterrence
		},
		-- Beast mastery
		[1] = {
			[82726] = true, -- Fervor
			[19574] = true, -- Bestial Wrath
			[19577] = true, -- Intimidation
		},
		-- Marksmanship
		[2] = {
			[34490] = true, -- Silencing Shot
			[23989] = true, -- Readiness
		},
		-- Survival
		[3] = {
			[13813] = false, -- Explosive Trap
			[ 3674] = true, -- Black Arrow
		},
	},
}
