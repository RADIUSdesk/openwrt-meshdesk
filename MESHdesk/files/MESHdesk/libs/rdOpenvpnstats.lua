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
    
    self.x:foreach('vpn-gateways', 'gateway',
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
			                --2023-10-22 20:14:03
			                local date_side =  string.gsub(i, "%s+.+", "");
			                local time_side =  string.gsub(i, ".+%s+", "");
			                local date_components = rdOpenvpnstats._mysplit(date_side,'-');
                            local time_components = rdOpenvpnstats._mysplit(time_side, ":");   
                            local stat_stamp = os.time({year=date_components[1], month=date_components[2], day=date_components[3], hour=time_components[1],min=time_components[2],sec=time_components[3]})
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

