require( "class" )

-------------------------------------------------------------------------------
-- Class used to set up the reboot_setting settings -------------------------------
-------------------------------------------------------------------------------
class "rdRebootSettings"

--Init function for object
function rdRebootSettings:rdRebootSettings()
	require('rdLogger')
	self.version    = "1.0.1"
	self.tag	    = "MESHdesk"
	self.debug	    = true
	--self.debug	    = false
	self.json	    = require("json")
	self.logger	    = rdLogger()	
	self.l_uci    	= require("luci.model.uci");
	self.crontab    = '/etc/crontabs/root';
end
        
function rdRebootSettings:getVersion()
	return self.version
end

function rdRebootSettings:configureFromJson(file)
	self:log("==Configure Reboot Settings from JSON file "..file.."==")
	self:__configureFromJson(file)
end

function rdRebootSettings:configureFromTable(tbl)
	self:log("==Configure Reboot Settings from  Lua table==")
	self:__configureFromTable(tbl)
end

function rdRebootSettings:clear()
	self:log("==Clear Reboot settings if there were any==")
	self:__clearCrontab();
	self:__disableCntAutoReboot();
end


function rdRebootSettings:log(m,p)
	if(self.debug)then
		self.logger:log(m,p)
	end
end

--[[--
========================================================
=== Private functions start here =======================
========================================================
--]]--

function rdRebootSettings.__configureFromJson(self,json_file)

	self:log("Configuring Reboot Settings from a JSON file")
	local contents 	= self:__readAll(json_file)
	local o			= self.json.decode(contents)
	if(o.config_settings.reboot_setting ~= nil)then
		self:log("Found Reboot Settings - completing it")		
		self:__configureFromTable(o.config_settings.reboot_setting)
	else
		self:log("No Reboot Settings found, Check and clear older ones")
		self:__clearCrontab();
	end
end

function rdRebootSettings.__configureFromTable(self,tbl)
    self:__clearCrontab();
    self:__disableCntAutoReboot();
	for k in pairs(tbl) do
    	local val = tbl[k];
		if(k == 'reboot_at')then
		    --value should be in format 12:00 PM
		    local a_or_p = string.gsub(val, ".*:.*%s+", "");
		    
		    local hour = string.gsub(val, ":.*", "");
		    hour = string.format("%d", hour);
		    
		    local min = string.gsub(val, ".*:", "");
		    min = string.gsub(min, "%s+[A|P]M", "");
		    min = string.format("%d", min);
		
		    if((a_or_p == 'PM')and(hour == '12'))then
		        hour = 0;
		    end
		    
		    if((a_or_p == 'PM')and(hour ~= '12'))then
		        hour = tonumber(hour)+12;
		    end		    
		    self:__addCrontab(min,hour);
		    os.execute("/etc/init.d/cron reload");
		end
		
		if(k == 'controller_reboot_time')then
		    self.l_uci.cursor():set('meshdesk','settings','cnt_auto_reboot', '1');
		    self.l_uci.cursor():set('meshdesk','settings','cnt_auto_reboot_time', val);
		    self.l_uci.cursor():save('meshdesk');
	        self.l_uci.cursor():commit('meshdesk');
		end	
  	end  
end

function rdRebootSettings.__readAll(self,file)
    local content = ''; --Empty string by default
	local f = io.open(file,"rb")
	if(f~=nil)then
	    local content = f:read("*all");
	    f:close();
    end
	return content;
end

function rdRebootSettings.__clearCrontab(self)
    local found_flag = false;
    local cron_file  = io.open(self.crontab,"r");
    local new_content= '';
    if(cron_file~=nil)then
        for line in cron_file:lines() do
            if(string.find(line,"/sbin/reboot"))then
                found_flag = true;
            else
                if(line:match'^%s%S' == nil)then
                    line = line.."\n";
                    new_content = new_content..line;
                end       
            end
        end       
        cron_file:close();
        if(found_flag)then
            local f,err = io.open(self.crontab,"w")
			if not f then return print(err) end
			f:write(new_content);
			f:close();
			os.execute("/etc/init.d/cron reload");       
        end         
    end
end

function rdRebootSettings.__addCrontab(self,min,hour)
    local contents 	= self:__readAll(self.crontab);
    local new_line  = min.." "..hour.." * * * /sbin/reboot\n";
    contents        = contents..new_line;
    local f,err         = io.open(self.crontab,"w")
	if not f then return print(err) end
	f:write(contents);
	f:close();
end

function rdRebootSettings.__disableCntAutoReboot(self)
    self.l_uci.cursor():set('meshdesk','settings','cnt_auto_reboot', '0');	
    self.l_uci.cursor():save('meshdesk');
    self.l_uci.cursor():commit('meshdesk');
end
