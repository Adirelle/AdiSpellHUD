--[[
AdiSpellHUD - Spell overlay customization and spell state HUD.
Copyright 2011 Adirelle (adirelle@tagada-team.net)
All rights reserved.
--]]

local addonName, addon = ...
local L = addon.L

local COOLDOWNS

local mod = addon:NewModule("Cooldonws", "AceEvent-3.0", "AceTimer-3.0")

function mod:OnInitialize()
	self.cooldowns = {}
	self.spellsToWatch = {}
	self:SetEnabledState(false)
	self.RegisterEvent(self.name, "ACTIVE_TALENT_GROUP_CHANGED", self.CheckActivation, self)
end

function mod:CheckActivation()
	local primaryTree = GetPrimaryTalentTree()
	if not primaryTree then return end
	local _, class = UnitClass("player")
	local spells = self.spellsToWatch
	wipe(spells)
	if COOLDOWNS[class] then
		if COOLDOWNS[class]['*'] then
			for spellID, cond in pairs(COOLDOWNS[class]['*']) do
				if IsSpellKnown(spellID) then
					spells[spellID] = cond
				end
			end
		end
		if COOLDOWNS[class][primaryTree] then
			for spellID, cond in pairs(COOLDOWNS[class][primaryTree]) do
				if IsSpellKnown(spellID) then
					spells[spellID] = cond
				end
			end
		end
	end
	local hasSpell = next(spells) ~= nil
	if hasSpell and not self:IsEnabled() then
		self:Enable()
	elseif not hasSpell and self:IsEnabled() then
		self:Disable()
	end
end

function mod:OnEnable()
	wipe(self.cooldowns)
	self.timer = nil
	self:Update(true)
	self:RegisterEvent("SPELL_UPDATE_COOLDOWN")
end

function mod:Update(silent)
	if self.timer then
		self:CancelTimer(self.timer, true)
		self.timer = nil
	end
	local nextCheck = 0
	local now = GetTime()
	for spellID, condition in pairs(self.spellsToWatch) do
		local start, duration = 0, 0
		if type(condition) ~= "function" or condition(spellID) then
			start, duration = GetSpellCooldown(spellID)
		end
		local timeLeft = max(0, (start and duration and start+duration or 0) - now)
		if timeLeft > 0 then
			nextCheck = max(nextCheck, timeLeft)
			self.cooldowns[spellID] = timeLeft
		elseif self.cooldowns[spellID] then
			self.cooldowns[spellID] = nil
			if not silent then
				print(GetSpellInfo(spellID), "has reset !")
			end
		end
	end
	if nextCheck > 0 then
		self.timer = self:ScheduleTimer("Update", nextCheck+0.1)
	end
end

function mod:SPELL_UPDATE_COOLDOWN()
	return self:Update()
end

COOLDOWNS = {
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
		},
	},
	HUNTER = {
		['*'] = {
		},
		-- Beast mastery
		[1] = {
		},
		-- Marksmanship
		[2] = {
		},
		-- Survival
		[3] = {
		},
	},
}
