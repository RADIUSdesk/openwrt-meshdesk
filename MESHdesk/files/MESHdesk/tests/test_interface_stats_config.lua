#!/usr/bin/lua
-- SPDX-FileCopyrightText: 2025 Dirk van der Walt <dirkvanderwalt@gmail.com>
--
-- SPDX-License-Identifier: GPL-3.0-or-later

--[[--

This test script will test the rdInterfaceStats object class's various methods

--]]--

-- Include libraries
package.path = "../libs/?.lua;" .. package.path

function main()
	require('rdInterfaceStats');
	local a = rdInterfaceStats();
	print("Version is " .. a:getVersion());
	print("Configure Interface Stats from JSON file");
	local f = '/etc/MESHdesk/tests/sample_config_stats.json';
	a:configureFromJson(f);
	--w:configureFromTable()
end

main();
