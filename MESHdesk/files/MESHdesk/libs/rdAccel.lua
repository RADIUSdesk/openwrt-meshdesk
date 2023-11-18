require( "class" )

-------------------------------------------------------------------------------
-- Accel (ppp) Class  -------------
-------------------------------------------------------------------------------
class "rdAccel"

--Init function for object
function rdAccel:rdAccel()

	require('rdLogger');
	self.version 	= "1.0.0"
	self.tag	    = "MESHdesk"
	self.logger	    = rdLogger()
	self.debug	    = true
	self.json       = require('luci.json');
	self.accelConf  = "/etc/accel-ppp/accel-ppp.conf";
	self.txtConf    = '';
end
        
function rdAccel:getVersion()
	return self.version
end

function rdAccel:configureFromJson(file)
	self:log("==Configure Accel-ppp from JSON file "..file.."==")
	self:__configureFromJson(file)
end

function rdAccel:configureFromTable(tbl)
	self:log("==Configure Accel-ppp from Lua table==")
	self:__configureFromTable(tbl)
end


function rdAccel:log(m,p)
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

function rdAccel.__configureFromJson(self,json_file)

	self:log("Configuring Accel-ppp from a JSON file")
	local contents 	= self:__readAll(json_file)
	local o			= self.json.decode(contents)
	if(o.config_settings.accel_servers ~= nil)then
		self:log("Found Accel-ppp settings - completing it")		
		self:__configureFromTable(o.config_settings.accel_servers)
	else
		self:log("No Accel-ppp settings found, please check JSON file")
	end
end

function rdAccel.__configureFromTable(self,table)
    self:__prepAccel()
    self:__newAccel()    
	for i, table_entry in ipairs(table) do
	    local conf_txt = self:__buildConfig(table_entry,0); 
        if(string.len(conf_txt) > 10)then
            --writeAndRestart(conf_txt);
            self:__writeAndRestart(conf_txt);
            print(conf_txt);
        end	
	end	  
end

-- Clean start Accel-ppp                                               
function rdAccel.__newAccel(self)

	local f= self.accelConf;
    os.execute("rm " .. f);
    os.execute("touch " .. f);
    
end

function rdAccel.__readAll(self,file)
	local f = io.open(file,"rb")
	local content = f:read("*all")
	f:close()
	return content
end

function rdAccel.__writeAll(self,file,contents)
    local f,err = io.open(file,"w")
	if not f then return print(err) end
	f:write(contents)
	f:close()
end

function rdAccel.__prepAccel(self)
    os.execute('/etc/init.d/accel-ppp disable');
    os.execute('mkdir /var/log/accel-ppp');
    os.execute('ln -s /usr/lib/accel-ppp/libconnlimit.so /usr/lib');
    os.execute('ln -s /usr/lib/accel-ppp/libvlan-mon.so  /usr/lib');
    os.execute('ln -s /usr/lib/accel-ppp/libradius.so   /usr/lib');
end

function rdAccel.__buildConfig(self,t,level)
    --print("==Looping Level "..level);
    for k, v in pairs(t) do
        if(type(k) == 'string')then
            if(level == 0)then
                --print("\n["..k.."]");
                self.txtConf=self.txtConf.."\n\n["..k.."]";
            else                
                if(type(v) == 'string')then
                    --print(k);
                    if((k == 'pools')or(k == 'server' ))then
                        self.txtConf=self.txtConf.."\n"..v;
                    else                    
                        if(tonumber(k))then
                            --print(v);
                            self.txtConf=self.txtConf.."\n"..v;
                        else
                            --print(k..'='..v);
                            self.txtConf=self.txtConf.."\n"..k..'='..v;
                        end                       
                    end                   
                end
                if(type(v) == 'number')then
                    --print(k..'='..v);
                    self.txtConf=self.txtConf.."\n"..k..'='..v;
                end               
            end
            --print(type(v));
            if(type(v) == 'table')then
                self:__buildConfig(v,level+1);    
            end
        end
        if(type(k)== 'number')then
            --print(v);
            self.txtConf=self.txtConf.."\n"..v;
        end
    end   
    return self.txtConf;    
end

function rdAccel.__writeAndRestart(self,conf_txt)
    local file = io.open(self.accelConf, "w" )
    if( io.type( file ) == "file" ) then
        file:write(conf_txt)
        file:close();
        os.execute('/etc/init.d/accel-ppp restart');
    end
end

