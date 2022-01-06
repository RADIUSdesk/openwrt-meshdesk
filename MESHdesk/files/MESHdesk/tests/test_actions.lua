#!/usr/bin/lua

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
