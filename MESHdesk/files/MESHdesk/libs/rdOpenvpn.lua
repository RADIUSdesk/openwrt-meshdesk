require( "class" )

-------------------------------------------------------------------------------
-- Openvpn -------------
-------------------------------------------------------------------------------
class "rdOpenvpn"

--Init function for object
function rdOpenvpn:rdOpenvpn()
	require('rdLogger');
	require('rdExternal');

    local uci 	    = require("uci")
    self.x		    = uci.cursor()
	self.version 	= "1.0.0"
	self.tag	    = "MESHdesk"
	self.logger	    = rdLogger()
	self.debug	    = true
	self.json	    = require("json")
	--Add external command object
	self.external	= rdExternal()

end
        
function rdOpenvpn:getVersion()
	return self.version
end

function rdOpenvpn:configureFromJson(file)
	self:log("==Configure OpenVPN from JSON file "..file.."==")
	self:__configureFromJson(file)
end

function rdOpenvpn:configureFromTable(tbl)
	self:log("==Configure OpenVPN from  Lua table==")
	self:__configureFromTable(tbl)
end


function rdOpenvpn:log(m,p)
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

function rdOpenvpn.__configureFromJson(self,json_file)

	self:log("Configuring OpenVPN from a JSON file")
	local contents 	= self:__readAll(json_file)
	local o			= self.json.decode(contents)
	if(o.config_settings.openvpn_bridges ~= nil)then
		self:log("Found OpenVPN settings - completing it")		
		self:__configureFromTable(o.config_settings.openvpn_bridges)
	else
		self:log("No OpenVPN settings found, please check JSON file")
	end
end


function rdOpenvpn.__configureFromTable(self,table)

    self:__newOpenvpn()
    
	for i, table_entry in ipairs(table) do
	    self:log("Doing OpenVPN config item  number "..i);
	    
	    local ca;                                                 
	    local up;
	    local interface;                                                 
	    local config_file = {}; -- New empty array for this entry;
	    local vpn_gateway_address;
	    local vpn_client_id;
	    
	    --Here we collect the various things to eventually process them                             
		for key, val in pairs(table_entry) do                           
            print("The key is "..key);
            if(key == 'ca')then
                ca = val
            end
            if(key == 'up')then
                up = val
            end
            if(key == 'interface')then
                interface = val
            end 
            if(key == 'vpn_gateway_address')then
                vpn_gateway_address = val
            end 
            if(key == 'vpn_client_id')then
                vpn_client_id = val
            end 
            
            if(key == 'config_file')then
                for k, v in pairs(val) do                                                                  
                	config_file[k] = v                                                                     
              	end  
            end     	                                                                                                 
    	end
    		
    	-- Now we have gathered the info ---
    	
    	-- Add entries to config file
    	self.x.set('openvpn',interface,'openvpn')
		for key, val in pairs(config_file) do
            print("There " .. key .. ' and '.. val);
            self.x.set('openvpn',interface,key,val);
        end
        
        -- Add the CA --
        local ca_filename = '/etc/openvpn/'..interface.."_ca.crt";
        self:__writeAll(ca_filename,ca)
        
        -- Add the UP --
        local up_filename = '/etc/openvpn/'..interface.."_up";
        self:__writeAll(up_filename,up)
        
        -- Write the vpn-gateways
        self.x.set('vpn-gateways',interface,'gateway')
        self.x.set('vpn-gateways',interface,'ipaddr',vpn_gateway_address);
        self.x.set('vpn-gateways',interface,'vpn_client_id',vpn_client_id);
        self.x.set('vpn-gateways',interface,'interface',interface);
      
    end
    self.x.commit('openvpn');
    self.x.commit('vpn-gateways');
end

-- Clean start OpenVPN                                                
function rdOpenvpn.__newOpenvpn(self)
	local f="/etc/config/openvpn";

    os.execute("rm " .. f);
    os.execute("touch " .. f);

    --List of the gateways--
	local gw="/etc/config/vpn-gateways"   
    
    os.execute("rm " .. gw);
    os.execute("touch " .. gw);
end


function rdOpenvpn.__readAll(self,file)
	local f = io.open(file,"rb")
	local content = f:read("*all")
	f:close()
	return content
end

function rdOpenvpn.__writeAll(self,file,contents)
    local f,err = io.open(file,"w")
	if not f then return print(err) end
	f:write(contents)
	f:close()
end


