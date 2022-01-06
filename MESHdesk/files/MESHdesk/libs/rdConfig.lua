require( "class" )

-------------------------------------------------------------------------------
-- A class to fetch the configuration for the mesh and return it as a file ----
-------------------------------------------------------------------------------
class "rdConfig"

--Init function for object
function rdConfig:rdConfig()
	require('rdLogger');
	require('rdExternal');
	require('rdNetwork');
	require('luci.http');
    local uci 	    = require("uci");
    self.socket     = require("socket");
        
	self.version 	= "1.0.0"
	self.sleep_time = 1;
	self.json	    = require("json")
	self.logger	    = rdLogger()
	self.external	= rdExternal()
	self.n          = rdNetwork();
	
	self.debug	    = true
	--self.debug	    = false
    self.x		    = uci.cursor();

    self.ping_counts    = 3
    self.ok_ping_count  = 2
    self.retry_count    = 5
    self.current_try    = 0

    --Determine the Files to use--
	self.new_file = self.x.get('meshdesk', 'settings','config_file');
    self.old_file = self.x.get('meshdesk', 'settings','previous_config_file');
    self.protocol = self.x.get('meshdesk', 'internet1','protocol');
    
    --Files that exists when connection is up
    self.lan_up_file    = self.x.get('meshdesk','settings','lan_up_file');
    self.wifi_up_file   = self.x.get('meshdesk','settings','wifi_up_file');
    self.wbw_up_file    = self.x.get('meshdesk','settings','wbw_up_file');

    
    --Settings For Config Captive Portal
    self.fs         = require('nixio.fs');
    self.nixio      = require("nixio");
    self.util       = require('luci.util');
    self.sys        = require('luci.sys');
    self.f_captive_config = '/etc/MESHdesk/configs/captive_config.json';   
    self.w_b_w_keep = {ifname=true, network=true, mode=true, device=true};
 
end
        
function rdConfig:getVersion()
	return self.version
end

function rdConfig:log(m,p)
	if(self.debug)then
	    print(m);
		self.logger:log(m,p)
	end
end

function rdConfig:pingTest(server)
	local handle = io.popen('ping -q -c ' .. self.ping_counts .. ' ' .. server .. ' 2>&1')
	local result = handle:read("*a")                          
	handle:close()     
	result = string.gsub(result, "[\r\n]+$", "")
	if(string.find(result," unreachable"))then --If the network is down
		return false
	end
	      
	result = string.gsub(result, "^.*transmitted,", "")       
	result = string.gsub(result, "packets.*$", "")            
	result = tonumber(result)                          
	if(result >= self.ok_ping_count)then  
		return true
	else
		return false
	end
end


--For the dynamic gateway internal testing
function rdConfig:httpTest(server,http_override)

        http_override = http_override or false --default value
    
        local proto  = self.protocol;
        if(http_override)then
            proto = 'http';
        end

        local url    = '/check_internet.txt'.."?_dc="..os.time();
        local handle = io.popen('curl --connect-timeout 10 -k -o /tmp/check_internet.txt  '..proto..'://' .. server .. url..' 2>&1')
        local result = handle:read("*a")
        handle:close()
        result = string.gsub(result, "[\r\n]", " ")
        self:log('Server Check Result: ' .. result)
        --if(string.find(result," error: "))then --If the network is down
        if((string.find(result,"rror"))or(string.find(result,'Failed to'))or(string.find(result,'timed out')))then --If the network is down
                return false
        else
                return true
        end
end


-- == CONFIGURE DEVICE ==
function rdConfig:configureDevice(config,doWanSynch)

    doWanSynch = doWanSynch or false --default value

	print("Configuring device according to " .. config);
	self:log("Configuring device according to " .. config);	
	local contents      = self:readAll(config)         
	local o             = self.json.decode(contents)  
	local ret_table     = {mac_not_defined = false,config_success = false};

    if(o.success == false)then --If the device was not yet assigned we need to give feedback about it
	    print("The server returned an error");
	    self:log("The server returned an error");

        --There might be an error message
	    if(o.error ~= nil)then
	        print(o.error);
	        self:log(o.error);
	        self:log("Setting the device in CP config mode")
	        ret_table.mac_not_defined = true;
	        return ret_table;
	    end

        --There might also be an option to point the device to another server for its settings
        if(o.new_server ~= nil)then
            self:log("Setting new config server to " .. o.new_server);
            self.x.set('meshdesk','internet1','dns',o.new_server);
            self.x.set('meshdesk','internet1','protocol',o.new_server_protocol); --We also add the protocol
            self.x.commit('meshdesk');
            self:reboot();
	        return;  
        end
             
        --Also an option return to base server (return_to_base)
        if((o.return_to_base ~= nil)and(o.return_to_base == true))then
            self:log("Returning the Hardware to Base server");
            local base_dns  = self.x.get('meshdesk','internet1','base_dns');
            local base_ip   = self.x.get('meshdesk','internet1','base_ip');
            self.x.set('meshdesk','internet1','dns',base_dns);
            self.x.set('meshdesk','internet1','ip',base_ip);
            self.x.commit('meshdesk');
            self:reboot();
	        return;  
        end
    end
    
    --Do we have wbw settings; if ensure its off
    if(o.config_settings.web_by_wifi ~= nil)then
        self:setWebByWifiFromTable(o.config_settings.web_by_wifi);
    else
        self:disableWebByWifi();
    end
    
    --Do we have reboot_setting; if ensure its off
    require("rdRebootSettings")
	local r = rdRebootSettings();
    if(o.config_settings.reboot_setting ~= nil)then
        r:configureFromTable(o.config_settings.reboot_setting);
    else
        r:clear();
    end
      
	-- Do we have any batman_adv settings? --
	if(o.config_settings.batman_adv ~= nil)then   
		--print("Doing Batman-adv")
        require("rdBatman")
	    local batman = rdBatman()
	    batman:configureFromTable(o.config_settings.batman_adv)             
	end
	-- Is this perhaps a gateway node? --
	if(o.config_settings.gateways ~= nil)then
		-- Set up the gateways --	
		require("rdGateway")
		local a = rdGateway()
		a:enable(o.config_settings) --We include everything if we want to use it in future		
	else
		-- Break down the gateways --
		require("rdGateway")
		local a = rdGateway()
		a:disable()
	end

	-- Do we have some network settings?       
	if(o.config_settings.network ~= nil)then   
		print("Doing network")
	    self.n:configureFromTable(o.config_settings.network)  
	    if(doWanSynch)then
	        self.n:doWanSynch();
	    end           
	end 
	
	-- Do we have some wireless settings?      
	if(o.config_settings.wireless ~= nil)then  
		print("Doing wireless")         
	    local w = rdWireless()    
	    w:configureFromTable(o.config_settings.wireless) 
	end  
    os.execute("/etc/init.d/network reload");
	-- Do we have some system settings?
	if(o.config_settings.system ~= nil)then  
		print("Doing system")
		require("rdSystem")           
	    local s = rdSystem()    
	    s:configureFromTable(o.config_settings.system) 
	end
    
	if(o.config_settings.gateways ~= nil)then	
		require("rdGateway");
		local a = rdGateway();
		a:restartServices();
	end

	self.external:startOne('/etc/MESHdesk/heartbeat.lua &','heartbeat.lua');
    self:log('Starting Batman neighbour scan');
    self.external:startOne('/etc/MESHdesk/batman_neighbours.lua &','batman_neighbours.lua');
    if(o.config_settings.captive_portals ~= nil)then
    	print("Doing Captive Portals");  	
    	--Wait for the network to come up properly--
    	--(resolv.conf.auto start out empty and are filled when DHCP is completed)
    	local wait_total    = 30;
    	local wait_start    = 1;
    	
    	--local rc_auto       = "/tmp/resolv.conf.auto"; --Up to 19.07
    	local rc_auto       = "/tmp/resolv.conf.d/resolv.conf.auto"; --Master July 2020
    	 	
    	while(wait_start < wait_total)do
            local size = self.fs.stat(rc_auto,'size');
            print("---RESOLV FILE SIZE---");
            print(size);
            print("---RESOLV FILE SIZE END---");
            if(size > 0)then
                self:log("Waited "..wait_start.." seconds for DHCP to complete");
                --We can exit the loop since it came up
                self:_sleep(15); --sleep 15 more seconds for everythin else to come up
                break;
            end
    	    self:_sleep(1);
    	    wait_start = wait_start + 1;
    	end  	
    	--END --
    	
    	require("rdCoovaChilli");
    	local a = rdCoovaChilli();
    	a:createConfigs(o.config_settings.captive_portals);                  
    	a:startPortals();
    	self:_sleep(10);
    	a:setDnsMasq(o.config_settings.captive_portals);	
    end
    
    if(o.config_settings.openvpn_bridges ~= nil)then
        print("Doing OpenVPN Bridges")
        require("rdOpenvpn")
	    local v = rdOpenvpn()
        v:configureFromTable(o.config_settings.openvpn_bridges)
        os.execute("/etc/init.d/openvpn start")
    end
         
    ret_table.config_success = true;
    return ret_table;
    
end
--== END CONFIGURE DEVICE ==


--This method will be used to try and reach the config server and fetch the configuration for the device--
--It specifies the method the device is connected to get Internet. Depending on this method the back-end will dynamically adjust the configuration
--Current Methods recognised is: 
-- 1.) lan  => node is gateway we assume
-- 2.) wifi => node is NOT gateway
-- 3.) wbw  => node is using wifi client and we this have to specify the channel so the back-end can adjust accordingly

function rdConfig:tryForConfigServer(method)
    print("Trying to reach the config server using "..method);
    self:log("Trying to reach the config server using "..method);
    self:log("==== RESTART DNS MASQ =====");
    os.execute("/etc/init.d/dnsmasq restart");
    local sleep = 5; --lan
    
    if(method == 'lan')then
        --See which protocol we are using
        local lan_proto = self.x.get('network','lan','proto');
        --self:log("==== PROTO IS "..lan_proto.." ====");
        if(lan_proto == 'pppoe')then
            --self:log("==== EXTEND SLEEP FOR PPPOE ====");
            sleep = 15; --We wait 15seconds for PPPOE to come up
        end
    end
        
    if(method == 'wifi')then --going onto the Mesh hidden SSID
        sleep = 10;
    end
    if(method == 'wbw')then
        sleep = 15; --going onto an unknown SSID
    end   
    self:_sleep(sleep);
    
	local got_settings	    = false; 
	local loop	            = true;
	local dhcp_try_flag     = false;
	local start_time	    = os.time();
	local config_file		= self.x.get('meshdesk','settings','config_file');
	local retry_counter     = 10;	
	local gw                = true;
	local dns_works         = false;
	local ret_table         = { got_settings = got_settings, dns_works = dns_works };
	
	if(method == 'wifi')then
	    gw = false;
	end
		
	--Prime the hostmane / ip table
	local server_tbl        = self:_get_ip_for_hostname();
	local server            = server_tbl.ip;
	
	if(server_tbl.v6_enabled)then
	    server            = server_tbl.ip_6;
	end
	
	--local id	= "A8-40-41-13-60-E3"
	local id_if         = self.x.get('meshdesk','settings','id_if');
	local id		    = self:getMac(id_if);
	local proto 	    = self.x.get('meshdesk','internet1','protocol');
	local url   	    = self.x.get('meshdesk','internet1','url');
	
	local http_port     = self.x.get('meshdesk','internet1','http_port');
    local https_port    = self.x.get('meshdesk','internet1','https_port');
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
	
	--***LOOP***
    while (retry_counter > 0) do  
		self:_sleep(self.sleep_time);		
		if(server_tbl.fallback)then
		    --Try again
		    self:log("Could not resolve "..server_tbl.hostname.." (try "..retry_counter..")");
		    server_tbl   = self:_get_ip_for_hostname();
		    server       = server_tbl.ip;
		    if(server_tbl.v6_enabled)then
	            server  = server_tbl.ip_6;        
	        end
	    else
            dns_works = true;
	        self:log(server_tbl.hostname.." resolved to "..server_tbl.ip.." using DNS");
		end
		
		--if(self:pingTest(server))then--Do httpTest by default rather
		if(self:httpTest(server))then
	        	self:log("Ping os server was OK try to fetch the settings");
	        	local query     = proto .. "://" .. server .. port_string .. url;
	        	if(server_tbl.v6_enabled)then
	                query     = proto .. "://[" .. server .. "]".. port_string .. url;        
	            end     
	        	print("Query url is " .. query );
	        	
	        	local od = {};
	        	if(method == 'wbw')then --wbw we need specify the channel to the back-end
	        	    local channel       = 0; --default
	        	    local wbw_device    = self.x.get('meshdesk','web_by_wifi','device');
                    local iw            = self.sys.wifi.getiwinfo(wbw_device);
	                od.wbw_channel      = iw.channel;
	                od.wbw_active       = 1;
	            end
	            
	        	if(self:fetchSettings(query,id,gw,od))then
		        	self:log("Cool -> got settings through "..method)
		        	got_settings = true;
		        	break --We can exit the loop
	        	end
        else
	        self:log("Ping Controller Failed through "..method.." (try "..retry_counter..")");
        end
      
        if(self:_is_interface_still_up(method))then --make sure the interface is still with us
            self:log("Interface for "..method.." is still up - retry");
            retry_counter = retry_counter - 1;
        else
            self:log("WARNING Interface for "..method.." is down");
            retry_counter = 0;  --Zero it to introduce a FAIL      
        end
        
        --Jun2021 introduce support of other protocols (besides dhcp)
        if((method == 'lan')and(lan_proto ~= 'dhcp')and(dhcp_try_flag == false))then
            if(retry_counter == 1)then
                --retry cpounter run out on non-dhcp on LAN--
                --set DHCP and retry again on LAN--
                dhcp_try_flag = true; -- One shot
                self.x.set('network','lan','proto','dhcp');            
                self.x.save('network');
                self.x.commit('network');
                retry_counter = 10;
                os.execute("/etc/init.d/network reload");
            end        
        end 
        
        if((method == 'lan')and(lan_proto ~= 'pppoe')and(dhcp_try_flag == false))then
            --self:log("**** PPPOE WAITED 15 Seconds and FAILED FALL BACK TO DHCP****  ");
            --retry cpounter run out on non-dhcp on LAN--
            --set DHCP and retry again on LAN--
            dhcp_try_flag = true; -- One shot
            self.x.set('network','lan','proto','dhcp');            
            self.x.save('network');
            self.x.commit('network');
            retry_counter = 10;
            os.execute("/etc/init.d/network reload"); 
        end        
                 
    end
    --*** END LOOP ***

    ret_table.got_settings  = got_settings;
    ret_table.dns_works     = dns_works;
    return ret_table; 
end

function rdConfig._is_interface_still_up(self,method)
    if(method == 'lan')then
        return self:_file_exists(self.lan_up_file);
    end
    
    if(method == 'wifi')then
        return self:_file_exists(self.wifi_up_file);
    end
    
    if(method == 'wbw')then
        return self:_file_exists(self.wbw_up_file);
    end
end


function rdConfig._get_ip_for_hostname(self)
    local server        = self.x.get('meshdesk','internet1','ip');
    local h_name        = self.x.get('meshdesk','internet1','dns');
    local server_6      = self.x.get('meshdesk','internet1','ip_6');
	local local_ip_v6   = self.n:getIpV6ForInterface('br-lan');
	local v6_enabled    = false;
	
	local base_ip       = self.x.get('meshdesk','internet1','base_ip');
    local base_dns      = self.x.get('meshdesk','internet1','base_dns');

	if(local_ip_v6)then
	    v6_enabled = true;
	end
    
    --For now we're not updating it     
    local return_table  = {fallback=true, ip=server, hostname=h_name,ip_6=server_6, v6_enabled=v6_enabled,base_ip=base_ip,base_dns=base_dns};
    
    --Current controller DNS Check
    local a             = self.nixio.getaddrinfo(h_name);
    if(a)then
        local ip = a[1]['address'];
        
        if(ip ~= server)then
            --Update the thing
            self.x.set('meshdesk','internet1','ip', ip);
	        self.x.save('meshdesk');
	        self.x.commit('meshdesk'); 
        end
        return_table.ip = ip;
        return_table.fallback = false;     
    end
      
    --Current controller DNS Check
    local b             = self.nixio.getaddrinfo(base_dns);
    if(b)then
        local b_ip = b[1]['address'];       
        if(b_ip ~= base_ip)then --Only if it was changed
            self.x.set('meshdesk','internet1','base_ip', b_ip);
	        self.x.save('meshdesk');
	        self.x.commit('meshdesk'); 
        end
        return_table.base_ip = b_ip;    
    end   
    return return_table;
end

function rdConfig._sleep(self,sec)
    self.socket.select(nil, nil, sec)
end
 
--END--

function rdConfig:fetchSettings(url,device_id,gateway,optional_data)
    optional_data   = optional_data or {};
	gateway         = gateway or false;
	if(gateway)then
		gw = "true";
	else
		gw = "false";
	end

	if(self:_file_exists(self.new_file))then
        self:log('Move '..self.new_file.." to "..self.old_file)
		os.execute("mv " .. self.new_file .. " " .. self.old_file)
	end

	local q_s       = {}	
	q_s['mac']      = device_id;
	q_s['gateway']  = gw;	
	--Add fw version to know how to adapt the back-end
	q_s['version'] = '19.07';
	--q_s['version']  = '18.06';		
	q_s['_dc']      = os.time();
	
	--Merge the optional data (only if there are any)--
	local next = next ;
	if(next(optional_data))then
        for k, v in pairs(optional_data) do
            if (type(v) == "table") and (type(q_s[k] or false) == "table") then
                merge(q_s[k], optional_data[k])
            else
                q_s[k] = v
            end
        end
    end
	
	--If there is a VLAN setting defined we should use it
	local use_vlan = self.x.get('meshdesk', 'lan', 'use_vlan');
	if(use_vlan == '1')then
	    local vlan_number = self.x.get('meshdesk','lan', 'vlan_number');
	    q_s['vlan_number'] = vlan_number;
	end
	
	local enc_string = luci.http.build_querystring(q_s);
	enc_string       = self:_urlencode(enc_string);
	self:log('QS '..enc_string..'END')
	url = url..enc_string;
	self:log('URL is '..url..'END')
	
      	local retval = os.execute("curl -k -o '" .. self.new_file .."' '" .. url .."'")
      	self:log("The return value of curl is "..retval)
      	if(retval ~= 0)then
      		self:log("Problem executing command to fetch config")
      		return false   
      	end
	if(self:_file_exists(self.new_file))then
        self:log("Got new config file "..self.new_file)
        if(self:_file_size(self.new_file) == 0)then
            self:log("File size of zero - not cool")
            return false
        else
            return true
        end
	else
        self:log("Failed to get latest config file")
		return false
	end
end

function rdConfig:prepCaptiveConfig(dns_works,wifi_flag)

    local wifi_flag = wifi_flag or false;

    --First we need to get some values that we will use to replace values in the file
    local id_if         = self.x.get('meshdesk','settings','id_if');
    local id            = self:getMac(id_if);
    local protocol      = self.x.get('meshdesk','internet1','protocol');
    local ip            = self.x.get('meshdesk','internet1','ip');
    local dns           = self.x.get('meshdesk','internet1','dns');
    local hardware      = self.x.get('meshdesk','settings','hardware');
    local http_port     = self.x.get('meshdesk','internet1','http_port');
    local https_port    = self.x.get('meshdesk','internet1','https_port');
    local port_string   = '';
    
    if(protocol == 'http')then
        if(http_port ~= '80')then
            port_string = ":"..http_port;
        end
    end
    
    if(protocol == 'https')then
        if(https_port ~= '443')then
            port_string = ":"..https_port;
        end
    end
     
    local cp_config     = self.f_captive_config;
    local strCpConfig   = self.fs.readfile(cp_config);
    local tblCpConfig   = self.json.decode(strCpConfig);
    
    local config_ssid   = 'two';
    
    local c_int         = 'web_by_w'; --Headsup Here we use 'web_by_w' -> The name used in wireless and network config files 
    local c_disabled    = '1'; --By default we disable the web-by-wifi
    if(wifi_flag)then
        c_disabled = '0';   
    end
    
    if(tblCpConfig.config_settings ~= nil)then
        --Wireless adjustments--
        if(tblCpConfig.config_settings.wireless ~= nil)then
            for k,v in pairs(tblCpConfig.config_settings.wireless) do 
                for key,val in pairs(v)do
                    --Do the Channel adjustment if needed
                    if(key == 'wifi-device')then
                        --We set the channel only if wifi_flag is set...
                        if(wifi_flag)then
                            local connInfo       = self:getWiFiInfo(); -- Get the web-by-wifi connection info it will have .channel and .hwmode 
                            --also .success => true / false to indicate if we should go ahead
                            local currChannel   = tblCpConfig.config_settings.wireless[k].options.channel;
                            local currMode      = tblCpConfig.config_settings.wireless[k].options.hwmode;
                            if(connInfo.success)then
                                if(connInfo.hwmode == currMode)then --Only if the mode (freq band) is the same e.g. 11g or 11a
                                    if(connInfo.channel ~= currChannel)then
                                        tblCpConfig.config_settings.wireless[k].options.channel = connInfo.channel;
                                    end
                                end
                            end
                        end
                    end
                    
                    --Write out the SSID
                    if(key == 'wifi-iface')then
                        if(val == config_ssid)then
                            tblCpConfig.config_settings.wireless[k].options.ssid = "CONFIG #"..id;
                        end
                    
                        --Endable the client interface
                        if(val == c_int)then
                            local currDisabled = tblCpConfig.config_settings.wireless[k].options.disabled;
                            if(currDisabled ~= c_disabled)then
                                tblCpConfig.config_settings.wireless[k].options.disabled = c_disabled;
                            end
                        end
                    end
                end
            end
        end
        
        --Network adjustments--
        if(tblCpConfig.config_settings.network ~= nil)then
            for k,v in pairs(tblCpConfig.config_settings.network) do
                for key,val in pairs(v)do
                    --Do the Channel adjustment if needed
                    if(key == 'interface')then
                        if(val == 'lan')then
                            if(wifi_flag)then
                                tblCpConfig.config_settings.network[k].options.proto = 'static';
                            else
                                tblCpConfig.config_settings.network[k].options.proto = 'dhcp';
                            end
                        end
                    end
                end
            end    
        end

        
        --===Maybe we can do the Captive Portals more correct in future===--
        tblCpConfig.config_settings.captive_portals[1].radius_1 = ip;
        tblCpConfig.config_settings.captive_portals[1].coova_optional = 'ssid '..id.."\n"..'vlan '..hardware.."\n";
        --Make it more robust to fallback to IP if DNS is not working 
        if(dns_works == true)then
            self:log('*** DNS WORKS ***');
            tblCpConfig.config_settings.captive_portals[1].uam_url = protocol..'://'..dns..port_string..'/conf_dev/index.html';    
        else
            self:log('*** DNS NOT WORKING ***');
            tblCpConfig.config_settings.captive_portals[1].uam_url = protocol..'://'..ip..port_string..'/conf_dev/index.html';
        end
        local strNewCpConf = self.json.encode(tblCpConfig);
        self.fs.writefile(cp_config,strNewCpConf);

    end
end


function rdConfig:checkCaptiveWebByWiFi()
    local cp_config     = self.f_captive_config;
    local strCpConfig   = self.fs.readfile(cp_config);
    local tblCpConfig   = self.json.decode(strCpConfig);
    
    if(tblCpConfig.config_settings.wireless[3].options.disabled == '0')then
        return true;
    end
    return false;
    
end

function rdConfig:getMac(interface)
	interface = interface or "eth0"
	io.input("/sys/class/net/" .. interface .. "/address")
	t = io.read("*line")
	dashes, count = string.gsub(t, ":", "-")
	dashes = string.upper(dashes)
	return dashes
end

function rdConfig:getWiFiInfo()
    local connInfo      = {}; 
    connInfo.success    = false;
    --local iwinfo        = self.sys.wifi.getiwinfo('wlan0'); --FIXME WILL THIS STILL BE wlan0 when radio1 is used? please check
    
    local wbw_device    = self.x.get('meshdesk','web_by_wifi','device');
    local iwinfo        = self.sys.wifi.getiwinfo(wbw_device);
    
    if(iwinfo.channel)then
        connInfo.success = true;
        connInfo.channel = iwinfo.channel;
        local hw_modes   = iwinfo.hwmodelist or { };
        if(hw_modes.g)then
            connInfo.hwmode  = '11g';   
        end     
    end 
    return connInfo;
end

function rdConfig:setWebByWifiFromTable(wbw)
     local mod_flag = false;
     local dis = self.x.get('meshdesk','web_by_wifi','disabled');     
     for k, v in pairs(wbw) do
        local c_val = self.x.get('meshdesk','web_by_wifi',k);
        local n_val = v;
        if(c_val ~= nil)then           
            if(c_val ~= n_val)then -- Only if there are changes
                self:log('==WBW== change '..c_val.." to "..n_val);
                self.x.set('meshdesk','web_by_wifi',k,n_val);
                mod_flag = true;
            end
        else
            self:log('==WBW== addition '..n_val);
            self.x.set('meshdesk','web_by_wifi',k,n_val);
            mod_flag = true;
        end
    end
    
    self.x.foreach('meshdesk', 'wifi-iface', function(a)
        if(a['.name'] == 'web_by_wifi')then
            for key, val in pairs(a) do
                if(string.find(key, '.', 1, true) == nil)then
                    --See if it is in the new settings and if it is in the required list / if not delete it
                    if ((self.w_b_w_keep[key])or(wbw[key])) then 
                        self:log('==WBW== keep '..key);
                    else
                        self:log('==WBW== delete '..key);
                        self.x.delete('meshdesk','web_by_wifi',key);
                        mod_flag = true;   
                    end
                end
            end
	    end  
    end)
    
    
    if(dis == '1')then
        self.x.set('meshdesk','web_by_wifi','disabled','0'); --Enable it
        mod_flag = true;
    end
           
    if(mod_flag == true)then
        self.x.set('meshdesk','web_by_wifi','disabled','0'); --Enable it
        self.x.commit('meshdesk');
    end
end

function rdConfig:disableWebByWifi()
    local c_dis = self.x.get('meshdesk','web_by_wifi','disabled');
    if(c_dis ~= '1')then
        self:log('==WBW== found to be '..c_dis..' need to disable it');
        self.x.set('meshdesk','web_by_wifi','disabled','1');
        self.x.commit('meshdesk');    
    end    
end

function rdConfig:ignoreWebByWifiCheck()
    local config_file	    = self.x.get('meshdesk','settings','config_file');
    local contents          = self.fs.readfile(config_file);
	local tblConfig         = self.json.decode(contents);	
	local ignore            = true;
	self:log('==WBW== look for WBW settings');
	
	if(tblConfig.config_settings ~= nil)then
	    if(tblConfig.config_settings.web_by_wifi ~= nil)then
	        self:log('==WBW== found WBW settings');
            self:setWebByWifiFromTable(tblConfig.config_settings.web_by_wifi);
        else
            self:disableWebByWifi();
        end
    end
    
    self:log('==WBW== WBW disabled setting setting '..self.x.get('meshdesk','web_by_wifi','disabled'));   
    if(self.x.get('meshdesk','web_by_wifi','disabled') == '0')then
        ignore = false; --its not disabled thus we can't ignore it
        self:log('==WBW== WBW DO NOT IGNORE');
    end 
    return ignore;       
end


--[[--
========================================================
=== Private functions start here =======================
========================================================
--]]--

function rdConfig._file_exists(self,name)
    local f=io.open(name,"r")                                          
        if f~=nil then io.close(f) return true else return false end       
end

function rdConfig._file_size(self,name)
    local file = io.open(name,"r");
    local size = file:seek("end")    -- get file size
    file:close()        
    return size
end 

function rdConfig._urlencode(self,str)
   if (str) then
      str = string.gsub (str, "%s+", '%%20');--escape the % with a %
   end
   return str    
end 

function rdConfig.readAll(self,file)                     
	local f = io.open(file, "rb")      
        local content = f:read("*all")     
        f:close()                          
        return content                     
end

function rdConfig.reboot(self)   
	os.execute("reboot");	
end

