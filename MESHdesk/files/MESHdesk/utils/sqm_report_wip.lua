#!/usr/bin/lua
-- Include libraries
package.path = "../libs/?.lua;./libs/?.lua;/etc/MESHdesk/libs/" .. package.path

require("rdSqm");
local sqm   = rdSqm();
print(sqm:getStatsJson());
