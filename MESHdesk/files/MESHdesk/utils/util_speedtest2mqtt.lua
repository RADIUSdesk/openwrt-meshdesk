#!/usr/bin/lua
-- SPDX-FileCopyrightText: 2025 Dirk van der Walt <dirkvanderwalt@gmail.com>
--
-- SPDX-License-Identifier: GPL-3.0-or-later


-- Include libraries
package.path = "../libs/?.lua;./libs/?.lua;" .. package.path

--[[

 speedtest --output json
{
    "client":{"ip":"41.117.152.82","lat":"-26.2309","lon":"28.0583","isp":"MTN SA MOBILE"},
    "servers_online":10,
    "server":{"name":"Johannesburg","id":23339,"sponsor":"Syrex","distance":2,"latency":18,"host":"zatjnb01-ookla1.syrex.co.za.prod.hosts.ooklaserver.net:8080","recommended":0},
    "ping":18,
    "jitter":17,
    "download":8639626.56,
    "download_mbit":8.64,
    "upload":6064663.50,
    "upload_mbit":6.06,
    "_":"all ok"
}


--]]

local json      = require("json");
local utils     = require("rdMqttUtils");
local mqtt      = require("mosquitto");
local client    = mqtt.new();

MQTT_USER       = 'openwrt';
MQTT_PASS       = 'openwrt';
MQTT_HOST       = '192.168.8.140';

client:login_set(MQTT_USER, MQTT_PASS)
client:connect(MQTT_HOST)

function mainPart()
    local meta_data = utils.getMetaData();   
    if meta_data == nil then
        print("This node does not have any Meta Data in its config")
    else
        if(meta_data.mode and meta_data.mode == 'ap')then
        	print("AP mode "..meta_data.ap_id);
        	speed2mqtt('ap',meta_data.ap_id)
        end
    end    
end


function speed2mqtt(mode,id)

    local json   = require("luci.jsonc") -- or require("cjson")
    local result = {}

    --local handle = io.popen("stdbuf -oL speedtest --latency --output verbose", "r")
    local handle = io.popen("stdbuf -oL speedtest --output verbose", "r")
    if not handle then
        result.error = "Failed to run speedtest"
        print(json.stringify(result, true))
        return
    end

    local buffer = ""
    local last_json = ""

    while true do
        local char = handle:read(1)
        if not char then break end

        buffer = buffer .. char

        if char == "\n" then
            -- Line is complete, parse known types

            if buffer:match("^IP") then
                local ip, isp, lat, lon = buffer:match("IP:%s*(%d+%.%d+%.%d+%.%d+)%s*%(%s*(.-)%s*%)%s*Location:%s*%[([%-%.%d]+),%s*([%-%.%d]+)%]")
                if ip and isp and lat and lon then
                    result.client = {
                        ip = ip,
                        isp = isp,
                        lat = lat,
                        lon = lon
                    }
                end
            end

            if buffer:match("^Server") then
                local id, name, host, sponsor, distance, latency = buffer:match("Server #(%d+): (.-) ([^ ]+) by (.-) %((%d+) km.-%)%: (%d+) ms")
                if id and name and host and sponsor and distance and latency then
                    result.server = {
                        id = tonumber(id),
                        name = name,
                        sponsor = sponsor,
                        distance = tonumber(distance),
                        latency = tonumber(latency),
                        host = host,
                        recommended = 0
                    }
                end
            end

            if buffer:match("^Ping:") then
                local ping = tonumber(buffer:match("Ping:%s*(%d+)%s*ms"))
                result.ping = ping
            end

            if buffer:match("^Jitter:") then
                local jitter = tonumber(buffer:match("Jitter:%s*(%d+)%s*ms"))
                result.jitter = jitter
            end

            if buffer:match("Download:%s*([%d%.]+)%s*Mbit/s") then
                result.download = buffer:match("Download:%s*([%d%.]+)%s*Mbit/s")
                result.dl_live  = result.download; -- update the 'live' one
            end

            if buffer:match("Upload:%s*([%d%.]+)%s*Mbit/s") then
                result.upload   = buffer:match("Upload:%s*([%d%.]+)%s*Mbit/s")
                result.ul_live  = result.upload; -- update the 'live' one
                result.done     = true --upload test is last
            end

            -- Reset buffer
            buffer = ""

        else
            -- Mid-line live updates
            if buffer:match("Testing download speed %(%d+%)%:%s+[%d%.]+%s+Mbit/s") then
                result.dl_live  = buffer:match("Testing download speed %(%d+%)%:%s+([%d%.]+)")
                buffer = ""
            end
            
            if buffer:match("Testing upload speed %(%d+%)%:%s+[%d%.]+%s+Mbit/s") then           
                result.ul_live  = buffer:match("Testing upload speed %(%d+%)%:%s+([%d%.]+)")
                --Tweak it to be halve of it 
                result.ul_live = string.format("%.2f", result.ul_live / 2)
                buffer = ""
            end
        end

        -- Optional: periodically print the current cumulative result (for debug/demo)
        if next(result) then
            local current_json = json.stringify(result, true)
            if current_json ~= last_json then
               -- print(current_json)
                local topic = "/"..mode.."/" .. id .. "/speedtest"
                print(topic);
                client:publish(topic, current_json, 0, false)
                last_json = current_json
            end
        end       
    end
end


mainPart();


