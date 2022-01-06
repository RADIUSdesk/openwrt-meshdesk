#!/usr/bin/lua

--[[--

This test script will test the rdWireless object class's various methods

--]]--

-- Include libraries
package.path = "../libs/?.lua;" .. package.path

function main()
	require("rdWireless")
	local w = rdWireless()
	print("Version is " .. w:getVersion())
	print("Running newWireless")
	w:newWireless()
	--print("Connect client")
	--w:connectClient()
	--print('Configure WiFi from JSON file')
	--local f = '/etc/MESHdesk/tests/sample_config.json'
	--w:configureFromJson(f)
	--w:configureFromTable()
end

main()
