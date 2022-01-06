#!/usr/bin/lua
-- Include libraries
package.path = "../libs/?.lua;./libs/?.lua;/etc/MESHdesk/libs/?.lua;" .. package.path

require('luci.util');
require('nixio.fs');
require('luci.json');

--SOME DEFAULT VALUES--
local nasid     = "TEST_NASID";
local report_to = "cloud.radiusdesk.com";
local cfg_file  = "/etc/chilli/config";

local result_file   = '/tmp/fresult.json';

function getInfo()
    local file = io.open(cfg_file);
    if file then
        for line in file:lines() do
         if(string.match(line, '^%s*HS_NASID%s*=%s*'))then
            nasid = string.gsub(line, '^%s*HS_NASID%s*=%s*', "");
            print("Found NASID "..line.."I");
         end
         if(string.match(line, '^%s*HS_RADIUS%s*=%s*'))then
            report_to = string.gsub(line, '^%s*HS_RADIUS%s*=%s*', "");
            print("Found RADIUS "..line.."H");
         end
        end
        file:close();
    else
        error(config_file..' not found');
    end
end


function main()
	require("rdSoftflowLogs")
	local s = rdSoftflowLogs()
	print("Version is " .. s:getVersion())
	--s:chilliInfo();	
	local flows = s:doDumpFlows();		
	local curl_data = '{"report_type":"softflow","nasid":"'..nasid..'","flows":'..luci.json.encode(flows)..'}';
	local query     = "http://" .. report_to .. "/cake3/rd_cake/softflows/report.json";
	--local query     = "http://cloud.radiusdesk.com/cake3/rd_cake/softflows/report.json";

	os.remove(result_file)  
    os.execute('curl -k -o '..result_file..' -X POST -H "Content-Type: application/json" -d \''..curl_data..'\' '..query);	
end

getInfo();
main();


