require( "class" )

-------------------------------------------------------------------------------
-- A class to fetch network statistics and return it in JSON form -------------
-------------------------------------------------------------------------------
class "rdNetstats"

--Init function for object
function rdNetstats:rdNetstats()

	require('rdLogger');
	require('rdExternal');
	require('rdNetwork');
	
	local uci 		= require("uci");
	self.version 	= "1.0.0"
	self.json		= require("json");
	self.ubus       = require('ubus');
	self.logger		= rdLogger()
	self.external	= rdExternal()
	--self.debug		= true
	self.debug		= false
	self.x			= uci.cursor()
	self.network    = rdNetwork
	self.iwinfo     = require('iwinfo')	
end
        
function rdNetstats:getVersion()
	return self.version
end


function rdNetstats:getWifi()
	return self:_getWifi()
end

function rdNetstats:getWifiUbus()
	return self:_getWifiUbus()
end

function rdNetstats:getEthernet()

	local wifi = self.x:get('meshdesk', 'settings','hardware')
	self.x:foreach('meshdesk', 'hardware',
		function(a)
			if(a['.name'] == hardware)then
				self.led = a['morse_led']
				if(a['swap_on_off'] == '1')then
					--print("Swapping on and off")
					self:swapOnOff()
				end
			end	
		end)
end

function rdNetstats:mapEthWithMeshMac()
	--Prime the object with easy lookups
	self:_createWirelessLookup()
	return self:__mapEthWithMeshMac()
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

function rdNetstats.__mapEthWithMeshMac(self)

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


function rdNetstats._getWifi(self)
	self:log('Getting WiFi stats')
	local w 	= {}
	w['radios']	= {}
	
	local id_if = self.x:get('meshdesk','settings','id_if');
    local id    = self.network:getMac(id_if)
    w['eth0']   = id --FIXME The back-end still thinks its eth0 but it can be set in firmware
    
    --DEC 2020 We add a flag for the 9888(/6) to do an alternative wat to get the mesh stations since it seems to have a bug
    local use_iwinfo = self.x:get('meshdesk','settings','use_iwinfo_for_mesh_stations');
	
	local phy 	= nil
	local i_info	= {}
	
	local dev = self.external:getOutput("iw dev")
	for line in string.gmatch(dev, ".-\n")do
		
		line = line:gsub("^%s*(.-)%s*$", "%1")
		if(line:match("^phy#"))then
			--Get the interface number 
			phy = line:gsub("^phy#", '')
			w['radios'][phy]		={}
			w['radios'][phy]['interfaces']	={}
			w['radios'][phy]['info']	={}
		end
		if(line:match("^Interface "))then
			line = line:gsub("^Interface ", '')
			i_info['name']	= line
		end
		if(line:match("^addr "))then
			line = line:gsub("^addr ", '')
			i_info['mac']	= line
		end
		if(line:match("^ssid "))then
			line = line:gsub("^ssid ", '')
			i_info['ssid']	= line
		end
		if(line:match("^type "))then
			line = line:gsub("^type ", '')
			i_info['type']	= line	
			--Sometimes the ssid is not listed per interface, then we have to search for it
			if(i_info['ssid'] == nil)then
				i_info['ssid'] = self._getSsidForInterface(self,i_info['name']);
				--print(i_info['ssid']);	
			end
			
		end
		if(line:match("^channel "))then
			line = line:gsub("^channel ", '') -- channel 1 (2412 MHz), width: 20 MHz, center1: 2412 MHz
			line = line:gsub("%s*%((.-)$", '') -- REMOVES: (2412 MHz), width: 20 MHz, center1: 2412 MHz
			i_info['channel']	= line
		end
		if(line:match("^txpower "))then
			line = line:gsub("^txpower ", '')
			line = line:gsub("%s*dBm(.-)$", '') -- REMOVES: dBm;
			i_info['txpower']	= line;
			
			local stations = {};
			
			if(i_info['type'] == 'mesh point')then --Only for type mesh point AND it specified else we do iw station dump
			    if(use_iwinfo == '1')then
			        --print("Use iwinfo alternative to iw station dump");
                    stations = self._getAssoclist(self,i_info['name'])
			    else
			        --print("Use iw station dump");
			        stations = self._getStations(self,i_info['name'])
			    end			    
		    else
		        stations = self._getStations(self,i_info['name'])    
			end
			
			--Now we can add the info
			
			--txpower is last so once we have that item we then add the interface to the table
			table.insert(w['radios'][phy]['interfaces'],{
		        name        = i_info['name'],
		        mac         = i_info['mac'], 
		        ssid        = i_info['ssid'], 
		        channel     = i_info['channel'],
		        txpower     = i_info['txpower'],
		        type        = i_info['type'],
		        stations    = stations
	        });
	        
	        i_info['ssid'] = nil --zero it again for the next round	 (Probably related to hidden SSIDs)	
		end		
	end
	return self.json.encode(w)
end


function rdNetstats._getAssoclist(self,interface)

    self:log('Use iwinfo to get Stations connected to '..interface)
    
    local s 	    = {};
	local s_info	= {};
    local assoclist = rdNetstats._getinfo(self, interface, "assoclist");
    
    if assoclist then
		local count = 0;
		local mac, info;
		for mac, info in pairs(assoclist) do

		    local new_info  = {};
		    
		    --These are just 'fillers'---
		    new_info['authenticated']   = "yes";
		    new_info['authorized']      = "yes";
		    new_info['connected time']  = "0"; --Make this zero to catch later (in rdSqliteReports) to see if it is the same session
		    new_info['inactive time']   = "0";
		    new_info['MFP']             = "no";
            new_info['preamble']        = "short";  
            new_info['TDLS peer']       = "no";    
            new_info['tx failed']       = "0";
            new_info['tx retries']      = "0";
            new_info['WMM/WME']         = "yes";
            --END These are just 'fillers'---
 
		    new_info['mac']         = mac;
		    new_info['signal avg']  = tostring(info.signal);
		    new_info['signal']      = tostring(info.signal);
		    new_info['rx packets']  = tostring(info.rx_packets);
		    new_info['tx packets']  = tostring(info.tx_packets);
		    new_info['rx bytes']    = tostring((info.rx_packets)*1000); --We're not using 1500 (mtu since most packets might be smaller - mesh managment packets)
		    new_info['tx bytes']    = tostring((info.tx_packets)*1000); --We're not using 1500 (mtu since most packets might be smaller - mesh managment packets)
		    new_info['tx bitrate']  = tostring((info.tx_rate)/1024).." MBit/s";
		    new_info['rx bitrate']  = tostring((info.rx_rate)/1024).." MBit/s";
		    
			--luci.util.dumptable(info);
			table.insert(s,new_info);
		end
	end
	
	local want_these= {
		'inactive time', 'rx bytes','rx packets','tx bytes','tx packets','tx retries','tx failed',
		'signal', 'signal avg', 'tx bitrate', 'rx bitrate', 'authorized', 'authenticated', 'preamble',
		'WMM/WME', 'MFP', 'TDLS peer','connected time'
	};
	--luci.util.dumptable(s);
	return s;
     
end

function rdNetstats._getinfo(self,ifname, func)
	local driver_type = self.iwinfo.type(ifname)
	if driver_type and iwinfo[driver_type][func] then
		return iwinfo[driver_type][func](ifname)
	end
	return nil
end



function rdNetstats._getStations(self,interface)

	self:log('Getting Stations connected to '..interface)
	local s 	= {}
	local s_info	= {}
	
	local want_these= {
		'inactive time', 'rx bytes','rx packets','tx bytes','tx packets','tx retries','tx failed',
		'signal', 'signal avg', 'tx bitrate', 'rx bitrate', 'authorized', 'authenticated', 'preamble',
		'WMM/WME', 'MFP', 'TDLS peer','connected time'
	};
	
    --We take what we can ...
    --[[local want_these= {
        "authenticated","authorized","associated","beacon interval","connected time","expected throughput",
        "inactive time","MFP","preamble","rx bitrate","rx bytes","rx duration","rx packets","rx drop misc",
        "short preamble","short slot time","signal","signal avg","TDLS peer","DTIM period",
        "tx bitrate","tx bytes","tx failed","tx packets","tx retries","WMM/WME"
    };--]]

	local last_item = "connected time"
	
	local dev = self.external:getOutput("iw dev "..interface.." station dump")

	for line in string.gmatch(dev, ".-\n")do	--split it up on newlines
		
		line = line:gsub("^%s*(.-)%s*$", "%1")  --remove leading and trailing spaces
		if(line:match("^Station"))then
			line = line:gsub("^Station-%s(.-)%s.+","%1")
			s_info['mac'] = line;
		end
		
		for i, v in ipairs(want_these) do 
			local l = line
			if(l:match("^"..v..":"))then
				l  		= l:gsub("^"..v..":-%s+","");
				--print("ITEM "..v.." VALUE ".. l);
				s_info[v] 	= l;

				if(line:match(last_item))then
					--create a new table and insert it into the s table
					local new_info = {}
					for j,k in ipairs(want_these) do
						new_info[k] = s_info[k]
					end
					new_info['mac'] = s_info['mac']
					table.insert(s,new_info)
				end
			end
		end
	end
	return s
end

function rdNetstats._getSsidForInterface(self,interface)
	local retval = nil
	self.x:foreach('wireless','wifi-iface', 
		function(a)
			--print(a['.name'].." "..interface)
			--Check the name--
			if(a['ifname'] ~= nil)then
				if(string.find(a['ifname'],interface))then
					retval = a['ssid']
				end
			end
 		end)
	return retval
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
			    if(i_info['mode'] == 'Master')then
			        i_info['type'] = 'AP';    
			    end
			    if(i_info['mode'] == 'Mesh Point')then
			        i_info['type'] = 'mesh point';    
			    end
			    if(i_info['mode'] == 'Client')then
			        i_info['type'] = 'managed';    
			    end
			    if(i_info['mode'] == 'IBSS')then
			        i_info['type'] = 'IBSS';    
			    end
			    i_info['stations'] = {};
			    
			    for o, p in ipairs(vlans) do		    
			        --Here we have to loop though a list of 'devices' which might include the VLAN numbers
			        if(p ~= 0)then
			            ifname = ifname..'.'..p; --if it is zero we do not chenge the ifname
			        end	
			        --print("==== STATIONS FOR ".. ifname .."====");    
			        local  assoclist   = conn:call("iwinfo", "assoclist", { device = ifname });
			        for c, d in ipairs(assoclist['results'])do			    
		                d['connected time'] = d['connected_time'];
		                d['inactive time']  = d['inactive'];	            
		                d['MFP']            = d['mfp'];
                        d['TDLS peer']      = d['dtls'];    
                        d['tx failed']      = d['tx']['failed'];
                        d['tx retries']     = d['tx']['retries'];
                        d['WMM/WME']        = d['wme'];
		                d['signal avg']     = d['signal_avg'];
		                d['signal']         = d['signal'];
		                d['rx packets']     = d['rx']['packets']; 
		                d['tx packets']     = d['tx']['packets']; 
		                d['rx bytes']       = d['rx']['bytes']; --We're not using 1500 (mtu since most packets might be smaller - mesh managment packets)
		                d['tx bytes']       = d['tx']['bytes']; --We're not using 1500 (mtu since most packets might be smaller - mesh managment packets)
		                d['tx bitrate']     = self._toM(self,d['tx']['rate']);
		                d['rx bitrate']     = self._toM(self,d['rx']['rate']);
		                d['vlan']           = p;
		                --print("TX BITRATE "..d['tx bitrate']);
		                --print("RX BITRATE "..d['rx bitrate']);    
			            table.insert(i_info['stations'],d); 
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
