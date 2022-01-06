require( "class" )

-------------------------------------------------------------------------------
-- Class used to disconnect and COA existing Coova Connections-----------------
-------------------------------------------------------------------------------
class "rdCoa"

--Init function for object
function rdCoa:rdCoa()
	require('rdLogger');
	require('rdNetwork');	
	local uci	    = require('uci')
	self.version    = "1.0.1"
	self.tag	    = "MESHdesk"
	self.debug	    = true
	--self.debug	    = false
	self.json	    = require("json")
	self.logger	    = rdLogger()
	self.network	= rdNetwork()
	self.x		    = uci.cursor()
	local id_if     = self.x.get('meshdesk','settings','id_if');	
	self.id_if		= self.network:getMac(id_if);
	
	self.util       = require("luci.util");
	self.results	= '/tmp/coa_result.json';
	self.coaForMac  = "/cake3/rd_cake/coa-requests/coa-for-mac.json";
	self.ReplyRes	= '/tmp/reply_result.json';
	self.coaReply   = "/cake3/rd_cake/coa-requests/coa-reply.json";
end
        
function rdCoa:getVersion()
	return self.version
end

function rdCoa:check()
	self:log("== Do the check for any awaiting COA Requests ==")
	self:_check()
end


function rdCoa:log(m,p)
	if(self.debug)then
		self.logger:log(m,p)
	end
end

--[[--
========================================================
=== Private functions start here =======================
========================================================
--]]--


function rdCoa._check(self)
	local curl_data = '{"mac":"'..self.id_if..'"}'
    local proto 	= self.x.get('meshdesk','internet1','protocol')
    local url       = self.coaForMac;
    local server    = self.x.get('meshdesk','internet1','ip')
    
	local local_ip_v6   = self.network:getIpV6ForInterface('br-lan');
	if(local_ip_v6)then
	    server      = self.x.get("meshdesk", "internet1", "ip_6");
	    server      = '['..server..']';
	end
	
	local http_port     = self.x.get('meshdesk','internet1','http_port');
    local https_port    = self.x.get('meshdesk','internet1','https_port');
    local port_string   = '/';
    
    if(proto == 'http')then
        if(http_port ~= '80')then
            port_string = ":"..http_port.."/";
        end
    end
    
    if(proto == 'https')then
        if(https_port ~= '443')then
            port_string = ":"..https_port.."/";
        end
    end
		
    local query     = proto .. "://" .. server .. port_string .. url

    --Remove old results                                                                                              
    os.remove(self.results)
    os.execute('curl -k -o '..self.results..' -X POST -H "Content-Type: application/json" -d \''..curl_data..'\' '..query)
    
    --Read the results
    local f=io.open(self.results,"r")
    if(f)then
        result_string = f:read("*all")
        r =self.json.decode(result_string)
        if(r.success)then
			if(r.items)then
				self:_executeActions(r.items)
			end
        end
    end
end

function rdCoa._executeActions(self,actions)
	--Actions is a list in the format [{'id':"98","command": "reboot"}]--
	local table_results = {};
	for i, row in ipairs(actions)do
		print("Doing action NR "..row.id)
		--self:_addToCompleted(row.id)
		print("Doing "..row.request_type); --can be pod or coa
		local s_avp = "";
		local s_file = "/tmp/avps.txt";
        for key,value in pairs(row.avp) do 
            if (type(value) == "table") then  --The only TWO (so far we know of) which might come in table (list)'XWF-Authorize-Class-Name' / 'XWF-Authorize-Bytes-Left'
                for i, v in ipairs(value) do 
                    --print(i, v);
                    if(key == 'XWF-Authorize-Class-Name')then
                        --The one that goes with it is => XWF-Authorize-Class-Name
                        --print('XWF-Authorize-Class-Name ='..' "'..v..'"');
                        s_avp = s_avp..'XWF-Authorize-Class-Name ='..' "'..v..'"'.."\n";
                        
                        
                        local bytes_left = row.avp['XWF-Authorize-Bytes-Left'][i];
                        --print('XWF-Authorize-Bytes-Left = '..bytes_left);
                        s_avp = s_avp..'XWF-Authorize-Bytes-Left = '..bytes_left.."\n";
                        
                    end 
                end
            else
                --print(key..' ='..' "'..value..'"');
                s_avp = s_avp..key..' ='..' "'..value..'"'.."\n"; 
            end            
        end
        
        local f,err = io.open(s_file,"w")
		if not f then return print(err) end
		f:write(s_avp)
		f:close()
		local request_type = row.request_type;
		if(request_type == 'pod')then
		    request_type = 'disconnect';
		end 
		
		local coa_results   = self.util.exec("cat "..s_file.." |radclient  -r 2 -t 2 127.0.0.1:3799 "..request_type.." testing123");
		table.insert(table_results,{id = row.id, results = coa_results});
		--os.execute(row.command)
	end
	
	if (next(table_results) ~= nil) then
	    local json_results  = self.json.encode(table_results);
	    local curl_data     = '{"mac":"'..self.id_if..'","coa_results":'..json_results..'}';
	    
        local proto 	    = self.x.get('meshdesk','internet1','protocol')
        local url           = self.coaReply;
        local server        = self.x.get('meshdesk','internet1','ip');  
        local http_port     = self.x.get('meshdesk','internet1','http_port');
        local https_port    = self.x.get('meshdesk','internet1','https_port');
        local port_string   = '/';
        
        if(proto == 'http')then
            if(http_port ~= '80')then
                port_string = ":"..http_port.."/";
            end
        end
        
        if(proto == 'https')then
            if(https_port ~= '443')then
                port_string = ":"..https_port.."/";
            end
        end
        
        
	    local local_ip_v6   = self.network:getIpV6ForInterface('br-lan');
	    if(local_ip_v6)then
	        server      = self.x.get("meshdesk", "internet1", "ip_6");
	        server      = '['..server..']';
	    end
	    
        local query     = proto .. "://" .. server .. port_string .. url;
    
        os.remove(self.ReplyRes);
	    os.execute('curl -k -o '..self.ReplyRes..' -X POST -H "Content-Type: application/json" -d \''..curl_data..'\' '..query);
	    print(json_results);
	end	
end


