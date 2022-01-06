require( "class" )

-------------------------------------------------------------------------------
-- Class used to set up the system settings handed from the config server -----
-- For now it only is the system password and hostname ------------------------
-- It will only do something if there was a change ----------------------------
-------------------------------------------------------------------------------
class "rdSystem"

--Init function for object
function rdSystem:rdSystem()
	require('rdLogger')
	local uci	    = require('uci')
	self.version    = "1.0.1"
	self.tag	    = "MESHdesk"
	--self.debug	    = true
	self.debug	    = false
	self.json	    = require("json")
	self.logger	    = rdLogger()
	self.x		    = uci.cursor()
	self.s			= "/etc/shadow"
	self.t			= "/tmp/t"
end
        
function rdSystem:getVersion()
	return self.version
end

function rdSystem:configureFromJson(file)
	self:log("==Configure System from JSON file "..file.."==")
	self:__configureFromJson(file)
end

function rdSystem:configureFromTable(tbl)
	self:log("==Configure System from  Lua table==")
	self:__configureFromTable(tbl)
end


function rdSystem:log(m,p)
	if(self.debug)then
		self.logger:log(m,p)
	end
end

--[[--
========================================================
=== Private functions start here =======================
========================================================
--]]--

function rdSystem.__configureFromJson(self,json_file)

	self:log("Configuring System from a JSON file")
	local contents 	= self:__readAll(json_file)
	local o			= self.json.decode(contents)
	if(o.config_settings.system ~= nil)then
		self:log("Found System settings - completing it")		
		self:__configureFromTable(o.config_settings.system)
	else
		self:log("No System settings found, please check JSON file")
	end
end

function rdSystem.__configureFromTable(self,tbl)

	--First we do the password
	local c_pw 		= self:__getCurrentPassword()
	if(c_pw)then
		local new_pw	= tbl.password_hash
		if(new_pw)then
			if(c_pw ~= new_pw)then
				self:__replacePassword(new_pw,'root')
			end
		end	
	end

	--Then we do the hostname
	local c_hn 	= self:__getCurrentHostname()
	if(c_hn)then
		local new_hn	= tbl.hostname
		if(new_hn)then
			if(c_hn ~= new_hn)then
				self:__setHostname(new_hn)
			end
		end
	end

	-- Do the timezone
	local c_tz	= self:__getCurrentTimezone()
	if(c_tz)then
		local new_tz	= tbl.timezone
		if(new_tz)then
			if(c_tz ~= new_tz)then
				self:__setTimezone(new_tz)
			end
		end
	end

	--Gateway and Heartbeat settings--
	local items = {'gw_dhcp_timeout', 'gw_use_previous', 'gw_auto_reboot', 'gw_auto_reboot_time', 'heartbeat_dead_after' }
	for i, item in ipairs(items) do
  		local item_from_config = self.x.get('meshdesk', 'settings', item )
		if(item_from_config)then
			local new_item = tbl[item]
			--Some changes for boolean items--
			local t = type(new_item);
            if(t == 'boolean')then
          		local bool_item = "0"
           		if(new_item)then
                  		bool_item = "1"
           		end
				new_item = bool_item
			end
			if(new_item)then
				if(item_from_config ~= new_item)then
					self.x.set('meshdesk', 'settings', item,new_item)
				end
			end
		end
	end	
	
	--Reporting settings--
	items = {'report_adv_enable','report_adv_proto','report_adv_light','report_adv_full','report_adv_sampling'};
	for i, item in ipairs(items) do
  		local item_from_config = self.x.get('meshdesk', 'reporting', item )
		if(item_from_config)then
			local new_item = tbl[item]
			--Some changes for boolean items--
			local t = type(new_item);
            if(t == 'boolean')then
          		local bool_item = "0"
           		if(new_item)then
                  		bool_item = "1"
           		end
				new_item = bool_item
			end
			if(new_item)then
				if(item_from_config ~= new_item)then
					self.x.set('meshdesk', 'reporting', item,new_item)
					--FIXME DO we need to specify a something here (like touching a file in temp)
					--So he heartbeat script knows about this...
				end
			end
		end
	end	
	self.x.commit('meshdesk')
 
end


function rdSystem.__getCurrentPassword(self,user)
    if(user == nil)then user = 'root' end
	local enc = nil
	for line in io.lines(self.s) do
		if(string.find(line,'^'..user..":.*"))then
			line = string.gsub(line, '^'..user..":", "")
			line = string.gsub(line, ":.*", "")
			--return line
			enc = line
			break
		end 
	end
	return enc
end


function rdSystem.__replacePassword(self,password,user)	
    if(user == nil)then user = 'root' end
	local new_shadow = '';
	for line in io.lines(self.s) do
		if(string.find(line,'^'..user..":.*"))then
			line = string.gsub(line, '^'..user..":.-:", "")
			line = user..":"..password..":"..line --Replace this line
		end
		new_shadow = new_shadow ..line.."\n"
	end

	local f,err = io.open(self.t,"w")
	if not f then return print(err) end
	f:write(new_shadow)
	f:close()
	os.execute("cp "..self.t.." "..self.s)
	os.remove(self.t)
end

function rdSystem.__getCurrentHostname(self)
	local hostname = nil
	self.x.foreach('system','system', 
		function(a)
			hostname = self.x.get('system', a['.name'], 'hostname')
	end)
	return hostname
end

function rdSystem.__setHostname(self,hostname)
	self.x.foreach('system','system', 
		function(a)
			self.x.set('system', a['.name'], 'hostname',hostname)
	end)
	self.x.commit('system')
	--Activate it
	os.execute("echo "..hostname.." > /proc/sys/kernel/hostname")	
end

function rdSystem.__getCurrentTimezone(self)
	local timezone = nil
	self.x.foreach('system','system', 
		function(a)
			timezone = self.x.get('system', a['.name'], 'timezone')
	end)
	return timezone
end

function rdSystem.__setTimezone(self,timezone)
	self.x.foreach('system','system', 
		function(a)
			self.x.set('system', a['.name'], 'timezone',timezone)
	end)
	self.x.commit('system')
end

function rdSystem.__readAll(self,file)
	local f = io.open(file,"rb")
	local content = f:read("*all")
	f:close()
	return content
end

