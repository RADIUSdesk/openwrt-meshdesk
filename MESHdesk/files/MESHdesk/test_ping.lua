#!/usr/bin/lua

--[[--

Startup script to get the config of the device from the config server

--]]--

-- Include libraries
package.path = "libs/?.lua;" .. package.path

--Configure object
require("rdConfig");

local n     = require "nixio";
local a     = n.getaddrinfo('cloud.mesh-manager.com');

local util  = require "luci.util";

if(a)then
    print(util.dumptable(a));
    print(a[1]['address']);

    local c = rdConfig();
    local server = "192.168.1.1";
end

--[[--
if(c:pingTest(server))then
    print("I could ping "..server);
else
    print("No ping for "..server);
end
--]]--
