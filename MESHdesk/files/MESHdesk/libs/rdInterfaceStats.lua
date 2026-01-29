-- SPDX-FileCopyrightText: 2025 Dirk van der Walt <dirkvanderwalt@gmail.com>
--
-- SPDX-License-Identifier: GPL-3.0-or-later

require( "class" )

-- 05 AUG 2025 --

-------------------------------------------------------------------------------
-- Class to manage nlbwmon ----------------------------------------------------
-------------------------------------------------------------------------------

--[[

=== Sample /etc/config/nlbwmon ===
=== We will just be working on the list -> "list local_network 'ex_zro'"... These item will come from meta_data.exits.stats flag

config nlbwmon
	# The buffer size for receiving netlink conntrack results, in bytes.
	# If the chosen size is too small, accounting information might get
	# lost, leading to skewed traffic counting results
	option netlink_buffer_size 524288

	# Interval at which the temporary in-memory database is committed to
	# the persistent database directory
	option commit_interval 24h

	# Interval at which traffic counters of still established connections
	# are refreshed from netlink information
	option refresh_interval 30s

	# Storage directory for the database files
	option database_directory /var/lib/nlbwmon

	# Amount of database generations to retain. If the limit is reached,
	# the oldest database files are deleted.
	option database_generations 10

	# Accounting period interval; may be either in the format YYYY-MM-DD/NN
	# to start a new accounting period exactly every NN days, beginning at
	# the given date, or a number specifiying the day of month at which to
	# start the next accounting period.
	#option database_interval '2017-01-17/14' # every 14 days, starting at Tue
	#option database_interval '-2' # second last day of month, e.g. 30th in March
	option database_interval '1' # first day of month (default)

	# The maximum amount of entries that should be put into the database,
	# setting the limit to 0 will allow databases to grow indefinitely.
	option database_limit 10000

	# Whether to preallocate the maximum possible database size in memory.
	# This is mainly useful for memory constrained systems which might not
	# be able to satisfy memory allocation after longer uptime periods.
	# Only effective in conjunction with database_limit, ignored otherwise.
	#option database_prealloc 0

	# Whether to gzip compress archive databases. Compressing the database
	# files makes accessing old data slightly slower but helps to reduce
	# storage requirements.
	#option database_compress 1

	# Protocol description file, used to distinguish traffic streams by
	# IP protocol number and port
	option protocol_database /usr/share/nlbwmon/protocols

	# List of local subnets. Only conntrack streams from or to any of these
	# subnets are counted. Logical interface names may be specified to
	# resolve the local subnets on the fly.
	#list local_network '192.168.0.0/16'
	#list local_network '172.16.0.0/12'
	#list local_network '10.0.0.0/8'
	#list local_network 'lan'
	list local_network 'ex_zro'
	
==== Sample JSON ===
==== We use the Meta Data -> exits ===

"meta_data": {
    "mode": "ap",
    "mac": "20-05-B6-FF-94-46",
    "ap_id": 133,
    "node_id": 133,
    "exits": [
        {
            "id": 199,
            "ap_profile_exit_id": 199,
            "type": "nat",
            "device": "br-ex_zro",
            "sqm": true,
            "interface": "ex_zro",
            "stats": true
        },
        {
            "id": 200,
            "ap_profile_exit_id": 200,
            "type": "nat",
            "device": "br-ex_one",
            "sqm": false,
            "interface": "ex_one",
            "stats": true
        }
    ],
    "zro0": 124,
    "one0": 125,
    "WbwActive": false,
    "QmiActive": false
},

--]]

class "rdInterfaceStats"

--Init function for object
function rdInterfaceStats:rdInterfaceStats()
    require('rdLogger');
	self.version 	= "1.0.1";
	self.tag	    = "MESHdesk";
	self.uci 		= require("uci");
	self.util       = require('luci.util');
	self.logger	    = rdLogger();
	self.debug	    = true
	self.json       = require('luci.json');
		
end
        
function rdInterfaceStats:getVersion()
	return self.version	
end

function rdInterfaceStats:configureFromJson(file)
	self:log("==Configure nlbwmon from JSON file "..file.."==")
	self:_configureFromJson(file)
end

function rdInterfaceStats:configureFromTable(tbl)
	self:log("==Configure nlbwmon from Lua table==")
	self:_configureFromTable(tbl)
end

function rdInterfaceStats:log(m,p)
	if(self.debug)then
		self.logger:log(m,p)
	end
end

--[[--
========================================================
=== Private functions start here =======================
========================================================
--]]--


function rdInterfaceStats._configureFromJson(self,json_file)

	self:log("Configuring nlbwmon from a JSON file");
	local contents 	= self:_readAll(json_file);
	local o			= self.json.decode(contents);
	if(o.meta_data ~= nil)then
		self:log("Found MetaData  - completing it");	
		self:_configureFromTable(o.meta_data);
	else
		self:log("No nlbwmon settings found, please check JSON file")
	end
end

function rdInterfaceStats:_configureFromTable(meta_data)
    local values_to_add = {}

    for _, exit in ipairs(meta_data.exits) do
        if exit.stats then
            table.insert(values_to_add, exit.interface)
        end
    end

    -- Only touch UCI if we actually have values
    if #values_to_add > 0 then
        local x = self.uci:cursor()

        x:foreach('nlbwmon', 'nlbwmon', function(a)
            local sid = a['.name']

            -- remove old entries
            x:delete('nlbwmon', sid, 'local_network')

            -- add new entries
            x:set('nlbwmon', sid, 'local_network', values_to_add)
        end)

        x:save('nlbwmon')
        x:commit('nlbwmon')

        self.util.exec("sysctl -w net.core.rmem_max=524288")
        self.util.exec("/etc/init.d/nlbwmon restart")
    end
end

function rdInterfaceStats._readAll(self,file)
	local f = io.open(file,"rb")
	local content = f:read("*all")
	f:close()
	return content
end
