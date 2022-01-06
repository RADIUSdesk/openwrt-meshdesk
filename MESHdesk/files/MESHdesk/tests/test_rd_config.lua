#!/usr/bin/lua

--[[--

This test script will test the rdConfig object's methods

--]]--

-- Include libraries
package.path = "../libs/?.lua;./libs/?.lua;" .. package.path

function main()
	require("rdConfig")
	local c = rdConfig();
	print("Version is " .. c:getVersion())
	local ret_table = c:tryForConfigServer('lan');
end

main()
