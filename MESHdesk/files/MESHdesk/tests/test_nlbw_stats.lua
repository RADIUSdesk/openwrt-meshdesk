#!/usr/bin/lua
-- SPDX-FileCopyrightText: 2025 Dirk van der Walt <dirkvanderwalt@gmail.com>
--
-- SPDX-License-Identifier: GPL-3.0-or-later

--[[--

This test script will test the rdAccel object class's various methods

--]]--

-- Include libraries
package.path = "../libs/?.lua;" .. package.path

function main()
	require('rdNlbwStats');
	local a = rdNlbwStats();
	print("Version is " .. a:getVersion());
	print("Collect Nlbw Stats");
	--a:tableStats();
	print(a:jsonStats());
end

main();
