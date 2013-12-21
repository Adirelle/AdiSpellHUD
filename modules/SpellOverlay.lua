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
local GetTime = _G.GetTime
local UnitBuff = _G.UnitBuff
local max = _G.max
local min = _G.min
local pi = _G.math.pi
local setmetatable = _G.setmetatable
local sin = _G.sin
local tDeleteItem = _G.tDeleteItem
local tinsert = _G.tinsert

local addonName, addon = ...
local L = addon.L

local mod = addon:NewModule("SpellOverlay", "LibMovable-1.0")

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
end

function mod:OnEnable()
	if not self.Orig_SpellActivationOverlay_CreateOverlay then
		self.Orig_SpellActivationOverlay_CreateOverlay = _G.SpellActivationOverlay_CreateOverlay
		_G.SpellActivationOverlay_CreateOverlay = function(...)
			if self:IsEnabled() then
				self:Debug('SpellActivationOverlay_CreateOverlay', ...)
				return self:SpellActivationOverlay_CreateOverlay(...)
			else
				return self.Orig_SpellActivationOverlay_CreateOverlay(...)
			end
		end
		self:Debug('Hooked')
	end
end

function mod:OnDisable()
	self:UnregisterAllEvents()
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

local NOOP = function() end

local overlayProto = setmetatable({}, { __index = CreateFrame("Frame") })
local overlayMeta = { __index = overlayProto }

overlayProto.Debug = addon.Debug

local serial = 0
function mod:SpellActivationOverlay_CreateOverlay(parent)
	local overlay = setmetatable(CreateFrame("Frame", self.name.."SpellOverlay"..serial, parent), overlayMeta)
	serial = serial + 1
	overlay:Initialize()
	return overlay
end

function overlayProto:Initialize()
	self:Hide()

	self:SetScript('OnShow', self.OnShow)
	self:SetScript('OnHide', self.OnHide)
	self:SetScript('OnEvent', self.OnEvent)
	self:SetScript('OnUpdate', self.OnUpdate)
	self:RegisterUnitEvent('UNIT_AURA', "player")

	self.expires, self.duration, self.count = 0, 0, 0

	local texture = self:CreateTexture(nil, "ARTWORK")
	self.texture = texture

	local text = self:CreateFontString(nil, "OVERLAY")
	text:SetFont([[Fonts\FRIZQT__.TTF]], 24, "THICKOUTLINE")
	text:SetAllPoints(self)
	text:SetJustifyH("CENTER")
	text:SetJustifyV("MIDDLE")
	text:Hide()
	self.text = text

	-- Fake the animations of SpellActivationOverlayTemplate.
	-- They will be used by Blizzard legacy code.
	self.animIn = {
		Play = function() self:SetAnimation("in") end,
		Stop = function() self:SetAnimation(nil) end,
		Pause = NOOP,
	}
	self.pulse = {
		Play = function() self:SetAnimation("pulse") end,
		Stop = self.animIn.Stop,
		Pause = NOOP,
	}
	self.animOut = {
		Play = function() self:SetAnimation("out") end,
		Stop = self.animIn.Stop,
		Pause = NOOP,
	}
end

function overlayProto:Update()
	if mod:IsEnabled() then
		for index = 1, 128 do
			local name, _, _, count, _, duration, expires, _, _, _, spellID = UnitBuff("player", index)
			if name then
				if spellID == self.spellID then
					self:SetAuraInfo(duration, expires, count)
					return
				end
			else
				break
			end
		end
	end
	self:SetAuraInfo(0, 0, 0)
end
overlayProto.UNIT_AURA = overlayProto.Update

function overlayProto:SetAuraInfo(duration, expires, count)
	duration, expires, count = duration or 0, expires or 0, count or 0
	if self.duration == duration and self.expires == expires and self.count == count then return end
	self.textTimer, self.duration, self.expires, self.count = 0, duration, expires, count
	if duration > 0 then
		self.text:Show()
	else
		self.text:Hide()
	end
end

function overlayProto:SetTextureScale(scale)
	if self.textureScale == scale then return end
	self.textureScale = scale
	local w, h = self:GetSize()
	self.texture:SetSize(scale * w, scale * h)
end

local animations = {
	["in"] = {
		duration = 0.3,
		Update = function(self, progress)
			self:SetAlpha(progress)
			self:SetTextureScale(0.5 + progress / 2)
		end,
		Finished = function(self)
			self:SetAnimation("pulse")
		end,
	},
	["pulse"] = {
		duration = 0.5,
		Update = function(self, progress)
			self:SetTextureScale(1 + 0.05 * sin(progress * 2 * pi))
		end,
		Finished = function(self)
			self:SetAnimation("pulse")
		end,
	},
	["out"] = {
		duration = 0.3,
		Update = function(self, progress)
			self:SetAlpha(1 - progress)
			self:SetTextureScale(1 + progress)
		end,
		Finished = function(self)
			return self:Hide()
		end,
	}
}

function overlayProto:SetAnimation(animName)
	if self.animName == animName then return end
	self:SetAlpha(1)
	self:SetTextureScale(1)
	self.animName, self.animation, self.timer = animName, animName and animations[animName], 0
end

function overlayProto:OnEvent(event, ...)
	if self:IsVisible() and mod:IsEnabled() then
		return self[event](self, event, ...)
	end
end

function overlayProto:OnShow()
	self:Debug('OnShow')
	local point = self:GetPoint()
	self.texture:ClearAllPoints()
	self.texture:SetPoint(point, self, point, 0, 0)
	self:SetAnimation("in")
	self:Update()
end

function overlayProto:OnHide()
	self:Debug('OnHide')
	self:SetAnimation(nil)
	tDeleteItem(frame.overlaysInUse[self.spellID], self)
	tinsert(frame.unusedOverlays, self);
end

function overlayProto:OnUpdate(elapsed)
	local anim = self.animation
	if anim then
		self.timer = self.timer + elapsed
		local progress = self.timer / anim.duration
		if progress >= 1 then
			self:SetAnimation(nil)
			anim.Finished(self)
		else
			anim.Update(self, progress)
		end
	end

	if self.text:IsVisible() and self.expires > 0 then
		self.textTimer = self.textTimer - elapsed
		if self.textTimer < 0 then
			local timeleft = self.expires - GetTime()
			if timeleft <= 3 then
				self.text:SetFormattedText("%3.1f", timeleft)
				self.textTimer = timeleft % 0.1
			else
				self.text:SetFormattedText("%d", timeleft)
				self.textTimer = timeleft % 1
			end
			local f = timeleft / self.duration
			self.text:SetTextColor(1, min(2*f, 1), max(2*f-1, 0))
		end
	end
end
