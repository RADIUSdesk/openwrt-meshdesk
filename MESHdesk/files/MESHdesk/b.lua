#!/usr/bin/lua

-- SPDX-FileCopyrightText: 2024 Dirk van der Walt <dirkvanderwalt@gmail.com>
--
-- SPDX-License-Identifier: GPL-3.0-or-later


-- Include libraries
package.path = "libs/?.lua;" .. package.path;
require("rdLogger");
require("rdConfig");

local uci    	        = require("uci");
local uci_cursor        = uci.cursor();
local dns_works         = false; --'global' flag which indicates if we could resolve DNS to IP
local debug			    = true;
local c 				= rdConfig();
local l			        = rdLogger();
local config_success    = false;

--======================================
---- Some helper functions ------------
--======================================
function log(m,p)
	if(debug)then
	    print(m);
		l:log(m,p)
	end
end

function fetch_latest_config()
    local config_file	    = uci_cursor:get('meshdesk','settings','config_file');
    local wifi_captive      = false;
    local found_config      = false;   
    os.execute("/etc/MESHdesk/main_led.lua start lan");
    local ret_tbl   = c:fetchFreshConfig('lan');
    dns_works       = ret_tbl.dns_works;
    if(ret_tbl.got_settings)then
        log("Lekker man Got the slettings");
        local ret_conf = c:configureDevice(config_file,true);--include doWanSynch here    
        if(ret_conf.config_success == true)then
            config_success = true;
        end        
    end  
end

fetch_latest_config();
if(config_success)then
    l:log("Fresh configuration successful commited");
else
    l:log("Could not commit fresh configuration");
end
