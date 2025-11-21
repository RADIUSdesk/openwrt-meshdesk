#!/usr/bin/lua
-- SPDX-FileCopyrightText: 2025 Dirk van der Walt <dirkvanderwalt@gmail.com>
--
-- SPDX-License-Identifier: GPL-3.0-or-later

--[[--

This test script will test the rdOvpnStats. It will need existing configured Wireguard interfaces

--]]--

-- Include libraries
package.path = "../libs/?.lua;" .. package.path

function main()
	require('rdOvpnStats');
	local a = rdOvpnStats();
	print("Version is " .. a:getVersion());
	print("Collect OpenVPN Stats");
	--a:tableStats();
	print(a:jsonStats());
end

main();
