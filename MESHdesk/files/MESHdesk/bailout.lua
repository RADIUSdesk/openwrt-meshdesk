#!/usr/bin/lua

--[[
    24 May 2018
    This script can  be called when trouble arises as a gentle way to attempt to bring back the hardware to a working state.
    Once called it will take 24 hours before activated. 
    Also remember to call with the & in order to send it to the background
--]]

-- Include libraries
package.path = "libs/?.lua;" .. package.path;
local socket = require("socket");

function sleep(sec)
    socket.select(nil, nil, sec)
end

sleep(86400);
os.execute("reboot");
