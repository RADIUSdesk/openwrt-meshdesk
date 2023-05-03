require( "class" )

-- 02 MAY 2023 --

-------------------------------------------------------------------------------
-- Class to manage nftables on the **bridge adv-meshdesk** table ------------------
-------------------------------------------------------------------------------
class "rdAdvNftables"

--Init function for object
function rdAdvNftables:rdAdvNftables()
    require('rdLogger');
	self.version 	= "1.0.1"
	self.tag	    = "MESHdesk"
	self.priority	= "debug"
	self.util       = require('luci.util'); --26Nov 2020 for posting command output
	self.chains     = {'input', 'forward', 'output'}
end
        
function rdAdvNftables:getVersion()
	return self.version	
end

function rdAdvNftables:initConfig()
    self:_initConfig();
end

function rdAdvNftables:flushTable()
    self:_flushTable();
end

function rdAdvNftables:clearSets()
    self:_clearSets();
end


function rdAdvNftables:addSet(set) 
    self:_addSet(set);
end

function rdAdvNftables:addEntry(entry)
    self:_addEntry(entry);  
end


function rdAdvNftables:macOn(mac)
    self:_macOn(mac);
end

function rdAdvNftables:macOff(mac)
    self:_macOff(mac);
end

function rdAdvNftables:macLimit(mac,bw_up,bw_down)
    self:_macLimit(mac,bw_up,bw_down);
end

function rdAdvNftables:log(m,p)
	if(self.debug)then
		self.logger:log(m,p)
	end
end

--[[--
========================================================
=== Private functions start here =======================
========================================================
--]]--

function rdAdvNftables._initConfig(self)

    local i  = self.util.execi("nft list table bridge adv_meshdesk 2>&1"); --Important to direct stderror also to stdout :-)
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
        self.util.exec("nft add table bridge adv_meshdesk")
        self.util.exec("nft add chain bridge adv_meshdesk forward '{type filter hook forward priority 0; }'");
        self.util.exec("nft add chain bridge adv_meshdesk input '{type filter hook input priority 0; }'");
        self.util.exec("nft add chain bridge adv_meshdesk output '{type filter hook output priority 0; }'");
    else
        self:log("Table already there");   
    end	
end

function rdAdvNftables._flushTable(self)
    self:log("Flush table adv_meshdesk");
    self.util.exec("nft flush table bridge adv_meshdesk")
end

function rdAdvNftables._clearSets(self)
    self:log("Remove All Sets");    
    local i  = self.util.execi(" nft -e -a list table bridge adv_meshdesk");
    if(i)then
        for line in i do
             if(string.match(line,".+set.+ handle%s+") ~= nil)then
                local handle = string.gsub(line,".+set.+ handle%s+", "");
                self:log(handle);
                self.util.exec('nft delete set bridge adv_meshdesk handle '..handle);
             end
        end
    end
end

function rdAdvNftables._addSet(self,set)
    --set has the following
    -- name; elements list (string) and comment
    --print('nft add set bridge adv_meshdesk '..set.name..' { type ipv4_addr\\; flags interval\\; elements={ '..set.elements..' comment \"'..set.comment..'\" }\\; }');
    self.util.exec('nft add set bridge adv_meshdesk '..set.name..' { type ipv4_addr\\; flags interval\\; elements={ '..set.elements..' comment \\"'..set.comment..'\\" }\\; }'); 
end

function rdAdvNftables._addEntry(self,entry)

    -- entry has the following
    -- type (string); interfaces (list) ; rules (list)
    local chain = 'input';
    if(entry.type == 'bridge')then
        chain = 'forward';
    end
    
    local if_string = '';
    for i, interface in ipairs(entry.interfaces) do
        if_string = interface..','..if_string;
    end  
    print('Doing entry on chain '..chain..' and interfaces '..if_string);
     
    
    --Now the rules
    for j, rule in ipairs(entry.rules)do
        print(rule.action); 
        print("RULE"); 
        
        local time_set = '';
        local time_set_2 = false;          
        if(rule.schedule == 'every_day')then
        
            if(rule.start_time < rule.end_time)then
                local start_m   = rule.start_time % 60;
                local start_h   = rule.start_time / 60;
                local end_m     = rule.end_time % 60;
                local end_h     = rule.end_time / 60;         
                time_set        = 'hour '..start_h..':'..start_m..'-'..end_h..':'..end_m;
            else            
                local start_m   = rule.start_time % 60;
                local start_h   = rule.start_time / 60;
                local end_m     = rule.end_time % 60;
                local end_h     = rule.end_time / 60;         
                time_set        = 'hour '..start_h..':'..start_m..'-'..'23:59';
                time_set_2      = 'hour 00:00'..'-'..end_h..':'..end_m;                           
            end                  
        end           
        if(rule.action == 'limit')then
            print('Add Limit rule in chain '..chain..' for interfaces '..if_string)
            if(chain == 'forward')then
                self.util.exec('nft add rule bridge adv_meshdesk '..chain..' '..time_set..' iif {'..if_string..'} limit rate over '..rule.bw_up..' kbytes/second counter drop comment \\"LIMIT iif '..if_string..'\\"');
                self.util.exec('nft add rule bridge adv_meshdesk '..chain..' '..time_set..' oif {'..if_string..'} limit rate over '..rule.bw_down..' kbytes/second counter drop comment \\"LIMIT oif '..if_string..'\\"');
                
                if(time_set_2)then
                    self.util.exec('nft add rule bridge adv_meshdesk '..chain..' '..time_set_2..' iif {'..if_string..'} limit rate over '..rule.bw_up..' kbytes/second counter drop comment \\"LIMIT iif '..if_string..'\\"');
                    self.util.exec('nft add rule bridge adv_meshdesk '..chain..' '..time_set_2..' oif {'..if_string..'} limit rate over '..rule.bw_down..' kbytes/second counter drop comment \\"LIMIT oif '..if_string..'\\"');
                end
                                
            end
            if(chain == 'input')then
                self.util.exec('nft add rule bridge adv_meshdesk '..chain..' '..time_set..' iif {'..if_string..'} limit rate over '..rule.bw_up..' kbytes/second counter drop comment \\"LIMIT iif '..if_string..'\\"');
                self.util.exec('nft add rule bridge adv_meshdesk '..'output '..time_set..' oif {'..if_string..'} limit rate over '..rule.bw_down..' kbytes/second counter drop comment \\"LIMIT oif '..if_string..'\\"');
                
                if(time_set_2)then
                    self.util.exec('nft add rule bridge adv_meshdesk '..chain..' '..time_set_2..' iif {'..if_string..'} limit rate over '..rule.bw_up..' kbytes/second counter drop comment \\"LIMIT iif '..if_string..'\\"');
                    self.util.exec('nft add rule bridge adv_meshdesk '..'output '..time_set_2..' oif {'..if_string..'} limit rate over '..rule.bw_down..' kbytes/second counter drop comment \\"LIMIT oif '..if_string..'\\"');
                end
            end
           --nft add rule bridge filter forward ether daddr 0c:c6:fd:7b:8b:aa iif br-ex_zero limit rate over 200 kbytes/second counter drop      
        end 
         
    end
    
end


function rdAdvNftables._macOn(self,m)
    self:log("Clear Block on MAC "..m);   
    for i, chain in ipairs(self.chains) do
        self:log('Clear rules in chain '..chain..' of mac '..m)      
        local i  = self.util.execi("nft -e -a list chain bridge adv_meshdesk "..chain);
        if(i)then
            for line in i do
                 if(string.match(line,".+"..m..".+ handle%s+") ~= nil)then
                    local handle = string.gsub(line,".+"..m..".+ handle%s+", "");
                    self:log(handle);
                    self.util.exec('nft delete rule bridge adv_meshdesk '..chain..' handle '..handle);
                 end
            end
        end        
    end 
end


function rdAdvNftables._macOff(self,m)
    --Clear it first
    self:_macOn(m);
    self:log("Block MAC "..m);
    for i, chain in ipairs(self.chains) do
        self:log('Add Block rule in chain '..chain..' for mac '..m)
        self.util.exec('nft add rule bridge adv_meshdesk '..chain..' ether daddr '..m..' counter drop comment \\"DROP DST '..m..'\\"');
        self.util.exec('nft add rule bridge adv_meshdesk '..chain..' ether saddr '..m..' counter drop comment \\"DROP SRC '..m..'\\"');   
    end
end

function rdAdvNftables._macLimit(self,m,bw_up,bw_down)
    --Clear it first
    self:_macOn(m);
    self:log("Limit MAC "..m);
    for i, chain in ipairs(self.chains) do
        self:log('Add Limit rule in chain '..chain..' for mac '..m)
        self.util.exec('nft add rule bridge adv_meshdesk '..chain..' ether daddr '..m..' limit rate over '..bw_down..' kbytes/second counter drop comment \\"LIMIT DST '..m..'\\"');
        self.util.exec('nft add rule bridge adv_meshdesk '..chain..' ether saddr '..m..' limit rate over '..bw_up..' kbytes/second counter drop comment \\"LIMIT SRC '..m..'\\"');          
    end
end

