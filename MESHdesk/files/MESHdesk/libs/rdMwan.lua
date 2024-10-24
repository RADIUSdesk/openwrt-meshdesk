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
	end
	if mwan.network then
		self:log("Found Network MWAN Process it")
		self:_doMwanNetwork(mwan.network);	
	end
	
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

function rdMwan:get_md5sum(filepath)
    local result = self.util.exec("md5sum " .. filepath)
    return string.match(result, "^%w+")  -- Extract the MD5 hash
end

