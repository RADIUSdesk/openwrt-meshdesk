require( "class" )

-------------------------------------------------------------------------------
-- Class used read and write to Alred and to read from Alfred -----------------
-- We write JSON and read Lua tables ------------------------------------------
-------------------------------------------------------------------------------
class "rdAlfred"

--Init function for object
function rdAlfred:rdAlfred()

	require('rdLogger')
    require('rdExternal');
	local uci	    = require('uci')
    self.socket    	= require("socket")
	self.version    = "1.0.1"
	self.tag	    = "MESHdesk"
	--self.debug	    = true
	self.debug	    = false
	self.json	    = require("json")
	self.logger	    = rdLogger()
	self.x		    = uci.cursor()
    self.external   = rdExternal()
	self.bat_hosts  = '/etc/alfred/bat-hosts.lua'
    self.interface  = 'br-one' --This used to work if specified as 'br-one' (bat0.1) on BB but not on CC
    self.no_mesh_interface = 'br-lan'
end
        
function rdAlfred:getVersion()
	return self.version
end

function rdAlfred:writeData(item,nr)
	self:log("==Write Alfred data to "..nr.." ==")
	self:__writeData(item,nr)
end

function rdAlfred:readData(nr)
	self:log("==Read Alfred data from "..nr.." ==")
	return self:__readData(nr)
end

function rdAlfred:cleanUp()
   self:log("== Clean up potential stuck processes ==")
   self:__cleanUp() 
end

function rdAlfred:masterEnableAndStart()

    local interface = self.x.get('alfred','alfred','interface')
    if(interface ~= self.interface)then
        self.x.set('alfred','alfred','interface',self.interface)
    end

    local mode      = self.x.get('alfred','alfred','mode')
    if(mode ~= 'master')then
        self.x.set('alfred','alfred','mode','master')
    end

    local disabled  = self.x.get('alfred','alfred','disabled')
    if(disabled ~= '0')then
        self.x.set('alfred','alfred','disabled','0')
    end
      
	--Enable this regardless
   	self.x.set('alfred','alfred','start_vis','1')
   	--Set this regardless
   	self.x.set('alfred','alfred','batmanif','bat0')

    self.x.commit('alfred')

	--Remove the /etc/alfred/bat-hosts.lua file since installer fails
	local f=io.open(self.bat_hosts,"r")                                                   
    if f~=nil then 
		io.close(f) 
 		os.remove(self.bat_hosts)
		os.execute("/etc/init.d/alfred disable")
	end
    --start the service
    self:log("**Start up alfred master**")
    os.execute("/etc/init.d/alfred start")

end

function rdAlfred:slaveEnableAndStart()

    local interface = self.x.get('alfred','alfred','interface')
    if(interface ~= self.interface)then
        self.x.set('alfred','alfred','interface', self.interface)
    end

    local mode  = self.x.get('alfred','alfred','mode')
    --Make it master due to crashes / reboots
    
    --FIXME 20/12/17 We try a work-around - enable the slave mode again
    if(mode ~= 'slave')then
        self.x.set('alfred','alfred','mode','slave')
    end
    
    --FIXME We disable the initial workaround
    --if(mode ~= 'master')then
    --    self.x.set('alfred','alfred','mode','master')
    --end
    --FIXME END

    local disabled  = self.x.get('alfred','alfred','disabled')
    if(disabled ~= '0')then
        self.x.set('alfred','alfred','disabled','0')
    end

	--We also need to start the vis server so all can join in
    --Enable this regardless
   	self.x.set('alfred','alfred','start_vis','1')
   	--Set this regardless
   	self.x.set('alfred','alfred','batmanif','bat0')

    self.x.commit('alfred')
	--Remove the /etc/alfred/bat-hosts.lua file since installer fails
	local f=io.open(self.bat_hosts,"r")                                                   
    if f~=nil then 
		io.close(f) 
 		os.remove(self.bat_hosts)
		os.execute("/etc/init.d/alfred disable")
	end
    --start the service
    self:log("**Start up alfred slave**")
    os.execute("/etc/init.d/alfred start")
	
end

--Because we are not always running Meshes!
function rdAlfred:masterNoBatmanEnableAndStart()

    local interface = self.x.get('alfred','alfred','interface')
    if(interface ~= self.no_mesh_interface)then
        self.x.set('alfred','alfred','interface',self.no_mesh_interface)
    end

    local mode      = self.x.get('alfred','alfred','mode')
    if(mode ~= 'master')then
        self.x.set('alfred','alfred','mode','master')
    end

    local disabled  = self.x.get('alfred','alfred','disabled')
    if(disabled ~= '0')then
        self.x.set('alfred','alfred','disabled','0')
    end
      
	--Disable this regardless
   	self.x.set('alfred','alfred','start_vis','0')
   	--Set this to none since we don't use mesh
   	self.x.set('alfred','alfred','batmanif','none')

    self.x.commit('alfred')

	--Remove the /etc/alfred/bat-hosts.lua file since installer fails
	local f=io.open(self.bat_hosts,"r")                                                   
    if f~=nil then 
		io.close(f) 
 		os.remove(self.bat_hosts)
		os.execute("/etc/init.d/alfred disable")
	end
    --start the service
    self:log("**Start up alfred master NO MESH**")
    os.execute("/etc/init.d/alfred start")
end


--Because we are not always running Meshes!
function rdAlfred:slaveNoBatmanEnableAndStart()

    local interface = self.x.get('alfred','alfred','interface')
    if(interface ~= self.no_mesh_interface)then
        self.x.set('alfred','alfred','interface',self.no_mesh_interface)
    end

    local mode      = self.x.get('alfred','alfred','mode')
    if(mode ~= 'slave')then
        self.x.set('alfred','alfred','mode','slave')
    end

    local disabled  = self.x.get('alfred','alfred','disabled')
    if(disabled ~= '0')then
        self.x.set('alfred','alfred','disabled','0')
    end
      
	--Disable this regardless
   	self.x.set('alfred','alfred','start_vis','0')
   	--Set this to none since we don't use mesh
   	self.x.set('alfred','alfred','batmanif','none')

    self.x.commit('alfred')

	--Remove the /etc/alfred/bat-hosts.lua file since installer fails
	local f=io.open(self.bat_hosts,"r")                                                   
    if f~=nil then 
		io.close(f) 
 		os.remove(self.bat_hosts)
		os.execute("/etc/init.d/alfred disable")
	end
    --start the service
    self:log("**Start up alfred master NO MESH**")
    os.execute("/etc/init.d/alfred start")
end

function rdAlfred:log(m,p)
	if(self.debug)then
		self.logger:log(m,p)
	end
end

--[[--
========================================================
=== Private functions start here =======================
========================================================
--]]--
function rdAlfred.__writeData(self,item,nr)
    os.execute("echo '"..self.json.encode(item).."' | alfred -s "..nr)
end

function rdAlfred.__readData(self,nr)

    local rows  = nil;                           
    for n = 1, 3 do
    local fd = io.popen("alfred -r " .. nr)
      --[[ this command returns something like
      { "54:e6:fc:b9:cb:37", "00:11:22:33:44:55 ham_wlan0\x0a00:22:33:22:33:22 ham_eth0\x0a" },
      { "90:f6:52:bb:ec:57", "00:22:33:22:33:23 spam\x0a" },
      ]]--
        if fd then
          local output = fd:read("*a")
          fd:close()
          if output and output ~= "" then
            assert(loadstring("rows = {" .. output .. "}"))()
            break
          end
        end
    end
    return rows;
    
end

function rdAlfred.__cleanUp(self)
--We added this since there seems to be a problem where the 'alfred -r <nr>' would sometimes hang, breaking things.
    local fd = io.popen("pgrep -fl 'alfred -r *'") 
    if fd then
        local found_problem = false
        for line in fd:lines() do
            --print(line)
            --print(string.find(line, 'pgrep'))
            local process = string.gsub(line, "%s+.+", "")
            --print(process)
            if(string.find(line, 'pgrep')== nil)then
                os.execute('kill '..process)
                found_problem = true
            end
        end
        if(found_problem)then
            os.execute('/etc/init.d/alfred restart')
        end
    end
end


function rdAlfred.__sleep(self,sec)                                                                     
    self.socket.select(nil, nil, sec)                              
end 
