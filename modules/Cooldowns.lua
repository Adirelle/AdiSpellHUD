--[[
AdiSpellHUD - Spell overlay customization and spell state HUD.
Copyright 2011 Adirelle (adirelle@tagada-team.net)
All rights reserved.
--]]

local addonName, addon = ...
local mod = addon:NewModule("Cooldowns", "AceEvent-3.0", "LibMovable-1.0")

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
			return name, texture
		end,
		GetCooldown = GetSpellCooldown, 
		GetTexture = function(id) return select(3, GetSpellInfo(id)) end,
		IsMuted = function(id)
			local index = mod.petSpells[id]
			return index and select(2, GetSpellAutocast(index, "pet"))
		end,
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
	self.RegisterEvent(self.name, "SPELLS_CHANGED", self.UpdateEnabledState, self)
	self.RegisterEvent(self.name, "UNIT_INVENTORY_CHANGED", self.UNIT_INVENTORY_CHANGED, self)
	self:UpdateEnabledState("OnInitialize")

	self.unusedOverlays = {}
	self.overlaysInUse = {}
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
	self:Debug('UpdateEnabledState', event)
	local primaryTree = GetPrimaryTalentTree()
	if not primaryTree then
		if event == "OnInitialize" then
			self.RegisterEvent(self.name, "PLAYER_ALIVE", function(event)
				if GetPrimaryTalentTree() then
					self.UnregisterEvent(self.name, "PLAYER_ALIVE")
				 	return self:UpdateEnabledState(event)
				end
			end)
		end
		return
	end
	local _, class = UnitClass("player")
	self:Debug('CheckActivation:', class, primaryTree)

	local cooldownsToWatch = self.cooldownsToWatch
	local spells = wipe(cooldownsToWatch.spells or {})
	local items = wipe(cooldownsToWatch.items or {})
	local petSpells = wipe(self.petSpells)

	if addon.db.profile.modules[self.name] then
		MergeSpells(spells, COOLDOWNS.COMMON)
		if COOLDOWNS[class] then
			MergeSpells(spells, COOLDOWNS[class]['*'])
			MergeSpells(spells, COOLDOWNS[class][primaryTree])
		end
		if HasPetSpells() then
			for index = 1, math.huge do
				local link = GetSpellLink(index, "pet")
				if link then
					if not IsPassiveSpell(index, "pet") then
						self:Debug('Watch for pet spell', link)
						local id = tonumber(strmatch(link, "spell:(%d+)"))
						spells[id] = true
						petSpells[id] = index
					end
				else
					break
				end				
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
	self:Update(true)
end

--------------------------------------------------------------------------------
-- Monitoring and feedback
--------------------------------------------------------------------------------

function mod:Update(silent)
	self:Debug("Update", silent)
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

local function FadeIn_OnPlay(anim)
	mod:Debug('FadeIn_OnPlay', anim)
	anim:GetRegionParent():SetAlpha(0)
end

local function FadeIn_OnFinished(anim)
	mod:Debug('FadeIn_OnFinished', anim)
	anim:GetRegionParent():SetAlpha(1)
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
	overlay:Hide()
	
	overlay:SetScript('OnShow', Overlay_OnShow)

	local texture = overlay:CreateTexture(nil, "OVERLAY")
	texture:SetAllPoints(overlay)
	texture:SetTexCoord(5/64, 59/64, 5/64, 59/64)
	overlay.texture = texture
	
	local animation = overlay:CreateAnimationGroup()
	animation:SetScript('OnFinished', Animation_OnFinished)
	overlay.animation = animation
	
	local fadeIn = animation:CreateAnimation("Alpha")
	fadeIn:SetOrder(1)
	fadeIn:SetDuration(0.5)
	fadeIn:SetChange(1)
	fadeIn:SetScript('OnPlay', FadeIn_OnPlay)
	fadeIn:SetScript('OnFinished', FadeIn_OnFinished)
	fadeIn:SetSmoothing("OUT")
	
	local scaleIn = animation:CreateAnimation("Scale")
	scaleIn:SetOrder(1)
	scaleIn:SetDuration(0.5)
	scaleIn:SetScale(2, 2)
	scaleIn:SetSmoothing("OUT")
	
	local fadeOut = animation:CreateAnimation("Alpha")
	fadeOut:SetOrder(2)
	fadeOut:SetDuration(0.5)
	fadeOut:SetChange(-1)
	fadeOut:SetSmoothing("IN")

	local scaleOut = animation:CreateAnimation("Scale")
	scaleOut:SetOrder(2)
	scaleOut:SetDuration(0.5)
	scaleOut:SetScale(2, 2)
	scaleOut:SetSmoothing("IN")
	
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
			values[id] = format("|T%s:24|t %s", texture, name)
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
