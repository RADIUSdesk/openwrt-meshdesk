-- SPDX-FileCopyrightText: 2026 Dirk van der Walt <dirkvanderwalt@gmail.com>
--
-- SPDX-License-Identifier: GPL-3.0-or-later

require( "class" )

-- 10 JAN 2026 --

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
            "interface": "xfrm01",
            "type": "ipsec",
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

class "rdIpsecStats"

--Init function for object
function rdIpsecStats:rdIpsecStats()
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
        
function rdIpsecStats:getVersion()
	return self.version	
end

function rdIpsecStats:jsonStats()
	self:log("== Produce Wireguard stats as JSON ==")
	return self.json.encode(self:_tableStats());
end

function rdIpsecStats:tableStats()
	self:log("== Produce Wireguard stats as a table ==")
	return self:_tableStats();
end

function rdIpsecStats:log(m,p)
	if(self.debug)then
		self.logger:log(m,p)
	end
end

--[[--
========================================================
=== Private functions start here =======================
========================================================
--]]--

function rdIpsecStats:_tableStats()
	if(self:checkForOpenvpn())then
		local conn   	= self.ubus.connect();		
		local devices    = conn:call("luci-rpc", "getNetworkDevices", {});
		conn:close();
		if(devices)then
			local ipsec_stats = {}
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
					table.insert(ipsec_stats, { id = id, ip = ip, tx_bytes = tx_bytes, rx_bytes = rx_bytes, timestamp = ts});
					print("For Device "..device.. " id is "..id.." ip is "..ip.." Gateway is "..gw.." timestamp "..ts);	
								
				end
			end
			if next(ipsec_stats) then
				return ipsec_stats;
			end
			return nil;
		end
	end
	return nil;				
end

-- ======================================================--
-- ========= ADDITION TO REPORT DELTAS ==================--
-- ======================================================--

function rdIpsecStats.fileExists(name)
   local f=io.open(name,"r")
   if f~=nil then io.close(f) return true else return false end
end

function rdIpsecStats:checkForOpenvpn()

    local config_file 	= self.cfg_file;
    local foundIpsec	= nil;

    if self.fileExists(config_file) then
        local cfg = self.nfs.readfile(config_file)
        local config_data = self.json.decode(cfg)
        if config_data['success'] == true then
        	local meta_data = config_data.meta_data;      	
        	for _, vpn in ipairs(meta_data.vpns or {}) do
				if vpn['type'] == 'ipsec' then
					foundIpsec	= true;
					local interface = vpn['interface'];
					local id = vpn['id'];
					self.idLookup[interface] = id;  
				end
			end            
        end
    else
        return nil;
    end
    return foundIpsec;  
end

