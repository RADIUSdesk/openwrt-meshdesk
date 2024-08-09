#!/usr/bin/lua
-- SPDX-FileCopyrightText: 2024 Dirk van der Walt <dirkvanderwalt@gmail.com>
--
-- SPDX-License-Identifier: GPL-3.0-or-later

-- Include libraries
package.path = "../libs/?.lua;./libs/?.lua;" .. package.path
require('rdAccelstats');
require("rdNetwork");
require("rdConfig");
require('rdLogger');

local result_file   = '/tmp/accel_result.json'
local a_json        = rdAccelstats();
local logger        = rdLogger();
local j             = require("luci.json");
local uci           = require("uci");
local x             = uci.cursor();
local socket        = require('socket');
local network       = rdNetwork();
local config        = rdConfig();
local util          = require("luci.util");
local report        = 'light'; -- can be light or full
local password      = 'testing123';
local report_url    = 'cake4/rd_cake/accel-servers/submit-report.json';

if(arg[1])then
    report = arg[1];
end

function sleep(sec)
	socket.select(nil, nil, sec)                                                                          
end 

function afterReport()
    local ok_flag = false;
    local follow_up = false;
    --Read the results
    local f=io.open(result_file,"r")
    if(f)then
        result_string = f:read("*all")
        print(result_string);
        r = j.decode(result_string);
        if(r.success)then
            ok_flag = true;       
        end       
      
        if(r.data)then
            if(r.data.terminate)then --Terminate
                --Get the password
                password = a_json:getPassword();           
                for index, value in pairs(r.data.terminate) do
                    follow_up = true;
                    print("Terminate "..value);
                    os.execute('accel-cmd -P '..password..' terminate sid '..value);   
                end
            end
            if(r.data.restart_service)then --Restart Service
                follow_up = true;
                print("Restart Service");
                os.execute('/usr/bin/killall accel-pppd');
                sleep(3);
                os.execute('/etc/init.d/accel-ppp start');
                sleep(3);   
            end            
        end                                    
    end
    
    if(follow_up)then
        print("Doing a follow up");
        sleep(10); --Give it enough time to connect again
        lightReport();
    end     
end

function lightReport()

    local pid_accel = util.exec("pidof accel-pppd");
    local accel_enabled = false;
    if(pid_accel == '')then
	    print("== Accel-ppp Not Running Returning ==");
        return;
    end 
    
    local proto     = x:get("meshdesk", "reporting", "report_adv_proto");
    url             = report_url .. "?_dc="..os.time(); 
    
    local server_tbl= config:getIpForHostname();
    local server    = server_tbl.hostname;
	if(server_tbl.fallback)then
	    server = server_tbl.ip;
	end
 
	local local_ip_v6   = network:getIpV6ForInterface('br-lan');
	if(local_ip_v6)then
	    server      = x:get("meshdesk", "internet1", "ip_6");
	    server      = '['..server..']';
	end
	
	local http_port     = x:get('meshdesk','internet1','http_port');
    local https_port    = x:get('meshdesk','internet1','https_port');
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
    --print(query);
      
    local id_if = x:get('meshdesk','settings','id_if');
    local id    = network:getMac(id_if);
    local mode  = network:getMode();
       
    local stat  = a_json:showStat();
    local j_stat= j.encode(stat);
    local sess  = a_json:showSessions();
    local j_sess= j.encode(sess);
    local curl_data= '{"report_type":"light","mac":"'..id..'","stat":'..j_stat..',"sessions":'..j_sess..',"mode":"'..mode..'"}';
    os.remove(result_file)  
    os.execute('curl -k -o '..result_file..' -X POST -H "Content-Type: application/json" -d \''..curl_data..'\' '..query);
    afterReport();

end

if(report == 'light')then
    lightReport();
end


print("Doing the *"..report.."* report");

