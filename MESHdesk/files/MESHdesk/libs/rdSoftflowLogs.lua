require( "class" )

-------------------------------------------------------------------------------
-- Class that will gather info from Softflowd using  softflowctl dump-flows ---
-------------------------------------------------------------------------------
----------------------------------------------------------------------------------
-- Privoxy is a blixem so we have to rip the lag file and assemble our own lines--
----------------------------------------------------------------------------------
class "rdSoftflowLogs"

--Init function for object
function rdSoftflowLogs:rdSoftflowLogs()

    require('rdLogger');
    
	self.version 	= "JUL_2021_a"
	self.tag	    = 'MESHdesk';
	self.debug	    = true;
	--self.debug	    = false;
	self.json	    = require('luci.json');
	self.nfs        = require('nixio.fs');
	self.util       = require("luci.util");
	self.uci    	= require('luci.model.uci');
	self.x          = self.uci.cursor();
	self.logger		= rdLogger();

end
        
function rdSoftflowLogs:getVersion()
	return self.version
end

function rdSoftflowLogs:log(m,p)
	if(self.debug)then
		self.logger:log(m,p)
	end
end

function rdSoftflowLogs:chilliInfo()
    return self:_chilliInfo();
end

function rdSoftflowLogs:doDumpFlows()
    return self:_doDumpFlows();
end


function rdSoftflowLogs:doDeleteAll()
    self:_doDeleteAll()
end


--[[--
========================================================
=== Private functions start here =======================
========================================================
(Note they are in the pattern function <rdName>._function_name(self, arg...) and called self:_function_name(arg...) )
--]]--


function rdSoftflowLogs._doDeleteAll(self)
    self.util.exec("softflowctl delete-all");
end

function rdSoftflowLogs._chilliInfo(self)

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


function rdSoftflowLogs._doDumpFlows(self)

    self:log('Doing Dump Flows');
    local flows_info    = {};
    local chilli_info   = self:_chilliInfo();
    
    local df = self.util.execi("softflowctl dump-flows");  
    local flow_id = 1; 
    for line in df do
        --print("Output of Dump Flows");
        --print(line)
        local l_table = self.util.split(line," ");
        if(self.util.contains(l_table,'ACTIVE'))then
            --self.util.dumptable(l_table);          
            local flow_line = {};     
            local src   = self:_ip_port(l_table[3]);
            local dst   = self:_ip_port(l_table[5]);
            local start = l_table[11];
            start       = start:gsub("^start:", "");
            local fin   = l_table[12];
            fin         = fin:gsub("^finish:", "");
            
            local oct_out   = l_table[7];
            oct_out         = oct_out:gsub("^octets>:", "");
            local pckt_out  = l_table[8];
            pckt_out        = pckt_out:gsub("^packets>:", "");
            
            local oct_in    = l_table[9];
            oct_in          = oct_in:gsub("^octets<:", "");
            local pckt_in   = l_table[10];
            pckt_in         = pckt_in:gsub("^packets<:", "");
            
            --Proto 6 = TCP and 17 = UDP
            local proto     = l_table[6];
            proto           = proto:gsub("^proto:", "");
            
            -- WE NEED TO RECORD TALKBACK ALSO WHERE src is outside and dst is inside
            -- EG ACTIVE seq:231 [8.8.8.8]:53 <> [192.168.182.21]:18955 proto:17 octets>:88 packets>:1 octets<:72 packets<:1 
            -- start:2021-07-23T05:27:37.115 finish 2021-07-23T05:27:37.169 tcp>:00 tcp<:00 flowlabel>:00000000 flowlabel<:00000000 EXPIRY EVENT for flow 231 in 27 seconds
   
            --print("Src IP: "..src.ip.." Src Port: "..src.port.." Dst IP: "..dst.ip.." Dst Port: "..dst.port.. " Starting: "..start.." Ending: "..fin.."\n");
            
            -- TALKING OUT --
            local chilli_item_out = chilli_info[src.ip];
            if(chilli_item_out)then
                table.insert(flows_info, {
                    id          = flow_id,
                    src_ip      = src.ip,
                    src_mac     = chilli_item_out['mac'],
                    username    = chilli_item_out['user'],
                    proto       = proto,
                    src_port    = src.port,
                    dst_ip      = dst.ip,
                    dst_port    = dst.port,
                    oct_out     = oct_out,
                    pckt_out    = pckt_out,
                    oct_in      = oct_in,
                    pckt_in     = pckt_in,                  
                    start       = start,
                    finish      = fin
                });
                flow_id = flow_id+1;
            end
            
            -- TALKING IN --
            local chilli_item_in = chilli_info[dst.ip];
            if(chilli_item_in)then
                table.insert(flows_info, {
                    id          = flow_id,
                    src_ip      = dst.ip,--SWAP
                    src_mac     = chilli_item_in['mac'],
                    username    = chilli_item_in['user'],
                    proto       = proto,
                    src_port    = dst.port,--SWAP
                    dst_ip      = src.ip,--SWAP
                    dst_port    = src.port,--SWAP
                    oct_out     = oct_in, --SWAP
                    pckt_out    = pckt_in,--SWAP
                    oct_in      = oct_out,--SWAP
                    pckt_in     = pckt_out,--SWAP                  
                    start       = start,
                    finish      = fin
                });
                flow_id = flow_id+1;
            end           
        end
    end
    self.util.dumptable(flows_info);
    self:_doDeleteAll(); -- clean up (Since we have now reported on the connections)
    return flows_info;
end

function rdSoftflowLogs._ip_port(self,value)
    local ip_port   = {};
    local l_table   = self.util.split(value,":");
    local ip        = l_table[1];
    ip = ip:gsub("^%[", "");
    ip = ip:gsub("%]", "");
    ip_port['ip']   = ip;
    ip_port['port'] = l_table[2];
    return ip_port;
end


