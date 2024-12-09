-- SPDX-FileCopyrightText: 2024 Mathis Arthur Boumaza <maboum2000@gmail.com>
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
    self.sys        = require('luci.sys');
    self.util       = require('luci.util'); 
    self.ubus       = require('ubus');
    self.json		= require("json");
    self.fs			= require('nixio.fs');
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
	local wanStats 	= {}; --Start with empty
	local ifUsage  	= {};
	local lteSignal = {};
	local wifiSignal= {};
	local mwanStatus= {};
	
	local conn = ubus.connect()
	if not conn then
		error("Failed to connect to ubusd")
	end
	local interfaces = conn:call("network.interface", "dump", { })
	for _, interface in ipairs(interfaces['interface']) do
		if(self:_matchesPattern(interface.interface))then				
			if(interface.up)then
				local ipv4_address = interface['ipv4-address'];
				local ipv6_address = interface['ipv6-address'];			
				if(interface.proto == 'qmi')then
					--We find the IP Address for qmi interfaces a bit different
					ipv4_address = self:_getIpForQmi(interfaces, interface.interface,'4');
					ipv6_address = self:_getIpForQmi(interfaces, interface.interface,'6');
				end	
				local dev 	= interface.l3_device;
				local stats = self:_getDeviceStats(interface.l3_device)
				-- Adding a new interface dynamically
				table.insert(ifUsage, { interface = interface.interface, ipv4_address = ipv4_address , ipv6_address =  ipv6_address, statistics = stats});
				if(interface.proto == 'qmi')then
					local lteStats = self:_getLteStats(interface.interface);
					lteStats.interface = interface.interface;
					table.insert(lteSignal, lteStats);
				end
			end
		end
	end
	
	local devices = conn:call("iwinfo", "devices", { })
	for _, device in ipairs(devices['devices']) do
		if(self:_matchesPattern(device))then		
			local iwInfo = self:_getWifiStats(device);
			if(self:_isNotEmpty(ifUsage))then
				table.insert(wifiSignal,iwInfo);
			end	
		end
	end
	
	local size = self.fs.stat('/etc/config/mwan_network', 'size')
	if size and size > 0 then
		mwanStatus = conn:call("mwan3", "status", {})
	end
		
	if(self:_isNotEmpty(ifUsage))then
		wanStats.usage = ifUsage;
	end
	
	if(self:_isNotEmpty(lteSignal))then
		wanStats.lteSignal = lteSignal;
	end
	
	if(self:_isNotEmpty(wifiSignal))then
		wanStats.wifiSignal = wifiSignal;
	end
	
	if(self:_isNotEmpty(mwanStatus))then
		wanStats.mwanStatus = mwanStatus;	
	end
				
	conn:close();	
	--print(self.json.encode(wanStats));	
	return wanStats;
end

function rdNetstatsWan:_getDeviceStats(device)
	local conn = ubus.connect()	
	local device = conn:call("network.device", "status", { name = device })
	local stats  = device.statistics
	conn:close();
	return stats;
end

function rdNetstatsWan:_getIpForQmi(interfaces,interface,version)
	local if_name 	= interface.."_"..version;
	local key	  	= 'ipv'..version..'-address';
	local value		= nil;
	for _, interface in ipairs(interfaces['interface']) do
		if(interface.interface == if_name)then
			value = interface[key];
		end	
	end	
	return value;
end	

function rdNetstatsWan:_getLteStats(interface)

	local lteData		= {} 
	local cursor 		= self.uci:cursor();
	local section_name 	=  interface-- Replace with your interface section name
	local option_name 	= "device" -- The option you want to retrieve
	local device 		= cursor:get("network", section_name, option_name)
	if device then
		local signal_info 	= self.util.exec("uqmi -t 1000 -d "..device.." --get-signal-info");
        local system_info 	= self.util.exec("uqmi -t 1000 -d "..device.." --get-system-info");
        local lte_data_s    = '{"signal" : '..signal_info..',"system":'..system_info..'}';	
        lteData = self.json.decode(lte_data_s);	
	else
		print("Device information not found for interface " .. section_name)
	end
	return lteData;	
end

function rdNetstatsWan:_getWifiStats(interface)

	local iwInfo  = {};
    local iw      = self.sys.wifi.getiwinfo(interface);
    --Note this iw is an iwinfo object whic is not a table so you will not be able to get keys and values out of it
    --You can however query it for some items like channel signal noise etc
      
    if(iw.channel ~= nil)then
    	iwInfo['interface']	  = interface;
        iwInfo['channel']     = iw.channel;
        iwInfo['signal']      = iw.signal;
        iwInfo['txpower']     = iw.txpower;
        iwInfo['noise']       = iw.noise; 
        iwInfo['bitrate']     = iw.bitrate; 
       	iwInfo['quality']     = iw.quality;
        iwInfo['ssid']        = iw.ssid;
        local sta_list          = iw.assoclist;      
        local throughput        = 0;
        local tx_rate           = 0;
        local rx_rate           = 0;
        local tx_packets        = 0;
        local rx_packets        = 0;
        
        for key,value in pairs(sta_list) do 
            throughput = sta_list[key]['expected_throughput'];
            tx_rate    = sta_list[key]['tx_rate'];
            rx_rate    = sta_list[key]['rx_rate'];
            tx_packets = sta_list[key]['tx_packets'];
            rx_packets = sta_list[key]['rx_packets'];
        end
        iwInfo['expected_throughput']     = throughput;
        iwInfo['tx_rate']                 = tx_rate;
        iwInfo['rx_rate']                 = rx_rate;
        iwInfo['tx_packets']              = tx_packets;
        iwInfo['rx_packets']              = rx_packets;      
    end
    return iwInfo;
end

function rdNetstatsWan:_matchesPattern(value)
    -- Match 'lan' or strings starting with 'mw' followed by one or more digits
    return value == "lan" or value:match("^mw%d+$") ~= nil
end


function rdNetstatsWan:_isNotEmpty(table)
    -- Check if any key exists in the table
    for _ in pairs(table) do
        return true -- Found at least one key, so the table is not empty
    end
    return false -- No keys found, the table is empty
end

function rdNetstatsWan:_getMwanStatus()

	if(self.fs.stat('/usr/sbin/mwan3','size')>0)then
		local signal_info 	= self.util.exec("mwan3 status");
	else
		return {};
	end
end

