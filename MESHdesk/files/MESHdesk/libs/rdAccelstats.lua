require( "class" )

----------------------------------------------------------------------------------
-- A class that uses accel-cmd to return info on accel-ppp file in JSON format ---
----------------------------------------------------------------------------------
class "rdAccelstats"

--Init function for object
function rdAccelstats:rdAccelstats()
	require('rdLogger');	
	self.version 	= "1.0.0";
	self.json	    = require('luci.json');
	self.logger	    = rdLogger();
	self.debug	    = true;
	self.password   = 'testing124';
	self.config     = '/etc/accel-ppp/accel-ppp.conf'
end
        
function rdAccelstats:getVersion()
	return self.version
end

function rdAccelstats:getPassword()
	self:_primePassword();
    return self.password;	
end


function rdAccelstats:getStats()
	self:_primePassword();
    return self:_showStat();	
end

function rdAccelstats:showStat()
    self:_primePassword();
    return self:_showStat();	
end

function rdAccelstats:showSessions()
    self:_primePassword();
    return self:_showSessions();	
end


function rdAccelstats:log(m,p)
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

function rdAccelstats._file_exists(name)
    print("Test if file exists");
    local f=io.open(name,"r")
    if(f~=nil)then     
        return f; 
    else 
        return false;
    end
end 


function rdAccelstats._showStat(self)

    local a   = io.popen('accel-cmd -P '..self.password..' show stat') 
    local str = a:read('*a')
    local items = {};
    for s in str:gmatch("[^\r\n]+") do
        if(string.match(s,"^%a.+:.+$"))then --Patterns like 'uptime: 0.10:40:13'
            local k   = string.gsub(s,":.+", '')
            local v   = string.gsub(s,".+:%s+", '')
            items[k]  = v;
        end
        if(string.match(s,"^%a.+:$"))then --Patterns like 'sessions:'
            section           = string.gsub(s,":", '')
            items[section]    = {};
        end
        if(string.match(s,"^%s+%a.+:.+$"))then --Petterns like '  starting: 0'
            local k = string.gsub(s,":.+", '')
            k       = string.gsub(k,"^%s+",'')
            local v = string.gsub(s,".+:%s+", '')
            local entry = {name = k, value = v}
           --entry[k]  = v;
            table.insert(items[section],entry)
        end
    end
    return items;
end

--[[--
show sessions [columns] [order <column>] [match <column> <regexp>] - shows sessions
	columns:
		netns - network namespace name
		vrf - vrf name
		ifname - interface name
		username - user name
		ip - IP address
		ip6 - IPv6 address
		ip6-dp - IPv6 delegated prefix
		type - connection type
		state - state of session
		uptime - uptime (human readable)
		uptime-raw - uptime (in seconds)
		calling-sid - calling station id
		called-sid - called station id
		sid - session id
		comp - compression/encryption method
		rx-bytes - received bytes (human readable)
		tx-bytes - transmitted bytes (human readable)
		rx-bytes-raw - received bytes
		tx-bytes-raw - transmitted bytes
		rx-pkts - received packets
		tx-pkts - transmitted packets
		inbound-if - inbound interface
		service-name - PPPoE service name
		rate-limit - rate limit down-stream/up-stream (Kbit)
--]]--

function rdAccelstats._showSessions(self)
    local a     = io.popen('accel-cmd -P '..self.password..' show sessions ifname,username,ip,state,uptime,calling-sid,called-sid,sid,rx-bytes-raw,tx-bytes-raw,rx-pkts,tx-pkts,inbound-if,rate-limit') 
    local str   = a:read('*a')
    local counter = 0;
    local keys  = {};
    local items = {};
    for s in str:gmatch("[^\r\n]+") do
        --table.insert(lines, s)
        counter = counter +1;
        local entry = {};
        --print("BEGIN"..s..counter.."END"); --FIXME Figure out haw to handle blank values
        local item_counter = 0;
        for t in s:gmatch("[^%s?|%s?]+")do
            item_counter = item_counter +1;
            --print("TAB"..t..item_counter.."ENDTAB")
            if(counter == 1)then
                table.insert(keys,t)
            end
            if(counter > 2)then               
                local k     = keys[item_counter]
                entry[k]    = t;
            end
        end
        if(counter > 2)then
            table.insert(items,entry);
        end
    end
    return items;
end

function rdAccelstats._primePassword(self) --read the password from the server's config file
    conf_string = self:__readAll(self.config);
    --print(conf_string);
    for line in string.gmatch(conf_string,'[^\r\n]+') do
        if(string.match(line,"^password=") ~= nil)then
            line = string.gsub(line, "^password=", "");
            self.password = line;
        end 
    end
end

function rdAccelstats.__readAll(self,file)
	local f = io.open(file,"rb")
	local content = f:read("*all")
	f:close()
	return content
end
