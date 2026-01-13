-- SPDX-FileCopyrightText: 2025 Dirk van der Walt <dirkvanderwalt@gmail.com>
--
-- SPDX-License-Identifier: GPL-3.0-or-later

require( "class" )

-- 21 NOV 2025 --

--------------------------------------------------------------------------------------
-- Class to configure VPN items specified in the config returned by AP / Mesh node ---
--------------------------------------------------------------------------------------

class "rdVpn"

--Init function for object
function rdVpn:rdVpn()
    require('rdLogger');
	self.version 	= "1.0.1";
	self.tag	    = "MESHdesk";
	self.uci 		= require("uci");
	self.util       = require('luci.util');
	self.logger	    = rdLogger();
	self.debug	    = true
	self.json       = require('luci.json');
	self.fs         = require('nixio.fs');
	self.ovpnFound  = false;
	self.ipsecFound = false;
	self.ztFound = false;
end
        
function rdVpn:getVersion()
	return self.version	
end

function rdVpn:configureFromJson(file)
	self:log("==Configure VPN items from JSON file "..file.." ==")
	self:_configureFromJson(file)
end

function rdVpn:configureFromTable(tbl)
	self:log("==Configure VPN items from Lua table==")
	self:_configureFromTable(tbl)
end

function rdVpn:configureRouting(meta_data)
	self:_configureRouting(meta_data)
end

function rdVpn:log(m,p)
	if(self.debug)then
		self.logger:log(m,p)
	end
end

--[[--
========================================================
=== Private functions start here =======================
========================================================
--]]--

function rdVpn:_configureRouting(meta_data)

    local current_by_id 	= {}    -- section_id -> zone_name
    local current_by_name 	= {}  -- zone_name -> section_id
    local new_config 		= {}
    local changed 			= false
    
    local x = self.uci:cursor()
    
    -- Get existing entries starting with 'vpn_'
    x:foreach('firewall', 'zone', function(s)
        if string.match(s['name'], '^vpn_') then
            current_by_id[s['.name']] = s['name']
            current_by_name[s['name']] = s['.name']
        end
    end)

    -- Build new config list
    if meta_data.vpns and next(meta_data.vpns) ~= nil then
        for _, vpn_config in ipairs(meta_data.vpns) do
            local zone_name = 'vpn_' .. vpn_config['interface']
            new_config[zone_name] = vpn_config
        end
    end
    
    -- Check for items to ADD (in new_config but not in current_by_name)
    for zone_name, vpn_config in pairs(new_config) do
        if not current_by_name[zone_name] then
            --print(zone_name .. ' not found - adding it')
            local item_name = x:add('firewall', 'zone')
            x:set('firewall', item_name, 'name', zone_name)
            x:set('firewall', item_name, 'input', 'REJECT')
            x:set('firewall', item_name, 'output', 'ACCEPT')
            x:set('firewall', item_name, 'forward', 'REJECT')
            x:set('firewall', item_name, 'masq', '1')
            x:set('firewall', item_name, 'mtu_fix', '1')
            -- Add the network list using the interface from vpn_config
            x:set('firewall', item_name, 'network', { vpn_config['interface'] })
            changed = true 
        end
    end
    
    -- Check for items to DELETE (in current_by_name but not in new_config)
    for zone_name, section_id in pairs(current_by_name) do
        if not new_config[zone_name] then
            --print(zone_name .. ' should be removed (section: ' .. section_id .. ')')
            x:delete('firewall', section_id)
            changed = true
        end
    end
    
    if changed then
        x:save('firewall')
        x:commit('firewall')
        --print("Firewall configuration updated")
    else
        --print("No changes needed")
    end
end

function rdVpn._configureFromJson(self,json_file)

	self:log("Configuring VPN items from a JSON file");
	local contents 	= self.fs.readfile(json_file);
	local o					= self.json.decode(contents);
	
	if o.config_settings and o.config_settings.vpn then
		self:log("Found VPN Data  - completing it");
		self:_configureFromTable(o.config_settings.vpn);
		self:_configureRouting(o.meta_data);
	else
		self:log("No VPN Data settings found, please check JSON file")
	end
end

function rdVpn:_configureFromTable(vpn_data)

	for vpn_type, vpn_configs in pairs(vpn_data) do
        if(vpn_type == 'ovpn')then
        	for _, config in ipairs(vpn_configs) do
				self:_configureOvpn(config)
			end
        end
         if(vpn_type == 'ipsec')then
        	for _, config in ipairs(vpn_configs) do
				self:_configureIpsec(config)
			end
        end
        if(vpn_type == 'zt')then
        	for _, config in ipairs(vpn_configs) do
				self:_configureZeroTier(config)
			end
        end
    end
    --Check what needs to be restarted
    self:_restartCheck();  
end

function rdVpn._configureIpsec(self,config)
	self.ipsecFound 	= true; --Set this flag to check later	
	print("==== IPSEC =====");
	local ss_name = config.name;
	local ss_conf	= config.config;
	local cert 		= ss_name..'_cert.pem';
	local key 		    = ss_name..'_cert.key';
	local ca_cert   	= ss_name..'_ca.crt';
	local tpl           = '/etc/MESHdesk/configs/swanctl.conf.tpl';
	local final	  	= '/etc/swanctl/conf.d/'..ss_name..'.conf';
	local temp  		= ss_name..'.conf';
	
	local vars = {
	    SS_NAME				= ss_name,
		REMOTE_ADDR   = ss_conf.ipsec_server,
		LOCAL_ID      		= ss_conf.ipsec_client_id,
		REMOTE_ID    		= ss_conf.ipsec_server_id,
		LOCAL_CERT    	= cert,
		IF_ID         			= ss_conf.ipsec_if_id,
		ESP_PROPOSALS = ss_conf.ipsec_esp_proposals,
		IKE_PROPOSALS = ss_conf.ipsec_proposals,
		CA_CERT				= ca_cert
	}
	
	local template  = self.fs.readfile(tpl);
	for k, v in pairs(vars) do
		template = template:gsub("%${" .. k .. "}", v)
	end	
	self:_checkAndReplace(temp,final,template);
	
	local ca_file 	= '/etc/swanctl/x509ca/'..ss_name..'_ca.crt';
	local t_ca_file  = ss_name..'_ca.crt';
	self:_checkAndReplace(t_ca_file,ca_file,ss_conf.ipsec_ca);
	
	local cert_file	= '/etc/swanctl/x509/'..ss_name..'_cert.pem';
	local t_cert_file= ss_name..'_cert.pem';
	self:_checkAndReplace(t_cert_file,cert_file,ss_conf.ipsec_cert);
	
	local key_file	= '/etc/swanctl/private/'..ss_name..'_cert.key';
	local t_key_file= ss_name..'_cert.key';
	self:_checkAndReplace(t_key_file,key_file,ss_conf.ipsec_key);
		
	self:_prepXfrm(ss_name,ss_conf);
	
end

function rdVpn._configureOvpn(self,config)

	self.ovpnFound 	= true; --Set this flag to check later
	local final 	= '/etc/openvpn/'..config.name..'.ovpn';
	local temp  = config.name..'.ovpn';
	self:_checkAndReplace(temp,final,config.config)
	
	--Set the config if not present
	local x = self.uci:cursor()
	local section_exists = false

	-- Check if named section already exists
	x:foreach('openvpn', 'openvpn', function(s)
		if s['.name'] == config.name then
		    section_exists = true
		end
	end)

	if not section_exists then
		-- Create named section directly
		x:set('openvpn', config.name, 'openvpn')
		x:set('openvpn', config.name, 'enabled', '1')
		x:set('openvpn', config.name, 'config', final)
		x:save('openvpn')
		x:commit('openvpn')
	end
			
end

function rdVpn._configureZeroTier(self,config)

	self.ztFound 	= true; --Set this flag to check later
	local tpl           = '/etc/MESHdesk/configs/zerotier.tpl';
	
	--Set the config if not present
	local x = self.uci:cursor()
	local section_exists = false

	-- Check if named section already exists
	x:foreach('zerotier', 'zerotier', function(s)
		if( s['.name'] == 'global')then
			if((s['secret']) and (string.len(s['secret']) > 20))then
				print("Secret Found and Set");
			else
				print("No Secret Found -> Create one from template");
				self.util.exec('cp '..tpl..' /etc/config/zerotier');
				self.util.exec("/etc/init.d/zerotier restart")
			end
		end
	end)
	
	--Set the config if not present
	local x = self.uci:cursor()
	local section_exists = false

	-- Check if named section already exists
	x:foreach('zerotier', 'network', function(s)
		if s['.name'] == config.config.zt_network_id then
		    section_exists = true
		end
	end)

	if not section_exists then
		-- Create named section directly
		x:set('zerotier', config.config.zt_network_id, 'network')
		x:set('zerotier', config.config.zt_network_id, 'id', config.config.zt_network_id)
		x:set('zerotier', config.config.zt_network_id, 'allow_managed', '1')
		x:set('zerotier', config.config.zt_network_id, 'allow_global', '0')
		x:set('zerotier', config.config.zt_network_id, 'allow_default', '0')
		x:set('zerotier', config.config.zt_network_id, 'allow_dns', '0')
		x:save('zerotier')
		x:commit('zerotier')
	end		
end


function rdVpn._restartCheck(self)
	if(self.ovpnFound)then
		os.execute("/etc/init.d/openvpn restart")
	end
	if(self.ztFound)then
		os.execute("sleep 20")
		os.execute("/etc/init.d/zerotier restart")
	end
end

function rdVpn._prepXfrm(self,ss_name,ss_conf)
	local gw = ss_conf.ipsec_xfrm_gw;
	local ip   = ss_conf.ipsec_xfrm_ip;
	local id   = ss_conf.ipsec_if_id;
	self.util.exec("ip link add "..ss_name.." type xfrm if_id "..id.." 2>/dev/null || true");
	self.util.exec("ip addr add "..ip.."/32 dev xfrm01 2>/dev/null || true");
	self.util.exec("ip link set "..ss_name.." up");
	self.util.exec("sleep 5");
	self.util.exec("ip route add "..gw.."/32 dev "..ss_name.." 2>/dev/null || true");
	self.util.exec("sleep 5");
	self.util.exec("/etc/init.d/swanctl stop");
	self.util.exec("/etc/init.d/swanctl start");
end

function rdVpn._checkAndReplace(self,temp,final,contents)
	temp = '/tmp/'..temp;
	self.fs.writefile(temp,contents);
	local temp_md5 = self.util.exec("md5sum "..temp);
	local temp_md5 = string.match(temp_md5, '^(%x+)');
	
	--Compare with existing (If there are any)	
	local f=io.open(final,"r")                                                   
    if f~=nil then 
		io.close(f)
		local final_md5 = self.util.exec("md5sum "..final);
		local final_md5 = string.match(final_md5, '^(%x+)');
		if(temp_md5 ~= final_md5)then 
			self.fs.move(temp,final);
		else
			self.fs.unlink(temp);	
		end
	else
		self.fs.move(temp,final);
	end
end
