#!/usr/bin/lua
-- SPDX-FileCopyrightText: 2026 Dirk van der Walt <dirkvanderwalt@gmail.com>
--
-- SPDX-License-Identifier: GPL-3.0-or-later

--[[--

This test script will test the rdIpsecStats. It will need existing configured StrongSwan with xfrm interfaces

--]]--

-- Include libraries
package.path = "../libs/?.lua;" .. package.path

function main()
	require('rdIpsecStats');
	local a = rdIpsecStats();
	print("Version is " .. a:getVersion());
	print("Collect IpsecVPN Stats");
	--a:tableStats();
	print(a:jsonStats());
end

main();
