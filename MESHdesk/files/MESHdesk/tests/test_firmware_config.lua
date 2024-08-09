#!/usr/bin/lua
-- SPDX-FileCopyrightText: 2024 Dirk van der Walt <dirkvanderwalt@gmail.com>
--
-- SPDX-License-Identifier: GPL-3.0-or-later

--[[--

This test script will test the rdFirmwareConfig object class's various methods

--]]--

-- Include libraries
package.path = "../libs/?.lua;" .. package.path

function main()
	require("rdFirmwareConfig")
	local f = rdFirmwareConfig()
	print("Version is " .. f:getVersion())	
	f:runConfig()
end

main()
