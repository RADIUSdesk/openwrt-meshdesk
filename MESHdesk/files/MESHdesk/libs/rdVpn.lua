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
	local contents 	= self:_readAll(json_file);
	local o			= self.json.decode(contents);
	
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
    end
    --Check what needs to be restarted
    self:_restartCheck();  
end


function rdVpn._configureOvpn(self,config)

	self.ovpnFound 	= true; --Set this flag to check later
	local final 	= '/etc/openvpn/'..config.name..'.ovpn';
	
	--Write the config to /tmp and get md5sum
	local temp  = '/tmp/'..config.name..'.ovpn';
	self.fs.writefile(temp,config.config);
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

function rdVpn._restartCheck(self)

	if(self.ovpnFound)then
		os.execute("/etc/init.d/openvpn restart")
	end
end


function rdVpn._readAll(self,file)
	local f = io.open(file,"rb")
	local content = f:read("*all")
	f:close()
	return content
end
