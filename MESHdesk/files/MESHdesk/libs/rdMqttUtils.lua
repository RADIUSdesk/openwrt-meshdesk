local nfs = require("nixio.fs")
local json = require("json")
local http = require("socket.http")
local ltn12 = require("ltn12")
local sck = require("socket")
require("rdLogger")

local rdMqttUtils = {}
local lg = rdLogger()

debug = false

function rdMqttUtils.fileExists(name)
   local f=io.open(name,"r")
   if f~=nil then io.close(f) return true else return false end
end

function rdMqttUtils.getCount(tbl)
    local cntr = 0
    for i in pairs(tbl) do
        cntr = cntr + 1
    end

    return cntr
end

function rdMqttUtils.log(m,p)
	if (debug) then
		lg:log(m,p)
	end
end

function rdMqttUtils.sleep(sec)
    sck.select(nil, nil, sec)
end

function rdMqttUtils.getMqttData()
    local mqtt_data = {}
    local config_file = '/etc/MESHdesk/configs/current.json'

    if rdMqttUtils.fileExists(config_file) then
        local cfg = nfs.readfile(config_file)
        local config_data = json.decode(cfg)

        if config_data['success'] == true then
            local systm = config_data['config_settings']['system']
            
            mqtt_data['mqtt_user'] = systm['mqtt_user']
            mqtt_data['mqtt_password'] = systm['mqtt_password']
            mqtt_data['mqtt_server_url'] = systm['mqtt_server_url']
            mqtt_data['mqtt_command_topic'] = systm['mqtt_command_topic']

            return mqtt_data
        else
            return nil   
        end
    else
        return nil
    end
    
end

function rdMqttUtils.getMeshID()
    local config_file = '/etc/MESHdesk/configs/current.json'

    if rdMqttUtils.fileExists(config_file) then
        local cfg = nfs.readfile(config_file)
        local config_data = json.decode(cfg)

        if config_data['success'] == true then
            local wireless = config_data['config_settings']['wireless']
            local mesh_id = ""

            for k,wifi in pairs(wireless) do
                local wifi_iface = wifi['wifi-iface']
                -- if wifi_iface ~= nil and wifi_iface == 'zero' then
                if wifi_iface ~= nil and string.match(wifi_iface, 'zero') then
                    mesh_id = mesh_id .. wifi['options']['mesh_id']
                    break
                end
            end

            if mesh_id ~= nil then
                return string.upper(string.gsub(mesh_id,'_','-'))
            else
                return mesh_id
            end
        else
            return nil   
        end
    else
        return nil
    end
    
end

function rdMqttUtils.getNodeMacAddress()
    local config_file = '/etc/MESHdesk/configs/current.json'

    if rdMqttUtils.fileExists(config_file) then
        local cfg = nfs.readfile(config_file)
        local config_data = json.decode(cfg)

        if config_data['success'] == true then
            local ntwrk = config_data['config_settings']['network']
            local mac_address = ""

            for k,lan in pairs(ntwrk) do
                local lan_iface = lan['interface']
                if lan_iface ~= nil and lan_iface == 'lan' then
                    mac_address = mac_address .. lan['options']['macaddr']
                    break
                end
            end

            if mac_address ~= nil then
                return string.upper(string.gsub(mac_address,':','-'))
            else
                return mac_address
            end
        else
            return nil   
        end
    else
        return nil
    end
    
end

function rdMqttUtils.md5Check(checkfile)
	local md5result = false
	local handle = io.popen("md5sum -c " .. checkfile)
	local result = handle:read("*a")
	handle:close()
    
    if string.match(result, "OK") then
          md5result = true
          return md5result
    end
    
    return md5result
end

function rdMqttUtils.downloadLatestFirmware(fw_url, checkfile_url)
	-- Firmware Download Counter
    local fwcounter = 5
    local md5result = false
    local firmware_file_name = "latest-ta8h-fw.bin"
    local firmware_check_file = "latestfw_md5.txt"

    -- Remove Previous Firmware File(s)
    if rdMqttUtils.fileExists("/tmp/" .. firmware_file_name) then
        os.execute("rm /tmp/" .. firmware_file_name)
    end
    if rdMqttUtils.fileExists("/tmp/" .. firmware_check_file) then
        os.execute("rm /tmp/" .. firmware_check_file)
    end

    -- TODO: Remove this Temporary Addition for production
    if rdMqttUtils.fileExists("/tmp/dseries_forced.txt") then
        os.execute("rm /tmp/dseries_forced.txt")
    end
    if rdMqttUtils.fileExists("/tmp/dseries_normal.txt") then
        os.execute("rm /tmp/dseries_normal.txt")
    end

    -- Download Latest Firmware and MD5 Checksum File
    rdMqttUtils.downloadFile('/tmp/' .. firmware_file_name, fw_url)
    rdMqttUtils.downloadFile('/tmp/' .. firmware_check_file, checkfile_url)

    md5result = rdMqttUtils.md5Check("/tmp/" .. firmware_check_file)

    -- Try Downloading the Firmware Again
    while (md5result == false and fwcounter > 0) do
        -- Remove Previous Firmware File(s)
        if rdMqttUtils.fileExists("/tmp/" .. firmware_file_name) then
            os.execute("rm /tmp/" .. firmware_file_name)
        end
        if rdMqttUtils.fileExists("/tmp/" .. firmware_check_file) then
            os.execute("rm /tmp/" .. firmware_check_file)
        end
        
        rdMqttUtils.downloadFile('/tmp/' .. firmware_file_name, fw_url)
        rdMqttUtils.downloadFile('/tmp/' .. firmware_check_file, checkfile_url)

        md5result = rdMqttUtils.md5Check("/tmp/" .. firmware_check_file)

		fwcounter = fwcounter - 1
	end

	if (md5result == false) then
		return -1
	end

	return 0
end

function rdMqttUtils.downloadFile(file, fw_url)
    local fw = io.open(file, "a")

    http.request{ 
        url = fw_url, 
        sink = ltn12.sink.file(fw)
    }
    -- io.close(fw) -- Close Open File Handle
end

return rdMqttUtils