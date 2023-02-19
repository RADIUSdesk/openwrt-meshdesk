#!/usr/bin/lua
-- Include libraries
package.path = "../libs/?.lua;./libs/?.lua;" .. package.path

require("rdNftables");

local nft   = rdNftables();
local mac;
local action = 'off'; --default is to block
local util   = require('luci.util'); --26Nov 2020 for posting command output
local chains = {'input', 'forward', 'output'}
local bw_up;
local bw_down;

function printUsage()
    print("--- Utility Script by MESHdesk used to manage MAC Addresses on the **bridge meshdesk** table ----");
    print("Usage -> /etc/MESHdesk/utils/nft_setter.lua '<MAC>' ['clear'|'on'|'off'|'bw' (bw in kBps)]");
    os.exit();
end

function initialConfig()
    nft:initConfig();
end

function macOn(m)
    nft:macOn(m);  
end

function macOff(m)
    nft:macOff(m);
end

function macLimit(m)
    nft:macLimit(m,bw_up,bw_down);    
end

function mainPart()
    initialConfig();
    if(action == 'clear')then
        nft:flushTable();
    end
    
    if(action == 'on')then
        macOn(mac)
    end
    
    if(action == 'off')then
        macOn(mac);--Clear rules first
        macOff(mac);
    end
    
    if(action == 'bw')then
        macOn(mac)
        macLimit(mac)
    end
          
end


--Get the MAC Address
if(arg[1])then
    mac = arg[1];
end

if(arg[2])then
    action = arg[2];
    if((action ~= 'clear')and(action ~= 'on')and(action ~= 'off')and(action ~= 'bw'))then
        printUsage();
    end
    if(action == 'bw')then
        if((not (arg[3]))or(not (arg[4])))then
            printUsage();
        else
            bw_up = arg[3];
            bw_down = arg[4];
        end
    end
else
    printUsage();
end


print("Setting "..mac.." to "..action );
nft:initConfig();
nft:flushTable();

local url       = 'http://192.168.8.165/cake4/rd_cake/firewalls/get-config-for-node.json?gateway=true&_dc=1651070922&version=22.03&mac=64-64-4A-DD-07-FC'
local retval    = util.exec("curl -k '" .. url .."'");
local json      = require("json");
local tblConfig = json.decode(retval);

if(tblConfig.config_settings ~= nil)then
    if(tblConfig.config_settings.firewall ~= nil)then
        for a, rule in ipairs(tblConfig.config_settings.firewall) do
            local mac   = rule.mac
            print(mac);
            if(rule.action == 'block')then
                nft:macOff(mac);
            end
            if(rule.action == 'limit')then
                nft:macLimit(mac,rule.bw_up,rule.bw_down)
            end
        end    
    end
end

--print("Output Start");
--print(retval);
--print("Output END");
--mainPart();

