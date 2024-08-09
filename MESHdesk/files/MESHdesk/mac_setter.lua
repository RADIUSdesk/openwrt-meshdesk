#!/usr/bin/lua

-- SPDX-FileCopyrightText: 2024 Dirk van der Walt <dirkvanderwalt@gmail.com>
--
-- SPDX-License-Identifier: GPL-3.0-or-later



-- Include libraries
package.path = "../libs/?.lua;./libs/?.lua;/etc/MESHdesk/libs/?.lua;" .. package.path


function main()
	require("rdNetwork")
	local n = rdNetwork()
	print("Version is " .. n:getVersion())	
	n:addMacs();
end

main();
