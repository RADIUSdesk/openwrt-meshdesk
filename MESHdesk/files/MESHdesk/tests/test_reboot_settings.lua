#!/usr/bin/lua
-- SPDX-FileCopyrightText: 2024 Dirk van der Walt <dirkvanderwalt@gmail.com>
--
-- SPDX-License-Identifier: GPL-3.0-or-later

--[[--

This test script will test the rdRebootSettings object class's various methods

--]]--

-- Include libraries
package.path = "../libs/?.lua;" .. package.path

function main()
	require("rdRebootSettings")
	local r = rdRebootSettings()
	print("Version is " .. r:getVersion())
	print("Configure Reboot Settings from JSON file")
	--local f = '/etc/MESHdesk/tests/sample_config_batman_adv.json'
	local f = '/etc/MESHdesk/configs/current.json'
	--r:configureFromJson(f)
	--r:configureFromTable()
	r:clear();
end

main()
