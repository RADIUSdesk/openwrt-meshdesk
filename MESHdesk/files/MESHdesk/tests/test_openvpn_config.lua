#!/usr/bin/lua
-- SPDX-FileCopyrightText: 2024 Dirk van der Walt <dirkvanderwalt@gmail.com>
--
-- SPDX-License-Identifier: GPL-3.0-or-later

--[[--

This test script will test the rrdOpenvpn object class's various methods

--]]--

-- Include libraries
package.path = "../libs/?.lua;" .. package.path

function main()
	require("rdOpenvpn")
	local o = rdOpenvpn()
	print("Version is " .. o:getVersion())
	print("Configure OpenVPN from JSON file")
	local f = '/etc/MESHdesk/tests/sample_config_openvpn.json'
	o:configureFromJson(f)
	--w:configureFromTable()
end

main()
