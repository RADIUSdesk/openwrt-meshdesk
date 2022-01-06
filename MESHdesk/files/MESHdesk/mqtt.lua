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
MQTT_USER = mqtt_data['mqtt_user']
MQTT_PASS = mqtt_data['mqtt_password']
MQTT_HOST = mqtt_data['mqtt_server_url']
FW_HOST = "amp-dev01.mesh-manager.com"

-- Enable Debugging
debug = true

client          = mqtt.new()

client.ON_CONNECT = function()
        -- Subscribe to topic
        print("Connected to Broker at : ", MQTT_HOST)
        -- client:subscribe("$SYS/#")
        local mesh_id = utils.getMeshID()
        if mesh_id == nil then
            print("This node does not belong to a MESH!")
        else
            local mid = client:subscribe("/AMPLE/NODE/" .. mesh_id .. "/COMMAND", 1) -- QoS 0
        end
end

client.ON_MESSAGE = function(mid, topic, payload)
    -- Parse/Decode JSON Payload
    local jsonStr           = luci_json.parse(payload)
    -- Check if message belongs to us (MAC Address)
    local nodeMacAddr       = utils.getNodeMacAddress();
    local meshNodeMacAddr   = string.upper(jsonStr['mac']);      
    if (utils.getCount(jsonStr) > 0 and nodeMacAddr == meshNodeMacAddr) then
        for k,v in pairs(jsonStr) do
            print(string.format("%s : %s", k, v))
        end

        local macAddr   = jsonStr['mac'];
        local nodeId    = jsonStr['node_id'];
        local meshId    = jsonStr['mesh_id'];
        local qos       = 1;
        local retain    = false;
        local message   = '';
        local cmdTopic  = mqtt_data['mqtt_command_topic'];

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
            print(message);
            client:publish(cmdTopic, json.encode(message), qos, retain)
            os.execute('reboot');
        else
            -- Run OS Command
            local cmdId = jsonStr['cmd_id']
            
            --Here depending on the value of jsonStr['action'] we will either just execute the command or execute and report the output
            if(jsonStr['action'] == 'execute')then
            
                local message = luci_json.stringify({node_id=nodeId,mesh_id=meshId,mac=macAddr,cmd_id=cmdId,status='os_command'})
                client:publish(cmdTopic, message, qos, retain)
                os.execute(jsonStr['cmd'])
            end
            
            if(jsonStr['action'] == 'execute_and_reply')then 
            
                fetched_client  = mqtt.new();
                fetched_client:login_set(MQTT_USER, MQTT_PASS)
                fetched_client:connect(MQTT_HOST)

                fetched_client.ON_CONNECT = function()       
                    local message = luci_json.stringify({node_id=nodeId,mesh_id=meshId,mac=macAddr,cmd_id=cmdId,status='fetched'})
                    fetched_client:publish(cmdTopic, message, qos, retain)
                end

                fetched_client.ON_PUBLISH = function()
                    fetched_client:disconnect()
                end
                fetched_client:loop_forever()                 
                                        
                local r     = luci_util.exec(jsonStr['cmd']);
                local j_r   = luci_json.stringify({reply=r,node_id=nodeId,mesh_id=meshId,mac=macAddr,cmd_id=cmdId,status='replied'}) 
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
