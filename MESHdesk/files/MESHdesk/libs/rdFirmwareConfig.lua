require( "class" )

-------------------------------------------------------------------------------
-- A class to report and configure the MESHdesk Firmware -------------
-------------------------------------------------------------------------------
class "rdFirmwareConfig"

--Init function for object
function rdFirmwareConfig:rdFirmwareConfig()
    require('rdLogger');
    require('rdExternal');
    require('rdNetwork');

    local uci 	    = require("uci")
	self.version 	= "1.0.0"
	self.logger	    = rdLogger()
    self.external   = rdExternal()
	self.debug	    = true
    self.x		    = uci.cursor()
	self.socket    	= require("socket")
    self.tcp        = nil
    self.network    = rdNetwork
end
        
function rdFirmwareConfig:getVersion()
	return self.version
end

function rdFirmwareConfig:runConfig()
    self:__runConfig()
end

function rdFirmwareConfig:log(m,p)
	if(self.debug)then
		self.logger:log(m,p)
	end
end



--[[--
========================================================
=== Private functions start here =======================
========================================================
(Note they are in the pattern function <rdName>._function_name(self, arg...) and called self:_function_name(arg...) )
--]]--

-- Run the config - send and receive                                               
function rdFirmwareConfig.__runConfig(self)

    local host      = self.x.get('meshdesk', 'settings','config_server')
    local port      = self.x.get('meshdesk', 'settings','config_port')
    local secret    = self.x.get('meshdesk', 'settings','shared_secret')

    self.tcp 	    = assert(self.socket.tcp()) --Create a tcp connection
    self.tcp:connect(host, port)                --Connect to the host
    self.tcp:settimeout(5)
    self:__md5check(secret)
	self.tcp:close()    --Close the connection
end

function rdFirmwareConfig.__sData(self,s)
	self.tcp:send(s)
end

function rdFirmwareConfig.__rData(self)
    local retval = nil
    while true do
        local s, status, partial = self.tcp:receive("*l")
        --If we send from the server with a "\n" we can read the whole line
        if(s)then
            retval = s
	    break
        end

        if status == 'timeout' then
            print('Connection timed out no response from server')
            break
        end
        if status == "closed" then
	    print("Server closed the connection") 
	    break 
        end
    end
    return retval
end

--Function that request the md5sum of the shared secret from the server
function rdFirmwareConfig.__md5check(self,shared_secret)

    --The letter 'a' asks the server to send us the md5sum of the secret
    self:__sData('a')
    local md5sum = self:__rData()
    if(md5sum)then
        print("The MD5Sum from the server is "..md5sum)
        if(string.find(md5sum, "md5sum="))then
            print("Correct data"..shared_secret)
            local filter_md5= string.gsub(md5sum, "md5sum=", "")
            --We had to use this as the LUA MD5 lib chockes on OpenWRT
            local m         = self.external:getOutput("echo -n '"..shared_secret.."' | md5sum") 
            m               = string.gsub(m, "%s+-\n", "")

            if(filter_md5 == m)then
                print("MD5sums are matching - go on")
		        self:__send_my_info()
		        self:__get_my_settings()
	        else
                print("MD5sums not matching - notify and terminate")
	            self:__sData('x')
	            self:__sData("Mismatch of the shared secrets\n")
	            self.tcp:close()
            end
        end
    else
        print("MD5Sum not sent from server, terminating the connection")
        self.tcp:close()
    end
end

--Function that sends the info of the device to the server
--The server needs to respond with 'ok' each time
function rdFirmwareConfig.__send_my_info(self)

    --The letter 'b' will inform the server there is local info about the device on its way
    local a         = {}

    --Insert id_if (typically eth0)
    local id_if   = self.x.get('meshdesk','settings','id_if');
    local id      = self.network:getMac(id_if)
    table.insert(a, 'eth0='..id) --FIXME Change the Node Config Utility to take whatever is specified

    --Insert server
    local server    = self.x.get('meshdesk', 'internet1','ip')
    table.insert(a, 'server='..server)
    
    --Insert protocol
    local protocol = self.x.get('meshdesk', 'internet1','protocol')
    table.insert(a, 'protocol='..protocol)

    --Insert firmware
    io.input("/etc/openwrt_release")
	local v = io.read("*all")
    v       = string.gsub(v, "\n", "|")
    v       = string.gsub(v, "DISTRIB_", "")
    table.insert(a, 'firmware='..v)

	--Insert the current client key
	local key = self.x.get('meshdesk','wifi_client','key')
	table.insert(a, 'key='..key)
	
	--Insert the current mode of the node
	local mode = self.x.get('meshdesk','settings','mode')
	table.insert(a, 'mode='..mode)

    for i, v in ipairs(a) do
	    self:__sData('b')
	    self:__sData(v.."\n")
	    local r = self:__rData()
	    print("GOT:"..r..":END")
	    if(r ~='ok')then --Stop of we don't get 'ok' back each time
		    print("Did not get an ok back")
		    break
	    end
    end
end

function rdFirmwareConfig.__get_my_settings(self)

    self:__sData('c') --Tell the server to send the settings along
    
    local next_setting      = true
    local mobile_settings   = {}
    local web_by_wifi       = {}
    
    while(next_setting)do
        local s = self:__rData()
        print("==== Settings from the server ====")
	    print(s)
	    print('-----------------------------')
        if(string.find(s, "hardware="))then
            local hw = string.gsub(s, "hardware=", "")
			self:__set_up_hardware(hw)
            self.x.set('meshdesk','settings','hardware',hw)
            self.x.commit('meshdesk')
        end
        
        if(string.find(s, "protocol="))then
            local protocol = string.gsub(s, "protocol=", "")
            self.x.set('meshdesk','internet1','protocol',protocol)
            self.x.commit('meshdesk')
        end
        

        if(string.find(s, "server="))then
            local ip = string.gsub(s, "server=", "")
            self.x.set('meshdesk','internet1','ip',ip)
            self.x.commit('meshdesk')
        end

        if(string.find(s, "secret="))then
            local secret = string.gsub(s, "secret=", "")
            self.x.set('meshdesk','settings','shared_secret',secret)
            self.x.commit('meshdesk')
        end

		if(string.find(s, "key="))then
		    if(string.find(s, "w_key="))then
		        print("Not this key")
		    else
                local key = string.gsub(s, "key=", "")
			    self.x.set('meshdesk','wifi_client','key',key)
                self.x.commit('meshdesk')
            end
        end
        
        if(string.find(s, "mode="))then
            local mode = string.gsub(s, "mode=", "")
			self.x.set('meshdesk','settings','mode',mode)
            self.x.commit('meshdesk')
        end
        
        --Mobile (3G) things
        if(string.find(s, "m_active="))then
			mobile_settings['enabled'] = string.gsub(s, "m_active=", "")
        end
        
        if(string.find(s, "m_proto="))then
			mobile_settings['proto'] = string.gsub(s, "m_proto=", "")
        end
        
        if(string.find(s, "m_service="))then
			mobile_settings['service'] = string.gsub(s, "m_service=", "")
        end
        
        if(string.find(s, "m_device="))then
			mobile_settings['device'] = string.gsub(s, "m_device=", "")
        end
        
        if(string.find(s, "m_apn="))then
			mobile_settings['apn'] = string.gsub(s, "m_apn=", "")
        end
        
        if(string.find(s, "m_pincode="))then
			mobile_settings['pincode'] = string.gsub(s, "m_pincode=", "")
        end
        
        if(string.find(s, "m_username="))then
			mobile_settings['username'] = string.gsub(s, "m_username=", "")
        end
        
        if(string.find(s, "m_password="))then
			mobile_settings['password'] = string.gsub(s, "m_password=", "")
        end
        --END Mobile (3G) things
        
        
        --Web By WiFi things
        if(string.find(s, "w_active="))then
            local w_active = string.gsub(s, "w_active=", "")
            if(w_active == '1')then
			    web_by_wifi['disabled'] = "0"
		    else
		        web_by_wifi['disabled'] = "1"
		    end  
        end
        
        if(string.find(s, "w_radio="))then
			web_by_wifi['device'] = string.gsub(s, "w_radio=", "")
        end
        
        if(string.find(s, "w_encryption="))then
			web_by_wifi['encryption'] = string.gsub(s, "w_encryption=", "")
        end
        
        if(string.find(s, "w_ssid="))then
			web_by_wifi['ssid'] = string.gsub(s, "w_ssid=", "")
        end
        
        if(string.find(s, "w_key="))then
			web_by_wifi['key'] = string.gsub(s, "w_key=", "")
        end
          
        --END Web By WiFi things
        
	if(s == 'last')then
		next_setting = false	
	end
	
    --See if there were mobile data
    if(mobile_settings['enabled'] ~= nil)then   
        if(mobile_settings['enabled'] == '0')then
        
            --Only if it is there, gently remove it
            self.x.foreach('meshdesk','interface', 
	            function(a)
	                if(a['.name'] == 'wwan')then
	                    --We found our man
		                self.x.set('meshdesk',a['.name'],'enabled',mobile_settings['enabled'])
		                self.x.commit('meshdesk')
	                end
            end)
        end
        
        if(mobile_settings['enabled'] == '1')then
            --Remove existing one if there was one--
            self:__clear_mobile() 
            --Create a new one--
            self.x.set('meshdesk', 'wwan', "interface")
	        self.x.commit('meshdesk')	
	        --Populate it 
	        for key, val in pairs(mobile_settings) do  
	             self.x.set('meshdesk', 'wwan',key, val)
	        end
	        self.x.commit('meshdesk')
        end
    end
    
    --See if there were web_by_wifi
    if(web_by_wifi['disabled'] ~= nil)then   
        if(web_by_wifi['disabled'] == '1')then
        
            --Only if it is there, gently remove it
            self.x.foreach('meshdesk','wifi-iface', 
	            function(a)
	                if(a['.name'] == 'web_by_wifi')then
	                    --We found our man
		                self.x.set('meshdesk',a['.name'],'disabled',web_by_wifi['disabled'])
		                self.x.commit('meshdesk')
	                end
            end)
        end
        
        if(web_by_wifi['disabled'] == '0')then
            --Remove existing one if there was one--
            self:__clear_web_by_wifi() 
            --Create a new one--
            self.x.set('meshdesk', 'web_by_wifi', "wifi-iface")
	        self.x.commit('meshdesk')	
	        --Populate it 
	        for key, val in pairs(web_by_wifi) do  
	             self.x.set('meshdesk', 'web_by_wifi',key, val)
	        end
	        --Add these two always
	        self.x.set('meshdesk', 'web_by_wifi','mode', 'sta')
	        self.x.set('meshdesk', 'web_by_wifi','network','web_by_wifi')
	        self.x.commit('meshdesk')
        end
    end
	
	self:__sData("ok\n")
    end
end

function rdFirmwareConfig.__set_up_hardware(self,hw)
	--Only if there are a change in the hardware
	local current_hw = self.x.get('meshdesk','settings','hardware')
	if(current_hw ~= hw)then
		self.x.set('meshdesk','settings','hardware',hw)
        self.x.commit('meshdesk')
	end

	--Add a fresh one if different
	local model_led 	= self.x.get('meshdesk',hw,'wifi_led')
	local current_led	= self.x.get('system','wifi_led', 'sysfs')
	if(model_led == current_led)then
		self:log("Wifi LEDs same - return")
		return
	end

	if(model_led == nil)then
		self:log("No WiFi LED defined - return")
		return
	end

	self:log("Wifi LEDs new config")

	--Now we need to get rid of all the LED entries and populate it with ours
	self.x.foreach('system','led', 
		function(a)
			self.x.delete('system',a['.name'])
	end)

	--Add a fresh one
	local wifi_led = self.x.set('system', 'wifi_led', "led")
	self.x.commit('system')	
	self.x.set('system', 'wifi_led','name', 'wifi')
	self.x.commit('system')	
	self.x.set('system', 'wifi_led','sysfs', 	model_led)
	self.x.commit('system')	
	self.x.set('system', 'wifi_led','trigger','netdev')	
	self.x.commit('system')	
	self.x.set('system', 'wifi_led', 'dev', 	'bat0')		
	self.x.commit('system')	
	self.x.set('system', 'wifi_led', 'mode',  'link tx rx')
	self.x.commit('system')	

end

function rdFirmwareConfig.__clear_mobile(self)
    --Now we need to get rid of the wwan interface entry
	self.x.foreach('meshdesk','interface', 
		function(a)
		    if(a['.name'] == 'wwan')then
		        --We found our man
			    self.x.delete('meshdesk',a['.name'])
			    self.x.commit('meshdesk')
		    end
	end)
end

function rdFirmwareConfig.__clear_web_by_wifi(self)
    --Now we need to get rid of the wwan interface entry
	self.x.foreach('meshdesk','wifi-iface', 
		function(a)
		    if(a['.name'] == 'web_by_wifi')then
		        --We found our man
			    self.x.delete('meshdesk',a['.name'])
			    self.x.commit('meshdesk')
		    end
	end)
end



