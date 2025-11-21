-- SPDX-FileCopyrightText: 2025 Dirk van der Walt <dirkvanderwalt@gmail.com>
--
-- SPDX-License-Identifier: GPL-3.0-or-later

require( "class" )

-- 12 NOV 2025 --

-------------------------------------------------------------------------------
-- Class to get stats from wireguard ------------------------------------------
-------------------------------------------------------------------------------

--[[
	
==== Sample JSON ===
==== We use the Meta Data -> vpns ===

"meta_data": {
    "mode": "ap",
    "mac": "20-05-B6-FF-94-46",
    "ap_id": 133,
    "node_id": 133,
    "exits": [
        {
            "id": 199,
            "ap_profile_exit_id": 199,
            "type": "nat",
            "device": "br-ex_zro",
            "sqm": true,
            "interface": "ex_zro",
            "stats": true
        },
        {
            "id": 200,
            "ap_profile_exit_id": 200,
            "type": "nat",
            "device": "br-ex_one",
            "sqm": false,
            "interface": "ex_one",
            "stats": true
        }
    ],
    "vpns": [
        {
            "id": 1,
            "interface": "wg01",
            "type": "wg",
            "stats": true,
            "routing": {
                "exit_points": [],
                "macs": []
            }
        },
        {
            "id": 2,
            "interface": "wg02",
            "type": "wg",
            "stats": true,
            "routing": {
                "exit_points": [],
                "macs": []
            }
        }
    ],
    "zro0": 124,
    "one0": 125,
    "WbwActive": false,
    "QmiActive": false
},

--]]

class "rdWgStats"

--Init function for object
function rdWgStats:rdWgStats()
    require('rdLogger');
	self.version 	= "1.0.1";
	self.tag	    = "MESHdesk";
	self.util       = require('luci.util');
	self.ubus       = require('ubus');
	self.nfs 		= require("nixio.fs")
	self.logger	    = rdLogger();
	self.debug	    = false;
	self.json       = require('luci.json');
	
	--Some variables
	self.cfg_file	= '/etc/MESHdesk/configs/current.json';		
end
        
function rdWgStats:getVersion()
	return self.version	
end

function rdWgStats:jsonStats()
	self:log("== Produce Wireguard stats as JSON ==")
	return self.json.encode(self:_tableStats());
end

function rdWgStats:tableStats()
	self:log("== Produce Wireguard stats as a table ==")
	return self:_tableStats();
end

function rdWgStats:log(m,p)
	if(self.debug)then
		self.logger:log(m,p)
	end
end

--[[--
========================================================
=== Private functions start here =======================
========================================================
--]]--

function rdWgStats:_tableStats()
	if(self:checkForWireguard())then
		local conn  = self.ubus.connect();		
		local wg    = conn:call("luci.wireguard", "getWgInstances", {});
		conn:close();
		if(wg)then
			return wg;
		end
	end
	return nil;				
end

-- ======================================================--
-- ========= ADDITION TO REPORT DELTAS ==================--
-- ======================================================--

function rdWgStats.fileExists(name)
   local f=io.open(name,"r")
   if f~=nil then io.close(f) return true else return false end
end

function rdWgStats:checkForWireguard()

    local config_file 	= self.cfg_file;

    if self.fileExists(config_file) then
        local cfg = self.nfs.readfile(config_file)
        local config_data = self.json.decode(cfg)
        if config_data['success'] == true then
        	local meta_data = config_data.meta_data;      	
        	for _, vpn in ipairs(meta_data.vpns or {}) do
				if vpn['type'] == 'wg' then
				    return true; --return on first Wireguard VPN
				end
			end            
        else
            return nil; 
        end
    else
        return nil;
    end  
end

