-- SPDX-FileCopyrightText: 2025 Dirk van der Walt <dirkvanderwalt@gmail.com>
--
-- SPDX-License-Identifier: GPL-3.0-or-later

require( "class" )

-- 21 NOV 2025 --

-------------------------------------------------------------------------------
-- Class to get stats from OpenVPN ------------------------------------------
-------------------------------------------------------------------------------

--[[
	
==== Sample JSON ===
==== We use the Meta Data -> vpns ===

"meta_data": {
    "mode": "ap",
    "mac": "20-05-B6-FF-94-46",
    "ap_id": 133,
    "node_id": 133,
    "vpns": [
        {
            "id": 3,
            "interface": "ovpn01",
            "type": "ovpn",
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

class "rdOvpnStats"

--Init function for object
function rdOvpnStats:rdOvpnStats()
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
        
function rdOvpnStats:getVersion()
	return self.version	
end

function rdOvpnStats:jsonStats()
	self:log("== Produce Wireguard stats as JSON ==")
	return self.json.encode(self:_tableStats());
end

function rdOvpnStats:tableStats()
	self:log("== Produce Wireguard stats as a table ==")
	return self:_tableStats();
end

function rdOvpnStats:log(m,p)
	if(self.debug)then
		self.logger:log(m,p)
	end
end

--[[--
========================================================
=== Private functions start here =======================
========================================================
--]]--

function rdOvpnStats:_tableStats()
	if(self:checkForOpenvpn())then
		local conn   	= self.ubus.connect();		
		local devices    = conn:call("luci-rpc", "getNetworkDevices", {});
		conn:close();
		if(devices)then
			for device, device_info in pairs(devices) do
				if(self.idLookup[device])then
					local id = self.idLookup[device];
					local ip = device_info['ipaddrs'][1]['address'];
					local gw = ip:match("^(%d+%.%d+%.%d+)%.") .. ".1";
					local tx_bytes = device_info['stats']['tx_bytes'];
					local rx_bytes = device_info['stats']['rx_bytes'];
					--  ping -q -W 1 -A -c 3 10.8.0.1
					local ping = self.util.exec("ping -q -W 1 -A -c 2  "..gw);
					print(ping);
					local ts = 0; --default if ping fails
					if(ping:match('[12] packets received'))then
						print("Got to Gateway");
						ts = os.time();
					end
					
					print("For Device "..device.. " id is "..id.." ip is "..ip.." Gateway is "..gw.." timestamp "..ts);	
								
				end
			end
		end
	end
	return nil;				
end

-- ======================================================--
-- ========= ADDITION TO REPORT DELTAS ==================--
-- ======================================================--

function rdOvpnStats.fileExists(name)
   local f=io.open(name,"r")
   if f~=nil then io.close(f) return true else return false end
end

function rdOvpnStats:checkForOpenvpn()

    local config_file 	= self.cfg_file;
    local foundOvpn		= nil;

    if self.fileExists(config_file) then
        local cfg = self.nfs.readfile(config_file)
        local config_data = self.json.decode(cfg)
        if config_data['success'] == true then
        	local meta_data = config_data.meta_data;      	
        	for _, vpn in ipairs(meta_data.vpns or {}) do
				if vpn['type'] == 'ovpn' then
					foundOvpn	= true;
					local interface = vpn['interface'];
					local id = vpn['id'];
					self.idLookup[interface] = id;  
				end
			end            
        end
    else
        return nil;
    end
    return foundOvpn;  
end

