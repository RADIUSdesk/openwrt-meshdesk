#!/usr/bin/lua

--[[--

This test script will test the rdSqliteReports object class's various methods

--]]--

-- Include libraries
--package.path = "../libs/?.lua;" .. package.path

-- Include libraries
package.path = "../libs/?.lua;./libs/?.lua;" .. package.path

function main()
	require("rdSqliteReports")
	local s = rdSqliteReports()
	print("Version is " .. s:getVersion())
	--print("Soft Init the DB")
    --s:initDb();
	--print("Run the Report");
	--s:runCollect();
	print(s:runReport());
end

main()
