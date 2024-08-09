#!/usr/bin/lua
-- SPDX-FileCopyrightText: 2024 Dirk van der Walt <dirkvanderwalt@gmail.com>
--
-- SPDX-License-Identifier: GPL-3.0-or-later

--[[--

This test script will test the rdAccel object class's various methods

--]]--

-- Include libraries
package.path = "../libs/?.lua;" .. package.path

function main()
    local json  = require('luci.json');
	require("rdAccelstats");
	local a = rdAccelstats();
	print("Version is " .. a:getVersion());
	print("Configure Accel-ppp from JSON file");
	
	local pwd  = a:getPassword();
	print(pwd);
	
	
	--local stat  = a:showStat();
    --local j_stat= json.encode(stat);
    --print(j_stat);
    --local sess  = a:showSessions();
    --local j_sess= json.encode(sess);
    --print(j_sess);

    --print(accel_stats);
end

main();
