-- SPDX-FileCopyrightText: 2024 FIXME REPLACE WITH YOUR INFO ... format: Mathis Arthur Boumaza <maboum2000@gmail.com>
--
-- SPDX-License-Identifier: GPL-3.0-or-later

require( "class" )

-------------------------------------------------------------------------------
-- Object to manage external programs (start and stop) ------------------------
-------------------------------------------------------------------------------
class "rdNetstatsWan"

--Init function for object
function rdNetstatsWan:rdNetstatsWan()
	require('rdLogger');   
	self.version 	= '1.0.1';
	self.tag	    = "MESHdesk"
	self.debug	    = true
    self.uci 		= require('uci');
    self.sys		= require('luci.sys');
    self.ubus       = require('ubus');
    self.logger		= rdLogger();
end
        
function rdNetstatsWan:getVersion()
	return self.version
end

function rdNetstatsWan:printHostname()
	local hostName = self:_getHostname();
	self:log('Hostname is '..hostName);
end

function rdNetstatsWan:getWanStats()
	return self:_getWanStats();
end

function rdNetstatsWan:log(m,p)
	if(self.debug)then
		print(m)
		self.logger:log(m,p)
	end
end


--[[--
========================================================
=== Private functions start here =======================
========================================================
--]]--


function rdNetstatsWan:_getHostname(json_file)
	self:log("Getting Hostname");
	return self.sys.hostname();
end



function rdNetstatsWan:_getWanStats(json_file)
	self:log("Getting WAN Stats using ubus");
	local wanStats = {}; --Start with empty
	local conn = ubus.connect()
	if not conn then
		error("Failed to connect to ubusd")
	end
	local interfaces = conn:call("network.interface", "dump", { })
	local wan_pattern = "^mw(%d+)$"
	for _, interface in ipairs(interfaces['interface']) do
		if(string.match(interface.interface, wan_pattern) and interface.up and interface.l3_device) then
			table.insert(wanStats, {
				interface = interface.interface,
				up = interface.up,
				statistics = self:_getDeviceStats(interface.l3_device)
			})
		end
	end
	conn:close();
	return wanStats;
end



function rdNetstatsWan:_getDeviceStats(device)
	local conn = ubus.connect()	
	local device = conn:call("network.device", "status", { name = device })
	conn:close();
	return device.statistics;
end
