#!/usr/bin/lua

-- SPDX-FileCopyrightText: 2024 Dirk van der Walt <dirkvanderwalt@gmail.com>
--
-- SPDX-License-Identifier: GPL-3.0-or-later


-- Include Libraries
package.path = "libs/?.lua;" .. package.path

-- Returns true when at least one mqtt.lua process exists.
-- The pattern '[m]qtt\.lua' cannot match the grep process itself, so the answer no longer depends on
-- the order of the ps listing. The old check (ps | grep mqtt.lua | head -1, then look for "grep")
-- misfired whenever grep's PID was lower than mqtt.lua's PID, i.e. after every PID wrap-around, and
-- started one more mqtt.lua each time; long-running nodes collected dozens of them (~1.8 MB each).
function mqtt_running()
    local p = io.popen("ps w | grep -c '[m]qtt\\.lua'")
    if p == nil then
        return true -- cannot tell; never spawn blindly
    end
    local n = tonumber(p:read("*line")) or 0
    p:close()
    return n > 0
end

function watch_mqtt()
    if not mqtt_running() then
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
