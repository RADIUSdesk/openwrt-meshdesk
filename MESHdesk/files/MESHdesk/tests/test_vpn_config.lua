#!/usr/bin/lua
-- SPDX-FileCopyrightText: 2025 Dirk van der Walt <dirkvanderwalt@gmail.com>
--
-- SPDX-License-Identifier: GPL-3.0-or-later

--[[--

This test script will test the rdVpn object class's various methods

--]]--

-- Include libraries
package.path = "../libs/?.lua;" .. package.path

function main()
	require('rdVpn');
	local v = rdVpn();
	print("Version is " .. v:getVersion());
	print("Configure VPN from JSON file");
	local f = '/etc/MESHdesk/tests/sample_config_vpn.json';
	v:configureFromJson(f);
	--v:configureFromTable();
end

main();
