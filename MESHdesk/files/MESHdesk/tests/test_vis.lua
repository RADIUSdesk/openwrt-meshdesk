#!/usr/bin/lua

--[[--

This test script will test the rdVis object's methods

--]]--

-- Include libraries
package.path = "../libs/?.lua;" .. package.path

function main()
	require("rdVis")
	local v = rdVis()
	print("Version is " .. v:getVersion())	
	print(v:getVisNoAlfred());
end

main()
