#!/usr/bin/lua


local luci_json    = require('luci.jsonc');
local luci_util    = require('luci.util'); --26Nov 2020 for posting command output

local reply     = luci_util.exec("cat /etc/config/system");

json = luci_json.stringify({ item = reply, values = { 1, 2, 3 } }) 
print(json)  -- '{"item":true,"values":[1,2,3]}'

--local s_reply   = json.encode(reply);
