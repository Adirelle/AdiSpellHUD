--[[
AdiSpellHUD - Spell overlay customization and spell state HUD.
Copyright 2011 Adirelle (adirelle@tagada-team.net)
All rights reserved.
--]]

local addonName, addon = ...
local L = addon.L

local handlerProto = {}
local handlerMeta = { __index = handlerProto }

function handlerProto:GetDatabase(info)
	return self.target.db.profile, info.args or info[#info]
end

function handlerProto:Get(info, subKey)
	local db, key = self:GetDatabase(info)
	if info.type == 'multiselect' then
		return db[key][subKey]
	elseif info.type == 'color' then
		return unpack(db[key], 1, info.hasAlpha and 4 or 3)
	else
		return db[key]
	end
end

function handlerProto:Set(info, ...)
	local db, key = self:GetDatabase(info)
	if info.type == 'multiselect' then
		local subKey, value = ...
		db[key][subKey] = value
	elseif info.type == 'color' then
		local r, g, b, a = ...
		local c = db[key]
		if not c then
			db[key] = { r, g, b, info.hasAlpha and a or nil }
		else
			c[1], c[2], c[3], c[4] = r, g, b, info.hasAlpha and a or nil
		end
	else
		db[key] = ...
	end
	addon:SendMessage('AdiProx_ConfigChanged_'..self.target.name, key, ...)
end

local function DecorateOptions(target, options)
	if not options.name then
		options.name =  L[target.moduleName or target.name or tostring(target)]
	end
	options.type = 'group'
	if not options.args then
		options.args = {}
	end
	if target.db then
		options.set = 'Set'
		options.get = 'Get'
		options.handler = setmetatable({ target = target }, handlerMeta)
	end
	if options.args.enabled == nil then
		options.args.enabled = {
			name = L['Enabled'],
			type = 'toggle',
			get = function(info) return addon.db.profile.modules[target.name] end,
			set = function(info, value)
				addon.db.profile.modules[target.name] = value
				target:UpdateEnabledState()
			end,
			disabled = false,
			order = 1,
		}
	end
	return options
end
addon.DecorateOptions = DecorateOptions

local options
function addon.GetOptions()
	if options then return options end
	
	local self = addon

	local profileOpts = LibStub('AceDBOptions-3.0'):GetOptionsTable(self.db)
	LibStub('LibDualSpec-1.0'):EnhanceOptions(profileOpts, self.db)
	profileOpts.order = -1

	options = DecorateOptions(self, {
		name = format("%s v%s", addonName, GetAddOnMetadata(addonName, "Version")),
		args = {
			enabled = false, -- bogus entry to prevent the decorator to add one
			general = {
				name = L['General'],
				type = 'group',
				order = 1,
				args = {
				}
			},
			profiles = profileOpts,
		}
	})
	
	options.args.enabled = nil
	
	for name, module in self:IterateModules() do
		if module.GetOptions then
			local modOptions = DecorateOptions(module, module:GetOptions())
			options.args[name] = modOptions
			module.GetOptions = nil
		end
	end
	
	return options
end

