require( "class" )

-------------------------------------------------------------------------------
-- Gateway
-------------------------------------------------------------------------------
class "rdGateway"

--Init function for object
function rdGateway:rdGateway()

	require('rdLogger');
	require('rdConfig');
	self.version 	= "1.0.0"
	--self.debug	    = true
	self.debug	    = false
	self.logger	    = rdLogger()
	self.config     = rdConfig();

	self.conf_zone  = 'one' -- network interface 'one' is the admin interface
	self.conf_rule	= 'one_rule' -- The name of the firewall rule that allow traffic to conf server.
	self.ntp_rule   = 'one_ntp'
	self.dns_rule   = 'one_dns' -- We might want to make this rule more strict ---
	self.mode       = 'mesh' -- Mode can be mesh or ap - With ap mode we do not need to set up the conf zone
	
	self.l_uci    	= require("luci.model.uci");
	
	self.gw_allow = {
	    --'176.31.15.210', --Current BASE server
	    --'172.105.52.126' --New CSC Server	
	}
	
	self.config_settings = nil;
end
        
function rdGateway:getVersion()
	return self.version
end

function rdGateway:getMode()
	return self.mode
end

function rdGateway:setMode(mode)
	self.mode = mode
end

function rdGateway:log(m,p)
	if(self.debug)then
		self.logger:log(m,p)
	end
end
 
function rdGateway:enable(configSettings)
    
    self.config_settings = configSettings;
    
	exPoints        = configSettings.gateways or {}

	
	self:disable()	--Clean up any left overs
	
	--ADD base server ip and self.config_settings.gw_allow to self.gw_allow
	self:__populateGwAllow();
	
	self:__fwAddMobileWanZone()
	
	self:__fwAddWebByWifiZone()
	
	self:__fwMasqEnable()
	
	if(self.mode == 'mesh')then --Default is mesh mode
	    self:__fwGwEnable()
	    self:__dhcpGwEnable()
    end
    
	self:__addExPoints(exPoints)
    os.execute("touch /tmp/gw")

	--We also have to remove (and re-enable the /etc/resolv.conf)
	os.execute("rm /etc/resolv.conf")
	os.execute("ln -s /tmp/resolv.conf /etc/resolv.conf")

	--Tell batman we are a server
	if(self.mode == 'mesh')then
	    self.l_uci.cursor():set('batman-adv','bat0','gw_mode', 'server')
	    self.l_uci.cursor():save('batman-adv')
	    self.l_uci.cursor():commit('batman-adv')
    end
end     

function rdGateway:disable()

    self:log("**Remove Mobile WAN**")
    self:__fwRemoveMobileWanZone()
    self:log("**Remove Web By WiF**")
    self:__fwRemoveWebByWifiZone()
    self:log("**MASQ Disable**")
    self:__fwMasqDisable()
    self:log("**GW Disable**")
	self:__fwGwDisable()
	self:__dhcpGwDisable()
    os.execute("rm /tmp/gw")

	--Tell batman we are a client
	if(self.mode == 'mesh')then
	    self.l_uci.cursor():set('batman-adv','bat0','gw_mode', 'client')
	    self.l_uci.cursor():save('batman-adv')
	    self.l_uci.cursor():commit('batman-adv')
    end
end

function rdGateway:addNat(network)
	self:__fwGwEnable(network,'no')
    os.execute("rm /tmp/gw")
end

function rdGateway:restartServices()

--	os.execute("/etc/init.d/dnsmasq stop")
--	os.execute("/etc/init.d/dnsmasq start")
--	os.execute("/etc/init.d/telnet stop")
--	os.execute("/etc/init.d/telnet start")
--	os.execute("/etc/init.d/dropbear stop")
--	os.execute("/etc/init.d/dropbear start")

end


--[[--
=========================================
========= Private methods =============== 
=========================================
--]]--

function rdGateway.__populateGwAllow(self)

    if(self.config_settings.gw_allow ~= nil)then
        self.gw_allow = self.config_settings.gw_allow
    end
    
    local ip        = self.l_uci.cursor():get('meshdesk','internet1','ip');
    local base_ip   = self.l_uci.cursor():get('meshdesk','internet1','base_ip');
    if(ip ~= base_ip)then --Add it if its different
        table.insert(self.gw_allow,base_ip)
    end   
end

function rdGateway.__addExPoints(self,exPoints)

	for k,v in pairs(exPoints)do 
		print(v) 
		self:__dhcpGwEnable(v)
		self:__fwGwEnable(v)
	end
end

function rdGateway.__dhcpGwEnable(self,network,start,limit)

	--Some sane defaults
	network 	= network or self.conf_zone
	start 		= start or 100
	limit		= limit or 200
	local leasetime   = '12h';
	local dns_servers = {};
	local ignore    = 0;
	
	local dtls  = self.config_settings.gateway_details;
	if(dtls)then
	    if(dtls[network] ~= nil)then
	        start       = dtls[network]['pool_start'];
	        limit       = dtls[network]['pool_limit'];
	        
	        if(dtls[network]['leasetime'] ~= nil)then
	            leasetime   = tostring(dtls[network]['leasetime'])..'h';
	        end
	        if(dtls[network]['ignore'] ~= nil)then
	            leasetime   = dtls[network]['ignore'];
	        end
	        
	        if(dtls[network]['dns_1'] ~= nil)then
	            table.insert(dns_servers, dtls[network]['dns_1'])
	        end
	        if(dtls[network]['dns_2'] ~= nil)then
	            table.insert(dns_servers, dtls[network]['dns_2'])
	        end        
	    end
    end
    
    local has_dns_servers = false;
    for _,_ in pairs(dns_servers) do
        has_dns_servers = true;
    end
	
	self.l_uci.cursor():set('dhcp','lan','ignore',1);
	self.l_uci.cursor():set('dhcp',network,'dhcp');
	self.l_uci.cursor():set('dhcp',network,'interface', network);
	self.l_uci.cursor():set('dhcp',network,'start', start);
	self.l_uci.cursor():set('dhcp',network,'limit', limit);
	self.l_uci.cursor():set('dhcp',network,'leasetime',leasetime);
	self.l_uci.cursor():set('dhcp',network,'ignore',ignore);
	
	if(has_dns_servers)then
	    self.l_uci.cursor():set('dhcp',network,'server',dns_servers);
	end
		
	self.l_uci.cursor():save('dhcp');
	self.l_uci.cursor():commit('dhcp');
end

function rdGateway.__dhcpGwDisable(self)
	self.l_uci.cursor():set('dhcp','lan','ignore',1) 
	self.l_uci.cursor():save('dhcp');                 
    self.l_uci.cursor():commit('dhcp'); 
    if(self.mode == 'mesh')then                                       
	    self.l_uci.cursor():delete('dhcp',self.conf_zone)
    end
	--Remove any previous NAT points (if there were any) the will start with ex_
	self.l_uci.cursor():foreach('dhcp','dhcp', 
		function(a)
			--print(a['.name'])
			--Check the name--
			if(string.find(a['.name'],"ex_"))then
				self.l_uci.cursor():delete('dhcp',a['.name'])
			end
 		end)
 		
	self.l_uci.cursor():save('dhcp')
	self.l_uci.cursor():commit('dhcp')
end

function rdGateway.__fwGwEnable(self,network,forward)
	print("Enable gateway on firewall")
	
	--Some sane defaults
	network 	= network or self.conf_zone
	forward		= forward or "yes" -- default is to add the forward rule
	
	local no_config_zone = true
	
	self.l_uci.cursor():foreach('firewall', 'zone',
		function(a)	
			-- Check if 'meshdesk_config' zone is present
			if(a['name'] == network)then
				no_config_zone = false
			end
		end)
		
	--If config zone not present / add it
	if(no_config_zone)then
		local zone_name = self.l_uci.cursor():add('firewall','zone')
		self.l_uci.cursor():set('firewall',zone_name,'name',		network)	
        self.l_uci.cursor():set('firewall',zone_name,'network', { network })	
		self.l_uci.cursor():set('firewall',zone_name,'input',	'ACCEPT')	
		self.l_uci.cursor():set('firewall',zone_name,'output',	'ACCEPT')	
		self.l_uci.cursor():set('firewall',zone_name,'forward',	'REJECT') -- By default we are not forwarding traffic
		self.l_uci.cursor():set('firewall',zone_name,'conntrack',	'1')	
	end
	
	-- Add the SNAT rules
	local no_redir = true
	self.l_uci.cursor():foreach('firewall', 'redirect',
		function(a)
			if((a.src == network)and(a.dst == 'lan'))then
				no_redir = false
			end
		end)
	if(no_redir)then
		local r = self.l_uci.cursor():add('firewall','redirect')
		self.l_uci.cursor():set('firewall',r, 'src',network)
		self.l_uci.cursor():set('firewall',r, 'dst','lan')
		self.l_uci.cursor():set('firewall',r, 'target','SNAT')
        self.l_uci.cursor():set('firewall',r, 'proto','tcpudp')
        --According the the documentation we are also suppose to add src_dip (and specify the IP of the LAN)
        --Problem is that the LAN IP can and will most probably change so it makes it impractical--
          
	end
	
	-- Add the forwarding entry
	local no_forwarding = true
	self.l_uci.cursor():foreach('firewall','forwarding',
		function(a)
			if((a.src == network)and(a.dst=='lan'))then
				no_forwarding = false
			end
		end)

	--We are not adding a forward rule for the conf_zone for security reasons
	if(no_forwarding and (forward == 'yes')and(network ~= self.conf_zone))then -- Only if we specified to add a forward rule
		local f = self.l_uci.cursor():add('firewall', 'forwarding')
		self.l_uci.cursor():set('firewall',f,'src',network)
		self.l_uci.cursor():set('firewall',f,'dst','lan')   	
	end
	
	--=====================================================
	--4G things
	--See if we need to add a rule for the 4G (wwan) connection
	
	local mobile_enabled = false;
	self.l_uci.cursor():foreach('network','interface', 
        function(a)
            if(a['.name'] == 'wwan')then
                if(a['disabled'] ~= nil)then
                    if(a['disabled'] == '0')then
                       mobile_enabled = true
                    end
                end
            end
    end)
	
	if(mobile_enabled)then
	
	    local no_redir_mobile = true
	    self.l_uci.cursor():foreach('firewall', 'redirect',
		    function(a)
			    if((a.src == network)and(a.dst == 'wwan'))then
				    no_redir_mobile = false
			    end
		    end)
	
	    if(no_redir_mobile)then
            --Create it
            local r_wwan = self.l_uci.cursor():add('firewall','redirect')
           	self.l_uci.cursor():set('firewall',r_wwan, 'src',network)
            self.l_uci.cursor():set('firewall',r_wwan, 'dst','wwan')
            self.l_uci.cursor():set('firewall',r_wwan, 'target','SNAT')
            self.l_uci.cursor():set('firewall',r_wwan, 'proto','tcpudp')
        end
    
        local no_forwarding_mobile = true
	    self.l_uci.cursor():foreach('firewall','forwarding',
		    function(a)
			    if((a.src == network)and(a.dst=='wwan'))then
				    no_forwarding_mobile = false
			    end
		    end)
	
        if(no_forwarding_mobile and (forward == 'yes')and(network ~= self.conf_zone))then -- Only if we specified to add a forward rule				
            --Create it
            local f_wwan = self.l_uci.cursor():add('firewall','forwarding')
           	self.l_uci.cursor():set('firewall',f_wwan,'src',network)
            self.l_uci.cursor():set('firewall',f_wwan,'dst','wwan')    	
	    end
	    
    end 
    --=========END 4G ===============================
	self.l_uci.cursor():save('firewall');
	self.l_uci.cursor():commit('firewall');

	--only for the config zone
	--We need to add a rule to allow traffic to the config server for the config zone
	
	if(network == self.conf_zone)then 
	
	    --Web_by_wifi check
	    local wifi_enabled = false;
	    self.l_uci.cursor():foreach('meshdesk','wifi-iface', 
            function(a)
                if(a['.name'] == 'web_by_wifi')then
                    if(a['disabled'] ~= nil)then
                        if(a['disabled'] == '0')then
                           wifi_enabled = true
                        end
                    end
                end
        end)
        
        --====Also it might be a auto captive portal config web-by-wifi FIXME Does not seem to be required here......
        if(self.config_settings ~= nil)then
            --Wireless test--
            if(self.config_settings.wireless ~= nil)then
                for k,v in pairs(self.config_settings.wireless) do 
                    for key,val in pairs(v)do
                        if(key == 'wifi-iface')then
                            if(val == 'web_by_w')then
                                if(self.config_settings.wireless[k].options.disabled == '0')then
                                    wifi_enabled = true;
                                end
                            end
                        end
                    end
                end
            end
        end
        --======
	

		--Avoid duplicates
		local no_conf_accept_rule = true
		self.l_uci.cursor():foreach('firewall','rule',
			function(a)
				if(a['name'] == self.conf_rule)then
					no_conf_accetp_rule = false --We found the entry
				end
			end)

		--Get the IP of the config server
		local conf_srv = self.l_uci.cursor():get('meshdesk','internet1','ip')

		--Add a rule for conf server 
		if(no_conf_accept_rule)then
			--For the conf server
			local r = self.l_uci.cursor():add('firewall','rule')
			self.l_uci.cursor():set('firewall',r,'src', network)
			self.l_uci.cursor():set('firewall',r,'dest', 'lan')
			self.l_uci.cursor():set('firewall',r,'dest_ip', conf_srv)
			self.l_uci.cursor():set('firewall',r,'target', 'ACCEPT')
			self.l_uci.cursor():set('firewall',r,'name', self.conf_rule)
			self.l_uci.cursor():set('firewall',r,'proto', 'all') --required to include ping
			
            --==WIP==
            for i, ip in ipairs(self.gw_allow) do
                local n_name = 'gw_allow_'..tostring(i);
                local ha = self.l_uci.cursor():add('firewall','rule')
			    self.l_uci.cursor():set('firewall',ha,'src', network)
			    self.l_uci.cursor():set('firewall',ha,'dest', 'lan')
			    self.l_uci.cursor():set('firewall',ha,'dest_ip', ip)
			    self.l_uci.cursor():set('firewall',ha,'target', 'ACCEPT')
			    self.l_uci.cursor():set('firewall',ha,'name', n_name)
			    self.l_uci.cursor():set('firewall',ha,'proto', 'all') --required to include ping       
            end
            --==WIP END==
			
			--For the ntp server
			local s = self.l_uci.cursor():add('firewall','rule')
			self.l_uci.cursor():set('firewall',s,'src', network)
			self.l_uci.cursor():set('firewall',s,'dest', 'lan')
			self.l_uci.cursor():set('firewall',s,'dest_port', '123')
			self.l_uci.cursor():set('firewall',s,'proto', 'udp')
			self.l_uci.cursor():set('firewall',s,'target', 'ACCEPT')
			self.l_uci.cursor():set('firewall',s,'name', self.ntp_rule)
			
			--For the dns server
			local t = self.l_uci.cursor():add('firewall','rule')
			self.l_uci.cursor():set('firewall',t,'src', network)
			self.l_uci.cursor():set('firewall',t,'dest', 'lan')
			self.l_uci.cursor():set('firewall',t,'dest_port', '53')
			self.l_uci.cursor():set('firewall',t,'proto', 'tcp udp')
			self.l_uci.cursor():set('firewall',t,'target', 'ACCEPT')
			self.l_uci.cursor():set('firewall',t,'name', self.dns_rule)
			
			if(mobile_enabled)then
			
			    local rm = self.l_uci.cursor():add('firewall','rule')
			    self.l_uci.cursor():set('firewall',rm,'src', network)
			    self.l_uci.cursor():set('firewall',rm,'dest', 'wwan')
			    self.l_uci.cursor():set('firewall',rm,'dest_ip', conf_srv)
			    self.l_uci.cursor():set('firewall',rm,'target', 'ACCEPT')
			    self.l_uci.cursor():set('firewall',rm,'name', self.conf_rule)
			    self.l_uci.cursor():set('firewall',rm,'proto', 'all') --required to include ping
			    
			    --==WIP==
                for i, ip in ipairs(self.gw_allow) do
                    local n_name = 'gw_allow_'..tostring(i);
                    local ha = self.l_uci.cursor():add('firewall','rule')
			        self.l_uci.cursor():set('firewall',ha,'src', network)
			        self.l_uci.cursor():set('firewall',ha,'dest', 'wwan')
			        self.l_uci.cursor():set('firewall',ha,'dest_ip', ip)
			        self.l_uci.cursor():set('firewall',ha,'target', 'ACCEPT')
			        self.l_uci.cursor():set('firewall',ha,'name', n_name)
			        self.l_uci.cursor():set('firewall',ha,'proto', 'all') --required to include ping       
                end
                --==WIP END==
			
			    --For the ntp server
			    local sm = self.l_uci.cursor():add('firewall','rule')
			    self.l_uci.cursor():set('firewall',sm,'src', network)
			    self.l_uci.cursor():set('firewall',sm,'dest', 'wwan')
			    self.l_uci.cursor():set('firewall',sm,'dest_port', '123')
			    self.l_uci.cursor():set('firewall',sm,'proto', 'udp')
			    self.l_uci.cursor():set('firewall',sm,'target', 'ACCEPT')
			    self.l_uci.cursor():set('firewall',sm,'name', self.ntp_rule)
			    
			    --For the dns server
			    local tm = self.l_uci.cursor():add('firewall','rule')
			    self.l_uci.cursor():set('firewall',tm,'src', network)
			    self.l_uci.cursor():set('firewall',tm,'dest', 'wwan')
			    self.l_uci.cursor():set('firewall',tm,'dest_port', '53')
			    self.l_uci.cursor():set('firewall',tm,'proto', 'tcp udp')
			    self.l_uci.cursor():set('firewall',tm,'target', 'ACCEPT')
			    self.l_uci.cursor():set('firewall',tm,'name', self.dns_rule)
					
			end
			
			if(wifi_enabled)then
			    local rw = self.l_uci.cursor():add('firewall','rule')
			    self.l_uci.cursor():set('firewall',rw,'src', network)
			    self.l_uci.cursor():set('firewall',rw,'dest', 'web_by_w')
			    self.l_uci.cursor():set('firewall',rw,'dest_ip', conf_srv)
			    self.l_uci.cursor():set('firewall',rw,'target', 'ACCEPT')
			    self.l_uci.cursor():set('firewall',rw,'name', self.conf_rule)
			    self.l_uci.cursor():set('firewall',rw,'proto', 'all') --required to include ping
			    
			    --==WIP==
                for i, ip in ipairs(self.gw_allow) do
                    local n_name = 'gw_allow_'..tostring(i);
                    local ha = self.l_uci.cursor():add('firewall','rule')
			        self.l_uci.cursor():set('firewall',ha,'src', network)
			        self.l_uci.cursor():set('firewall',ha,'dest', 'web_by_w')
			        self.l_uci.cursor():set('firewall',ha,'dest_ip', ip)
			        self.l_uci.cursor():set('firewall',ha,'target', 'ACCEPT')
			        self.l_uci.cursor():set('firewall',ha,'name', n_name)
			        self.l_uci.cursor():set('firewall',ha,'proto', 'all') --required to include ping       
                end
                --==WIP END==
			
			    --For the ntp server
			    local sw = self.l_uci.cursor():add('firewall','rule')
			    self.l_uci.cursor():set('firewall',sw,'src', network)
			    self.l_uci.cursor():set('firewall',sw,'dest', 'web_by_w')
			    self.l_uci.cursor():set('firewall',sw,'dest_port', '123')
			    self.l_uci.cursor():set('firewall',sw,'proto', 'udp')
			    self.l_uci.cursor():set('firewall',sw,'target', 'ACCEPT')
			    self.l_uci.cursor():set('firewall',sw,'name', self.ntp_rule)
			    
			    --For the dns server
			    local tw = self.l_uci.cursor():add('firewall','rule')
			    self.l_uci.cursor():set('firewall',tw,'src', network)
			    self.l_uci.cursor():set('firewall',tw,'dest', 'web_by_w')
			    self.l_uci.cursor():set('firewall',tw,'dest_port', '53')
			    self.l_uci.cursor():set('firewall',tw,'proto', 'tcp udp')
			    self.l_uci.cursor():set('firewall',tw,'target', 'ACCEPT')
			    self.l_uci.cursor():set('firewall',tw,'name', self.dns_rule)
			end		

            self.l_uci.cursor():save('firewall');
			self.l_uci.cursor():commit('firewall');
		end

	end

end

function rdGateway.__fwGwDisable(self)
	print("Disable gateway on firewall")
	
	-- Take care of the Zones --
	self.l_uci.cursor():foreach('firewall', 'zone',
		function(a)
			if((a['name'] == self.conf_zone) or (string.find(a['name'],"ex_")))then
				local z_name = a['.name']
				self.l_uci.cursor():delete('firewall',z_name)
			end
		end)
	
	-- Remove the SNAT rules --
	self.l_uci.cursor():foreach('firewall', 'redirect',
		function(a)
			if((a.src == self.conf_zone) or (string.find(a.src, "ex_")))then
				local r_zone = a['.name']
				self.l_uci.cursor():delete('firewall',r_zone)
			end
		end)
	
	-- Remove the forwarding entry --
	self.l_uci.cursor():foreach('firewall', 'forwarding',
		function(a)
			if((a.src == self.conf_zone) or (string.find(a.src,"ex_")))then
				local fwd_name	  = a['.name']
				self.l_uci.cursor():delete('firewall',fwd_name)
			end
		end)

	--Remove the rule allowing traffic to config servers well as NTP traffic
	self.l_uci.cursor():foreach('firewall', 'rule',
		function(a)
			if(a.name == self.conf_rule)then
				local r	  = a['.name']
				self.l_uci.cursor():delete('firewall',r)
			end

			if(a.name == self.ntp_rule)then
				local n = a['.name']
				self.l_uci.cursor():delete('firewall',n)
			end
			
			if(a.name == self.dns_rule)then
				local n = a['.name']
				self.l_uci.cursor():delete('firewall',n)
			end
			
			if(string.match(a.name, 'gw_allow_'))then     --Remove all the Home Agent Servers
                local n = a['.name']
				self.l_uci.cursor():delete('firewall',n);
            end
			
			
		end)
	self.l_uci.cursor():save('firewall');
	self.l_uci.cursor():commit('firewall');		
end

function rdGateway.__fwMasqEnable(self,network)
    network     = network or 'lan' --default is to do it on the LAN
    self.l_uci.cursor():foreach('firewall', 'zone',
	    function(a)
		    -- Add masq option to LAN --
		    if(a['name'] == 'lan')then
			    self.l_uci.cursor():set('firewall',a['.name'],'masq',1)
			    self.l_uci.cursor():set('firewall',a['.name'],'mtu_fix',1)
		    end
	end)
	self.l_uci.cursor():save('firewall');
    self.l_uci.cursor():commit('firewall');
    
end

function rdGateway.__fwMasqDisable(self,network)
    network     = network or 'lan' --default is to do it on the LAN
    self.l_uci.cursor():foreach('firewall', 'zone',
	    function(a)
		    -- Add masq option to LAN --
		    if(a['name'] == 'lan')then
			    self.l_uci.cursor():delete('firewall',a['.name'],'masq')
				self.l_uci.cursor():delete('firewall',a['.name'],'mtu_fix');
				self.l_uci.cursor():save('firewall');
		    end
	end)
	self.l_uci.cursor():save('firewall');
    self.l_uci.cursor():commit('firewall'); 
end

function rdGateway.__fwAddMobileWanZone(self)

    local mobile_enabled = false;
	self.l_uci.cursor():foreach('network','interface', 
        function(a)
            if(a['.name'] == 'wwan')then
                if(a['disabled'] ~= nil)then
                    if(a['disabled'] == '0')then
                       mobile_enabled = true
                    end
                end
            end
    end)
 
    if(mobile_enabled)then
        --Create it
        local zone_name = self.l_uci.cursor():add('firewall','zone')
        self.l_uci.cursor():set('firewall',zone_name,'name',		'wwan')	
        self.l_uci.cursor():set('firewall',zone_name,'network', { 'wwan' })	
        self.l_uci.cursor():set('firewall',zone_name,'input',	'ACCEPT')	
        self.l_uci.cursor():set('firewall',zone_name,'output',	'ACCEPT')	
        self.l_uci.cursor():set('firewall',zone_name,'forward',	'ACCEPT')
        self.l_uci.cursor():set('firewall',zone_name,'masq',	1)
        self.l_uci.cursor():set('firewall',zone_name,'mtu_fix',	1)
        self.l_uci.cursor():save('firewall')
        self.l_uci.cursor():commit('firewall')
    end
end

function rdGateway.__fwRemoveMobileWanZone(self)	
	self.l_uci.cursor():foreach('firewall', 'zone',
	    function(a)
		    if(a['name'] == 'wwan')then
			    local wwan_name	  = a['.name']
				self.l_uci.cursor():delete('firewall',wwan_name)
				self.l_uci.cursor():save('firewall');
				self.l_uci.cursor():commit('firewall');
		    end
	end)	
end

function rdGateway.__fwAddWebByWifiZone(self)

    local wifi_enabled = false;
	self.l_uci.cursor():foreach('meshdesk','wifi-iface', 
        function(a)
            if(a['.name'] == 'web_by_wifi')then
                if(a['disabled'] ~= nil)then
                    if(a['disabled'] == '0')then
                       wifi_enabled = true
                    end
                end
            end
    end)
    
    --====Also it might be a auto captive portal config web-by-wifi
    if(self.config_settings ~= nil)then
        --Wireless test--
        if(self.config_settings.wireless ~= nil)then
            for k,v in pairs(self.config_settings.wireless) do 
                for key,val in pairs(v)do
                    if(key == 'wifi-iface')then
                        if(val == 'web_by_w')then
                            if(self.config_settings.wireless[k].options.disabled == '0')then
                                wifi_enabled = true;
                            end
                        end
                    end
                end
            end
        end
    end
    --======
    
    if(wifi_enabled)then
        --Create it
        local zone_name = self.l_uci.cursor():add('firewall','zone')
        self.l_uci.cursor():set('firewall',zone_name,'name',		'web_by_w')	
        self.l_uci.cursor():set('firewall',zone_name,'network', { 'lan', 'web_by_w' })	
        self.l_uci.cursor():set('firewall',zone_name,'input',	'ACCEPT')	
        self.l_uci.cursor():set('firewall',zone_name,'output',	'ACCEPT')	
        self.l_uci.cursor():set('firewall',zone_name,'forward',	'ACCEPT')
        self.l_uci.cursor():set('firewall',zone_name,'masq',	1)
        self.l_uci.cursor():set('firewall',zone_name,'mtu_fix',	1)
        self.l_uci.cursor():save('firewall')
        self.l_uci.cursor():commit('firewall')
    end
end

function rdGateway.__fwRemoveWebByWifiZone(self)
	self.l_uci.cursor():foreach('firewall', 'zone',
	    function(a)
	        print(a['name']);
		    if(a['name'] == 'web_by_w')then
			    local relay_name	  = a['.name']
				self.l_uci.cursor():delete('firewall',relay_name)
				self.l_uci.cursor():save('firewall');
				self.l_uci.cursor():commit('firewall')
		    end
	end)	
end
