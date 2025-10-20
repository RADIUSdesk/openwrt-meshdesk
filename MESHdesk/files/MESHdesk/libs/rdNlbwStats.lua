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
			if(newrow[11] == nil)then
				newrow[11] = 'other'; --other proto = IP and layer7 = nill so we mark it as 'other' else the further inserts gets skewed
			end
			table.insert(newrow, l3if);
			table.insert(newrow, l3dev);
			table.insert(newrow, exit_id);
			table.insert(newrow, exit_type);
			table.insert(newdata, newrow)
		end
	end		
	-- Convert totals -> deltas on-device
	-- (emit first baseline once, then only positive deltas; skip zero slices)
	obj.data = newdata;
	obj.data = self:_computeDeltas(obj.data, {
		skip_zero = true,
		first_emit_baseline = true
	})
	------self.util.dumptable(obj);
	return obj
				
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

-- ======================================================--
-- ========= ADDITION TO REPORT DELTAS ==================--
-- ======================================================--

function rdNlbwStats:_statePath()
    return "/tmp/nlbw_state.json"
end

function rdNlbwStats:_loadState()
    local path = self:_statePath()
    local f = io.open(path, "r")
    if not f then return {} end
    local s = f:read("*a"); f:close()
    if not s or #s == 0 then return {} end
    local ok, t = pcall(self.json.decode, s)
    return (ok and t) or {}
end

function rdNlbwStats:_atomicWrite(path, contents)
    local tmp = path .. ".tmp"
    local f = assert(io.open(tmp, "w"))
    f:write(contents)
    f:flush(); f:close()
    os.rename(tmp, path)  -- atomic on same FS
end

function rdNlbwStats:_saveState(tbl)
    local path = self:_statePath()
    local s = self.json.encode(tbl)
    self:_atomicWrite(path, s)
end

function rdNlbwStats:_key(row)
    -- row indices from your code (after enrich):
    --  1:family, 2:proto, 3:port, 4:mac, 5:ip, 16:exit_id, 12:layer7
    local function S(v) return v and tostring(v) or "" end
    return table.concat({
        S(row[1]), S(row[2]), S(row[3]), S(row[4]), S(row[5]),
        S(row[16]), S(row[12])
    }, "|")
end

local function toint(v)
    if type(v) == "number" then return v end
    if type(v) == "string" then return tonumber(v) or 0 end
    return 0
end

-- data: array of rows (totals) with your enriched columns
-- opts:
-- skip_zero = true  -- drop rows where all counters + conns delta == 0
-- first_emit_baseline = true -- on first sighting, emit the current totals as a "delta"
function rdNlbwStats:_computeDeltas(data, opts)
    opts = opts or {}
    local skip_zero = (opts.skip_zero ~= false)    -- default true
    local first_emit_baseline = (opts.first_emit_baseline ~= false) -- default true

    local state = self:_loadState()
    local out = {}

    for _, r in ipairs(data) do
        local key = self:_key(r)
        local prev = state[key]

        -- Indices from your nlbw format:
        local rx_b = toint(r[7])   -- rx_bytes
        local rx_p = toint(r[8])   -- rx_pkts
        local tx_b = toint(r[9])   -- tx_bytes
        local tx_p = toint(r[10])  -- tx_pkts
        local cns  = toint(r[6])   -- conns

        local d_rx_b, d_rx_p, d_tx_b, d_tx_p, d_cns

        if not prev then
            if first_emit_baseline then
                d_rx_b, d_rx_p, d_tx_b, d_tx_p, d_cns = rx_b, rx_p, tx_b, tx_p, cns
            else
                d_rx_b, d_rx_p, d_tx_b, d_tx_p, d_cns = 0, 0, 0, 0, 0
            end
        else
            -- Reset if any counter decreased vs stored cumulative
            local reset = (rx_b < prev.rx_bytes) or (rx_p < prev.rx_pkts)
                       or (tx_b < prev.tx_bytes) or (tx_p < prev.tx_pkts)
                       or (cns  < prev.conns)

            if reset then
                d_rx_b, d_rx_p, d_tx_b, d_tx_p, d_cns = rx_b, rx_p, tx_b, tx_p, cns
            else
                d_rx_b = rx_b - prev.rx_bytes
                d_rx_p = rx_p - prev.rx_pkts
                d_tx_b = tx_b - prev.tx_bytes
                d_tx_p = tx_p - prev.tx_pkts
                d_cns  = cns  - prev.conns
            end
        end

        local changed = (d_rx_b > 0) or (d_rx_p > 0) or (d_tx_b > 0) or (d_tx_p > 0) or (d_cns > 0)

        if changed or not skip_zero then
            -- emit a row in the same shape but with deltas replacing totals
            local newrow = { unpack(r) }
            newrow[7]  = d_rx_b
            newrow[8]  = d_rx_p
            newrow[9]  = d_tx_b
            newrow[10] = d_tx_p
            newrow[6]  = d_cns
            table.insert(out, newrow)
        end

        -- Update cumulative state for next run
        state[key] = {
            rx_bytes = rx_b, rx_pkts = rx_p,
            tx_bytes = tx_b, tx_pkts = tx_p,
            conns    = cns
        }
    end
    self:_saveState(state)
    return out
end
