-- SPDX-FileCopyrightText: 2024 Dirk van der Walt <dirkvanderwalt@gmail.com>
--
-- SPDX-License-Identifier: GPL-3.0-or-later

require( "class" )

-- 25 JUL 2024 --

-------------------------------------------------------------------------------
-- Class to manage sqm items in /etc/config/sqm -------------------------------
-------------------------------------------------------------------------------

--[[

=== Section sample from /etc/config/sqm ===

config queue 'br_ex_vlan100'
	option enabled '1'
	option interface 'br-ex_vlan100'
	option download '4000'
	option upload '4000'
	option qdisc 'cake'
	option script 'piece_of_cake.qos'
	option linklayer 'none'
	option debug_logging '0'
	option verbosity '5'

--]]

class "rdSqm"

--Init function for object
function rdSqm:rdSqm()
    require('rdLogger');
	self.version 	= "1.0.1"
	self.tag	    = "MESHdesk"
	self.debug	    = false
	self.util       = require('luci.util'); --25Jul 2024 for posting command output
	self.nfs         = require('nixio.fs');
	self.json  		= require("json");
	self.mqtt_utils	= require("rdMqttUtils");
	self.sqm_config = '/etc/config/sqm';
	self.reportDir  = '/tmp/reports/';
	self.jSqm   	= self.reportDir..'jSqm.json';
		
end
        
function rdSqm:getVersion()
	return self.version	
end

function rdSqm:configureFromTable(tbl)
	self:_configureFromTable(tbl)
end

function rdSqm:getStatsTable()
	return self:_getStats()
end

function rdSqm:getStatsJson()
	return self:_getStats(true)
end


function rdSqm:log(m,p)
	if(self.debug)then
		self.logger:log(m,p)
	end
end

--[[--
========================================================
=== Private functions start here =======================
========================================================
--]]--

function rdSqm:_configureFromTable(sqm_entries)
    local file_contents = ""

    for _, sqm_entry in ipairs(sqm_entries) do
        if sqm_entry.interfaces then
            for _, interface in ipairs(sqm_entry.interfaces) do
                local s_name = interface:gsub("-", "_")
                file_contents = file_contents .. string.format("config queue '%s'\n", s_name)
                file_contents = file_contents .. string.format("\toption interface '%s'\n", interface)

                for key, val in pairs(sqm_entry.detail) do
                    file_contents = file_contents .. string.format("\toption %s '%s'\n", key, tostring(val))
                end

                self:log(string.format("Create entry for %s", interface))
                file_contents = file_contents .. "\n"
            end
        end
    end

    self.util.exec("/etc/init.d/sqm stop")
    self.nfs.unlink(self.sqm_config)
    self.nfs.writefile(self.sqm_config, file_contents)
    self.util.exec("/etc/init.d/sqm start")
end


function rdSqm:_getStats(doJson)
    doJson = doJson or false  -- Default value if isJson is missing

	
	local want_these 	= {'bytes', 'packets', 'drops', 'overlimits', 'backlog', 'qlen', 'memory_used'};
    local want_tins  	= {'peak_delay_us','avg_delay_us','base_delay_us','way_indirect_hits','way_misses'};
    local reply			= {};   
    local meta_data 	= self.mqtt_utils.getMetaData();
    local mode			= 'mesh';
    
    if meta_data and meta_data.mode then
    	mode = meta_data.mode
    end
               
   	if meta_data and meta_data.exits then
   		for _, exit in ipairs(meta_data.exits)do
   			local if_stats = exit;
   			
   			if (mode == 'ap')then
   				if_stats['ap_id'] = meta_data.ap_id;	
   			end		
   			if (mode == 'mesh') then
   				if_stats['node_id'] = meta_data.node_id;
   			end 			
            if(exit.sqm)then            	
            	--print(exit.device);
            	local retval = self.util.exec("tc -j -s qdisc show dev " .. exit.device);
				local tblSqm = self.json.decode(retval);
				for _, i in ipairs(tblSqm)do
					if(i.root)then -- Root table
						for _, wanted in ipairs(want_these)do
							if_stats[wanted] = i[wanted];
						end
					end
					if(i.tins)then
						for _, tin in ipairs(want_tins)do --We only use one tin (Traffic Isolation Nodes) in the MESHdesk implementation for now
							if_stats[tin] = i.tins[1][tin];
						end
					end
					--l_u.dumptable(i);
				end
				table.insert(reply,if_stats);
            end
                            
        end  
	end
	--print(self.json.encode(reply));
	if #reply > 0 then	
		reply = self:_addOrUpdate(reply);			
		if(doJson)then
			return self.json.encode(reply);
		end
		return reply;	
	end	
end


function rdSqm:_addOrUpdate(reply)

    -- Setup local variables for file paths
    local reportDir = self.reportDir
    local jSqm 		= self.jSqm

    -- Check if report directory exists
    local dirInfo = self.nfs.stat(reportDir)
    if not dirInfo or dirInfo.type ~= "dir" then
        self.nfs.mkdir(reportDir)
    end

    -- Check if JSON file exists
    local fileExists = self.nfs.stat(jSqm) ~= nil

    -- Add or update JSON file
    if not fileExists then
        self.nfs.writefile(jSqm, self.json.encode(reply))
        return reply; --No need to manipulate the reply
  	end
    
    
    -- Read and process existing data
    local oldData = self.json.decode(self.nfs.readfile(jSqm))
    self.nfs.writefile(jSqm, self.json.encode(reply))  -- Update file to latest

    -- Process data and calculate deltas
    local newData = {}
    local diffItems = {'bytes', 'packets', 'drops', 'overlimits'}
    local oldDataLookup = {}
    for _, oldItem in ipairs(oldData) do
        oldDataLookup[oldItem.id] = oldItem
    end

    for _, replyItem in ipairs(reply) do
        local oldItem = oldDataLookup[replyItem.id]
        if oldItem then
            --print("We have a match!")
            for _, k in ipairs(diffItems) do
                if replyItem[k] >= oldItem[k] then
                    replyItem[k] = replyItem[k] - oldItem[k]
                end
            end
        end
        table.insert(newData, replyItem)
    end

    return newData
    
    
end
