-- SPDX-FileCopyrightText: 2025 Dirk van der Walt <dirkvanderwalt@gmail.com>
--
-- SPDX-License-Identifier: GPL-3.0-or-later

require( "class" )

-- 15 AUG 2025 --

-------------------------------------------------------------------------------
-- Class to get stats from nlbwmon --------------------------------------------
-------------------------------------------------------------------------------

--[[
	
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

class "rdNlbwStats"

--Init function for object
function rdNlbwStats:rdNlbwStats()
    require('rdLogger');
	self.version 	= "1.0.1";
	self.tag	    = "MESHdesk";
	self.util       = require('luci.util');
	self.logger	    = rdLogger();
	self.debug	    = false;
	self.json       = require('luci.json');
	
	--Some variables
	self.cfg_file	= '/etc/MESHdesk/configs/current.json';
	self.pow2 		= {}; 
	for i=0,32 do self.pow2[i] = 2^i end
		
end
        
function rdNlbwStats:getVersion()
	return self.version	
end

function rdNlbwStats:jsonStats()
	self:log("== Produce nlbwmon stats as JSON ==")
	return self.json.encode(self:_tableStats());
end

function rdNlbwStats:tableStats()
	self:log("== Produce nlbwmon stats as a table ==")
	return self:_tableStats();
end

function rdNlbwStats:log(m,p)
	if(self.debug)then
		self.logger:log(m,p)
	end
end

--[[--
========================================================
=== Private functions start here =======================
========================================================
--]]--

function rdNlbwStats:_jsonStats()


end

function rdNlbwStats:_tableStats()

	local newdata = {}

	local stats 	= self:_getStatsInterfaces();
	local subnets	= self:_getSubnets();
	local nlbw 		= self:slurp("nlbw -c json 2>/dev/null");
	local ok, obj 	= pcall(self.json.decode, nlbw);
	if not ok or type(obj) ~= "table" or type(obj.data) ~= "table" then
	  --io.stderr:write("Failed to read nlbw JSON\n")
	  --os.exit(1)
	  return newdata; --Just return empty table to fail silently
	end

	-- Append columns: l3if,l3dev,device_id,exit_id,exit_type (device_id and exit_id is generic for both mesh and ap)
	obj.columns = obj.columns or {}
	table.insert(obj.columns, "l3if")
	table.insert(obj.columns, "l3dev")
	table.insert(obj.columns, "exit_id")
	table.insert(obj.columns, "exit_type")
	
	for _, row in ipairs(obj.data) do
		local ip 	= row[5];	
		local m  	= self:l3_by_ip(ip,subnets);		
		local l3if  = m and m.ifname or self.json.null;
		local l3dev = m and m.l3dev  or self.json.null;
		local ex 	= nil;

		--First try, if found don't do next one (stats.devices)
		if (l3if  and l3if  ~= self.json.null) then
			ex = stats.interfaces[l3if]; 
		end
		
		if (not ex and l3dev and l3dev ~= self.json.null) then
			ex = stats.devices[l3dev]; 
		end
				
		-- Only keep if matched an exit
		if ex then
			local exit_id = ex.ap_profile_exit_id or self.json.null					
			if(not exit_id)then --assume it is a mesh
				exit_id	= ex.mesh_exit_id or self.json.null;
			end
			local exit_type  = ex.type or self.json.null
			local newrow = { unpack(row) }
			table.insert(newrow, l3if);
			table.insert(newrow, l3dev);
			table.insert(newrow, exit_id);
			table.insert(newrow, exit_type);
			table.insert(newdata, newrow)
		end
	end		
	obj.data = newdata;
	--self.util.dumptable(obj);
	return obj;			
end


function rdNlbwStats:_getStatsInterfaces()
	local stats = {interfaces={},devices={}};
	do
	  local cfg = self:readfile(self.cfg_file);
	  if cfg and #cfg > 0 then
		local ok, obj = pcall(self.json.decode, cfg)
		if ok and obj and obj.meta_data then	
		  for _, exit in ipairs(obj.meta_data.exits or {}) do
		  	if exit.stats then
		  		if exit.interface then stats.interfaces[exit.interface] = exit 	end
		  		if exit.device    then stats.devices[exit.device] = exit 		end
		    end
		  end
		end
	  end
	end
    return stats;
end


function rdNlbwStats:_getSubnets()

	local subnets = {};
	local s = self:slurp("ubus call network.interface dump '{}' 2>/dev/null")
	local ok, obj = pcall(self.json.decode, s)
	if ok and obj and obj.interface then
		for _, ifo in ipairs(obj.interface) do
	  		local ifname = ifo.interface
	  		local l3dev  = ifo.l3_device or ifo.device or ifname
	  		for _, a in ipairs(ifo["ipv4-address"] or {}) do
				local net_u = self:ip_to_u32(a.address)
				local prefix = tonumber(a.mask or 0)
				if net_u and prefix and prefix>=0 and prefix<=32 then
		  			local key, block = self:subnet_key(net_u, prefix)
		  			table.insert(subnets, { ifname=ifname, l3dev=l3dev, key=key, block=block, prefix=prefix })
				end
	  		end
		end
	end
	--self.util.dumptable(subnets);
	return subnets;
	
end

function rdNlbwStats:ip_to_u32(ip)
  local a,b,c,d = ip:match("^(%d+)%.(%d+)%.(%d+)%.(%d+)$")
  if not a then return nil end
  return tonumber(a)*self.pow2[24] + tonumber(b)*self.pow2[16] + tonumber(c)*self.pow2[8] + tonumber(d)
end

function rdNlbwStats:subnet_key(u, prefix)
  local block = self.pow2[32 - prefix]
  return math.floor(u / block), block
end

function rdNlbwStats:l3_by_ip(ipstr,subnets)
  local u = self:ip_to_u32(ipstr)
  if not u then return nil end
  local best, bestp = nil, -1
  for _, s in ipairs(subnets) do
    local k = math.floor(u / s.block)
    if k == s.key and s.prefix > bestp then
      best, bestp = s, s.prefix
    end
  end
  return best
end

function rdNlbwStats:readfile(path)
  local f = io.open(path, "r");
  if not f then return nil end
  local s = f:read("*a"); f:close(); return s;
end

function rdNlbwStats:slurp(cmd)
  local f = io.popen(cmd); if not f then return "" end
  local s = f:read("*a") or ""; f:close(); return s
end


