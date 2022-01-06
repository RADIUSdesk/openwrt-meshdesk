#!/usr/bin/lua

-- Include libraries
package.path = "libs/?.lua;" .. package.path

--The default
local what_to_flash=arg[1]
if (what_to_flash == nil)then
	what_to_flash = "a"
end

if(what_to_flash == 'stop')then
	require("rdMorse")
	o_m = rdMorse()
	o_m:clearLed()
else
	require("rdMorse")
	o_m = rdMorse()
	o_m:startFlash(what_to_flash)
end    

