--[[
LibSpellWidget-1.0 - Simple library to display spell widget, with countdown and stacks
(c) 2009 Adirelle (adirelle@tagada-team.net)
All rights reserved.
--]]

local MAJOR, MINOR = 'LibSpellWidget-1.0', 2
local lib, oldMinor = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then return end
oldMinor = oldMinor or 0

lib.refFrame = lib.refFrame or CreateFrame("Frame")
lib.proto = lib.proto or setmetatable({}, {__index = lib.refFrame})
lib.meta = lib.meta or { __index = lib.proto }
lib.pool = lib.pool or {}
lib.inUse = lib.inUse or {}

local proto = lib.proto

function proto:SetSpell(spell)
	if spell ~= self.spell then
		self.spell = spell
		local texture = spell and select(3, GetSpellInfo(spell))
		if texture then
			self.Icon:SetTexture(texture)
			self.Icon:Show()
		else
			self.Icon:Hide()
		end
	end
end

function proto:SetCount(count)
	count = tonumber(count) or 0
	if count ~= self.count then
		self.count = count
		if count >= 10000 then
			self.Count:SetFormattedText("%dk", floor(count/1000))
			self.Count:Show()
		elseif count > 0 then
			self.Count:SetFormattedText("%d", count)
			self.Count:Show()
		else
			self.Count:Hide()
		end
	end
end

function proto:SetTimeleft(duration, expires)
	duration, expires = tonumber(duration) or 0, tonumber(expires) or math.huge
	if duration ~= self.duration or expires ~= self.expires then
		self.duration, self.expires = duration, expires
		local timeLeft = expires - GetTime()
		if duration > 0 and timeLeft > 0 then
			CooldownFrame_SetTimer(self.Cooldown, expires-duration, duration, 1)
			self.Cooldown.timeLeft = timeLeft
			self.Cooldown:Show()
		else
			self.Cooldown:Hide()
		end
	end
end

function proto:Release()
	if self.OnRelease then
		self:OnRelease()
	end
	self.OnRelease = nil
	self.OnCooldownEnd = nil
	self:SetScript('OnEvent', nil)
	self:SetScript('OnUpdate', nil)
	self:SetScript('OnEnter', nil)
	self:SetScript('OnLeave', nil)
	self:SetScript('OnShow', nil)
	self:SetScript('OnHide', nil)
	self:SetAlpha(1.0)
	self:Hide()
	self:SetParent(nil)
	self:ClearAllPoints()
	self:SetSpell()
	self:SetTimeleft()
	self:SetCount()
	lib.inUse[self.owner][self] = nil
	lib.pool[self] = true
end

function lib.Cooldown_OnUpdate(cooldown, elapsed)
	cooldown.timeLeft = cooldown.timeLeft - elapsed
	if cooldown.timeLeft > 0 then return end
	cooldown:Hide()
	if cooldown.widget.OnCooldownEnd then
		cooldown.widget:OnCooldownEnd()
	end
end

function lib:Create()
	local widget = CreateFrame("Frame")
	setmetatable(widget, lib.meta)
	
	local cooldown = CreateFrame("Cooldown", nil, widget)
	cooldown:SetAllPoints()
	cooldown:SetFrameLevel(widget:GetFrameLevel()+1)
	cooldown.widget = widget
	cooldown:SetScript('OnUpdate', lib.Cooldown_OnUpdate)
	widget.Cooldown = cooldown

	local icon = widget:CreateTexture(nil, "OVERLAY")
	icon:SetAllPoints()
	icon:SetTexCoord(5/64, 59/64, 5/64, 59/64)
	widget.Icon = icon
	
	local count = widget:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	count:SetAllPoints(icon)
	count:SetJustifyH("RIGHT")
	count:SetJustifyV("BOTTOM")
	count:SetFont(GameFontNormal:GetFont(), 13, "OUTLINE")
	count:SetShadowColor(0, 0, 0, 0)
	count:SetTextColor(1, 1, 1, 1)
	widget.Count = count

	return widget
end

function lib.Acquire(owner, size, spell, count, duration, expires)
	local widget = next(lib.pool) or lib:Create()
	lib.pool[widget] = nil
	if lib.inUse[owner] then
		lib.inUse[owner][widget] = true
	else
		lib.inUse[owner] = { [widget] = true }
	end
	size = size or 24
	widget:SetSize(size, size)
	widget:SetSpell(spell)
	widget:SetCount(count)
	widget:SetTimeleft(duration, expires)
	widget.owner = owner
	widget:Show()
	return widget
end

function lib.ReleaseAll(owner)
	if lib.inUse[target] then
		for widget in pairs(lib.inUse[target]) do
			widget:Release()
		end
	end
end

lib.embeds = lib.embeds or {}

function lib:Embed(target)
	lib.embeds[target] = true
	lib.inUse[target] = {}
	target.AcquireSpellWidget = lib.Acquire
	target.ReleaseAllSpellWidgets = lib.ReleaseAll
end

function lib:OnEmbedDisable(target)
	lib.ReleaseAll(target)
end

for target in pairs(lib.embeds) do
	lib:Embed(target)
end