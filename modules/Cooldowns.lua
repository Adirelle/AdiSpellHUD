--[[
AdiSpellHUD - Spell overlay customization and spell state HUD.
Copyright 2011 Adirelle (adirelle@tagada-team.net)
All rights reserved.
--]]

local addonName, addon = ...
local L = addon.L

local COOLDOWNS

local mod = addon:NewModule("Cooldowns", "AceEvent-3.0")

function mod:OnInitialize()
	self.cooldowns = {}
	self.spellsToWatch = {}
	self.RegisterEvent(self.name, "ACTIVE_TALENT_GROUP_CHANGED", self.CheckActivation, self)
	self.RegisterEvent(self.name, "UNIT_INVENTORY_CHANGED", function(event, unit)
		self:Debug(event, unit) 
		if unit == "player" then 
			self:CheckActivation(event)
		end 
	end)
	self:CheckActivation("OnInitialize")
	
	local timer = CreateFrame("Frame")
	timer:Hide()
	timer:SetScript('OnUpdate', function(_, elapsed)
		self.delay = self.delay - elapsed
		if self.delay <= 0 then
			timer:Hide()
			self:Update(false, "OnTimer")
		end
	end)
	self.delay = 0
	self.timer = timer
	
	SpellActivationOverlayFrame.HideOverlays = SpellActivationOverlay_HideOverlays
end

local SPELL_MODEL = {
	GetCooldown = GetSpellCooldown,
	GetTexture = function(id) return select(3, GetSpellInfo(id)) end,
}

local ITEM_MODEL = {
	GetCooldown = GetItemCooldown,
	GetTexture = function(id) return select(10, GetItemInfo(id)) end,
}

local function MergeSpells(dst, src)
	if src then
		for spellID, cond in pairs(src) do
			if not cond then
				dst[spellID] = nil
				mod:Debug('Do not watch for', GetSpellInfo(spellID))
			elseif IsSpellKnown(spellID) then
				mod:Debug('Watch for', (GetSpellInfo(spellID)))
				dst[spellID] = SPELL_MODEL
			end
		end	
	end
end

function mod:CheckActivation(event)
	self:Debug('CheckActivation', event)
	local primaryTree = GetPrimaryTalentTree()
	if not primaryTree then
		if event == "OnInitialize" then
			self.RegisterEvent(self.name, "PLAYER_ALIVE", self.CheckActivation, self)
		end
		return 
	end
	local _, class = UnitClass("player")
	self:Debug('CheckActivation:', class, primaryTree)
	local spells = self.spellsToWatch
	wipe(spells)
	MergeSpells(spells, COOLDOWNS.COMMON)
	if COOLDOWNS[class] then
		MergeSpells(spells, COOLDOWNS[class]['*'])
		MergeSpells(spells, COOLDOWNS[class][primaryTree])
	end
	for index = 1, 18 do
		local id = GetInventoryItemID("player", index)
		if id and GetItemSpell(id) then -- Only return values for items with on-use effects
			self:Debug('Watch for item', (GetItemInfo(id)))
			spells[id] = ITEM_MODEL
		end
	end
	local hasSpell = next(spells) ~= nil
	if event == "OnInitialize" then
		self:SetEnabledState(hasSpell)
	elseif hasSpell and not self:IsEnabled() then
		self:Debug('Enabling')
		self:Enable()
	elseif not hasSpell and self:IsEnabled() then
		self:Debug('Disabling')
		self:Disable()
	end
end

function mod:OnEnable()
	wipe(self.cooldowns)
	self:Update(true, "OnEnable")
	self:RegisterEvent("SPELL_UPDATE_COOLDOWN")
	self:Debug('Enabled')
end

function mod:Update(silent, event)
	self:Debug("Update", event or "OnTimer", silent, self.delay)
	local nextCheck = math.huge
	local now = GetTime()
	for id, model in pairs(self.spellsToWatch) do
		local start, duration = model.GetCooldown(id)
		local timeLeft = max(0, (start and duration and duration > 1.5 and start+duration or 0) - now)
		if timeLeft > 0 then
			nextCheck = min(nextCheck, timeLeft)
			self.cooldowns[id] = timeLeft
		elseif self.cooldowns[id] then
			self.cooldowns[id] = nil
			if not silent then
				self:ShowCooldownReset(id, model.GetTexture(id))
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
	return self:Update(false, "SPELL_UPDATE_COOLDOWN")
end

local AceTimer = LibStub("AceTimer-3.0")
function mod:ShowCooldownReset(id, icon)
	SpellActivationOverlay_ShowOverlay(SpellActivationOverlayFrame, id, icon, "CENTER", 0.5, 255, 255, 255, false, false)
	AceTimer.ScheduleTimer(SpellActivationOverlayFrame, "HideOverlays", 0.5, id)
end

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
