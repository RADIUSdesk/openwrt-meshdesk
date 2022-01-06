#!/usr/bin/lua
-- Include libraries
package.path = "../libs/?.lua;./libs/?.lua;" .. package.path
function main()
    require("rdJsonReports")
	local j = rdJsonReports();
	j:runCollect();
end
main();
