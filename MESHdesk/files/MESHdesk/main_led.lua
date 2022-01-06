#!/usr/bin/lua

start_stop = arg[1]
what_to_flash = arg[2]

-- Include libraries
package.path = "libs/?.lua;" .. package.path
--External programs object
require("rdExternal")
ext = rdExternal()

if((start_stop == nil)or(start_stop == 'start'))then
	ext:startOne("/etc/MESHdesk/led.lua " .. what_to_flash .. " &","led.lua")
end

if(start_stop == 'stop')then
	ext:startOne("/etc/MESHdesk/led.lua stop &","led.lua")
end

