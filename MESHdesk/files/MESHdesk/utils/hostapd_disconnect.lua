#!/usr/bin/lua
-- SPDX-FileCopyrightText: 2024 Dirk van der Walt <dirkvanderwalt@gmail.com>
--
-- SPDX-License-Identifier: GPL-3.0-or-later

-- Include libraries
package.path = "../libs/?.lua;./libs/?.lua;/etc/MESHdesk/libs/" .. package.path

local json  = require("json");
local utils = require("rdMqttUtils");
local l_u   = require('luci.util'); 
local mac;
local entry_id;


function printUsage()
    print("--- Utility Script by MESHdesk used to disconnect a station connected to hostapd ----");
    print("Usage -> /etc/MESHdesk/utils/hostapd_disconnect.lua '0C-C6-FD-7B-8B-AA' 'm_hosta_40_57_0_146'");
    os.exit();
end


function mainPart()
    local meta_data = utils.getMetaData();   
    if meta_data == nil then
        print("This node does not have any Meta Data in its config")
    else
        for key, value in pairs(meta_data)do
            if(tonumber(value) ==  tonumber(entry_id))then
                mac    = string.lower(string.gsub(mac,'-',':'));
                --ubus call hostapd.two0 del_client "{'addr':'0c:c6:fd:7b:8b:aa', 'reason':5, 'deauth':true, 'ban_time':0}"
                --Ban for 10 seconds to ensure a new session ID is sent to RADIUS
                local command = "ubus call hostapd."..key.." del_client \"{'addr':'"..mac.."', 'reason':5, 'deauth':true, 'ban_time':10000}\"";
                l_u.exec(command);
                --print(command);
            end           
        end
    end    
end

if(arg[1])then
    mac = arg[1];
end

if(arg[2])then
    entry_id = arg[2];
else
    printUsage();
end


mainPart();

