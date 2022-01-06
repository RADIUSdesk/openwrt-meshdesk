#!/usr/bin/lua
-- Include libraries
package.path = "../libs/?.lua;./libs/?.lua;/etc/MESHdesk/libs/?.lua;" .. package.path

require('rdNetstats');
local json	    = require('luci.json');
local netstats  = rdNetstats();
local n_stats  = netstats:getWifiUbus();
print(n_stats);
local radio_structure   = json.decode(n_stats);
