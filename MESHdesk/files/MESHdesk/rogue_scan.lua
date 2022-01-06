#!/usr/bin/lua

-- Include libraries
package.path = "/etc/MESHdesk/libs/?.lua;" .. package.path;

local fs    = require('nixio.fs');
local json  = require("json");
local uci   = require('uci');
local sys   = require("luci.sys")

require("rdLogger");
require("rdConfig");
require("rdNetwork");

local l   	    = rdLogger();
local url       =  'cake3/rd_cake/node-reports/submit_rogue_report.json';
local url       = url.."?_dc="..os.time();
local radio     = 'radio0';
local res_file  = '/tmp/rogue_report_result.json';

local j         = require("json")
local proto     = uci.get("meshdesk", "internet1", "protocol");
local server    = uci.get("meshdesk", "internet1", "ip");

local id_if     = uci.get("meshdesk", "settings", "id_if");
local mode      = uci.get("meshdesk", "settings", "mode");
 
local conf      = rdConfig();
local mac       = conf:getMac(id_if);

local n         = rdNetwork();
local local_ip_v6   = n:getIpV6ForInterface('br-lan');

if(local_ip_v6)then
    server      = uci.get("meshdesk", "internet1", "ip_6");
    server      = '['..server..']';
end

local http_port     = uci.get('meshdesk','internet1','http_port');
local https_port    = uci.get('meshdesk','internet1','https_port');
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

local query         = proto .. "://" .. server .. port_string .. url;

local iw            = sys.wifi.getiwinfo(radio);
local tblRogues     = iw.scanlist
local strRogues     = json.encode(tblRogues);

local s_scanData    = '"scan_data":' .. strRogues;
local s_mac         = '"mac": "' .. mac..'"';
local s_mode        = '"mode": "'.. mode..'"';

local curl_data     =   '{'..s_scanData..','..s_mac..','..s_mode..'}';
print(curl_data);

--Remove old results                                                                                              
os.remove(res_file)
os.execute('curl -k -o '..res_file..' -X POST -H "Content-Type: application/json" -d \''..curl_data..'\' '..query)


