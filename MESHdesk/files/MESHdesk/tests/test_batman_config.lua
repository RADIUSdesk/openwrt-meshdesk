#!/usr/bin/lua

--[[--

This test script will test the rdBatman object class's various methods

--]]--

-- Include libraries
package.path = "../libs/?.lua;" .. package.path

function main()
	require("rdBatman")
	local b = rdBatman()
	print("Version is " .. b:getVersion())
	print("Configure Batman adv from JSON file")
	local f = '/etc/MESHdesk/tests/sample_config_batman_adv.json'
	b:configureFromJson(f)
	--w:configureFromTable()
end

main()
