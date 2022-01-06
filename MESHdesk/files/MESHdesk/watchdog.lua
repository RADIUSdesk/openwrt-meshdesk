#!/usr/bin/lua

-- Include libraries
package.path = "libs/?.lua;" .. package.path
require("rdLogger");
local socket    = require("socket");

local must_run = {
   "heartbeat.lua",
   --"actions_checker.lua", --We do not need this any more wit the new reporting mechanism 
   --FIXME Wee need to have a check to bring this back in case the new reporting is not used
   "batman_neighbours.lua"
}

local debug = true;
local l     = rdLogger();
local util  = require("luci.util");
local zzz   = 60;

function log(m,p)
	if(debug)then                                                                                     
        	l:log(m,p)                                                                                
	end                               
end

function sleep(sec)
    socket.select(nil, nil, sec)
end

function check_watchdog()
	sleep(600);
	local ok_file = "/tmp/startup_ok";
	local pass_file = "/tmp/startup_pass";
	if (file_exists(ok_file)) then
		os.execute("rm " .. ok_file);
		os.execute("touch " .. pass_file);
		check_programs(); --Check the important programs...
	else
		os.execute("sleep 60");
		os.execute("reboot");
	end
end

function check_programs()
    local loop = true;
    while(loop)do 
        for index,value in ipairs(must_run)do  
            --log(index..".) Is "..value.." running?");
            local pid = util.exec("pidof "..value);
            if(pid == '')then
                log(value.." is not running starting it again");
                os.execute("cd /etc/MESHdesk && ./"..value.." &");
            end
        end
        sleep(zzz);
    end
end

function file_exists(name)
   local f=io.open(name,"r")
   if f~=nil then io.close(f) return true else return false end
end

check_watchdog()

--check_programs();
