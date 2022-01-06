require( "class" )

----------------------------------------------------------------------------------
-- A class to read the OpenVPN Client status file and return it in JSON format ---
----------------------------------------------------------------------------------
class "rdOpenvpnstats"

--Init function for object
function rdOpenvpnstats:rdOpenvpnstats()
	require('rdLogger');	
	local uci 		= require("uci")
	self.version 	= "1.0.0"
	self.json	    = require("json")
	self.logger	    = rdLogger()
	self.debug	    = true
	self.x			= uci.cursor()
end
        
function rdOpenvpnstats:getVersion()
	return self.version
end


function rdOpenvpnstats:getStats()
	return self:_getStats()
end


function rdOpenvpnstats:log(m,p)
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

function rdOpenvpnstats._getStats(self)
	self:log('Getting OpenVPN stats')
	local stats 	        = {}
    stats['vpn_gateways']   = {}  
    require('rdConfig');
    local c                 = rdConfig();
    local months            = {};
    months['Jan']=1;
    months['Feb']=2;
    months['Mar']=3;
    months['Apr']=4;
    months['May']=5;
    months['Jun']=6;
    months['Jul']=7;
    months['Aug']=8;
    months['Sep']=9;
    months['Oct']=10;
    months['Nov']=11;
    months['Dec']=12;
    
    self.x.foreach('vpn-gateways', 'gateway',
		function(s)	
		    local ipaddr;
		    local vpn_client_id;
		    local interface;
		    local state = false;
		    local to_old = true;
		    local traffic_flow = false;
		
            for key, value in pairs(s) do
                if(key == 'ipaddr')then
                    ipaddr = tostring(value);
                end
                if(key == 'vpn_client_id')then
                    vpn_client_id = tostring(value);
                end               
                if(key == 'interface')then
                    interface = tostring(value);
                end          
            end
            
            --The status file is using this convention: /var/run/openvpn.[(interface eg ex_zero)].status
            if(interface)then
                local f_name = '/var/run/openvpn.'..interface..'.status';
                local f = rdOpenvpnstats._file_exists(f_name);
                if(f)then
                    for line in f:lines() do
                        --Figure out when last the update was
                        if(string.find(line, "Updated,"))then
                            local i = string.gsub(line, "^Updated,", "");
                            --Fri Apr 14 08:27:00 2017
                            local date_components = {};
                            local j = 0;
                            for i in string.gmatch(i, "%S+") do
                                date_components[j] = i;
                                j = j+1;
                            end
                            
                            local month     = date_components[1];
                            time_components = rdOpenvpnstats._mysplit(date_components[3], ":");   
                            local stat_stamp = os.time({year=date_components[4], month=months[month], day=date_components[2], hour=time_components[1],min=time_components[2],sec=time_components[3]})
                            local now_stamp  = os.time();
                            if((now_stamp - stat_stamp)< 240)then --Older then 4 minutes ... to old
                                to_old = false;
                            end
                        end
                        
                        if(string.find(line, "TCP/UDP read bytes,"))then
                            local a = string.gsub(line, "^TCP/UDP read bytes,", "");
                            if(tonumber(a) > 0)then
                                traffic_flow = true;   
                            end 
                        end
                    end
                end   
            end
            if(ipaddr and vpn_client_id)then
                if((to_old == false)and(traffic_flow == true))then
                    state = true;
                end
                table.insert(stats['vpn_gateways'],{ipaddr=ipaddr,vpn_client_id=vpn_client_id,state=state,timestamp=os.time()})
            end
		end)     
    return (self.json.encode(stats)) 	
end

function rdOpenvpnstats._file_exists(name)
    print("Test if file exists");
    local f=io.open(name,"r")
    if(f~=nil)then     
        return f; 
    else 
        return false;
    end
end 

function rdOpenvpnstats._mysplit(inputstr, sep)
        if sep == nil then
                sep = "%s"
        end
        local t={} ; i=1;
        for str in string.gmatch(inputstr, "([^"..sep.."]+)") do
                t[i] = str
                i = i + 1
        end
        return t
end

