#!/usr/bin/lua


-- Include libraries
package.path = "libs/?.lua;" .. package.path;

local uci 	    = require("uci");
local json	    = require('luci.json');
local fs        = require('nixio.fs');
local x         = uci.cursor("/etc/MESHdesk/configs")
local wan_n     = '/etc/MESHdesk/configs/wan_network';
local captive   = '/etc/MESHdesk/configs/captive_config.json';
local board     = '/etc/board.json';


function setMacOnWan(mac)
    local wan_missing = true;  
    x:foreach("wan_network", "device", function(s)
        if(s['name'] == id_if)then
            wan_missing = false;
            if(s['macaddr'] ~= nil)then
                if(s['macaddr'] ~= mac)then
                    print("Update MAC Address To "..mac);
                    x:set("wan_network", s[".name"], "macaddr", mac);
                    x:commit("wan_network");    
                end
            end
            return false;
        end
        return true;
    end)
    
    if(wan_missing)then
        print("Missing "..id_if.." device - add one");
        x:set("wan_network", "wan", "device");
        x:commit("wan_network");
        x:set("wan_network", "wan", "name", "wan");
        x:set("wan_network", "wan", "macaddr", mac);
        x:commit("wan_network"); 
    end   
end

function setMacOnCaptive(mac)
    local strCpConfig   = fs.readfile(captive);
    local tblCpConfig   = json.decode(strCpConfig);
    local wan_missing   = true;
    
    --Network adjustments--
    if(tblCpConfig.config_settings.network ~= nil)then
        for k,v in pairs(tblCpConfig.config_settings.network) do
            for key,val in pairs(v)do
                --Do the Channel adjustment if needed
                if(key == 'device')then
                    if(val == id_if)then
                        wan_missing = false;
                        if(tblCpConfig.config_settings.network[k].options.macaddr ~= mac)then
                            print("Update CP MAC Address To "..mac);
                            tblCpConfig.config_settings.network[k].options.macaddr = mac;
                            --Commit the changes
                            local strNewCpConf = json.encode(tblCpConfig);
                            fs.writefile(captive,strNewCpConf);
                        end
                    end
                end
            end
        end    
    end
    
    if(wan_missing)then
        print("Add WAN Device to CP");
        local device        = {};
        device['device']    = id_if;
        device['options']   = {};
        device['options']['name']       = id_if;
        device['options']['macaddr']    = mac;
        table.insert(tblCpConfig.config_settings.network,device);
        --Commit the changes
        local strNewCpConf = json.encode(tblCpConfig);
        fs.writefile(captive,strNewCpConf);            
    end
end


--Get the id_if name (NEEDS GLOBAL SCOPE)
id_if     = x.get('meshdesk','settings','id_if');
print("ID IF IS "..id_if);

local contents      = fs.readfile(board);         
local o             = json.decode(contents); 

if(o.network ~= nil)then
    if(o.network[id_if] ~= nil)then
        if(o.network[id_if]['macaddr'] ~=nil)then
            local macaddr = o.network[id_if]['macaddr'];
            setMacOnWan(macaddr);
            setMacOnCaptive(macaddr);
        end
    else
        print(id_if.." Not found in board.json - Assuming old style config");
    end
end 
