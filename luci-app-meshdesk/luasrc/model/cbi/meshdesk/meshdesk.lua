local NX   = require "nixio";
local SYS  = require "luci.sys";
local uci  = require("uci");
local x    = uci.cursor(nil,'/var/state');

m = Map("meshdesk", "MESHdesk") -- We want to edit the uci config file /etc/config/network


s = m:section(NamedSection, "internet1",'internet', "Controller Details") 


function s.validate(self, sectionid)
    local field, obj
    local values = { }
    for field, obj in pairs(self.fields) do
        local fieldval = obj:formvalue(sectionid)
        if not values[fieldval] then
            values[fieldval] = true
        else
            return nil -- raise error
        end
    end

    return sectionid -- signal success
end


f1 = s:option(ListValue, "disabled", "Central Management") -- Creates an element list (select box)
f1.widget="radio"
f1:value("1", "Disabled") -- Key and value pairs
f1:value("0", "Enabled")
f1.default = "disable"
function f1.write(self, section, value)
    return Flag.write(self, section, value)
end


function f1.validate(self, value)
    if (value == "0")then 
        f2.optional = false;
    end
    
    if (value == "1")then 
        f2.optional = true;
        f2.rmempty = false;
    end
    
    return value
end


local protocol = s:option(ListValue,"protocol", "Protocol");                               
protocol:value("http","HTTP");                                                                                           
protocol:value("https","HTTPS");                                         
protocol:depends("disabled","0"); 
                                                     
function protocol.cfgvalue(self,section)                                                   
        local val = self.map:get(section,"protocol");                                      
        return val         
end   


f2=s:option(Value,"dns",'FQDN','Supply Dummy Value If Not Using DNS System')
f2:depends("disabled","0")


--function f2.validate(self, value)
--    return nil
--end

function f2.cfgvalue(self,section)
    local val = self.map:get(section, "dns")--Value.cfgvalue(self, section)
    return val
end

f3=s:option(Value,"ip",'IP Address','Optional If FQDN Fails / Not Used')
f3:depends("disabled","0")


function f3.cfgvalue(self,section)
    local val = self.map:get(section, "ip")--Value.cfgvalue(self, section)              
    return val
end



m.on_after_commit = function(self)
    local new_disabled      = luci.http.formvalue("cbid.meshdesk.internet1.disabled")
    local current_disabled  = x:get("meshdesk", "internet1", "disabled");
    if(current_disabled ~= new_disabled)then --Did the mode change?
        if(new_disabled == '1')then
            SYS.exec("touch /etc/config/network");
            SYS.exec("rm /etc/config/network");
            SYS.exec("touch /etc/config/wireless");
            SYS.exec("rm /etc/config/wireless");
		    NX.nanosleep(1)		-- sleep a second
		    SYS.exec("/bin/config_generate");
		    SYS.exec("/sbin/wifi config");
		    SYS.exec("cp /etc/MESHdesk/configs/firewall /etc/config/firewall");--Restore the firewall which was backed up on first boot
		    SYS.exec("cp /etc/MESHdesk/configs/dhcp /etc/config/dhcp");--Restore the dhcp which was backed up on first boot
		    return true;   
        end
    end
end


return m -- Returns the map
