#!/usr/bin/env lua

-- /etc/MESHdesk/utils/iperf_to_rd.lua

local args = {...} -- or use the global 'arg' table (args = arg)

-- Validate minimum number of arguments (5 mandatory)
if #args < 5 then
    print("Usage: lua iperf_to_rd.lua <IP> <PORT> <PROTOCOL> <DURATION> <STREAMS> [ping]")
    os.exit(1)
end

-- Assign mandatory arguments
local ip          	= args[1]   -- e.g., "192.168.8.176"
local port        = args[2]   -- e.g., "5201"
local protocol  = args[3]   -- e.g., "tcp"
local duration = args[4]   -- e.g., "1"
local streams  = args[5]   -- e.g., "1"

-- Handle optional 6th argument (the "ping" flag)
local pingFlag = false
if args[6] and args[6]:lower() == "ping" then
    pingFlag = true
end

-- (Optional) Convert numeric strings to numbers if needed
port    		= tonumber(port)
duration  = tonumber(duration)
streams 	= tonumber(streams)

-- Example usage of the parsed variables
print("IP: " .. ip)
print("Port: " .. port)
print("Protocol: " .. protocol)
print("Duration: " .. duration .. " seconds")
print("Number of streams: " .. streams)
print("Ping enabled: " .. tostring(pingFlag))


local command = string.format("iperf3  -J --connect-timeout 200 -c %s -p %d -t %d -P %d", ip, port, duration, streams);

-- if pingFlag then command = command .. " --ping" end
-- os.execute(command)

-- =========================================================
--  Single-instance guard (OpenWrt "lock" utility)
-- =========================================================
local lockfile = "/var/run/iperf_to_rd.lock"

local function acquire_lock()
    -- Try to acquire the lock non-blocking.
    -- Returns non-zero if another instance holds it.
    local ret = os.execute("lock -n " .. lockfile .. " >/dev/null 2>&1")
    if ret ~= 0 then
        print("Another instance of this script is already running. Exiting.")
        os.exit(1)
    end
end

local function release_lock()
    -- Best-effort unlock; ignore errors
    os.execute("lock -u " .. lockfile .. " >/dev/null 2>&1")
end

acquire_lock()

-- Make sure we always try to release the lock before exiting normally
local function safe_exit(code)
    release_lock()
    os.exit(code or 0)
end
-- =========================================================

--[[
-- Check if correct number of arguments provided
if #arg ~= 2 then
    print("Usage: " .. arg[0] .. " <server_ip_or_fqdn> <duration_in_seconds>")
    print("Example: " .. arg[0] .. " 8.8.8.8 60")
    print("Example: " .. arg[0] .. " example.com 120")
    safe_exit(1)
end

-- Get arguments
local server = arg[1]
local duration = tonumber(arg[2])

-- Validate duration is a number
if not duration then
    print("Error: Duration must be a valid number")
    safe_exit(1)
end

-- Validate duration is positive
if duration <= 0 then
    print("Error: Duration must be greater than 0")
    safe_exit(1)
end

-- Main script logic
print(string.format("Iperf3 server: %s", server))
print(string.format("Test duration: %d seconds", duration))
print(string.format("Starting at: %s", os.date("%Y-%m-%d %H:%M:%S")))
--]]

function getMac(interface)
    interface = interface or "eth0"
    io.input("/sys/class/net/" .. interface .. "/address")
    t = io.read("*line")
    dashes, count = string.gsub(t, ":", "-")
    dashes = string.upper(dashes)
    return dashes
end

function readAll(file)
    local f = io.open(file,"rb")
    local content = f:read("*all")
    f:close()
    return content
end


local uci        = require("uci");
local x          = uci.cursor();
local id_if      = x.get('meshdesk','settings','id_if');
local id         = getMac(id_if);
local proto      = x.get('meshdesk','internet1','protocol');
local url        = 'cake4/rd_cake/iperf-tests/submit-results.json'
local server     = x.get('meshdesk','internet1','ip'); 
local http_port  = x.get('meshdesk','internet1','http_port');
local https_port = x.get('meshdesk','internet1','https_port');
local port_string   = '/';
    
if(proto == 'http')then
    if(http_port ~= '80')then
        port_string = ":"..http_port.."/";
    end
end
    
if(proto == 'https')then
    if(https_port ~= '443')then
        port_string = ":"..https_port.."/";
    end
end

local query     = proto .. "://" .. server .. port_string .. url;

local j_file = '/etc/MESHdesk/configs/current.json';
local j       = require("luci.json");
local util    = require("luci.util");
local c       = readAll(j_file);
local o       = j.decode(c);

local mode  = o.meta_data.mode;
local dev_id= o.meta_data.ap_id;

local result_file = '/tmp/iperf_to_rd.json';
local fwd = util.exec(command); --Upload
util.exec('/bin/sleep 2');
local rvs = util.exec(command..' -R');--Download

local fwt_tbl = j.decode(fwd);
local rvs_tbl = j.decode(rvs);

local curl_table= {};
curl_table['download'] 	= rvs_tbl;
curl_table['duration']		= doration;
curl_table['streams']		= streams;
curl_table['protocol']		= protocol;

curl_table['upload']  = fwt_tbl;
curl_table['mac']   	= id;
curl_table['mode'] 	= mode;
curl_table['dev_id'] 	= dev_id;
curl_table['ip']			= ip;
curl_table['port']		= port;

local curl_string = j.encode(curl_table);

print(curl_string);

os.remove(result_file);
util.exec('curl -k -o '..result_file..' -X POST -H "Content-Type: application/json" -d \''..curl_string..'\' '..query);

print(string.format("Completed at: %s", os.date("%Y-%m-%d %H:%M:%S")))

-- Release the lock on normal completion
release_lock()

