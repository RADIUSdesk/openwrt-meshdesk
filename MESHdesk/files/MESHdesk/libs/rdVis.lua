require( "class" )

-------------------------------------------------------------------------------
-- Class used to Prepare the Vis data for the back end  -----------------------
-- We substitute the mesh0 macs with eth0 among other things-------------------
-------------------------------------------------------------------------------
class "rdVis"

--Init function for object
function rdVis:rdVis()

	require('rdLogger')
	self.version    = "1.0.1"
	self.tag	    = "MESHdesk"
	--self.debug	    = true
	self.debug	    = false
	self.json	    = require("json")
	self.logger	    = rdLogger()
	self.ethmap		= 110
	self.mac_map	= {};	
	self.util       = require "luci.util";
end
        
function rdVis:getVersion()
	return self.version
end

function rdVis:getVisNoAlfred()
    return self:_getVisNoAlfred()
end


function rdVis:getVis()
	self:log("==Get batadv-vis formatted to out liking ==")
	return self:_getVisNoAlfred();
	--return self:_getVis()
end

function rdVis:log(m,p)
	if(self.debug)then
		self.logger:log(m,p)
	end
end

--[[--
========================================================
=== Private functions start here =======================
========================================================
--]]--

function rdVis._getVis(self)
	local fb_data = {}
	fd    = io.popen("batadv-vis -f jsondoc")
	if fd then
        output = fd:read("*a")
        if(string.len(output) ~=0 )then     
            local json_vis = self.json.decode(output)
            for i, row in ipairs(json_vis.vis) do            
                    for j, n in ipairs(row.neighbors) do     
                        table.insert(fb_data, n)                
                    end                                         
            end                                         
        else                       
            --There were no result from batadv-vis restart Alfred
            os.execute("/etc/init.d/alfred stop");       
            os.execute("/etc/init.d/alfred start");
        end
        fd:close()
    end
	return self.json.encode(fb_data)
end

function rdVis._getVisNoAlfred(self)
    self:log("Getting Vis Results without Alfred");
    local fb_o      = self.util.exec("/usr/sbin/batctl o");
    local fb_n      = self.util.exec("/usr/sbin/batctl n");
    local t_fb_o    = self.util.split(fb_o);
    local t_fb_n    = self.util.split(fb_n);
    local router    = '';
    local t_nbr     = {};
    local t_orig    = {};
    
    for index,value in ipairs(t_fb_o) do
        if(value:match("^%s+%*%s+"))then
            local orig_mac  = string.gsub(value,"^%s+%*%s+",'');
            orig_mac        = string.gsub(orig_mac,"%s+%d.*",'');
            local metric    = string.gsub(value,".*%s+%(",'');
            metric          = string.gsub(metric,"%)%s+.*",'');
            metric          = metric/255;
            metric          = rdVis:round(metric,3);
            t_orig[orig_mac]= metric;
        end
    end
    
    for index,value in ipairs(t_fb_n) do     
        if(index == 1)then
            router = string.gsub(value, '.*MainIF/MAC:', '');
            router = string.gsub(router, '%s*.%(bat.*', '');
            router = string.gsub(router, '%s*mesh.*/', '');
        end
        
        if(value:match("^%s+mesh"))then
            local neighbor
            local neighbor = string.gsub(value,"%s+mesh%d+%s+",'');
            neighbor = string.gsub(neighbor,"%s+.*",'');
            --{"metric":"1.000","neighbor":"9c:b7:93:e3:56:c4","router":"9c:b7:93:e3:56:e0"}
            local metric = t_orig[neighbor];
            local new_entry = {};
            new_entry['metric']     = metric; 
            new_entry['neighbor']   = neighbor;
            new_entry['router']     = router;
            table.insert(t_nbr,new_entry);
        end        
    end
    return self.json.encode(t_nbr);
end

function rdVis:round(x,n)
    n = math.pow(10, n or 0)
    x = x * n
    if x >= 0 then x = math.floor(x + 0.5) else x = math.ceil(x - 0.5) end
    return x / n
end


