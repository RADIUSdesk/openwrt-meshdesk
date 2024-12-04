#!/usr/bin/lua
-- SPDX-FileCopyrightText: 2024 FIXME REPLACE WITH YOUR INFO ... format: Dirk van der Walt <dirkvanderwalt@gmail.com>
--
-- SPDX-License-Identifier: GPL-3.0-or-later

--[[--

This test script will test the rdActions object's methods

--]]--

-- Include libraries
package.path = "../libs/?.lua;" .. package.path

function main()
	require("rdNetstatsWan")
	local nsw = rdNetstatsWan()
	print("Version is " .. nsw:getVersion())	
	printWanStats(nsw:getWanStats())
end

function printWanStats(wanStats)
    -- Loop through each item in the wanStats table
    for _, stat in ipairs(wanStats) do
        -- Print interface and status information
        print("Interface: " .. stat.interface)
        print("Up: " .. tostring(stat.up))

        -- Print statistics for the interface
        print("Statistics:")

        local stats = stat.statistics
        if stats then
            -- Print individual statistics fields
            for key, value in pairs(stats) do
                -- If the value is a table, we print it recursively
                if type(value) == "table" then
                    print("  " .. key .. ":")
                    for subkey, subvalue in pairs(value) do
                        print("    " .. subkey .. ": " .. tostring(subvalue))
                    end
                else
                    print("  " .. key .. ": " .. tostring(value))
                end
            end
        else
            print("  No statistics available")
        end
        
        print("\n") -- Adding a newline for readability between interfaces
    end
end

main()
