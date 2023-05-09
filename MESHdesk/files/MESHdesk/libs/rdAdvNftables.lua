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
	self.days       = { mo = 'Monday', tu = 'Tuesday', we = 'Wednesday', th = 'Thursday', fr = 'Friday', sa = 'Saturday', su = 'Sunday'}
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

function rdAdvNftables:addMac(mac)
    self:_addMac(mac);  
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

function rdAdvNftables._addMac(self,mac)

    local add_string = 'nft add rule bridge adv_meshdesk';
    local m = mac.mac;
    
    --Now the rules
    for j, rule in ipairs(mac.rules)do
        print(rule.action); 
        print("RULE");             
        local time_part = self:_timePart(rule);
        local a_c_part  = self:_actionComment(rule,mac.mac);
        local ctg_set   = self:_categorySet(rule);
        local app_flag  = false
        if(rule.category == 'app')then
            app_flag = true;
        end
        
        --===        
        if(a_c_part['allow'])then --allow and block is just one direction needed 
        
            if(not(app_flag))then
            
                for i, chain in ipairs(self.chains) do
                    self:log('Add Limit rule in chain '..chain..' for mac '..m)
                    local s = add_string..' '..chain..' '..time_part..' ether daddr '..m..' ip daddr '..ctg_set..' '..a_c_part['allow'];
                    print(s);
                    self.util.exec(s)
                    s = add_string..' '..chain..' '..time_part..' ether saddr '..m..' ip daddr '..ctg_set..' '..a_c_part['allow'];
                    print(s);
                    self.util.exec(s)
                end
            end
            
            if(app_flag)then
                for k, app in ipairs(rule.apps) do
                    for i, chain in ipairs(self.chains) do
                        --rule (with app set) for each app
                        local s = add_string..' '..chain..' '..time_part..' ether daddr '..m..' ip daddr \\@'..app..' '..a_c_part['allow'];
                        print(s);
                        self.util.exec(s)
                        s = add_string..' '..chain..' '..time_part..' ether saddr '..m..' ip daddr \\@'..app..' '..a_c_part['allow'];
                        print(s);
                        self.util.exec(s)
                    end            
                end                    
            end
                                    
        end
        
        if(a_c_part['block'])then --allow and block is just one direction needed
        
            if(not(app_flag))then
            
                for i, chain in ipairs(self.chains) do         
                    local s = add_string..' '..chain..' '..time_part..' ether daddr '..m..' ip daddr '..ctg_set..' '..a_c_part['block'];
                    print(s);
                    self.util.exec(s);
                    s = add_string..' '..chain..' '..time_part..' ether saddr '..m..' ip daddr '..ctg_set..' '..a_c_part['block'];
                    print(s);
                    self.util.exec(s);
                end
            end
            
            if(app_flag)then
                for k, app in ipairs(rule.apps) do
                    for i, chain in ipairs(self.chains) do
                        --rule (with app set) for each app
                        local s = add_string..' '..chain..' '..time_part..' ether daddr '..m..' ip daddr \\@'..app..' '..a_c_part['block'];
                        print(s);
                        self.util.exec(s)
                        s = add_string..' '..chain..' '..time_part..' ether saddr '..m..' ip daddr \\@'..app..' '..a_c_part['block'];
                        print(s);
                        self.util.exec(s)
                    end            
                end                    
            end
                         
        end
        
        if(a_c_part['limit'])then --limit needs out and in direction rate limit
         
            if(not(app_flag))then 
                 
                for i, chain in ipairs(self.chains) do 
                    local s_up      = add_string..' '..chain..' '..time_part..' ether saddr '..m..' ip daddr '..ctg_set..' '..a_c_part['limit_up'];
                    local s_down    = add_string..' '..chain..' '..time_part..' ether daddr '..m..' ip saddr '..ctg_set..' '..a_c_part['limit_down']; --forward remain the same
                    print(s_up);
                    self.util.exec(s_up);
                    print(s_down);
                    self.util.exec(s_down);    
                end
               
            end
            
            if(app_flag)then
                for k, app in ipairs(rule.apps) do
                
                    for i, chain in ipairs(self.chains) do
                        local s_up      = add_string..' '..chain..' '..time_part..' ether saddr '..m..' ip daddr \\@'..app..' '..a_c_part['limit_up'];
                        local s_down    = add_string..' '..chain..' '..time_part..' ether daddr '..m..' ip saddr \\@'..app..' '..a_c_part['limit_down']; --forward remain the same
                    
                        print(s_up);
                        self.util.exec(s_up);
                        print(s_down);
                        self.util.exec(s_down);
                    end
                           
                end                    
            end
                       
        end                 
    end    
end

function rdAdvNftables._addEntry(self,entry)

    -- entry has the following
    -- type (string); interfaces (list) ; rules (list)
    local chain = 'input';
    if(entry.type == 'bridge')then
        chain = 'forward';
    end
    
    local add_string = 'nft add rule bridge adv_meshdesk';
    
    local if_string = '';
    for i, interface in ipairs(entry.interfaces) do
        if_string = interface..','..if_string;
    end  
    print('Doing entry on chain '..chain..' and interfaces '..if_string);
     
    
    --Now the rules
    for j, rule in ipairs(entry.rules)do
        print(rule.action); 
        print("RULE");             
        local time_part = self:_timePart(rule);
        local a_c_part  = self:_actionComment(rule,if_string);
        local ctg_set   = self:_categorySet(rule);
        local app_flag  = false
        if(rule.category == 'app')then
            app_flag = true;
        end
        
        --===        
        if(a_c_part['allow'])then --allow and block is just one direction needed 
        
            if(not(app_flag))then       
                local s = add_string..' '..chain..' '..time_part..' iif {'..if_string..'} ip daddr '..ctg_set..' '..a_c_part['allow'];
                print(s);
                self.util.exec(s);
            end
            
            if(app_flag)then
                for k, app in ipairs(rule.apps) do
                    --rule (with app set) for each app
                    local s = add_string..' '..chain..' '..time_part..' iif {'..if_string..'} ip daddr \\@'..app..' '..a_c_part['allow'];
                    print(s);
                    self.util.exec(s)            
                end                    
            end
                                    
        end
        
        if(a_c_part['block'])then --allow and block is just one direction needed
        
            if(not(app_flag))then         
                local s = add_string..' '..chain..' '..time_part..' iif {'..if_string..'} ip daddr '..ctg_set..' '..a_c_part['block'];
                print(s);
                self.util.exec(s);
            end
            
            if(app_flag)then
                for k, app in ipairs(rule.apps) do
                    --rule (with app set) for each app
                    local s = add_string..' '..chain..' '..time_part..' iif {'..if_string..'} ip daddr \\@'..app..' '..a_c_part['block'];
                    print(s);
                    self.util.exec(s)            
                end                    
            end
                         
        end
        
        if(a_c_part['limit'])then --limit needs out and in direction rate limit
         
            if(not(app_flag))then      
                local s_up      = add_string..' '..chain..' '..time_part..' iif {'..if_string..'} ip daddr '..ctg_set..' '..a_c_part['limit_up'];
                local s_down    = add_string..' '..chain..' '..time_part..' oif {'..if_string..'} ip saddr '..ctg_set..' '..a_c_part['limit_down']; --forward remain the same
                if(chain == 'input')then
                    s_down    = add_string..' output '..time_part..' oif {'..if_string..'} ip saddr '..ctg_set..' '..a_c_part['limit_down']; --input and output swaps
                end
                print(s_up);
                self.util.exec(s_up);
                print(s_down);
                self.util.exec(s_down);
            end
            
            if(app_flag)then
                for k, app in ipairs(rule.apps) do
                    local s_up      = add_string..' '..chain..' '..time_part..' iif {'..if_string..'} ip daddr \\@'..app..' '..a_c_part['limit_up'];
                    local s_down    = add_string..' '..chain..' '..time_part..' oif {'..if_string..'} ip saddr \\@'..app..' '..a_c_part['limit_down']; --forward remain the same
                    if(chain == 'input')then
                        s_down    = add_string..' output '..time_part..' oif {'..if_string..'} ip saddr \\@'..app..' '..a_c_part['limit_down']; --input and output swaps
                    end
                    print(s_up);
                    self.util.exec(s_up);
                    print(s_down);
                    self.util.exec(s_down);       
                end                    
            end
                       
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

function rdAdvNftables._round(self,number)
    if (number - (number % 0.1)) - (number - (number % 1)) < 0.5 then
        number = number - (number % 1)
    else
        number = (number - (number % 1)) + 1
    end
    return number
end

function rdAdvNftables._timePart(self,rule)

    local time_part = '';
    if(rule.schedule == 'every_week')then
        local day_string = 'day {';
    
        for k in pairs(self.days) do
            if(rule[k])then
                day_string = day_string..' '..self.days[k]..' , ';
            end        
        end      
        day_string = day_string..'} ';
        time_part = day_string;       
    end               
    if((rule.schedule == 'every_day')or(rule.schedule == 'every_week')or(rule.schedule == 'one_time'))then
        local start_m   = self:_round(rule.start_time % 60);
        local start_h   = self:_round(rule.start_time / 60);
        local end_m     = self:_round(rule.end_time % 60);
        local end_h     = self:_round(rule.end_time / 60);        
        if(rule.end_time < rule.start_time)then
            time_part    = time_part..'hour != '..end_h..':'..end_m..'-'..start_h..':'..start_m;
        else
            time_part    = time_part..'hour '..start_h..':'..start_m..'-'..end_h..':'..end_m;           
        end                      
    end
            
    return time_part;
end

function rdAdvNftables._actionComment(self,rule,if_string)

    local a_c_part = {
        allow       = false,
        block       = false,
        limit_up    = false,
        limit_down  = false,
        limit       = false
    };
    
    if(rule.action == 'limit')then 
        a_c_part['limit']       = true;
        a_c_part['limit_up']    = 'limit rate over '..rule.bw_up..' kbytes/second counter drop comment \\"LIMIT UPLOAD ON '..if_string..'\\"';
        a_c_part['limit_down']  = 'limit rate over '..rule.bw_down..' kbytes/second counter drop comment \\"LIMIT DOWNLOAD ON '..if_string..'\\"';   
    end
    
    if(rule.action == 'block')then   
        a_c_part['block']  = ' counter drop comment \\"DROP ON '..if_string..'\\"';
    end
    
    if(rule.action == 'allow')then
        a_c_part['block']  = ' counter accept comment \\"ACCEPT ON '..if_string..'\\"'; 
    end
                
    return a_c_part;
end

function rdAdvNftables._categorySet(self,rule)

    if(rule.category == 'internet')then
        return '!= \\@md_internet_not';
    end
    
    if(rule.category == 'local_network')then
        return '\\@md_lan';
    end
    
    if(rule.category == 'ip_address')then
        return '{'..rule.ip_address..'}';
    end
    
    if(rule.category == 'domain')then
        return '{'..rule.ip_address..'}';
    end
    
end
