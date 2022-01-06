require( "class" )

-------------------------------------------------------------------------------
-- A class to fetch system statistics and return it in JSON form -------------
-------------------------------------------------------------------------------
class "rdSystemstats"

--Init function for object
function rdSystemstats:rdSystemstats()
	require('rdLogger');
	require('rdExternal');
	require('rdNetwork');
	
	local uci 		= require("uci")
	
	self.version 	= "1.0.0"
	self.json	    = require("json")
	self.logger	    = rdLogger()
	self.external	= rdExternal()
	--self.debug	    = true
	self.debug	    = false
	self.x			= uci.cursor()
	self.network    = rdNetwork
end
        
function rdSystemstats:getVersion()
	return self.version
end


function rdSystemstats:getStats()
	return self:_getStats()
end


function rdSystemstats:log(m,p)
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


function rdSystemstats._getStats(self)
	self:log('Getting System stats')
	local s 	= {}

	local id_if = self.x.get('meshdesk','settings','id_if');
    local id    = self.network:getMac(id_if)                                                                 
	s['eth0']   = id 

    s['sys']    = {}
	
    --Read the memory
    local file = assert(io.open("/proc/meminfo", "r"))
    s['sys']['memory'] = {}
    for line in file:lines() do 
        if(string.find(line, "MemTotal:"))then
            local mt = string.gsub(line, "^MemTotal:%s*", "")
            s['sys']['memory']['total'] = mt
        end
        if(string.find(line, "MemFree:"))then
            local mf = string.gsub(line, "^MemFree:%s*", "")
            s['sys']['memory']['free'] = mf
        end
    end
    file:close()
    
    --Read the CPU info
    local file = assert(io.open("/proc/cpuinfo","r"))
    s['sys']['cpu'] = {}
    for line in file:lines() do
        if(string.find(line, "system type%s*:"))then
            local i = string.gsub(line, "^system type%s*:%s*", "")
            s['sys']['cpu']['system_type'] = i
        end
        if(string.find(line, "cpu model%s*:"))then
            local i = string.gsub(line, "^cpu model%s*:%s*", "")
            s['sys']['cpu']['cpu_model'] = i
        end
        if(string.find(line, "BogoMIPS%s*:"))then
            local i = string.gsub(line, "^BogoMIPS%s*:%s*", "")
            s['sys']['cpu']['BogoMIPS'] = i
        end
    end
    file:close()
    
    --Get the uptime
    local handle = io.popen("uptime")                                      
    local result = handle:read("*a")
    result = string.gsub(result,"^%s*","")
    result = string.gsub(result,"\n","")
    
    handle:close()  
    s['sys']['uptime'] = result
    
    --get the release
    local file = assert(io.open("/etc/openwrt_release", "r"))
    local c = file:read("*all");
    --Remove the single quotes from Chaos Calmer (the previous ones had double quotes)
    c = string.gsub(c,"'","")
    s['sys']['release'] = c	    
      
    return (self.json.encode(s)) 	
end 

