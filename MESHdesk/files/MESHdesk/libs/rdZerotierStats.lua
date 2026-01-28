-- SPDX-FileCopyrightText: 2026 Dirk van der Walt <dirkvanderwalt@gmail.com>
--
-- SPDX-License-Identifier: GPL-3.0-or-later

require( "class" )

-- 28 JAN 2026 --

-------------------------------------------------------------------------------
-- Class to get stats from Zerotier ------------------------------------------
-------------------------------------------------------------------------------

--[[
	
==== Sample JSON ===
==== We use the Meta Data -> vpns ===

 "meta_data": {
    "mode": "ap",
    "mac": "00-18-0A-36-B4-4C",
    "ap_id": 160,
    "node_id": 160,
    "admin_state": "active",
    "exits": [
        {
            "id": 361,
            "ap_profile_exit_id": 361,
            "type": "nat",
            "device": "br-ex_zro",
            "sqm": false,
            "interface": "ex_zro",
            "stats": false,
            "ipaddr": "10.200.100.1",
            "netmask": "255.255.255.0"
        }
    ],
    "vpns": [
        {
            "id": 9,
            "interface": "zt01",
            "type": "zt",
            "network_id": "9bee8941b51fae7b",
            "ifname": "zt3jnzn36o",
            "stats": true,
            "routing": {
                "exit_points": [
                    null
                ],
                "macs": []
            }
        },
        {
            "id": 10,
            "interface": "zt02",
            "type": "zt",
            "network_id": "68bea79acfb27bf1",
            "ifname": "zt6jyrlyj6",
            "stats": true,
            "routing": {
                "exit_points": [
                    null
                ],
                "macs": []
            }
        }
    ],
    "WbwActive": false,
    "QmiActive": false
},

--]]

class "rdZerotierStats"

--Init function for object
function rdZerotierStats:rdZerotierStats()
    require('rdLogger');
	self.version 	= "1.0.1";
	self.tag	    = "MESHdesk";
	self.util       = require('luci.util');
	self.ubus       = require('ubus');
	self.nfs 		= require("nixio.fs")
	self.logger	    = rdLogger();
	self.debug	    = false;
	self.json       = require('luci.json');
	self.idLookup	= {};
	
	--Some variables
	self.cfg_file	= '/etc/MESHdesk/configs/current.json';		
end
        
function rdZerotierStats:getVersion()
	return self.version	
end

function rdZerotierStats:jsonStats()
	self:log("== Produce Zerotier stats as JSON ==")
	return self.json.encode(self:_tableStats());
end

function rdZerotierStats:tableStats()
	self:log("== Produce Wireguard stats as a table ==")
	return self:_tableStats();
end

function rdZerotierStats:log(m,p)
	if(self.debug)then
		self.logger:log(m,p)
	end
end

--[[--
========================================================
=== Private functions start here =======================
========================================================
--]]--

function rdZerotierStats:_tableStats()
	if(self:checkForZerotier())then
		local conn   	= self.ubus.connect();		
		local devices    = conn:call("luci-rpc", "getNetworkDevices", {});
		conn:close();
		if(devices)then
			local zerotier_stats = {}
			for device, device_info in pairs(devices) do
				if(self.idLookup[device])then
					local id = self.idLookup[device];
					local ip = device_info['ipaddrs'][1]['address'];
					local tx_bytes = device_info['stats']['tx_bytes'];
					local rx_bytes = device_info['stats']['rx_bytes'];
					--  ping -q -W 1 -A -c 3 10.8.0.1
					local ping = self.util.exec("ping -q -W 1 -A -c 2  "..ip);
					print(ping);
					local ts = 0; --default if ping fails
					if(ping:match('[12] packets received'))then
						print("Ping Zerotier Interface");
						ts = os.time();
					end
					table.insert(zerotier_stats, { id = id, ip = ip, tx_bytes = tx_bytes, rx_bytes = rx_bytes, timestamp = ts});
					print("For Device "..device.. " id is "..id.." ip is "..ip.." timestamp "..ts);									
				end
			end
			if next(zerotier_stats) then
				return zerotier_stats;
			end
			return nil;
		end
	end
	return nil;				
end

-- ======================================================--
-- ========= ADDITION TO REPORT DELTAS ==================--
-- ======================================================--

function rdZerotierStats.fileExists(name)
   local f=io.open(name,"r")
   if f~=nil then io.close(f) return true else return false end
end

function rdZerotierStats:checkForZerotier()

    local config_file 	= self.cfg_file;
    local foundZerotier	= nil;

    if self.fileExists(config_file) then
        local cfg = self.nfs.readfile(config_file)
        local config_data = self.json.decode(cfg)
        if config_data['success'] == true then
        	local meta_data = config_data.meta_data;      	
        	for _, vpn in ipairs(meta_data.vpns or {}) do
				if vpn['type'] == 'zt' then
					foundZerotier	= true;
					local interface = vpn['interface'];
					local ifname	= vpn['ifname'];
					local id = vpn['id'];
					self.idLookup[ifname] = id;  
				end
			end            
        end
    else
        return nil;
    end
    return foundZerotier;  
end

