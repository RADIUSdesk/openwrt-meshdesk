#!/usr/bin/lua
-- Include libraries
package.path = "../libs/?.lua;./libs/?.lua;" .. package.path

require("uci");
local luci_gw_file  = '/www/gw.txt';
local www_gw_file   = '/gw.txt';
local gw_file       = '/tmp/gw';
local ip_base       = '10.5.5.';
local resolv_file   = '/etc/resolv.conf';

local utl           = require "luci.util";
local nfs           = require "nixio.fs";
local sys           = require "luci.sys";


function supplyGateway()
    --We will only supply a gateway if we are a gateway (file /tmp/gw exists)
    local f = nfs.access(gw_file)    
    if f then
        --Add the luci_gw_file since we are the gateway
        local have_luci_gw = nfs.access(luci_gw_file)
        if not have_luci_gw then
            utl.exec("echo 'hello' > "..luci_gw_file)
        end    
    else
        --Check if the luci_gw_file is present. If so; remove it
        local have_luci_gw = nfs.access(luci_gw_file)
        if(have_luci_gw)then
            nfs.remove(luci_gw_file)
        end
    end   
end

function updateGateway()

    --We don't update the gateway self
     local f = nfs.access(gw_file)
    if f~=nil then 
        return 
    end
    
    local set_gw       = false;
    local x            = uci.cursor();
    local status_gw    = x.get("mesh_status", "status", "gateway");
    local current_gw   = getCurrentGateway();
    
    if(status_gw)then
        print("Found status GW "..status_gw);
        local is_still_valid = testForGw(status_gw);
        if(is_still_valid)then
            set_gw = status_gw; 
        else
            set_gw = lookForGw();
            if(set_gw)then
                --Add this one to the "mesh_status"
                 utl.exec("touch /etc/config/mesh_status")
                 x.set('mesh_status', 'status', 'gateway', set_gw)
                 x.commit('mesh_status')
            end
        end
    else
        print("No status GW Found");
        set_gw =  lookForGw()
        if(set_gw)then
            --Add this one to the "mesh_status"
             utl.exec("touch /etc/config/mesh_status")
             x.set('mesh_status','status','status')
             x.set('mesh_status', 'status', 'gateway', set_gw)
             x.commit('mesh_status')
        end
    end
    
    if(set_gw == false)then -- There was not gw detected which means the mesh is useless so we might as well retry later
        return; 
    end
    
    if(set_gw ~= current_gw)then
        if((current_gw == nil) and (set_gw ~= nil))then --simply add the new gw
            print("Add new gw entry")
            os.execute("route add default gw ".. set_gw);        
        end

        if((current_gw ~= nil)and(set_gw ~= nil))then -- remove the current add the new
            print("Remove old gw entry")
            os.execute("route del default gw "..current_gw);
            os.execute("route add default gw ".. set_gw);
        end
        --Write the new gateway as the nameserver
        nfs.writefile(resolv_file,"nameserver "..set_gw); 
        os.execute("/etc/init.d/system reload"); --Do adjustments 
        os.execute("/etc/init.d/sysntpd stop"); --Do adjustments
        os.execute("/etc/init.d/sysntpd start"); --Do adjustments
    end
end

function testForGw(ip)
    local found_gw = false;
    local url = "http://"..ip..www_gw_file;
    local handle = io.popen('wget -c -P /tmp '..url..' 2>&1')
    local result = handle:read("*a")
    handle:close()
    result = string.gsub(result, "[\r\n]", " ")
    if(string.find(result,"Writing to "))then --If the network is down
      found_gw = ip
    end     
    return found_gw;
end

function lookForGw()
    local found_gw = false;
    local i;
    for i = 1,20,1 
    do 
        print(i);
        local ip  = ip_base..i;
        local url = "http://"..ip..www_gw_file;
        local handle = io.popen('wget -c -P /tmp '..url..' 2>&1')
        local result = handle:read("*a")
        handle:close()
        result = string.gsub(result, "[\r\n]", " ")
        if(string.find(result,"Writing to "))then --If the network is down
            found_gw = ip
            break; 
        end     
    end
    return found_gw;  
end


function getCurrentGateway()
    --Get the current GW
    local current_gw = nil
    local fd = io.popen("route -n")
    if fd then
        for line in fd:lines() do
            if(string.find(line, "^0.0.0.0.*UG.*"))then
                found_gw = true
                current_gw = string.gsub(line, "^0.0.0.0%s*", "")
                current_gw = string.gsub(current_gw,"%s+.*UG.*","")
            end  
        end
        fd:close()
    end
    return current_gw	
end

function checkForAutoReboot()
	--We don't check for reboot on the gateway itself
    local f=io.open(gw_file,"r")
    
    if f~=nil then 
        return 
    end

	local gw_missing_file 	= "/tmp/gw_missing_stamp";

	local uci 		= require('uci')
	local x	  		= uci.cursor()
	local gw_auto_reboot 	= x.get('meshdesk', 'settings', 'gw_auto_reboot')
	local reboot_time	= x.get('meshdesk', 'settings', 'gw_auto_reboot_time')

	if(gw_auto_reboot == '1')then

		--Find the current gateway--
		local current_gw = getCurrentGateway()

		local complete_missing_action = true

		--=====CURRENT GW=========
		if(current_gw ~= nil)then
			require('rdConfig');
			local c = rdConfig();
			--local test_for_ip = "10.5.5.2";
			local test_for_ip = current_gw;
			if(c:httpTest(test_for_ip,true))then --We override the default httpTest if it might be https for local testing
				os.remove(gw_missing_file)
				complete_missing_action = false
			end
		end

		if(complete_missing_action)then

			--Check if it is the first time the gateway is missing
			local mf =io.open(gw_missing_file,"r")
			if mf==nil then
				print("Create new gw missing file")
				--Write the current timestamp to the file
				local ts = os.time()
				--Write this to the config file
				local f,err = io.open(gw_missing_file,"w")
				if not f then return print(err) end
				f:write(ts)
				f:close()
			else
				print("Existing missing file... check timestamp")
				local ts_last = mf:read()
				print("The last failure was at "..ts_last)
				if(ts_last+reboot_time < os.time())then
					print("We need to reboot")
					os.execute("reboot")
				end
				mf:close()
			end
		end
	end
end

supplyGateway()
updateGateway()
checkForAutoReboot()
