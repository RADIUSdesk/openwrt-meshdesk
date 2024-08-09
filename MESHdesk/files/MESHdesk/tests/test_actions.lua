#!/usr/bin/lua
-- SPDX-FileCopyrightText: 2024 Dirk van der Walt <dirkvanderwalt@gmail.com>
--
-- SPDX-License-Identifier: GPL-3.0-or-later

--[[--

This test script will test the rdActions object's methods

--]]--

-- Include libraries
package.path = "../libs/?.lua;" .. package.path

function main()
	require("rdActions")
	local a = rdActions()
	print("Version is " .. a:getVersion())	
	a:check()
end

main()
