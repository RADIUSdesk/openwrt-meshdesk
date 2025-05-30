-- SPDX-FileCopyrightText: 2025 Dirk van der Walt <dirkvanderwalt@gmail.com>
--
-- SPDX-License-Identifier: GPL-3.0-or-later

require( "class" )

-------------------------------------------------------------------------------
-- A class to fetch network statistics and return it in JSON form -------------
-------------------------------------------------------------------------------
class "rdNetstats"

--Init function for object
function rdNetstats:rdNetstats()

	require('rdLogger');
	require('rdNetwork');
	
	local uci 		= require("uci");
	self.version 	= "1.0.0"
	self.json		= require("json");
	self.ubus       = require('ubus');
	self.logger		= rdLogger()
	--self.debug		= true
	self.debug		= false
	self.x			= uci.cursor()
	self.network    = rdNetwork	
end
        
function rdNetstats:getVersion()
	return self.version
end

function rdNetstats:getWifiUbus()
	return self:_getWifiUbus()
end

function rdNetstats:mapEthWithMeshMac()
	--Prime the object with easy lookups
	self:_createWirelessLookup()
	return self:_mapEthWithMeshMac()
end

function rdNetstats:log(m,p)
	if(self.debug)then
		self.logger:log(m,p)
	end
end
--[[--
========================================================
=== Private functions start here =======================
========================================================
(Note they are in the pattern function <rdName>._function_name(self, arg...) and called self:_function_name(arg...) )
--]]--

function rdNetstats._mapEthWithMeshMac(self)

	--This part is used for us so we can have a mapping between eth0 (the 'id' of the Node)
	--And the various mesh interfaces (mesh0... mesh5)-----
	--We have to go though each one since anit can have mesh1 running but not mesh0 , or both can be on...

	local m     = {};
	local id_if = self.x:get('meshdesk','settings','id_if');
    local id    = self.network:getMac(id_if)                                                                           
	m['eth0']   = id --FIXME The back-end still thinks its eth0 but it can be set in firmware to be another eth

	--Our loopy-de-loop
	local i 	= 0;
	while i  <= 2 do

		local mesh  = 'mesh'..i
		local file_to_check = "/sys/class/net/" .. mesh .. "/address"

		--Check if file exists
		local f=io.open(file_to_check,"r")                                                   
		if f~=nil then --This file exists
			io.close(f)

			--Read the file now we know it exists
			io.input(file_to_check)
			local mac 	= io.read("*line")
			m[mesh] 	= mac

			--Also record the hwmode of this interface (we need this to show different coulors on the spiderweb)
			local device 		= self[mesh]['device'];
			local hwmode 		= self[device]['hwmode'];
			m['hwmode_'..mesh]  = hwmode;

		else

			m[mesh] = false	--If there are no

		end

		--Increment the loop	
		i = i + 1;

	end

	--Also record if this node is a gateway or not
	m['gateway']    = 0;
	m['lan_proto']  = false;
	m['lan_ip']     = false;
	m['lan_gw']     = false;

	local f=io.open('/tmp/gw',"r")
	if f~=nil then
  		m['gateway'] = 1
	end

	return self.json.encode(m)
end


function rdNetstats._createWirelessLookup(self)
	--This will create a lookup on the object to determine the hardware mode a wifi-device has
	--So we only call this once
 
	local default_val = 'g' --We specify a 'sane' default of g	
	self.x:foreach('wireless','wifi-device', 
	function(a)
		local dev_name 	= a['.name'];
		local hwmode 	= a['hwmode'];
		if(hwmode == nil)then
			hwmode = default_val;
		end
		self[dev_name] = {}; --empty table
		self[dev_name]['hwmode'] = hwmode;
	end)

	self.x:foreach('wireless','wifi-iface', 
		function(a)
			--print(a['.name'].." "..interface)
			--Check the name--
			local ifname = a['ifname'];
			local device = a['device'];
			if(ifname ~= nil)then
				self[ifname] = a;
				--print(self[ifname]['device']);	
			end
	end)
end

function rdNetstats._getWifiUbus(self)
	self:log('Getting WiFi stats using Ubus')
	local w 	= {}
	w['radios']	= {}
	
	local id_if = self.x:get('meshdesk','settings','id_if');
    local id    = self.network:getMac(id_if)
    w['eth0']   = id --FIXME The back-end still thinks its eth0 but it can be set in firmware
    	
	local phy 	= nil
	local i_info= {};
	local conn  = self.ubus.connect();
	
	local ws = conn:call("network.wireless", "status", {})
    for k, v in pairs(ws) do
        --Format is radio0 ....
        if(k:match("^radio"))then
            --print("key=" .. k .. " value=" .. tostring(v))
            phy = k:gsub("^radio", '')
            --print(phy);
            w['radios'][phy]		        = {}
			w['radios'][phy]['interfaces']	= {};
			w['radios'][phy]['info']        = {};
			
			for a, b in ipairs(ws[k]['interfaces']) do
			    local ifname   = b['ifname'];
			    local vlans    = {0}; --prime it with the basic interface (no VLAN)
			    
			    --Here we will look if config.dynamic_vlan is present and set to "1"
			    --If so we need to call ubus call iwinfo devices '{ }' to see if there are any VLAN interfaces to get the stats from them
			    if(b['config']['dynamic_vlan'])then
			        if(b['config']['dynamic_vlan'] == 1)then
			            --print("==== VLAN ALERT FOR ".. ifname .."====");
			            local devices   = conn:call("iwinfo", "devices", { });
			            for m, n in ipairs(devices['devices'])do			                
			                if(n:match("^"..ifname.."."))then
			                    vlan = n:gsub("^"..ifname..".","");
			                    --print("==== VLAN NUMBER ".. vlan .."====");
			                    table.insert(vlans,vlan);  
			                end
			            end			            
			        end
			    end
			    
			    local i_info   = conn:call("iwinfo", "info", { device = ifname });
			    i_info['name'] = ifname;
			    i_info['mac']  = i_info['bssid'];
			    
			    local mode_map = {
					['Master']      = 'AP',
					['Mesh Point']  = 'mesh point',
					['Client']      = 'managed',
					['IBSS']        = 'IBSS'
				}
				i_info['type'] 		= mode_map[i_info['mode']] or 'unknown'			    			    
			    i_info['stations'] 	= {};
			    
			    for o, p in ipairs(vlans) do		    
			        --Here we have to loop though a list of 'devices' which might include the VLAN numbers
			        local dev = ifname;
			        if(p ~= 0)then
			            dev = dev..'.'..p; --if it is zero we do not chenge the ifname
			        end	
			        --print("==== STATIONS FOR ".. dev .."====");			            
			        local  assoclist   = conn:call("iwinfo", "assoclist", { device = dev });
			        for c, d in ipairs(assoclist['results'])do	
			        			        
			        	local rx = d['rx'] or {};
						local tx = d['tx'] or {};
						
						local sta = {
							mac			   = d.mac,
							signal         = d.signal,
							signal_avg     = d.signal_avg,
							noise          = d.noise,
							connected_time = d.connected_time,
							inactive_time  = d.inactive,

							rx_bitrate     = self:_toM(rx.rate),
							rx_mcs         = rx.mcs,
							rx_short_gi    = rx.short_gi,
							rx_packets     = rx.packets,
							rx_bytes       = rx.bytes,
							rx_ht          = rx.ht,
							rx_vht         = rx.vht,
							rx_he          = rx.he,
							rx_eht         = rx.eht,
							rx_mhz         = rx.mhz,

							tx_bitrate     = self:_toM(tx.rate),
							tx_mcs         = tx.mcs,
							tx_nss         = tx.nss,
							tx_short_gi    = tx.short_gi,
							tx_packets     = tx.packets,
							tx_bytes       = tx.bytes,
							tx_failed      = tx.failed,
							tx_retries	   = tx.retries,
							tx_ht          = tx.ht,
							tx_vht         = tx.vht,
							tx_he          = tx.he,
							tx_eht         = tx.eht,
							tx_mhz         = tx.mhz,

							wme            = d.wme,
							mfp            = d.mfp,
							tdls           = d.tdls,
							vlan           = p,
						}
						
						table.insert(i_info.stations, sta)			        
			        end			        	
			    end			    			    		    			    
			    table.insert(w['radios'][phy]['interfaces'],i_info);	
			end			
        end
    end    
    conn:close();
    --luci.util.dumptable(w);  
	return self.json.encode(w)
end


function rdNetstats._toM(self,value)
    local number = value/1024;
    number = number - (number % 1);
    return tostring(number);
end
