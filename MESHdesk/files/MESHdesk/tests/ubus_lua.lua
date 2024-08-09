#!/usr/bin/lua
-- SPDX-FileCopyrightText: 2024 Dirk van der Walt <dirkvanderwalt@gmail.com>
--
-- SPDX-License-Identifier: GPL-3.0-or-later

-- Include libraries
package.path = "../libs/?.lua;./libs/?.lua;/etc/MESHdesk/libs/?.lua;" .. package.path

require('rdNetstats');
local json	    = require('luci.json');
local netstats  = rdNetstats();
local n_stats  = netstats:getWifiUbus();
print(n_stats);
local radio_structure   = json.decode(n_stats);
