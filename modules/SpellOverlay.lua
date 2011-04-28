--[[
AdiSpellHUD - Spell overlay customization and spell state HUD.
Copyright 2011 Adirelle (adirelle@tagada-team.net)
All rights reserved.
--]]

local _G = _G
local CreateFrame = _G.CreateFrame
local pairs, wipe, min, max = _G.pairs, _G.wipe, _G.min, _G.max
local UnitBuff, GetTime = _G.UnitBuff, _G.GetTime
local huge = _G.math.huge
local SpellActivationOverlay = _G.SpellActivationOverlayFrame

local addonName, addon = ...
local L = addon.L

local mod = addon:NewModule("SpellOverlay", "AceEvent-3.0", "AceHook-3.0", "LibMovable-1.0")

local frame = SpellActivationOverlayFrame

local DEFAULT_SETTINGS = {
	profile = {
		anchor = {}
	}
}

function mod:OnInitialize()
	local t = DEFAULT_SETTINGS.profile.anchor
	t.scale, t.pointFrom, t.refFrame, t.pointTo, t.xOffset, t.yOffset = frame:GetScale(), frame:GetPoint()
	
	self.db = addon.db:RegisterNamespace(self.name, DEFAULT_SETTINGS)
	
	self.enhancedOverlays = {}

	self:RegisterMovable(frame, function() return self.db.profile.anchor end, addon.L["Blizzard Spell Overlay"], function(target)
		local anchor = CreateFrame("Frame", nil, target)
		anchor:SetPoint("CENTER")
		anchor:SetSize(460, 460)
		return anchor
	end)
	self:SetMovable(frame, false)
	frame:SetClampedToScreen(true)
end

function mod:OnEnable()
	for i, overlay in pairs(frame.unusedOverlays) do
		self:EnhanceOverlay(overlay)
	end
	for spell, overlays in pairs(frame.overlaysInUse) do
		for i, overlay in pairs(overlays) do
			self:EnhanceOverlay(overlay)
		end
	end
	self:RawHook('SpellActivationOverlay_CreateOverlay', true)
	self:RegisterEvent('UNIT_AURA')
	
	self:UpdateOverlaysInUse()
end

function mod:GetOptions()
	return {
		args = {
			unlock = {
				name = function()
					return self:AreMovablesLocked() and L["Unlock"] or L["Lock"]
				end,
				type = 'execute',
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

function mod:SpellActivationOverlay_CreateOverlay(...)
	local overlay = self.hooks.SpellActivationOverlay_CreateOverlay(...)
	overlay:Hide()
	self:EnhanceOverlay(overlay)
	if overlay.animIn:IsPlaying() then
		overlay.animIn:Stop()
		overlay.animIn:Play()
	end
	return overlay
end

function mod:UNIT_AURA(_, unit)
	if unit == "player" then
		self:UpdateOverlaysInUse()
	end
end

function mod:EnhanceOverlay(overlay)
	if self.enhancedOverlays[overlay] then return end
	self.enhancedOverlays[overlay] = true

	overlay:HookScript('OnHide', mod.Overlay_OnHide)
	overlay:HookScript('OnShow', mod.Overlay_OnShow)

	local text = overlay:CreateFontString(nil, "OVERLAY")
	text:SetFont([[Fonts\FRIZQT__.TTF]], 24, "THICKOUTLINE")
	text:SetAllPoints(overlay)
	text:SetJustifyH("CENTER")
	text:SetJustifyV("MIDDLE")
	text:Hide()
	overlay.text = text

	overlay.animIn:GetAnimations():SetDuration(0.3)
	local anim = overlay.animIn:CreateAnimation("Scale")
	anim:SetDuration(0.3)
	anim:SetScale(2, 2)
	anim:SetScript('OnPlay', mod.ScaleIn_OnPlay)
	anim:SetScript('OnFinished', mod.ScaleIn_OnFinishied)

	overlay.animOut:GetAnimations():SetDuration(0.3)
	anim = overlay.animOut:CreateAnimation("Scale")
	anim:SetDuration(0.3)
	anim:SetScale(2, 2)
	anim:SetScript('OnPlay', mod.ScaleOut_OnPlay)
	anim:SetScript('OnFinished', mod.ScaleOut_OnFinished)
end

local seen = {}
function mod:UpdateOverlaysInUse()
	local overlays = frame.overlaysInUse
	wipe(seen)
	for index = 1, huge do
		local name, _, _, count, _, duration, expires, _, _, _, spellID = UnitBuff("player", index)
		if not name then break end
		if spellID then
			seen[spellID] = true
			local overlays = frame.overlaysInUse[spellID]
			if overlays then
				for i, overlay in pairs(overlays) do
					self:UpdateOverlay(overlay, duration, expires, count)
				end
			end
		end
	end
	for spellID, overlays in pairs(frame.overlaysInUse) do
		if not seen[spellID]then
			for i, overlay in pairs(overlays) do
				self:UpdateOverlay(overlay)
			end
		end
	end
end

function mod.Overlay_OnShow(overlay)
	overlay.pulse:Stop()
	overlay.animIn:Stop()
	overlay:SetScale(0.5)
	overlay.animIn:Play()
end

function mod.Overlay_OnHide(overlay)
	overlay:SetScript('OnUpdate', nil)
	overlay.text:Hide()
end

function mod:UpdateOverlay(overlay, duration, expires, count)
	if duration and duration > 0 then
		overlay:SetScript('OnUpdate', mod.Overlay_OnUpdate)
		overlay.timeleft = expires - GetTime()
		overlay.duration = duration
		overlay.delay = 0
		mod.Overlay_OnUpdate(overlay, 0)
		overlay.text:Show()
	else
		mod.Overlay_OnHide(overlay)
	end
end

function mod.Overlay_OnUpdate(overlay, elapsed)
	overlay.delay = overlay.delay - elapsed
	overlay.timeleft = overlay.timeleft - elapsed
	if overlay.delay > 0 then
		return
	end
	if overlay.timeleft <= 0 then
		mod.Overlay_OnHide(overlay)
	elseif overlay.timeleft <= 3 then
		overlay.delay = overlay.timeleft % 0.1 + 0.01
		overlay.text:SetFormattedText("%3.1f", overlay.timeleft)
	else
		overlay.delay = overlay.timeleft % 1 + 0.01
		overlay.text:SetFormattedText("%d", overlay.timeleft)
	end
	local f = overlay.timeleft / overlay.duration
	overlay.text:SetTextColor(1, min(2*f, 1), max(2*f-1, 0))
end

function mod.ScaleIn_OnPlay(anim)
	local overlay = anim:GetRegionParent()
	local point, relativeTo, relativePoint, xOffset, yOffset = overlay:GetPoint()
	if point then
		overlay:SetPoint(point, relativeTo, relativePoint, (xOffset or 0) * 2 , (yOffset or 0) * 2)
		anim:SetOrigin(point, 0, 0)
	end
end

function mod.ScaleIn_OnFinishied(anim)
	local overlay = anim:GetRegionParent()
	local point, relativeTo, relativePoint, xOffset, yOffset = overlay:GetPoint()
	if point then
		overlay:SetPoint(point, relativeTo, relativePoint, (xOffset or 0) / 2, (yOffset or 0) / 2)
	end
	overlay:SetScale(1)
end

function mod.ScaleOut_OnPlay(anim)
	local overlay = anim:GetRegionParent()
	overlay.pulse:Stop()
	overlay:SetScale(1)
	local point = overlay:GetPoint()
	if point then
		anim:SetOrigin(point, 0, 0)
	end
end

function mod.ScaleOut_OnFinished(anim)
end
