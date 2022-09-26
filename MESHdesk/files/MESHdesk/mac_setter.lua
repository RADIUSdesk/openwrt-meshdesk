#!/usr/bin/lua


-- Include libraries
package.path = "../libs/?.lua;./libs/?.lua;/etc/MESHdesk/libs/?.lua;" .. package.path


function main()
	require("rdNetwork")
	local n = rdNetwork()
	print("Version is " .. n:getVersion())	
	n:addMacs();
end

main();
