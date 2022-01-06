#!/usr/bin/lua

--[[--

This test is used to troubleshoot uci write lockups

--]]--

-- Include libraries
package.path = "../libs/?.lua;" .. package.path

local uci   = require("uci")
local x	    = uci.cursor()
local utl   = require "luci.util";

local socket   = require("socket");

function main()
    
    local c  = 0;
    while (c < 500) do
        counter    = x.get("mesh_status", "status", "counter");
        print("Reading Counter and it is "..counter);
        --sleep(1);
        if(counter)then
             --utl.exec("touch /etc/config/mesh_status")
             x.set('mesh_status', 'status', 'counter', c)
             x.commit('mesh_status')
             print("We se counter to "..c)
        else
            --utl.exec("touch /etc/config/mesh_status")
            x.set('mesh_status','status','counter')
            x.set('mesh_status', 'status', 'counter', c)
            x.commit('mesh_status')
        end	
        c = c +1;
    end
end

function sleep(sec)
    socket.select(nil, nil, sec)
end

main()
