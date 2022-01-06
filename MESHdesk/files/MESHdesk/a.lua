#!/usr/bin/lua
--[[--
Startup script to get the config of the device from the config server
--]]--

-- Include libraries
package.path = "libs/?.lua;" .. package.path;
require("rdLogger");
require("rdExternal");
require("rdConfig");
require("rdNetwork");
require("rdWireless");

local socket            = require("socket");
local uci    	        = require("uci");
local uci_cursor        = uci.cursor();
local nixio             = require("nixio");
local dns_works         = false; --'global' flag which indicates if we could resolve DNS to IP
local sleep_time		= 1;
--local debug			    = false;
local debug			    = true;
local l			        = rdLogger();
local ext 			    = rdExternal();
local n                 = rdNetwork();
local c 				= rdConfig();
local lan_up_file       = uci_cursor.get('meshdesk','settings','lan_up_file');
local wifi_up_file      = uci_cursor.get('meshdesk','settings','wifi_up_file');
local wbw_up_file       = uci_cursor.get('meshdesk','settings','wbw_up_file');

--Rerun Checks on Failure
config_success          = false;
config_repeat_counter   = 500;
server_find_retry       = 10;
mac_not_defined         = false;

--======================================
---- Some helper functions ------------
--======================================
function log(m,p)
	if(debug)then
	    print(m);
		l:log(m,p)
	end
end

function sleep(sec)
    socket.select(nil, nil, sec)
end

function file_exists(name)                                                          
        local f=io.open(name,"r")                                                   
        if f~=nil then io.close(f) return true else return false end                
end                                                                                 
                                                                                                    
function reboot()   
	os.execute("reboot");	
end
--==============================
-- End Some helper functions --
--==============================

--======================================
---- Some test functions ---------------
--======================================

function did_wifi_came_up()
	if(file_exists(wifi_up_file))then
		return true		
	else
		return false
	end
end

function did_wbw_came_up()
    if(file_exists(wbw_up_file))then
		return true		
	else
		return false
	end
end

--======================================
---- END Some test functions -----------
--======================================

--======================================
---- FLOW FUNCTIONS --------------------
--======================================
function try_wifi()
	local got_new_config = false;	
	--Determine how many radios there are
	local wireless = rdWireless();
	wireless:newWireless();
	local config_file = uci_cursor.get('meshdesk','settings','config_file');
	--After this we can fetch a count of the radios
	radio_count = wireless:getRadioCount()
	log("Try to fetch the settings through the WiFi radios")
	log("Device has "..radio_count.." radios")
	local radio = 0 --first radio
	
	if(uci_cursor.get('meshdesk','settings','skip_radio_0') == '1')then
	    radio = 1
	end 
	
	--Here we will go through each of the radios
	while(radio < radio_count) do
		log("Try to get settings using radio "..radio);
		--Bring up the Wifi
		local wifi_is_up = wait_for_wifi(radio)
		if(wifi_is_up)then
		    local ret_tbl  = c:tryForConfigServer('wifi');
            dns_works      = ret_tbl.dns_works; 
                      
            if(ret_tbl.got_settings)then
				--flash D--
				got_new_config = true;	
				break -- We already got the new config and can break our search of next radio
			end
		end
		--Try next radio
		radio = radio+1
	end
	return got_new_config;
end

function wait_for_wifi(radio_number)

	if(radio_number == nil)then
		radio_number = 0
	end

	log("Try settings through WiFi network")
	if(radio_number == 0)then
	    os.execute("/etc/MESHdesk/main_led.lua start rone");
    end
	
	if(radio_number == 1)then
	    os.execute("/etc/MESHdesk/main_led.lua start rtwo");
    end
	
	-- Start the WiF interface
	local w = rdWireless()
                             
	w:connectClient(radio_number)
	
	local start_time	= os.time()
	local loop			= true
	local wifi_is_up	= false --default
	local wait_wifi_counter = tonumber(uci_cursor.get('meshdesk','settings','wifi_timeout'));
	
	while (wait_wifi_counter > 0) do
		sleep(sleep_time);
		-- If the wifi came up we will try to get the settings
		if(did_wifi_came_up())then
			wifi_is_up = true
			break
		end	
		wait_wifi_counter = wait_wifi_counter - 1
	end
	--See what happended and how we should handle it
	if(wifi_is_up)then
		-- sleep at least 10 seconds to make sure it got a DHCP addy
		sleep(10)
		print("Wifi is up try to get the settings through WiFi")
		log("Wifi is up try to get the settings through WiFi")
	end
	return wifi_is_up
end

function wait_for_wbw()                          
	local start_time	= os.time()
	local loop			= true
	local wbw_is_up	    = false --default
	local wait_wbw_counter = tonumber(uci_cursor.get('meshdesk','settings','wifi_timeout'));
	
	os.execute("/etc/MESHdesk/main_led.lua start wbw");
	
	--Start Web By Wifi
	local wireless = rdWireless();
	wireless:newWireless();
	n:wbwStart();
		
	while (wait_wbw_counter > 0) do
		sleep(sleep_time);
		-- If the wifi came up we will try to get the settings
		if(did_wbw_came_up())then
			wbw_is_up = true
			break
		end	
		wait_wbw_counter = wait_wbw_counter - 1
	end
	--See what happended and how we should handle it
	if(wbw_is_up)then
		-- sleep at least 20 seconds to make sure it got a DHCP addy
		sleep(10)
		print("Web-By-Wifi is up try to get the settings through WiFi");
		log("Web-By-Wifi is up try to get the settings through WiFi");
	end
	return wbw_is_up
end

function check_for_previous_settings()
    local previous_config_file 	= uci_cursor.get('meshdesk','settings','previous_config_file');
    if(file_exists(previous_config_file))then
        print("Using previous settings")
        log("Using previous settings");
        local ret_conf = c:configureDevice(previous_config_file);
        if(ret_conf.config_success == true)then
            config_success = true;
        end
	    os.execute("lua /etc/MESHdesk/bailout.lua &")
    end
end

function try_web_by_wifi()
    local found_config = false;
    --It might be that the device have web-by-wifi enabled
    local w_b_w = uci_cursor.get('meshdesk','web_by_wifi','disabled');
    if(w_b_w)then
        if(w_b_w == '0')then
            log("WEB BY WIFI IS ACTIVE");
	        if(wait_for_wbw())then
	        
	            local ret_tbl  = c:tryForConfigServer('wbw');
                dns_works       = ret_tbl.dns_works; 
                      
                if(ret_tbl.got_settings)then
			        --flash D--
			        found_config = true;
		        end
	        end
	    else
	        log("WEB BY WIFI DISABLED");            
        end     
    else
        log("WEB BY WIFI NOT DEFINED");
    end
    return found_config;   
end

function try_for_connectivity()
    local config_file	    = uci_cursor.get('meshdesk','settings','config_file');
    local cp_config_file	= uci_cursor.get('meshdesk','settings','cp_config_file');
    local wifi_captive      = false;
    local found_config      = false;
 
    --First try LAN
    os.execute("/etc/MESHdesk/main_led.lua start lan");
    local ret_tbl   = c:tryForConfigServer('lan');
    dns_works       = ret_tbl.dns_works;
       
    if(ret_tbl.got_settings)then
        log("===WBW Do ignore check==");
        if(c:ignoreWebByWifiCheck())then --If the config values that came back does not include wbw then we can say we found the final config
            found_config = true;
        end      
    end

    --Then WBW
    if(found_config == false)then --Either could not find settings through  LAN OR it has wbw settings which we need to do
        found_config = try_web_by_wifi();
    end
        
    --Then WiFi
    if(found_config == false)then
        if(try_wifi())then
            if(c:ignoreWebByWifiCheck())then --If the config values that came back does not include wbw then we can say we found the final config
                found_config = true;
                wifi_captive = true;
            else
                found_config = try_web_by_wifi();
            end
        end    
    end
    
    if(found_config)then
        local ret_conf = c:configureDevice(config_file,true);--include doWanSynch here
        
        if(ret_conf.config_success == true)then
            config_success = true;
        end
               
        if(ret_conf.mac_not_defined == true)then
		    log("MAC not known -> switch over to Auto Captive Portal over");
		    local c = rdConfig();
            c:prepCaptiveConfig(dns_works,wifi_captive); --Here we specify the WiFi flag (optional, but required here)--FIXME We need to determine id DNS WORKS!
            local ret_conf = c:configureDevice(cp_config_file);
            if(ret_conf.config_success == true)then
                config_success = true;
            end
        end
    else
        print("Fallback to last known good config");
        log("Fallback to last known good config");
        check_for_previous_settings();  
    end
end


--======================================
---- END FLOW FUNCTIONS ----------------
--======================================

--== START HERE ==
local disabled = uci_cursor.get('meshdesk','internet1','disabled');                                                                          
if(disabled)then                                                          
        if(disabled == '1')then                                           
                os.exit();                                                
        end                                                               
end   

while (config_success == false and config_repeat_counter > 0) do
	l:log("Try for connectivity ("..config_repeat_counter.." tries)");
	try_for_connectivity();
	config_repeat_counter = config_repeat_counter - 1;
end

if (config_success == false) then
	--log("No config found. Reboot in ten minutes.");
	l:log("No config found. Reboot in ten minutes.");
	sleep(600);
	reboot();
end

l:log("a.lua Configuration successful.");
