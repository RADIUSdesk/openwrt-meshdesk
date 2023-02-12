#!/usr/bin/lua
-- Include libraries
package.path = "../libs/?.lua;./libs/?.lua;" .. package.path


local mac;
local action = 'off'; --default is to block
local util   = require('luci.util'); --26Nov 2020 for posting command output
local chains = {'input', 'forward', 'output'}
local bw_up;
local bw_down;

function printUsage()
    print("--- Utility Script by MESHdesk used to manage MAC Addresses on the **bridge meshdesk** table ----");
    print("Usage -> /etc/MESHdesk/utils/nft_setter.lua '<MAC>' ['on'|'off'|'bw' (bw in kBps)]");
    os.exit();
end


function initialConfig()

    local i  = util.execi("nft list table bridge meshdesk 2>&1"); --Important to direct stderror also to stdout :-)
    local table_missing = false;
    if(i)then
        for line in i do
             if(string.match(line,"^Error: No such file or directory") ~= nil)then
                table_missing = true;
                break
            end
        end
    end
    if(table_missing)then
        print("Table missing add it");    
        util.exec("nft add table bridge meshdesk")
        util.exec("nft add chain bridge meshdesk forward '{type filter hook forward priority 0; }'");
        util.exec("nft add chain bridge meshdesk input '{type filter hook input priority 0; }'");
        util.exec("nft add chain bridge meshdesk output '{type filter hook output priority 0; }'");
    else
        print("Table already there");    
    end
end


function macOn(m)
    print("Clear Block on MAC "..m);   
    for i, chain in ipairs(chains) do
        print ('Clear rules in chain '..chain..' of mac '..m)      
        local i  = util.execi("nft -e -a list chain bridge meshdesk "..chain);
        if(i)then
            for line in i do
                 if(string.match(line,".+"..mac..".+ handle%s+") ~= nil)then
                    local handle = string.gsub(line,".+"..mac..".+ handle%s+", "");
                    print(handle);
                    util.exec('nft delete rule bridge meshdesk '..chain..' handle '..handle);
                 end
            end
        end        
    end    
end

function macOff(m)
    print("Block MAC "..m);
    for i, chain in ipairs(chains) do
        print ('Add Block rule in chain '..chain..' for mac '..m)
        util.exec('nft add rule bridge meshdesk '..chain..' ether daddr '..mac..' counter drop comment \\"DROP DST '..mac..'\\"');
        util.exec('nft add rule bridge meshdesk '..chain..' ether saddr '..mac..' counter drop comment \\"DROP SRC '..mac..'\\"');   
    end
end

function macLimit(m)
    print("Limit MAC "..m);
    for i, chain in ipairs(chains) do
        print ('Add Limit rule in chain '..chain..' for mac '..m)
        util.exec('nft add rule bridge meshdesk '..chain..' ether daddr '..mac..' limit rate over '..bw_down..' kbytes/second counter drop comment \\"LIMIT DST '..mac..'\\"');
        util.exec('nft add rule bridge meshdesk '..chain..' ether saddr '..mac..' limit rate over '..bw_up..' kbytes/second counter drop comment \\"LIMIT SRC '..mac..'\\"');          
    end    
end

function mainPart()
    initialConfig();
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
    if((action ~= 'on')and(action ~= 'off')and(action ~= 'bw'))then
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
mainPart();

