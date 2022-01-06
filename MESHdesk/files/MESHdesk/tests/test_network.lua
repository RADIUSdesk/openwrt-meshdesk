#!/usr/bin/lua

--[[--

This test script will test the rdVis object's methods

--]]--

-- Include libraries
package.path = "../libs/?.lua;" .. package.path

function main()
	require("rdNetwork")
	local n = rdNetwork()
	print("Version is " .. n:getVersion())	
	n:doWanSynch();
end

main()
