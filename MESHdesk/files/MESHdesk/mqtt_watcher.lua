#!/usr/bin/lua

-- Include Libraries
package.path = "libs/?.lua;" .. package.path

function watch_mqtt()
    local chck_mqtt_proc = io.popen("ps | grep mqtt.lua | head -1")
    local chck_mqtt_proc_str = chck_mqtt_proc:read("*line")
    chck_mqtt_proc:close()

    chck_mqtt_proc_str = string.match(chck_mqtt_proc_str,"grep")

    if chck_mqtt_proc_str ~= nil then
        -- mqtt.lua is not running, try to start it up
        os.execute("cd /etc/MESHdesk && ./mqtt.lua &")  
    end
end

while true do
    -- Wait for 30 seconds
    os.execute("sleep 30")

    -- Watch mqtt.lua and start it up when necessary
    watch_mqtt()
end