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
	if COOLDOWNS[class] then
		if COOLDOWNS[class]['*'] then
			for spellID, cond in pairs(COOLDOWNS[class]['*']) do
				if IsSpellKnown(spellID) then
					self:Debug('Watching for', (GetSpellInfo(spellID)))
					spells[spellID] = cond
				end
			end
		end
		if COOLDOWNS[class][primaryTree] then
			for spellID, cond in pairs(COOLDOWNS[class][primaryTree]) do
				if not cond then
					spells[spellID] = nil
					self:Debug('Do not watch for', GetSpellInfo(spellID), 'anymore')
				elseif IsSpellKnown(spellID) then
					self:Debug('Watching for', (GetSpellInfo(spellID)))
					spells[spellID] = cond
				end
			end
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
	for spellID, condition in pairs(self.spellsToWatch) do
		local start, duration = GetSpellCooldown(spellID)
		local timeLeft = max(0, (start and duration and duration > 1.5 and start+duration or 0) - now)
		if timeLeft > 0 then
			nextCheck = min(nextCheck, timeLeft)
			self.cooldowns[spellID] = timeLeft
		elseif self.cooldowns[spellID] then
			self.cooldowns[spellID] = nil
			if not silent then
				self:ShowCooldownReset(spellID)
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
function mod:ShowCooldownReset(spellID)
	local _, _, icon = GetSpellInfo(spellID)
	SpellActivationOverlay_ShowOverlay(SpellActivationOverlayFrame, spellID, icon, "CENTER", 0.5, 255, 255, 255, false, false)
	AceTimer.ScheduleTimer(SpellActivationOverlayFrame, "HideOverlays", 0.5, spellID)
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
		},
		-- Marksmanship
		[2] = {
		},
		-- Survival
		[3] = {
			[13813] = false, -- Explosive Trap
			[ 3674] = true, -- Black Arrow			
		},
	},
}
