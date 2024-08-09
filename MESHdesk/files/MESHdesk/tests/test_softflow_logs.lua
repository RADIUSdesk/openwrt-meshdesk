#!/usr/bin/lua
-- SPDX-FileCopyrightText: 2024 Dirk van der Walt <dirkvanderwalt@gmail.com>
--
-- SPDX-License-Identifier: GPL-3.0-or-later

--[[--

This test script will test the rdSoftflowLogs object's methods

--]]--

-- Include libraries
package.path = "../libs/?.lua;./libs/?.lua;" .. package.path

function main()
	require("rdSoftflowLogs")
	local s = rdSoftflowLogs()
	print("Version is " .. s:getVersion())
	s:chilliInfo();	
	s:doDumpFlows();
	--s:doDeleteAll();
end

main()
