--[[
AdiSpellHUD - Spell overlay customization and spell state HUD.
Copyright 2011 Adirelle (adirelle@tagada-team.net)
All rights reserved.
--]]

local _G = _G
local CreateFrame = _G.CreateFrame
local pairs, wipe, min, max, next = _G.pairs, _G.wipe, _G.min, _G.max, _G.next
local tinsert, tDeleteItem = _G.tinsert, _G.tDeleteItem
local UnitBuff, GetTime = _G.UnitBuff, _G.GetTime
local huge, sin, pi = _G.math.huge, _G.math.sin, _G.math.pi

local addonName, addon = ...
local L = addon.L

local mod = addon:NewModule("SpellOverlay", "AceEvent-3.0", "AceHook-3.0", "LibMovable-1.0")

local frame = _G.SpellActivationOverlayFrame

local DEFAULT_SETTINGS = {
	profile = {
		anchor = {}
	}
}

function mod:OnInitialize()
	local t = DEFAULT_SETTINGS.profile.anchor
	t.scale, t.pointFrom, t.refFrame, t.pointTo, t.xOffset, t.yOffset = frame:GetScale(), frame:GetPoint()
	
	self.db = addon.db:RegisterNamespace(self.name, DEFAULT_SETTINGS)

	self:RegisterMovable(frame, function() return self.db.profile.anchor end, addon.L["Blizzard Spell Overlay"], function(target)
		local anchor = CreateFrame("Frame", nil, target)
		anchor:SetPoint("CENTER")
		anchor:SetSize(460, 460)
		return anchor
	end)
	self:SetMovable(frame, false)
	frame:SetClampedToScreen(true)
	
	self.throttle = 0
	self.num = 0
end

function mod:OnEnable()
	self:RawHook('SpellActivationOverlay_CreateOverlay', true)
	self:RegisterEvent('UNIT_AURA')
	
	self:UpdateOverlaysInUse()
end

--@debug@
function _G.sotest()
	_G.SpellActivationOverlay_OnEvent(frame, "SPELL_ACTIVATION_OVERLAY_SHOW",
		16870, -- spellID
		"Textures\\SpellActivationOverlays\\Natures_Grace.BLP", -- texture
		"Left + Right (Flipped)", -- positions
		1, -- scale,
		255, 255, 255 -- r, g, b
	)
	_G.LibStub('AceTimer-3.0').ScheduleTimer(mod, function()
		_G.SpellActivationOverlay_OnEvent(frame, "SPELL_ACTIVATION_OVERLAY_HIDE", 16870)
	end, 8)
end
--@end-debug@

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

local function CreateAnimation(group, type, order, duration, smoothing, arg1, arg2)
	local anim = group:CreateAnimation(type)
	anim:SetOrder(order)
	anim:SetDuration(duration)
	anim:SetSmoothing(smoothing or "NONE")
	if type == "Scale" and arg1 and arg2 then
		anim:SetScale(arg1, arg2)
	elseif type == "Alpha" and arg1 then
		anim:SetChange(arg1)
	end
	return anim
end

local NOOP = function() end
local fakePulse = { Play = NOOP, Pause = NOOP, Stop = NOOP }

local i = 0
function mod:SpellActivationOverlay_CreateOverlay(parent)
	local overlay = CreateFrame("Frame", nil, parent)
	overlay:Hide()

	overlay:SetScript('OnShow', mod.Overlay_OnShow)
	overlay:SetScript('OnHide', mod.Overlay_OnHide)

	local texture = overlay:CreateTexture(nil, "ARTWORK")
	overlay.texture = texture

	local text = overlay:CreateFontString(nil, "OVERLAY")
	text:SetFont([[Fonts\FRIZQT__.TTF]], 24, "THICKOUTLINE")
	text:SetAllPoints(overlay)
	text:SetJustifyH("CENTER")
	text:SetJustifyV("MIDDLE")
	text:Hide()
	overlay.text = text
	
	overlay.pulse = fakePulse
	overlay.animIn = { overlay = overlay, Play = mod.AnimIn_Play }
	overlay.animOut = { overlay = overlay, Play = mod.AnimOut_Play, Stop = NOOP }

	return overlay
end

function mod:UNIT_AURA(_, unit)
	if unit == "player" then
		self:UpdateOverlaysInUse()
	end
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

function mod:UpdateOverlay(overlay, duration, expires, count)
	if duration and duration > 0 then
		overlay.time = expires - GetTime()
		overlay.duration = duration
		overlay.text:Show()
	else
		overlay.text:Hide()
	end
end

function mod.OnUpdate(_, elapsed)
	elapsed = elapsed + mod.throttle
	local num = mod.num + 1
	if elapsed < 0.1 and num < 2 then
		mod.throttle, mod.num = elapsed, num
		return
	end
	mod.throttle, mod.num = 0, 0
	if not next(frame.overlaysInUse) then
		frame:SetScript('OnUpdate', nil)
	else
		for spell, overlays in pairs(frame.overlaysInUse) do	
			for _, overlay in pairs(overlays) do
				mod.Overlay_OnUpdate(overlay, elapsed)
			end
		end
	end
end

function mod.Overlay_OnUpdate(overlay, time)
	time = time + overlay.time
	overlay.time = time
	
	local alpha, scale = 1, 1
	if overlay.phase == 1 then
		alpha = min(time / 0.3, 1)
		if alpha < 1 then
			scale = 0.5 + 0.5 * alpha 
		else
			overlay.phase = 2
		end
	elseif overlay.phase == 2 then
		scale = 1 + 0.05 * sin(time * 2 * pi)
	elseif overlay.phase == 3 then		
		alpha = max(1 - time / 0.3, 0)
		if alpha > 0 then
			scale = 2 - alpha
		else
			overlay:Hide()
			return
		end
	end
	overlay:SetAlpha(alpha)
	local w, h = overlay:GetSize()
	overlay.texture:SetSize(scale * w, scale * h)
	
	local text = overlay.text
	if text:IsVisible() then
		local timeleft = overlay.duration - time
		if timeleft <= 3 then
			text:SetFormattedText("%3.1f", timeleft)
		else
			text:SetFormattedText("%d", timeleft)
		end
		local f = timeleft / overlay.duration
		text:SetTextColor(1, min(2*f, 1), max(2*f-1, 0))
	end
end

function mod.Overlay_OnShow(overlay)
	mod:Debug('Overlay_OnShow', overlay)
	frame:SetScript('OnUpdate', mod.OnUpdate)
	local point = overlay:GetPoint()
	overlay.texture:ClearAllPoints()
	overlay.texture:SetPoint(point, overlay, point, 0, 0)
	overlay.animIn:Play()
	mod.Overlay_OnUpdate(overlay, 0)
end

function mod.Overlay_OnHide(overlay)
	mod:Debug('Overlay_OnHide', overlay)	
	tDeleteItem(frame.overlaysInUse[overlay.spellID], overlay)
	tinsert(frame.unusedOverlays, overlay);	
end

function mod.AnimIn_Play(anim)
	mod:Debug('AnimIn_Play', anim)
	local overlay = anim.overlay
	overlay.phase = 1
	overlay.time = 0
end

function mod.AnimOut_Play(anim)
	mod:Debug('AnimOut_Play', anim)
	local overlay = anim.overlay
	overlay.text:Hide()
	overlay.phase = 3
	overlay.time = 0
end

