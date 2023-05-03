#!/usr/bin/lua
-- Include libraries
package.path = "../libs/?.lua;./libs/?.lua;" .. package.path

require("rdAdvNftables");
local adv_nft   = rdAdvNftables();
local util      = require('luci.util');

function getMac(interface)
	interface = interface or "eth0"
	io.input("/sys/class/net/" .. interface .. "/address")
	t = io.read("*line")
	dashes, count = string.gsub(t, ":", "-")
	dashes = string.upper(dashes)
	return dashes
end

require('luci.http');
local uci 	= require("uci");
local x		= uci.cursor();
local id_if = x.get('meshdesk','settings','id_if');
local id	= getMac(id_if);
local proto = x.get('meshdesk','internet1','protocol');
local url   = 'cake4/rd_cake/firewalls/get-adv-config-for-node.json'
local server= x.get('meshdesk','internet1','ip');	
local http_port     = x.get('meshdesk','internet1','http_port');
local https_port    = x.get('meshdesk','internet1','https_port');
local port_string   = '/';
    
if(proto == 'http')then
    if(http_port ~= '80')then
        port_string = ":"..http_port.."/";
    end
end
    
if(proto == 'https')then
    if(https_port ~= '443')then
        port_string = ":"..https_port.."/";
    end
end

local query     = proto .. "://" .. server .. port_string .. url;

local q_s       = {}	
q_s['mac']      = id;
q_s['version']  = '22.03';
local enc_string= luci.http.build_querystring(q_s);
url = query..enc_string;

adv_nft:initConfig();
adv_nft:flushTable();
adv_nft:clearSets();

--local url       = 'http://192.168.8.165/cake4/rd_cake/firewalls/get-adv-config-for-node.json?gateway=true&_dc=1651070922&version=22.03&mac=64-64-4A-DD-07-FC'
local retval    = util.exec("curl -k '" .. url .."'");
local json      = require("json");
local tblConfig = json.decode(retval);

if(tblConfig.config_settings ~= nil)then

    if(tblConfig.config_settings.adv_firewall ~= nil)then           
        --add the sets
        if(tblConfig.config_settings.adv_firewall.sets)then
            for k in pairs(tblConfig.config_settings.adv_firewall.sets) do
                local set = tblConfig.config_settings.adv_firewall.sets[k];
                adv_nft:addSet(set);
            end
        end                
        --add the entries
        if(tblConfig.config_settings.adv_firewall.entries)then
            for a, entry in ipairs(tblConfig.config_settings.adv_firewall.entries) do
                adv_nft:addEntry(entry);          
            end        
        end  
    end
    
end

