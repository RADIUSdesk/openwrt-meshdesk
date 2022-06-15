#!/usr/bin/lua

-- Include Libraries
package.path    = "libs/?.lua;" .. package.path
local mqtt      = require("mosquitto");
local luci_json = require('luci.jsonc');
local utils     = require("rdMqttUtils")
local luci_util = require('luci.util'); --26Nov 2020 for posting command output 

local mqtt_data = utils.getMqttData()

print(mqtt_data['mqtt_server_url'])

if mqtt_data == nil then
    -- Terminate script and process
    os.exit()
end

-- MQTT Credentials
MQTT_USER = mqtt_data['mqtt_user'];
MQTT_PASS = mqtt_data['mqtt_password'];
MQTT_HOST = mqtt_data['mqtt_server_url'];
FW_HOST   = "cloud.radiusdesk.com";

-- Enable Debugging
debug   = true;
client  = mqtt.new()

client.ON_CONNECT = function()
    -- Subscribe to topic
    print("Connected to Broker at : ", MQTT_HOST)
    -- client:subscribe("$SYS/#")
    local meta_data = utils.getMetaData();
    if meta_data == nil then
        print("This node does not have any Meta Data in its config")
    else
        --If it is in mesh mode
        if(meta_data.mode == 'mesh')then
            local node_id = meta_data.node_id;
            local mid = client:subscribe("/RD/MESH/" .. node_id .. "/COMMAND", 1) -- QoS 0
        end
        --If it is in ap mode
        if(meta_data.mode == 'ap')then
            local ap_id = meta_data.ap_id;
            local mid = client:subscribe("/RD/AP/" .. ap_id .. "/COMMAND", 1) -- QoS 0
        end
    end
end

client.ON_MESSAGE = function(mid, topic, payload)
    -- Parse/Decode JSON Payload
    local jsonStr           = luci_json.parse(payload)
    -- Check if message belongs to us (MAC Address)

    local meta_data         = utils.getMetaData();
    local unitMacAddr       = meta_data.mac;
    local meshNodeMacAddr   = string.upper(jsonStr['mac']);      
    if (utils.getCount(jsonStr) > 0 and unitMacAddr == meshNodeMacAddr) then
        for k,v in pairs(jsonStr) do
            print(string.format("%s : %s", k, v))
        end
        
        local mode      = jsonStr['mode'];--Jun2022 Add mode 
        local macAddr   = jsonStr['mac'];
        local nodeId    = jsonStr['node_id'];--Will be null for APdesk
        local meshId    = jsonStr['mesh_id'];--Will be null for APdesk
        local apId      = jsonStr['ap_id'];--Will be null for MESHdesk
        local qos       = 1;
        local retain    = false;
        local message   = '';
        local cmdTopic  = mqtt_data['mqtt_command_topic']; -- /RD/NODE/COMMAND/RESPONSE

        if (jsonStr['cmd'] == 'fetch_config') then
            -- Fectch Config
            message = message..'{"node_id": '..nodeId..', "mesh_id": "'..meshId..'", "mac": "'..macAddr..'", "status": "config_fetched"}'
            print(message)

            client:publish(cmdTopic, json.encode(message), qos, retain)
            -- FIX: A more drastic approach to fetching config
            os.execute('reboot')
            
        elseif (jsonStr['cmd'] == 'check_for_coa') then
            -- Possible COA / POD waiting 
            local cmdId = jsonStr['cmd_id']
            message = message..'{"node_id": '..nodeId..', "mesh_id": "'..meshId..'", "mac": "'..macAddr..'", "cmd_id": "'..cmdId..'", "status": "check_for_coa"}'
            print(message);
            client:publish(cmdTopic, json.encode(message), qos, retain)                
            os.execute('/etc/MESHdesk/reporting/check_for_coa.lua')
            
         elseif (jsonStr['cmd'] == 'reboot') then
            -- Reboot Node
            local cmdId = jsonStr['cmd_id']
            message = message..'{"node_id": '..nodeId..', "mesh_id": "'..meshId..'", "mac": "'..macAddr..'", "cmd_id": "'..cmdId..'", "status": "reboot"}'
            client:publish(cmdTopic, json.encode(message), qos, retain)
            os.execute('reboot');
        else
            -- Run OS Command
            local cmdId = jsonStr['cmd_id']
            
            --Here depending on the value of jsonStr['action'] we will either just execute the command or execute and report the output
            if(jsonStr['action'] == 'execute')then
                print("MODE IS "..mode);
                if(mode == 'mesh')then
                    message = luci_json.stringify({mode=mode,node_id=nodeId,mesh_id=meshId,mac=macAddr,cmd_id=cmdId,status='os_command'});
                end
                if(mode == 'ap')then
                    message = luci_json.stringify({mode=mode,ap_id=apId,mac=macAddr,cmd_id=cmdId,status='os_command'});
                end              
                client:publish(cmdTopic, message, qos, retain)
                os.execute(jsonStr['cmd'])
            end
            
            if(jsonStr['action'] == 'execute_and_reply')then 
            
                fetched_client  = mqtt.new();
                fetched_client:login_set(MQTT_USER, MQTT_PASS)
                fetched_client:connect(MQTT_HOST)
                
                fetched_client.ON_CONNECT = function()
                    if(mode == 'mesh')then
                        message = luci_json.stringify({mode=mode,node_id=nodeId,mesh_id=meshId,mac=macAddr,cmd_id=cmdId,status='fetched'});
                    end
                    if(mode == 'ap')then
                        message = luci_json.stringify({mode=mode,ap_id=apId,mac=macAddr,cmd_id=cmdId,status='fetched'});
                    end
                    fetched_client:publish(cmdTopic, message, qos, retain)
                end

                fetched_client.ON_PUBLISH = function()
                    fetched_client:disconnect()
                end
                fetched_client:loop_forever()                 
                                        
                local r     = luci_util.exec(jsonStr['cmd']);
                local j_r   = luci_json.stringify({});
                if(mode == 'mesh')then
                    j_r     = luci_json.stringify({mode=mode,reply=r,node_id=nodeId,mesh_id=meshId,mac=macAddr,cmd_id=cmdId,status='replied'}) 
                end
                if(mode == 'ap')then
                    j_r     = luci_json.stringify({mode=mode,reply=r,ap_id=apId,mac=macAddr,cmd_id=cmdId,status='replied'}) 
                end
                client:publish(cmdTopic, j_r, qos, retain)                   
            end                 
        end
    end        
end

-- TODO: Remove for Production
client.ON_LOG = function(lvl, msg)
    print(msg)
end


client:login_set(MQTT_USER, MQTT_PASS)
client:connect(MQTT_HOST)
client:loop_forever()
