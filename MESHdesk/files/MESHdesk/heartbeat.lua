#!/usr/bin/lua

-- Include libraries
package.path = "libs/?.lua;" .. package.path

--[[--
This script will typically be started during the setup of the device
If will then loop while checking the following:
1.) It will run the
2.) Sleep
--]]--a

require("rdLogger");
require('rdConfig');
require('rdNetwork');
require('rdJsonReports');

debug 	    = true;
interval    = 120;
ping_sleep  = 30;

local socket    = require("socket");
local utl       = require "luci.util";
local l         = rdLogger();
local c         = rdConfig();
local network   = rdNetwork();
local nfs       = require "nixio.fs";
local uci       = require("luci.model.uci");
local uci       = require("uci");
local x         = uci.cursor();
local sch_min   = '/tmp/sch_min';
local conf_file = '/etc/MESHdesk/configs/current.json';
--local json	    = require("json");
local json	    = require('luci.json');

--This is for the new reporting system--
local rep_enable    = x:get('meshdesk','reporting','report_adv_enable');
local int_light     = tonumber(x:get('meshdesk','reporting','report_adv_light'));
local int_full      = tonumber(x:get('meshdesk','reporting','report_adv_full'));
local int_sampling  = tonumber(x:get('meshdesk','reporting','report_adv_sampling'));
local int_schedule  = 59;

local cntr_light    = 0;
local cntr_full     = 0;
local cntr_sampling = 0;
local cntr_schedule = 0;


--======================================
---- Some general functions -----------
--=====================================
function log(m,p)
	if(debug)then                                                                                     
        	l:log(m,p)                                                                                
	end                               
end
                                                                                                       
function sleep(sec)
	socket.select(nil, nil, sec)                                                                          
end 

function file_exists(name)
    local f=io.open(name,"r")
    if f~=nil then 
        io.close(f) 
        return true; 
    else 
        return false; 
    end
end 

function up_boot_count()
    local bootcycle     = x:get("mesh_status", "status", "bootcycle");
    if(bootcycle)then
        utl.exec("touch /etc/config/mesh_status");
        x:set('mesh_status','status','status');
        x:set('mesh_status','status','bootcycle', tonumber(bootcycle)+1);
    else
        utl.exec("touch /etc/config/mesh_status");
        x:set('mesh_status','status','status');
        x:set('mesh_status','status','bootcycle', 1); 
    end
    x:commit('mesh_status');   
end      

function light_report()
    log("Light Reporting");
    os.execute("/etc/MESHdesk/reporting/report_to_server.lua light");
    actions_checker();
    dynamic_gateway(); --We also include the dynamic gateway bit here  
end

function dynamic_gateway()
    os.execute("/etc/MESHdesk/reporting/dynamic_gateway.lua")
end

function actions_checker()
    os.execute("/etc/MESHdesk/reporting/check_for_actions.lua")
end

function full_report()
    log("Full Reporting");
    os.execute("/etc/MESHdesk/reporting/report_to_server.lua full");
    actions_checker();
end

function do_sample()
    os.execute("/etc/MESHdesk/reporting/report_sampling.lua");
end

function schedule_check()
    local hour      = os.date("%H");
    local min       = os.date("%M");
    local w_day     = os.date("%w");
    local m         = (hour*60)+min;
    local r_file    = io.open(sch_min, 'r');
    local last_min  = nil;
       
    if(r_file ~=nil)then
        last_min    = r_file:read();
        r_file:close();
    end
    --if(last_min ~= nil)then
        --log("== LAST MIN IS "..tostring(last_min).." ==");
    --else
        --log("== NO LAST MIN PRESENT ==");
    --end
    
    local w_file    = io.open(sch_min, 'w+');
    if(w_file ~= nil)then
        w_file:write(tostring(m));
        w_file:close();
        --log("== CURRMENT  MIN IS "..tostring(m).." ==");
    end
    
    if(last_min ~= nil)then
        if(m < tonumber(last_min))then        --It started the new day
            while(tonumber(last_min) <= 1439)do
                if(tonumber(last_min) == 1439)then
                    last_min = 0;
                    exSchedule(last_min,w_day);
                    break;
                else
                    last_min = tonumber(last_min)+1;
                    --w_day must be the previous one
                    local old_day = tonumber(w_day) - 1;
                    if(tonumber(w_day) == 0)then
                        old_day = 6; --If it was Sunday we need to turn back to Saturday (day6)
                    end
                    exSchedule(last_min,old_day); -- Only here we use the old day   
                end              
            end
            
            while(tonumber(last_min) < m)do
                last_min = tonumber(last_min)+1;
                exSchedule(last_min,w_day);      
            end           
        else
            while(tonumber(last_min) < m)do
                last_min = tonumber(last_min)+1;
                exSchedule(last_min,w_day);     
            end                    
        end
    end            
    --log("== Schedule Checker "..tostring(m).." ==");
end

function exSchedule(m,d)
    log("== **Looking for Schedules MINUTE "..tostring(m).." WEEK DAY "..tostring(d).." ==");                   
    local f = io.open(conf_file, 'r');      
    local content = f:read("*all");     
    f:close();
    local o  = json.decode(content);
    if(o.success == true)then
        if(o.config_settings.schedules ~= nil)then
            for i, schedule in ipairs(o.config_settings.schedules) do
                if(tonumber(schedule.event_time) == m)then
                    local did_match = false;
                    if((tonumber(d) == 0)and(schedule.su == true))then
                        did_match = true;
                    end 
                    if((tonumber(d) == 1)and(schedule.mo == true))then
                        did_match = true;
                    end
                    if((tonumber(d) == 2)and(schedule.tu == true))then
                        did_match = true;
                    end
                    if((tonumber(d) == 3)and(schedule.we == true))then
                        did_match = true;
                    end
                    if((tonumber(d) == 4)and(schedule.th == true))then
                        did_match = true;
                    end
                    if((tonumber(d) == 5)and(schedule.fr == true))then
                        did_match = true;
                    end
                    if((tonumber(d) == 6)and(schedule.sa == true))then
                        did_match = true;
                    end
                    if(did_match == true)then
                        log("== SCHEDULE MATCH ==");
                        if((schedule.type == 'command')or(schedule.type == 'predefined_command'))then
                            log(schedule.command);
                            os.execute(schedule.command);                       
                        end                   
                    end                   
                end
            end
        end    
    end
end


function checkForAdjustment()
    if(file_exists('/tmp/reporting_changed.txt'))then
        print("Found some changes in settings...Reread and adjust where needed");
        local n_light     = tonumber(x:get('meshdesk','reporting','report_adv_light'));
        local n_full      = tonumber(x:get('meshdesk','reporting','report_adv_full'));
        local n_sampling  = tonumber(x:get('meshdesk','reporting','report_adv_sampling'));
        if(n_light ~= int_light)then
            if(n_light > int_light)then
                light_delta     = n_light - int_light;
                cntr_light      = cntr_light + light_delta;
                int_light       = n_light;
            else
               light_delta      = int_light - n_light;
               cntr_light       = cntr_light - light_delta;
               int_light        = n_light; 
            end
        end
        if(n_sampling ~= int_sampling)then
            if(n_sampling > int_sampling)then
                sampling_delta     = n_sampling - int_sampling;
                cntr_sampling      = cntr_sampling + sampling_delta;
                int_sampling       = n_sampling;
            else
               sampling_delta      = int_sampling - n_sampling;
               cntr_sampling       = cntr_sampling - sampling_delta;
               int_sampling        = n_sampling; 
            end
        end
        if(n_full ~= int_full)then
            if(n_full > int_full)then
                full_delta     = n_full - int_full;
                cntr_full      = cntr_full + full_delta;
                int_full       = n_full;
            else
               full_delta      = int_full - n_full;
               cntr_full       = cntr_full - full_delta;
               int_full        = n_full; 
            end
        end        
        nfs.remove('/tmp/reporting_changed.txt');
    end
end


function reporting_loop()
    local loop = true;
    
    --Initial things to do
    local json_r = rdJsonReports();
    json_r:initJson(true); --Hard Init the DB
  
    os.execute('mkdir -p /etc/MESHdesk/mesh_status/waiting');
    os.execute('rm /etc/MESHdesk/mesh_status/waiting/*');
    
    os.execute('mkdir -p /etc/MESHdesk/mesh_status/completed');
    os.execute('rm /etc/MESHdesk/mesh_status/completed/*');
    
    do_sample();
    math.randomseed(os.time());
    local r = math.random(10);
    sleep(r);
    full_report(); --Initially we send a full report upon startup to 'prime' everything
    --END Initial things to do
    
    while(loop)do          
	    sleep(1);
	    cntr_light      = cntr_light + 1;
	    cntr_full       = cntr_full + 1;
	    cntr_sampling   = cntr_sampling + 1;
	    cntr_schedule   = cntr_schedule + 1;
	    
	    if(cntr_sampling == int_sampling)then --First sample before report
	        cntr_sampling = 0;
	        do_sample();
	        --collect_data();
	    end	
	    
	    if(cntr_light == int_light)then
	        cntr_light = 0;
	        light_report();
	    end
	    
	    if(cntr_full == int_full)then
	        cntr_full = 0;
	        full_report();
	    end
	    
	    if(cntr_schedule == int_schedule)then
	        cntr_schedule = 0;
	        schedule_check();
	    end	    
	    --On the fly adjustment if needed    
	    checkForAdjustment();     
    end
end

function conn_test_loop()
    local loop  = true;
    local count = 0;
    local test_for_ip = x:get('meshdesk','internet1','ip');
    
    local local_ip_v6   = network:getIpV6ForInterface('br-lan');
	if(local_ip_v6)then
	    test_for_ip      = x:get("meshdesk", "internet1", "ip_6");
	    test_for_ip      = '['..test_for_ip..']';
	end
	
	dynamic_gateway();
		  
    while(loop)do
        count = count + 1;
        log("Heartbeat startup test for connection try "..count); 
        if(c:httpTest(test_for_ip))then
            break;
        end 
        sleep(ping_sleep);
        dynamic_gateway();
    end
    --Will only reach here when it could reach the MD server
    reporting_loop();  
end

--=== BEGIN HERE ===---
up_boot_count();
conn_test_loop();

