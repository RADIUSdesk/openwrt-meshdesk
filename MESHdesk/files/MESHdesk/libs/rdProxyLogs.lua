require( "class" )

-------------------------------------------------------------------------------
-- Class that will gather the logs from Privoxy (or later Squid)  -------------
-------------------------------------------------------------------------------
----------------------------------------------------------------------------------
-- Privoxy is a blixem so we have to rip the lag file and assemble our own lines--
----------------------------------------------------------------------------------
class "rdProxyLogs"

--Init function for object
function rdProxyLogs:rdProxyLogs()

    require('rdLogger');
    
	self.version 	= "FEB_2021_a"
	self.tag	    = 'MESHdesk';
	self.debug	    = true;
	--self.debug	    = false;
	self.json	    = require('luci.json');
	self.nfs        = require('nixio.fs');
	self.util       = require("luci.util");
	self.uci    	= require('luci.model.uci');
	self.x          = self.uci.cursor();
	self.logger		= rdLogger();
	self.priv_log1   = '/etc/MESHdesk/tests/logfile.txt'
	self.priv_log   = '/var/log/privoxy1.log'

end
        
function rdProxyLogs:getVersion()
	return self.version
end

function rdProxyLogs:log(m,p)
	if(self.debug)then
		self.logger:log(m,p)
	end
end

function rdProxyLogs:chilliInfo()
    return self:_chilliInfo();
end

function rdProxyLogs:doPrivoxy()
    return self:_doPrivoxy();
end


function rdProxyLogs:truncLog()
    self:_truncLog()
end


--[[--
========================================================
=== Private functions start here =======================
========================================================
(Note they are in the pattern function <rdName>._function_name(self, arg...) and called self:_function_name(arg...) )
--]]--


function rdProxyLogs._truncLog(self)
    self.nfs.writefile(self.priv_log,"");
end

function rdProxyLogs._chilliInfo(self)

    local chilli_info = {};
    local cq_l = self.util.execi(" chilli_query list");   
    for line in cq_l do
        --print("Output of Chilli Query");
        --print(line)
        local l_table = self.util.split(line," ");
        --self.util.dumptable(l_table);
        local ip    = l_table[2];
        local mac   = l_table[1];
        local user  = l_table[6];
        chilli_info[ip] = {mac = mac, user = user}
    end
    --self.util.dumptable(chilli_info);
    return chilli_info;
end


function rdProxyLogs._doPrivoxy(self)

    self:log('Doing Privoxy Logs');
    local f = self.nfs.access(self.priv_log)
    if(f == nil)then
        self:log('Missing Privoxy Log file '..self.priv_log);
        return;
    end
    
    local s_file    = self.priv_log -- The file 
    local file      = io.open(s_file, "r");    
    local requests  = {};
    local logs      = {};
    local log_id    = 1;  
      
    for line in file:lines() do  
        local l_table = self.util.split(line," ");
        
        --self.util.dumptable(l_table);
        if(self.util.contains(l_table,'Request:'))then
            --print("==REQUEST==");
            --l_table[1]	gives something like 2021-02-12
            local y_m_d = self.util.split(l_table[1],"-");
            --l_table[2] gives something like this 07:22:55.011 --split it up and get a seconds value
            local h_m_s = self.util.split(l_table[2],":");
            local hour  = h_m_s[1];
            local min   = h_m_s[2];
            local sec   = self:_round(h_m_s[3]);
            local timestamp = os.time{year=y_m_d[1], month=y_m_d[2], day=y_m_d[3], hour=hour,min=min,sec=sec}
            full_url    = l_table[5];
            local host  = full_url:gsub("/.*", "");
            local relative_url = full_url:gsub(host, "");
            table.insert(requests, {timestamp =timestamp, host = host, full_url = full_url,relative_url = relative_url})
        else 
            --SAMPLE LINE (cathc on - and - (item2 and item3)      
            --10.1.1.2 - - [14/Feb/2021:22:18:30 +0530] "POST / HTTP/1.1" 200 472     
            if((l_table[2] =='-')and(l_table[3] =='-'))then
                --print("==LOG==");
                --l_table[4]	gives something like [12/Feb/2021:07:22:55
                local date_string = l_table[4];
                date_string = date_string:gsub("^%[", "");
                local s_d_m_y = date_string:gsub(":%d*", "");
                local d_m_y = self.util.split(s_d_m_y,"/");
                local s_h_m_s = date_string:gsub(".*/%d%d%d%d*:", "");
                local h_m_s = self.util.split(s_h_m_s,":");
                local hour  = h_m_s[1];
                local min   = h_m_s[2];
                local sec   = h_m_s[3];          
                local month = self:_m_to_number(d_m_y[2]);--12/Feb/2021
                local timestamp = os.time{year=d_m_y[3], month=month, day=d_m_y[1], hour=hour,min=min,sec=sec};
                table.insert(logs, {id=log_id, timestamp =timestamp,relative_url = l_table[7],full_string = line});
                log_id=log_id+1;
            end 
        end
        --print(line);  
    end   
    file:close();
    
    --self.util.dumptable(requests);
    --self.util.dumptable(logs);
    local temp_logs = logs;
    local found_logs = {};
    counter = 0;
    for i, v in ipairs(requests) do
        local r_ts = v.timestamp  
        for j, w in ipairs(temp_logs) do
            if((w.timestamp-1 <= r_ts+30)and(w.relative_url == v.relative_url)) then --We give a 31 seconds tolerance an remove the FIRST match we find from the table
                counter = counter+1;
                --print(tostring(w.id)..") Timestamps is the same and URL Matach "..v.host..w.relative_url)
                table.insert(found_logs,{id = w.id, host=v.host, full_url = v.host..w.relative_url, full_string = w.full_string});
                --Remove item from table since its now 'used up'
                --print("Removing table entry "..j);
                table.remove(temp_logs,j);
            end       
        end
    end
    
    --Get the infor from Chilli
    local chilli_info = self:_chilliInfo();
    
    for j,y in ipairs(found_logs) do
        --print(y.full_string);
        local f_table = self.util.split(y.full_string," ");
        f_table[7] = y.full_url;
        local souce_ip = f_table[1];
        found_logs[j].source_ip = souce_ip;
        local chilli_item = chilli_info[souce_ip];
        if(chilli_item)then
            found_logs[j].mac   = chilli_item['mac'];
            found_logs[j].username  = chilli_item['user'];
        end      
        found_logs[j].full_string = table.concat(f_table," ");
    end
    --self.util.dumptable(found_logs);
    self:_truncLog(); -- clean up 
    return found_logs;
end

function rdProxyLogs._round(self,number)
  if (number - (number % 0.1)) - (number - (number % 1)) < 0.5 then
    number = number - (number % 1)
  else
    number = (number - (number % 1)) + 1
  end
 return number
end

function rdProxyLogs._m_to_number(self,month)
    local m_list = { 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec' };
    for i, v in ipairs(m_list) do
        if(v == month)then
            return i;
        end 
    end
    return 1; -- failover
end


