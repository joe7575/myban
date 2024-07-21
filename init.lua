--[[
    MyBan - Simple ban/nonew solution for a IPv6 Server.
    Copyright (C) 2024  Joachim Stolberg

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU Affero General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU Affero General Public License for more details.

    You should have received a copy of the GNU Affero General Public License
    along with this program.  If not, see <https://www.gnu.org/licenses/>.
]]--

-- Load support for I18n.
local S = minetest.get_translator("myban")
-- Stores the list with banned players
local storage = minetest.get_mod_storage()
local BanList = minetest.deserialize(storage:get_string("BanList")) or {}
local NoNewState = storage:contains("NoNewState") and storage:get_string("NoNewState") or "off"
local NewPlayerList = minetest.deserialize(storage:get_string("NewPlayerList")) or {}

--local DAY_BAN_TIME  = 60*60*24     -- 1 day
local DAY_BAN_TIME  = 60    -- 1 day
local YEAR_BAN_TIME = 60*60*24*365 -- 1 year

local function remove_expired_entries()
	local list = {}
	for _, item in ipairs(BanList) do
		if item.expires and item.expires > minetest.get_gametime() then
			table.insert(list, item)
		end
	end
	BanList = list
	storage:set_string("BanList", minetest.serialize(BanList))
	storage:set_string("NewPlayerList", minetest.serialize(NewPlayerList))

	-- run every hour
	minetest.after(3600, remove_expired_entries)
end

minetest.after(100, remove_expired_entries)

local function player_list()
	local list = {}
	for name, _ in pairs(NewPlayerList) do
		table.insert(list, name)
	end
	return table.concat(list, ", ")
end

local function player_banned(name)
	for _, item in ipairs(BanList) do
		if item.name and item.expires then
			if item.name == name and item.expires > minetest.get_gametime() then
				return true
			end
		end
	end
end

local function ban_player(name, one_day)
	for _, item in ipairs(BanList) do
		if item.name and item.expires then
			if item.name == name and item.expires > minetest.get_gametime() then
				return
			end
		end
	end
	local expires = minetest.get_gametime() + (one_day and DAY_BAN_TIME or YEAR_BAN_TIME)
	table.insert(BanList, {name = name, expires = expires})	
	storage:set_string("BanList", minetest.serialize(BanList))
	return true
end

local function unban_player(name)
	for _, item in ipairs(BanList) do
		if item.name and item.name == name then
			item.expires = 0
			storage:set_string("BanList", minetest.serialize(BanList))
			return true
		end
	end
end

local function get_player_list()
	local list = {}
	for _, item in ipairs(BanList) do
		if item.expires > minetest.get_gametime() then
			table.insert(list, item.name)
		end
	end
	return table.concat(list, ", ")
end

local function on_ban_player(name, params, tempban)
	local plname, reason = params:match("(%S+)%s+(.+)")
	plname = plname or params:match("(%S+)")
	if not plname then
		return true, S("Ban list: @1", get_player_list())
	end
	if plname then
		if minetest.is_singleplayer() then
			return false, S("You cannot ban players in singleplayer!")
		end
		if not ban_player(plname, tempban) then
			return false, S("Failed to ban player.")
		end

		local reason = reason or S("No reason given.")
		minetest.log("action", "[myban] " .. name .. " bans " .. plname .. " with reason: " .. reason .. ".")
		minetest.kick_player(plname, reason)
		return true, S("Banned @1.", plname)
	end
	if tempban then
		return false, S("Syntax: /tempban <name> [<reason>]")
	else
		return false, S("Syntax: /ban <name> [<reason>]")
	end
end

minetest.register_chatcommand("ban", {
	params = S("[<name>] [<reason>]"),
	description = S("Ban a player by name or show the ban list"),
	privs = {superminer = true},
	func = function(name, params)
		return on_ban_player(name, params, false)
	end,
})

minetest.register_chatcommand("tempban", {
	params = S("<name> [<reason>]"),
	description = S("Ban a player by name for one day"),
	privs = {superminer = true},
	func = function(name, params)
		return on_ban_player(name, params, true)
	end,
})

minetest.register_chatcommand("unban", {
	params = S("<name>"),
	description = S("Remove player from ban list"),
	privs = {superminer = true},
	func = function(name, param)
		if not unban_player(param) then
			return false, S("Failed to unban player.")
		end
		minetest.log("action", "[myban] " .. name .. " unbans " .. param)
		return true, S("Unbanned @1.", param)
	end,
})

minetest.register_chatcommand("nonew", {
	params = S("[<state>]"),
	description = S("Set (on/off) or show the nonew state"),
	privs = {superminer = true},
	func = function(name, param)
		if param == "on" then
			NoNewState = "on"
			storage:set_string("NoNewState", NoNewState)
			minetest.log("action", "[myban] " .. name .. " sets nonew to " .. NoNewState)
			return true, S("Nonew state: @1", NoNewState)
		elseif param == "off" then
			NoNewState = "off"
			storage:set_string("NoNewState", NoNewState)
			minetest.log("action", "[myban] " .. name .. " sets nonew to " .. NoNewState)
			return true, S("Nonew state: @1", NoNewState)
		else
			return true, S("Nonew state: @1", NoNewState)
		end
	end,
})

minetest.register_on_prejoinplayer(function(name, ip)
	if player_banned(name) then
		return ("You are banned!")
	end
	if NoNewState == "on" and not NewPlayerList[name] then
		if not minetest.player_exists(name) then
			return ("New registration only via email to: iauit@gmx.de")
		end
	end
	NewPlayerList[name] = nil
end)


minetest.register_on_joinplayer(function(ObjectRef, last_login)
	local name = ObjectRef:get_player_name()
	if name and name ~= "" then
		if last_login == nil then  -- New player?
			local info = minetest.get_player_information(name)
			local s = string.format("%25s: avg_rtt=%.3f, lang_code=%s, formspec=%u protocol=%u",
				name, info.avg_rtt, info.lang_code, info.formspec_version, info.protocol_version)
			minetest.log("warning", "[myban] " .. s)
		end

		if minetest.check_player_privs(name, "superminer") then
			if NoNewState == "on" then
				minetest.chat_send_player(name, string.char(0x1b) .. "(c@#ff0000)" .. 
					"Info: 'nonew' is still active. You can deactivate 'nonew' with the command: /nonew off")
			end
		end
	end
end)

minetest.register_chatcommand("getinfo", {
	params = S("<name> "),
	description = S("Output player information"),
	privs = {superminer = true},
	func = function(name, params)
		local info = minetest.get_player_information(params)
		if info then
			local s = string.format("lag: %.3f s, lang_code: %2s, formspec: v%u, protocol: v%u",
				info.avg_rtt, info.lang_code, info.formspec_version, info.protocol_version)
			return true, "Info: " .. s
		end
		return false, "No valid player name"
	end,
})

minetest.register_chatcommand("newplayer", {
	params = S("<name> "),
	description = S("Add the name to the list of new players"),
	privs = {superminer = true},
	func = function(name, params)
		if params and params ~= "" then
			NewPlayerList[params] = true
			storage:set_string("NewPlayerList", minetest.serialize(NewPlayerList))
			return true, params .. " added"
		end
		return false, "No valid player name"
	end,
})

minetest.register_chatcommand("newplayerlist", {
	params = S("<name> "),
	description = S("Output the list of new players"),
	privs = {superminer = true},
	func = function(name, params)
		return true, player_list()
	end,
})
