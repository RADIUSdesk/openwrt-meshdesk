require( "class" )

-- 17 FEB 2023 --

-------------------------------------------------------------------------------
-- Class to manage nftables on the **bridge meshdesk** table ------------------
-------------------------------------------------------------------------------
class "rdNftables"

--Init function for object
function rdNftables:rdNftables()
    require('rdLogger');
	self.version 	= "1.0.1"
	self.tag	    = "MESHdesk"
	self.priority	= "debug"
	self.util       = require('luci.util'); --26Nov 2020 for posting command output
	self.chains     = {'input', 'forward', 'output'}
end
        
function rdNftables:getVersion()
	return self.version	
end

function rdNftables:initConfig()
    self:_initConfig();
end

function rdNftables:flushTable()
    self:_flushTable()
end

function rdNftables:macOn(mac)
    self:_macOn(mac);
end

function rdNftables:macOff(mac)
    self:_macOff(mac);
end

function rdNftables:macLimit(mac,bw_up,bw_down)
    self:_macLimit(mac,bw_up,bw_down);
end

function rdNftables:log(m,p)
	if(self.debug)then
		self.logger:log(m,p)
	end
end

--[[--
========================================================
=== Private functions start here =======================
========================================================
--]]--

function rdNftables._initConfig(self)

    local i  = self.util.execi("nft list table bridge meshdesk 2>&1"); --Important to direct stderror also to stdout :-)
    local table_missing = false;
    if(i)then
        for line in i do
             if(string.match(line,"^Error: No such file or directory") ~= nil)then
                table_missing = true;
                break
            end
        end
    end
    if(table_missing)then
        self:log("Table missing add it");   
        self.util.exec("nft add table bridge meshdesk")
        self.util.exec("nft add chain bridge meshdesk forward '{type filter hook forward priority 0; }'");
        self.util.exec("nft add chain bridge meshdesk input '{type filter hook input priority 0; }'");
        self.util.exec("nft add chain bridge meshdesk output '{type filter hook output priority 0; }'");
    else
        self:log("Table already there");   
    end	
end

function rdNftables._flushTable(self)
    self:log("Flush table meshdesk");
    self.util.exec("nft flush table bridge meshdesk")
end

function rdNftables._macOn(self,m)
    self:log("Clear Block on MAC "..m);   
    for i, chain in ipairs(self.chains) do
        self:log('Clear rules in chain '..chain..' of mac '..m)      
        local i  = self.util.execi("nft -e -a list chain bridge meshdesk "..chain);
        if(i)then
            for line in i do
                 if(string.match(line,".+"..m..".+ handle%s+") ~= nil)then
                    local handle = string.gsub(line,".+"..m..".+ handle%s+", "");
                    self:log(handle);
                    self.util.exec('nft delete rule bridge meshdesk '..chain..' handle '..handle);
                 end
            end
        end        
    end 
end

function rdNftables._macOff(self,m)
    --Clear it first
    self:_macOn(m);
    self:log("Block MAC "..m);
    for i, chain in ipairs(self.chains) do
        self:log('Add Block rule in chain '..chain..' for mac '..m)
        self.util.exec('nft add rule bridge meshdesk '..chain..' ether daddr '..m..' counter drop comment \\"DROP DST '..m..'\\"');
        self.util.exec('nft add rule bridge meshdesk '..chain..' ether saddr '..m..' counter drop comment \\"DROP SRC '..m..'\\"');   
    end
end

function rdNftables._macLimit(self,m,bw_up,bw_down)
    --Clear it first
    self:_macOn(m);
    self:log("Limit MAC "..m);
    for i, chain in ipairs(self.chains) do
        self:log('Add Limit rule in chain '..chain..' for mac '..m)
        self.util.exec('nft add rule bridge meshdesk '..chain..' ether daddr '..m..' limit rate over '..bw_down..' kbytes/second counter drop comment \\"LIMIT DST '..m..'\\"');
        self.util.exec('nft add rule bridge meshdesk '..chain..' ether saddr '..m..' limit rate over '..bw_up..' kbytes/second counter drop comment \\"LIMIT SRC '..m..'\\"');          
    end
end

