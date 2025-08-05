-- SPDX-FileCopyrightText: 2024 Dirk van der Walt <dirkvanderwalt@gmail.com>
--
-- SPDX-License-Identifier: GPL-3.0-or-later

require( "class" )

-- 22 OCT 2024 --

-------------------------------------------------------------------------------
-- Class to manage mwan3 items in /etc/config/mwan3 ---------------------------
-- and /etc/config/network and /etc/config/wireless ---------------------------
-------------------------------------------------------------------------------

class "rdMwan";

--Init function for object
function rdMwan:rdMwan()
    require('rdLogger');   
    self.uci 		= require("uci");
    self.logger		= rdLogger()
	self.version 	= "1.0.1"
	self.tag	    = "MESHdesk"
	self.debug	    = true
	self.util       = require('luci.util'); 
	self.nfs        = require('nixio.fs');
	self.json  		= require("json");
	self.mqtt_utils	= require("rdMqttUtils");
	self.mwan3_config = '/etc/config/mwan3';	
end
        
function rdMwan:getVersion()
	return self.version	
end

function rdMwan:getVersion()
	return self.version	
end

function rdMwan:startMwan()
	return self:_startMwan()
end


function rdMwan:configureFromJson(file)
	self:log("==Configure mwan3 from JSON file "..file.."==")
	self:_configureFromJson(file)
end

function rdMwan:configureFromTable(tbl)
	self:log("==Configure mwan3 from  Lua table==")
	self:_configureFromTable(tbl)
end

function rdMwan:log(m,p)
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


function rdMwan:_startMwan()
	self:log("=======Start MWAN======")
	--First we will check if the /etc/config/network file is differenct from the /etc/config/mwan_network
	--if it is; we will copy it over and restart the network--
	
	local old_file = 'network'
	local new_file = 'mwan_network'
	
	if(self.nfs.stat('/etc/config/'..new_file) == nil)then
		return nil; --No /etc/config/mwan_netowrk present; return false
	end
	
	local old_filepath = "/etc/config/" .. old_file
	local new_filepath = "/etc/config/" .. new_file

	-- Get the MD5 checksums of the old and new files
	local md5sum_old = self:get_md5sum(old_filepath)
	local md5sum_new = self:get_md5sum(new_filepath)

	-- Compare the MD5 checksums
	if md5sum_old ~= md5sum_new then
	    self.util.exec("cp " .. new_filepath .. " " .. old_filepath)  
	    self.util.exec("/etc/init.d/network restart")
	end
	
	self:_startMwanWifi()
	return true;	
end

function rdMwan:_startMwanWifi()
	--Check if there is a mwan WiFi entry
	--For it we start with a clean wifi config and append the mwan entries to it
	local wifi   = '/etc/config/mwan_wireless'
	if(self.nfs.stat(wifi) ~= nil)then
	    require("rdWireless");
	    local w = rdWireless();
	    w:newWireless();
	    --Append the wifi file and restart wifi
	    self.util.exec("cat "..wifi.." >> /etc/config/wireless");
	    
	    --Enable the radio--  
	    local x = self.uci:cursor();
	    x:foreach('mwan_wireless','wifi-iface', function(a)
	    
			local device = a['device'];
			x:set('wireless',device,'disabled','0') --Enable the specified radio also
			x:save('wireless');
	        x:commit('wireless');
	        
		end)
		
		self.util.exec("wifi");	    
	end	
end


function rdMwan:_configureFromJson(json_file)
	self:log("Configuring mwan3 from a JSON file")
	local contents 	= self.nfs.readfile(json_file)
	local o			= self.json.decode(contents)
	if o.config_settings and o.config_settings.mwan then
		self:log("Found MWAN settings - completing it")
		self:_configureFromTable(o.config_settings.mwan)
	else
		self:log("Found NO MWAN settings - exit")
	end
end

function rdMwan:_configureFromTable(mwan)

	if mwan.wireless then
		self:log("Found Wireless MWAN Process it")
		self:_doMwanWireless(mwan.wireless);
	else
		--FIXME Remove any left ower wireless files if there might be (/etc/config/mwan_wireless)	
	end
	if mwan.network then
		self:log("Found Network MWAN Process it");
		self:_doMwanNetwork(mwan.network);	
	end
	
	if mwan.firewall then
		self:log("Found MWAN Firewall entries");
		self:_doMwanFirewall(mwan.firewall);	
	end
	
	if mwan.mwan3 then
		self:log("Found mwan3 configs");
		self:_doMwan3(mwan.mwan3);
	end
	
	-- Aug 2025 -- **Restart regardless** -> We had startup routing issues on APdesk and removing this made it rock solid
	--if mwan.mode then
	--	if(mwan.mode == 'mesh')then
			self.util.exec("/etc/init.d/mwan3 restart"); --When doing Batman-adv mesh we need to restart the mwan3 service afterwards
	--	end
	--end
		
end

function rdMwan:_doMwanFirewall(tbl)
	-- First we look for existing firewall entries starting with 'mw' and make a list of them
	-- Then we compare them with this list of interfaces (tbl) --
	-- If there are existing ones not in the current list; we remove them --
	-- Then we add the new ones --
	-- Then we add forwarding rules --

	local x = self.uci:cursor();
	local existing_fw_items = {}
	local exit_points = tbl.forwarding;

	-- Collect existing firewall items that start with 'mw'
	x:foreach('firewall','zone', function(a)    
		if a['name']:sub(1, 2) == 'mw' then  -- Check if it starts with 'mw'
			table.insert(existing_fw_items, {name = a['name'], uci_name = a['.name']})
		end
	end)

	-- 1. Remove items that are in existing_fw_items but not in tbl.masq_zones
	for _, existing_fw in ipairs(existing_fw_items) do
		local found = false
		for _, fw_item in ipairs(tbl.masq_zones) do
			if fw_item == existing_fw['name'] then
				found = true
				break
			end
		end
		if not found then
			x:delete('firewall', existing_fw['uci_name'])
			--Also delete any forwarding rules--
			x:foreach('firewall','forwarding', function(b) 
				if(b['dest'] == existing_fw['name'])then
					x:delete('firewall', b['.name'])	
				end			
			end)			
		end
	end
		
	-- 2. Add items that are in tbl but not in existing_fw_items
	for _, fw_item in ipairs(tbl.masq_zones) do
		local found = false
		for _, existing_fw in ipairs(existing_fw_items) do
			if fw_item == existing_fw['name'] then
				found = true
				break
			end
		end
		if not found then
			-- Here you would add the firewall entry
			local zone_name = x:add('firewall','zone')
		    x:set('firewall',zone_name,'name', fw_item)	
		    x:set('firewall',zone_name,'network', fw_item)	
		    x:set('firewall',zone_name,'input',	'ACCEPT')	
		    x:set('firewall',zone_name,'output','ACCEPT')	
		    x:set('firewall',zone_name,'forward','ACCEPT')
		    x:set('firewall',zone_name,'masq',	1)
		    x:set('firewall',zone_name,'mtu_fix',	1)		        		    
		end
		
		-- 3 Add forwarding rules for this zone for each ex_ zone --
		for _, exit_point in ipairs(exit_points) do
			local fw_found = false;
			x:foreach('firewall','forwarding', function(b) 
				if ((b['dest'] == fw_item) and (b['src'] == exit_point)) then
					fw_found = true	
				end			
			end)
			if not fw_found then
				local forwarding_name = x:add('firewall',	'forwarding')
				x:set('firewall',forwarding_name,'src', 	exit_point)	
				x:set('firewall',forwarding_name,'dest', 	fw_item)					
			end	
		end						
	end
		
	-- Finally, commit the changes if you have any additions/removals
	x:save('firewall')
	x:commit('firewall')
	self.util.exec("/etc/init.d/firewall reload")	
end


function rdMwan:_doMwanWireless(tbl)

	local old_file = 'mwan_wireless'
	local new_file = 'mwan_wireless_new'
	local config   = old_file
	local existing = false
	
	if(self.nfs.stat('/etc/config/'..old_file) ~= nil)then
		config   = new_file
		existing = true
	end

	self.util.exec("touch /etc/config/"..config)
	
	local x = self.uci:cursor();

    for i, setting_entry in ipairs(tbl) do
		local entry_type
		local entry_name
		local options 	= {}
		local lists	= {}
		for key, val in pairs(setting_entry) do
			if((key == 'wifi-iface') or (key == 'wifi-device'))then
				entry_type = key
				entry_name = val
			else
				-- Run through all the options
				if(key == 'options')then
					options = val
				end
				-- Run through all the lists
				if(key == 'lists')then
					lists = val
				end
			end
		end
		
		x:set(config,entry_name,entry_type)
		
		local l	= {}
		for i, list in ipairs(lists) do
			local list_item = list['name']
			local value	= list['value']
			if(l[list_item] == nil)then
				l[list_item] = {}
			end
			table.insert(l[list_item], value)			
		end
		for key, val in pairs(l) do
			x:set(config,entry_name,key, val)
		end
		
		for key, val in pairs(options) do
			local t = type(val);
			if(t == 'boolean')then
				local bool_val = "0"
				if(val)then
					bool_val = "1"
				end
				x:set(config,entry_name,key,bool_val)
			else
				x:set(config,entry_name,key,val)
			end
		end
	end
	x:commit(config)
	
	--It existing, compare the two and if different replace the old one else delete the new one (since it is the same)
	if( existing )then
		print("Existing file found, comparing checksums...")    
		local old_filepath = "/etc/config/" .. old_file
		local new_filepath = "/etc/config/" .. new_file

		-- Get the MD5 checksums of the old and new files
		local md5sum_old = self:get_md5sum(old_filepath)
		local md5sum_new = self:get_md5sum(new_filepath)

		-- Compare the MD5 checksums
		if md5sum_old == md5sum_new then
		    self.util.exec("rm " .. new_filepath)  -- Remove the new file since it's identical
		else
		    self.util.exec("mv " .. new_filepath .. " " .. old_filepath)  -- Replace the old file
		end
	end	
end


function rdMwan:_doMwanNetwork(table)

	local old_file = 'mwan_network'
	local new_file = 'mwan_network_new'
	local config   = old_file
	local existing = false
	
	if(self.nfs.stat('/etc/config/'..old_file) ~= nil)then
		config   = new_file
		existing = true
	end
	
	self.util.exec("touch /etc/config/"..config)
	
	local x = self.uci:cursor();
                                                          
	for i, setting_entry in ipairs(table) do                                 
		local entry_type                                                 
	    local entry_name                                                  
	    local options = {} -- New empty array for this entry
	    local lists   = {};
		for key, val in pairs(setting_entry) do                           
        	-- If it is not an options entry; it is a type with value
            if((key ~= 'options') and (key ~= 'lists'))then                                                      
            	entry_type  = key                                                
                entry_name  = val                                                
         	else                                                                                                   
                -- Run through all the options
                if(key == 'options')then
                    for ko, vo in pairs(val) do                                                                  
                        options[ko] = vo                                                                     
                    end
                end
                if(key == 'lists')then
                    for kl, vl in pairs(val) do                                                                  
                        lists[kl] = vl                                                                     
                    end
                end                 	                                                                                            
            end                                                                                                    
    	end

    	if(entry_type == 'device')then --device is anonymous
    	    entry_name = x:add(config, 'device');
        else
            x:set(config, entry_name, entry_type);  
    	end  	
        x:commit(config)     
        --Set all the options       
    	for key, val in pairs(options) do
            --print("There " .. key .. ' and '.. val)          
            x:set(config, entry_name,key, val);
            x:commit(config)           
        end
        
        --Set all the lists
        for key, val in pairs(lists) do       
            x:set(config, entry_name,key, val);
            x:commit(config)           
        end    
    end
    
    --It existing, compare the two and if different replace the old one else delete the new one (since it is the same)
	if( existing )then
		print("Existing file found, comparing checksums...")    
		local old_filepath = "/etc/config/" .. old_file
		local new_filepath = "/etc/config/" .. new_file

		-- Get the MD5 checksums of the old and new files
		local md5sum_old = self:get_md5sum(old_filepath)
		local md5sum_new = self:get_md5sum(new_filepath)

		-- Compare the MD5 checksums
		if md5sum_old == md5sum_new then
		    self.util.exec("rm " .. new_filepath)  -- Remove the new file since it's identical
		else
		    self.util.exec("mv " .. new_filepath .. " " .. old_filepath)  -- Replace the old file
		end
	end	          
end

function rdMwan:_doMwan3(table)
	local old_file = 'mwan3'
	local new_file = 'mwan3_new'
	local config   = old_file
	local existing = false
	
	if(self.nfs.stat('/etc/config/'..old_file) ~= nil)then
		config   = new_file
		existing = true
	end
	
	self.util.exec("touch /etc/config/"..config)
	
	local x = self.uci:cursor();
	                                                        
	for i, setting_entry in ipairs(table) do                                 
		local entry_type                                                 
	    local entry_name                                                  
	    local options = {} -- New empty array for this entry
	    local lists   = {};
		for key, val in pairs(setting_entry) do                           
        	-- If it is not an options entry; it is a type with value
            if((key ~= 'options') and (key ~= 'lists'))then                                                      
            	entry_type  = key                                                
                entry_name  = val                                                
         	else                                                                                                   
                -- Run through all the options
                if(key == 'options')then
                    for ko, vo in pairs(val) do                                                                  
                        options[ko] = vo                                                                     
                    end
                end
                if(key == 'lists')then
                    for kl, vl in pairs(val) do                                                                  
                        lists[kl] = vl                                                                     
                    end
                end                 	                                                                                            
            end                                                                                                    
    	end

        x:set(config, entry_name, entry_type);   	
        x:commit(config)     
        --Set all the options       
    	for key, val in pairs(options) do
            --print("There " .. key .. ' and '.. val)          
            x:set(config, entry_name,key, val);
            x:commit(config)           
        end
        
        --Set all the lists
        for key, val in pairs(lists) do       
            x:set(config, entry_name,key, val);
            x:commit(config)           
        end    
    end
    
    --It existing, compare the two and if different replace the old one else delete the new one (since it is the same)
	if( existing )then
		print("Existing file found, comparing checksums...")    
		local old_filepath = "/etc/config/" .. old_file
		local new_filepath = "/etc/config/" .. new_file

		-- Get the MD5 checksums of the old and new files
		local md5sum_old = self:get_md5sum(old_filepath)
		local md5sum_new = self:get_md5sum(new_filepath)

		-- Compare the MD5 checksums
		if md5sum_old == md5sum_new then
		    self.util.exec("rm " .. new_filepath)  -- Remove the new file since it's identical	    
		else
		    self.util.exec("mv " .. new_filepath .. " " .. old_filepath)  -- Replace the old file
		    self.util.exec("/etc/init.d/mwan3 restart")
		end
	else
		self.util.exec("/etc/init.d/mwan3 restart")	
	end	          
end

function rdMwan:get_md5sum(filepath)
    local result = self.util.exec("md5sum " .. filepath)
    return string.match(result, "^%w+")  -- Extract the MD5 hash
end

