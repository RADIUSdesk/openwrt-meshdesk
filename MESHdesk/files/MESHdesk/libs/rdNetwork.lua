require( "class" )

-------------------------------------------------------------------------------
-- A class to configure the ethernet interfaces -------------
-------------------------------------------------------------------------------
class "rdNetwork"

--Init function for object
function rdNetwork:rdNetwork()
	require('rdLogger');
	require('rdExternal');
    local uci 	    = require("uci")
    self.x		    = uci.cursor()
	self.version 	= "2.0.0"
	self.logger	    = rdLogger()
	self.nfs        = require('nixio.fs');
	self.json	    = require('luci.json');
	self.debug	    = true
	--self.debug	    = false
  
	--Add external command object
	self.external	= rdExternal()
	
	self.new_file   = self.x.get('meshdesk', 'settings','config_file');
    self.old_file   = self.x.get('meshdesk', 'settings','previous_config_file');
    self.wan_network= 'wan_network';
    self.w_items    = { ssid=true, encryption=true, disabled=true, device=true, mode=true, key=true, network=true, ifname=true};
    --Only these items will be modified when synching (based on the value of proto)
    self.sta_items  = { dns=true, ipaddr=true, netmask=true, gateway=true};
    self.ppp_items  = { mtu=true, mac=true, username=true, password=true};
    self.qmi_items  = { pincode=true, username=true, password=true, apn=true};

end
        
function rdNetwork:getVersion()
	return self.version
end

function rdNetwork:getMode()
    return self:_getMode();
end

function rdNetwork:getIpForInterface(int)
	self:log("Get IPv4 address for interface "..int)
	return self:__getIpForInterface(int) 
end

function rdNetwork:getIpV6ForInterface(int)
	self:log("Get IPv6 address for interface "..int)
	return self:__getIpV6ForInterface(int) 
end

function rdNetwork:wbwStart()
    self:__includeWebByWifi();
end


function rdNetwork:getMac(int)
    return self:__getMac(int) --default is eth0
end

function rdNetwork:doWanSynch()
    self:log("==Synchronize WAN IF Required==");
    self:__doWanSynch();    
end

function rdNetwork:configureFromTable(tbl)
	self:log("==Configure Network from  Lua table==")
	self:__configureFromTable(tbl)
	
	--Are we using 3G?
    self:__includeMobileWan()
    
    --Is there any Wifi Web specified (We do it in the Wireless module)
    --self:__includeWebByWifi()
    
    --Do we need to override with a static IP Address
    self:__includeStaticCheck();
    
    --Is there any VLANS defined
    self:__includeVlanCheck();
    
    --If there was changes for startup
    --self:__doWanSynch();
    
end

function rdNetwork:log(m,p)
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

function rdNetwork.__doWanSynch(self)

    local mod_flag  = false;
    local lan_proto = 'dhcp';
    local no_wwan   = true;
       
    self.x.foreach('network' , 'interface', function(a)
        if(a['.name'] == 'lan')then
            lan_proto = a['proto'];
            if(lan_proto == 'dhcp')then
                --Delete Any Left-Overs
                for key, val in pairs(self.sta_items) do
                    local sta_val = self.x.get(self.wan_network,'lan',key);
                    if(sta_val)then
                        self:log('==STATIC== VALUE DELETE '..key);
                        self.x.delete(self.wan_network,'lan',key);
                        mod_flag = true;
                    end             
                end
                for key, val in pairs(self.ppp_items) do
                    local ppp_val = self.x.get(self.wan_network,'lan',key);
                    if(ppp_val)then
                        self:log('==PPP== VALUE DELETE '..key);
                        self.x.delete(self.wan_network,'lan',ppp_val);
                        mod_flag = true;
                    end             
                end
            end
            if(lan_proto == 'static')then
                for key, val in pairs(self.ppp_items) do
                    local ppp_val = self.x.get(self.wan_network,'lan',key);
                    if(ppp_val)then
                        self:log('==PPP== VALUE DELETE '..key);
                        self.x.delete(self.wan_network,'lan',ppp_val);
                        mod_flag = true;
                    end             
                end                
                for key, val in pairs(a) do
                    if(string.find(key, '.', 1, true) == nil)then
                        if(self.sta_items[key]) then 
                            local sta_val = self.x.get(self.wan_network,'lan',key);
                            if(sta_val ~= val)then
                                self:log('==STATIC== SET '..key);
                                self.x.set(self.wan_network,'lan',key,val);
                                mod_flag = true;
                            end
                        end                                  
                    end
                end
            end
            if(lan_proto == 'pppoe')then
                for key, val in pairs(self.sta_items) do
                    local sta_val = self.x.get(self.wan_network,'lan',key);
                    if(sta_val)then
                        self:log('==STATIC== VALUE DELETE '..key);
                        self.x.delete(self.wan_network,'lan',key);
                        mod_flag = true;
                    end             
                end
                for key, val in pairs(a) do
                    if(string.find(key, '.', 1, true) == nil)then                       
                        if(self.ppp_items[key]) then 
                            local ppp_val = self.x.get(self.wan_network,'lan',key);
                            if(ppp_val ~= val)then
                                self:log('==PPPoE== SET '..key);
                                self.x.set(self.wan_network,'lan',key,val);
                                mod_flag = true;
                            end
                        end                                 
                    end
                end
            end
	    end
	    
	    --LTE--
	    if(a['.name'] == 'wwan')then
	        --See it it is perhaps already in wan_network
	        no_wwan = false;
	        local wwan_proto = self.x.get(self.wan_network,'wwan','proto');
	        if(wwan_proto == nil)then --Not found ADD IT
	            mod_flag = true;
	            self.x.set(self.wan_network, "wwan", "interface");
	            for key, val in pairs(a) do
                    if(string.find(key, '.', 1, true) == nil)then                       
                        self.x.set(self.wan_network,'wwan',key,val);
                        mod_flag = true;              
                    end
                end
            else
                self:log('==WWAN SETTINGS ALREADY PRESENT=='); 
                for key, val in pairs(a) do
                    if(string.find(key, '.', 1, true) == nil)then                       
                        local c_val = self.x.get(self.wan_network,'wwan',key);
                        if(c_val ~= nil)then
                            if(c_val ~= val)then -- Only if there are changes
                                self:log('==LTE== change '..c_val.." to "..val);
                                self.x.set(self.wan_network,'wwan',key,val);
                                mod_flag = true;
                            end
                        else
                            self:log('==LTE== addition '..val);
                            self.x.set(self.wan_network,'wwan',key,val);
                            mod_flag = true;
                        end            
                    end
                end
                
                for key, val in pairs(self.qmi_items) do
                    local qmi_val = self.x.get(self.wan_network,'wwan',key);
                    if(qmi_val)then
                        if(a[key] == nil)then
                            self:log('==LTE== VALUE DELETE '..key);
                            self.x.delete(self.wan_network,'wwan',key);
                            mod_flag = true;
                        end                        
                    end             
                end
                                                  
	        end
	    end
	    --END LTE--          
    end)
    
    if(no_wwan == true)then
        --if we used wwan and turned it off we just disable the wwan interface 
        local disabled = self.x.get(self.wan_network,'wwan','disabled');
        if(disabled ~= nil)then
            if(tostring(disabled) == "0")then --IF IT IS ACTIVE TURN IT OFF
                self.x.set(self.wan_network,'wwan','disabled',"1");
                mod_flag = true;
            end   
        end    
    end

    if(mod_flag == true)then
        self.x.set(self.wan_network,'lan','proto',lan_proto);
        self.x.commit(self.wan_network);
        self:log('==MODIFY SETTINGS==');
        os.execute("cp /etc/config/"..self.wan_network.." /etc/MESHdesk/configs");  
    end         
end

-- Add WiFi Client if enabled
function rdNetwork.__includeWebByWifi(self)

    -- We need to find out if we perhaps also have wifi-iface configured and if it is enabled add it to the settings
    local iface_name_md         = 'web_by_wifi';
    local iface_name_wireless   = 'web_by_w'; 
    self.x.foreach('meshdesk','wifi-iface', 
		function(a)
		    if(a['.name'] == iface_name_md)then
		        if(a['disabled'] ~= nil)then
		            if(a['disabled'] == '0')then
		                --Create it
		                self.x.set('wireless', iface_name_wireless, "wifi-iface")
	                    self.x.commit('wireless')
		                for key, val in pairs(a) do
		                    if(string.find(key, '.', 1, true) == nil)then
	                            if self.w_items[key] then --Only those in the list
	                                self.x.set('wireless', iface_name_wireless,key, val)
	                                if(key == 'device')then
	                                    self.x.set('wireless',val,'disabled','0') --Enable the specified radio also
	                                end
	                            end
	                        end
	                    end
	                    self.x.commit('wireless');
	                    
	                    local wifi_proto = 'dhcp';
	                    if(a['proto'] ~= nil)then
	                        wifi_proto = a['proto'];
	                    end	                    	                    
	                    
	                    --Also include the configs in the netwok config
	                    self.x.set('network', iface_name_wireless, "interface")
	                    self.x.commit('network')
	                    self.x.set('network', iface_name_wireless,'proto', wifi_proto)
	                    	                    
	                    if(wifi_proto == 'static')then
	                        if(a['ipaddr'] ~= nil)then
	                            self.x.set('network', iface_name_wireless,'ipaddr', a['ipaddr']);
	                        end
	                        if(a['netmask'] ~= nil)then
	                            self.x.set('network', iface_name_wireless,'netmask', a['netmask']);
	                        end
	                        if(a['gateway'] ~= nil)then
	                            self.x.set('network', iface_name_wireless,'gateway', a['gateway']);
	                        end
	                        local dns = '';
	                        if(a['dns_1'] ~= nil)then
	                            dns = a['dns_1'];
	                        end
	                        if(a['dns_2'] ~= nil)then
	                            dns = dns..' '..a['dns_2'];
	                        end	                        
	                        if(dns ~= '')then
	                            self.x.set('network', iface_name_wireless,'dns', dns);
	                        end	                        	                    
	                    end
	                    
	                    if(wifi_proto == 'pppoe')then
	                        if(a['username'] ~= nil)then
	                            self.x.set('network', iface_name_wireless,'username', a['username']);
	                        end
	                        if(a['password'] ~= nil)then
	                            self.x.set('network', iface_name_wireless,'password', a['password']);
	                        end
	                        if(a['mac'] ~= nil)then
	                            self.x.set('network', iface_name_wireless,'mac', a['mac']);
	                        end
	                        if(a['mtu'] ~= nil)then
	                            self.x.set('network', iface_name_wireless,'mtu', a['mtu']);
	                        end
	                        local dns = '';
	                        if(a['dns_1'] ~= nil)then
	                            dns = a['dns_1'];
	                        end
	                        if(a['dns_2'] ~= nil)then
	                            dns = dns..' '..a['dns_2'];
	                        end	                        
	                        if(dns ~= '')then
	                            self.x.set('network', iface_name_wireless,'dns', dns);
	                        end	                        	                    
	                    end
	                    self.x.commit('network');
	                    	                    	                    
	                    self.x.set('network', 'stabridge', "interface")
	                    self.x.commit('network')
	                    self.x.set('network', 'stabridge','proto', 'relay')
	                    self.x.set('network', 'stabridge','network', 'lan '..iface_name_wireless)
	                    	                    
	                    --Also set a static address on the 'lan'
	                    self.x.set('network', 'lan','proto', 'static')
	                    self.x.set('network', 'lan','ipaddr','10.50.50.50')
	                    self.x.set('network', 'lan','netmask','255.255.255.0')
	           
	                    self.x.commit('network');	                    
	                    os.execute("/etc/init.d/network reload");
	                    --os.execute("wifi") --Bring up the WiFi (This caused problems on the radio on Master 18-Jul-2020)
		            end
		        end
		    end
	end)
end


-- Add 3G if enabled --
function rdNetwork.__includeMobileWan(self)

    -- We need to find out if we perhaps also have 3G (wwan) configured and if it is enabled add it to the settings 
    self.x.foreach('meshdesk','interface', 
		function(a)
		    if(a['.name'] == 'wwan')then
		        if(a['enabled'] ~= nil)then
		            if(a['enabled'] == '1')then
		                --Create it
		                self.x.set('network', 'wwan', "interface")
	                    self.x.commit('network')
		                for key, val in pairs(a) do
		                    if(string.find(key, '.', 1, true) == nil)then
	                            self.x.set('network', 'wwan',key, val)
	                        end
	                    end
	                    self.x.commit('network')
		            end
		        end
		    end
	end)
end

-- Check if there is perhaps a static IP defined --
function rdNetwork.__includeStaticCheck(self)
    -- We need to find out if we perhaps also have 'lan' interface configured and if it is set to proto == 'static'
    self.x.foreach('meshdesk','interface', 
		function(a)
		    if(a['.name'] == 'lan')then
		        if(a['proto'] ~= nil)then
		            if(a['proto'] == 'static')then
		                --Create it
		                self.x.set('network', 'lan', "interface")
	                    self.x.commit('network')
		                for key, val in pairs(a) do
		                    if(string.find(key, '.', 1, true) == nil)then
		                        if((key ~= 'vlan_number')and(key ~= 'use_vlan'))then
	                                self.x.set('network', 'lan',key, val)
	                            end
	                        end
	                    end
	                    self.x.commit('network')
		            end
		        end
		    end
	end)
end

function rdNetwork.__includeVlanCheck(self)
    --We need to find out if the lan interface has a VLAN that needs to be set for it to operate correct
    --If so we also need to create a fallback interface called 'fallback'
    self.x.foreach('meshdesk','interface',
        function(a)
             if(a['.name'] == 'lan')then
		        if((a['use_vlan'] ~= nil)and(a['vlan_number'] ~= nil))then
		            if(a['use_vlan'] == '1')then
		                self.x.set('network', 'lan', "interface")
	                    self.x.commit('network')    
	                    self.x.set('network', 'lan','ifname', 'eth0.' .. a['vlan_number']);
	                    self.x.commit('network')
	                    --Also create a fallback interface
	                    self.x.set('network', 'fallback', "interface")
	                    self.x.commit('network')
	                    self.x.set('network', 'fallback','ifname', 'eth0');
	                    self.x.set('network', 'fallback','proto', 'static');
	                    self.x.set('network', 'fallback','ipaddr', '10.1.2.3');
	                    self.x.set('network', 'fallback','netmask', '255.255.255.0');
	                    self.x.commit('network')   
		            end     
		        end
		    end    
    end)
end

-- Clean start Network                                                 
function rdNetwork.__newNetwork(self)
	local f="/etc/config/network"  
    os.execute("rm " .. f)
    os.execute("touch " .. f)
end

function rdNetwork.__getMac(self,interface)
	interface = interface or "eth0"

	local file_to_check = "/sys/class/net/" .. interface .. "/address"

	--Check if file exists
	local f=io.open(file_to_check,"r")                                                   
    if f~=nil then 
		io.close(f)
	else
		return false
	end

	--Read the file now we know it exists
	io.input(file_to_check)
	t = io.read("*line")
    if(t)then
	    dashes, count = string.gsub(t, ":", "-")
	    dashes = string.upper(dashes)
	    return dashes
    else
        return false
    end
end    

function rdNetwork.__configureFromTable(self,table)
	-- Clean start                                                           
	self:__newNetwork()                                                            
	for i, setting_entry in ipairs(table) do                                 
		local entry_type                                                 
	    local entry_name                                                  
	    local options = {} -- New empty array for this entry
		for key, val in pairs(setting_entry) do                           
        	-- If it is not an options entry; it is a type with value                
                if(key ~= 'options')then                                                 
                	entry_type  = key                                                
                        entry_name  = val                                                
             	else                                                                                                   
                -- Run through all the options                                                                 
                	for key, val in pairs(val) do                                                                  
                        	options[key] = val                                                                     
                      	end                                                                                            
                end                                                                                                    
    	end

    	-- Now we have gathered the info  
    	self.x.set('network', entry_name, entry_type)
        self.x.commit('network')        
    	for key, val in pairs(options) do
            print("There " .. key .. ' and '.. val)          
            self.x.set('network', entry_name,key, val);
            self.x.commit('network')           
        end
    end   
end

function rdNetwork.__getIpForInterface(self,interface)
	local ip = false
	local if_out = self.external:getOutput("ifconfig "..interface)
	if(if_out:match("inet addr:"))then
		if_out = if_out:gsub(".*inet addr:","")
		if_out = if_out:gsub("%s.+","")
		ip =if_out
	end
	return ip
end

function rdNetwork.__getIpV6ForInterface(self,interface)
	local ip_6 = false
	local if_out = self.external:getOutput("ifconfig "..interface)
	if(if_out:match("Scope:Global"))then
		if_out = if_out:gsub(".*inet6 addr:%s+","")
		if_out = if_out:gsub("/.+","")
		ip_6 =if_out
	end
	return ip_6
end

function rdNetwork._getMode(self)
    local mode      = 'mesh'; --Default value;                     
    --Get the node_id and interface id from the meta_data
    if(self:_file_exists(self.new_file))then
        local contents        = self.nfs.readfile(self.new_file);        
        local o               = self.json.decode(contents); 
        if(o.success == true)then
            if(o.meta_data)then
                mode            = o.meta_data.mode;
            end
        end
    else
        if(self:_file_exists(self.old_file))then
            local contents        = self.nfs.readfile(self.old_file);        
            local o               = self.json.decode(contents)  
            if(o.success == true)then
                if(o.meta_data)then
                    mode    = o.meta_data.mode; 
                end
            end
        end
    end
    if(mode == nil)then
        mode = 'mesh'; -- redo the default
    end
    return mode;
end

function rdNetwork._file_exists(self,name)
    local f=io.open(name,"r")                                          
        if f~=nil then io.close(f) return true else return false end       
end

