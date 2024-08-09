#!/usr/bin/lua
-- SPDX-FileCopyrightText: 2024 Dirk van der Walt <dirkvanderwalt@gmail.com>
--
-- SPDX-License-Identifier: GPL-3.0-or-later

-- Include libraries
package.path = "../libs/?.lua;./libs/?.lua;" .. package.path

require("rdSqm");
local luci_util = require("luci.util")
local uci = require("uci")
local json = require("json")
local http = require("luci.http")

-- Function to get MAC address
local function getMac(interface)
    interface = interface or "eth0"
    local file = io.open("/sys/class/net/" .. interface .. "/address", "r")
    local mac = file:read("*line")
    file:close()
    mac = string.upper(string.gsub(mac, ":", "-"))
    return mac
end

-- UCI configuration
local x = uci.cursor()
local id_if = x:get("meshdesk", "settings", "id_if")
local id = getMac(id_if)
local proto = x:get("meshdesk", "internet1", "protocol")
local server = x:get("meshdesk", "internet1", "ip")
local http_port = x:get("meshdesk", "internet1", "http_port")
local https_port = x:get("meshdesk", "internet1", "https_port")

-- Build URL
local port_string = "/"
if proto == "http" and http_port ~= "80" then
    port_string = ":" .. http_port .. "/"
end
if proto == "https" and https_port ~= "443" then
    port_string = ":" .. https_port .. "/"
end
local query = proto .. "://" .. server .. port_string .. "cake4/rd_cake/sqm-profiles/get-config-for-node.json"
local q_s = { mac = id, version = "22.03" }
local enc_string = http.build_querystring(q_s)
local url = query .. enc_string

-- Initialize sqm
local sqm   = rdSqm();

-- Fetch and parse JSON data
local retval = luci_util.exec("curl -k '" .. url .. "'")
local tblConfig = json.decode(retval)

-- Apply SQM items
if tblConfig.config_settings and tblConfig.config_settings.sqm then
	sqm:configureFromTable(tblConfig.config_settings.sqm);
end

