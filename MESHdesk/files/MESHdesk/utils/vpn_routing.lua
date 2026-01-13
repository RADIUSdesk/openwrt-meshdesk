#!/usr/bin/lua

-- SPDX-FileCopyrightText: 2026 Dirk van der Walt <dirkvanderwalt@gmail.com>
--
-- SPDX-License-Identifier: GPL-3.0-or-later

local nixio = require('nixio');
local util  = require('luci.util');
local json  = require('luci.json');
local fs    = require('nixio.fs');
local conf  = '/etc/MESHdesk/configs/current.json';

local tbl   = 110; --Start table number. Each VPN entry will have a unique table number
local rule  = 10010; --Start with priority
local o     = nill;


-- Convert dotted netmask to CIDR length
function netmask_to_cidr(netmask)
    local cidr = 0
    for octet in netmask:gmatch("(%d+)") do
        octet = tonumber(octet)
        while octet > 0 do
            cidr = cidr + (octet % 2)
            octet = math.floor(octet / 2)
        end
    end
    return cidr
end

-- Compute network address from IP and netmask
local function network_from_gateway(gateway, netmask)
    local ip = {}
    local mask = {}

    for o in gateway:gmatch("(%d+)") do
        ip[#ip + 1] = tonumber(o)
    end

    for o in netmask:gmatch("(%d+)") do
        mask[#mask + 1] = tonumber(o)
    end

    local network = {}
    for i = 1, 4 do
        network[i] = ip[i] - (ip[i] % (256 - mask[i]))
    end

    local cidr = netmask_to_cidr(netmask)

    return string.format(
        "%d.%d.%d.%d/%d",
        network[1], network[2], network[3], network[4], cidr
    )
end

function add_routing(table_number,vpn)

    print("Table Number is "..table_number);
    print("VPN Type is "..vpn.type);
    for _, exit_id in ipairs(vpn.routing.exit_points) do
        print(exit_id);
        if(vpn.type == 'zt')then
            add_exit_route(table_number,exit_id,vpn.type,vpn.ifname)  
        else
        	add_exit_route(table_number,exit_id,vpn.type,vpn.interface)
        end
    end
end


function add_exit_route(table_number,exit_id,vpn_type,vpn_interface)

    for _,exit in ipairs(o.meta_data.exits) do
        if(exit_id == exit.id)then
            local cidr = network_from_gateway(exit.ipaddr,exit.netmask);
            os.execute('ip route replace '..cidr..' dev '..exit.device..' table '..table_number);
            os.execute('ip route replace default dev '..vpn_interface..' table '..table_number);
            os.execute('ip rule add from '..cidr..' lookup '..table_number..' priority '..rule..' 2>/dev/null');
            os.execute('ip route show table '..table_number);
            os.execute('ip rule show');
            rule = rule + 1;       
        end   
    end
    
end

function check_for_vpn(int,action)

    local contents 	= fs.readfile(conf);
	o = json.decode(contents);
		
	if o.meta_data and o.meta_data.vpns then
	    print("Found VPNs");
	    for _, vpn in ipairs(o.meta_data.vpns) do
	        local loop_iface = vpn.interface	   
	        if(loop_iface == int)then --Get matches for the interface
	            if(action == 'ifup')then
	                add_routing(tbl,vpn);
	            end
	       end	
	       tbl = tbl + 1;
	              
	    end
	end
end


function interface_action()
	local act=nixio.getenv("ACTION");
	local int=nixio.getenv("INTERFACE");
	local dev=nixio.getenv("DEVICE");
		
	--dev="xfrm01";
	--int="xfrm01";
	--act="ifup";
	
	if string.find(int, "^xfrm") or --Filter for only VPN type of interfaces
       string.find(int, "^ovpn") or 
       string.find(int, "^zt") or 
       string.find(int, "^wg") then
        check_for_vpn(int,act);
    end
	os.execute('logger -p user.info -t MESHdeskVPN "LUA Interface '..int..' Action '..act..' Device '..dev..'"');	
end

interface_action()

