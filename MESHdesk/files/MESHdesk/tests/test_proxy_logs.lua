#!/usr/bin/lua

--[[--

This test script will test the rdProxyLogs object's methods

--]]--

-- Include libraries
package.path = "../libs/?.lua;./libs/?.lua;" .. package.path

function main()
	require("rdProxyLogs")
	local p = rdProxyLogs()
	print("Version is " .. p:getVersion())
	--p:chilliInfo();	
	p:doPrivoxy();
	--p:truncLog();
end

main()
