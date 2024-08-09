#!/usr/bin/lua
-- SPDX-FileCopyrightText: 2024 Dirk van der Walt <dirkvanderwalt@gmail.com>
--
-- SPDX-License-Identifier: GPL-3.0-or-later


-- Include libraries
package.path = "../libs/?.lua;./libs/?.lua;" .. package.path

local uci   = require("uci");
local x     = uci.cursor();
local ssid;
local action = 'off';

function printUsage()
    print("--- Utility Script by MESHdesk used to turn a WiFi SSID on or off ----");
    print("Usage -> /etc/MESHdesk/utils/ssid_on_off.lua '<SSID>' ['on'|'off']");
    os.exit();
end


function MainPart()
    local set_disabled_state = 0;
    if(action == 'off')then
        set_disabled_state = 1; 
    end
    local state_changed = false;
    
    x:foreach("wireless", "wifi-iface", function(s)
        local ssid_match = false;
        local disabled   = 0;
        
        if(s.ssid == ssid)then
            if(tostring(s.disabled) ~= tostring(set_disabled_state))then
                state_changed = true
                print("Turning "..ssid.." to "..action); 
                print(s[".name"]);
                x.set("wireless",s[".name"],"disabled",set_disabled_state)
            end       
        end
        
    end)
    
    if(state_changed)then
        print("Reloading WiFi");
        x.commit('wireless');
        os.execute("/sbin/wifi");
    end
    
end

if(arg[1])then
    ssid = arg[1];
end

if(arg[2])then
    action = arg[2];
    if((action ~= 'on')and(action ~= 'off'))then
        printUsage();
    end
else
    printUsage();
end


print("Setting "..ssid.." to "..action );
mainPart();


