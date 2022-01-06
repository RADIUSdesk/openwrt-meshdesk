#!/usr/bin/lua

--[[--

This test script will test the rdSystem object class's various methods

--]]--

-- Include libraries
package.path = "../libs/?.lua;" .. package.path

function main()
	require("rdSystem")
	local s = rdSystem()
	print("Version is " .. s:getVersion())	
	print('Configure System from JSON file')
	local f = '/etc/MESHdesk/tests/sample_config.json'
	s:configureFromJson(f)
end

main()
