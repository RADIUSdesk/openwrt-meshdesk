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


function rdVpn._configureFromJson(self,json_file)

	self:log("Configuring VPN items from a JSON file");
	local contents 	= self:_readAll(json_file);
	local o			= self.json.decode(contents);
	
	if o.config_settings and o.config_settings.vpn then
		self:log("Found VPN Data  - completing it");
		self:_configureFromTable(o.config_settings.vpn);
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
