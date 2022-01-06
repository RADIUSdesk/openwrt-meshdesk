require( "class" )

-------------------------------------------------------------------------------
-- Class used to set up the batman-adv settings -------------------------------
-------------------------------------------------------------------------------
class "rdBatman"

--Init function for object
function rdBatman:rdBatman()
	require('rdLogger')
	self.version    = "1.0.1"
	self.tag	    = "MESHdesk"
	--self.debug	    = true
	self.debug	    = false
	self.json	    = require("json")
	self.logger	    = rdLogger()	
	self.l_uci    	= require("luci.model.uci");
end
        
function rdBatman:getVersion()
	return self.version
end

function rdBatman:configureFromJson(file)
	self:log("==Configure Batman-adv from JSON file "..file.."==")
	self:__configureFromJson(file)
end

function rdBatman:configureFromTable(tbl)
	self:log("==Configure Batman-adv from  Lua table==")
	self:__configureFromTable(tbl)
end


function rdBatman:log(m,p)
	if(self.debug)then
		self.logger:log(m,p)
	end
end

--[[--
========================================================
=== Private functions start here =======================
========================================================
--]]--

function rdBatman.__configureFromJson(self,json_file)

	self:log("Configuring Batman-adv from a JSON file")
	local contents 	= self:__readAll(json_file)
	local o			= self.json.decode(contents)
	if(o.config_settings.batman_adv ~= nil)then
		self:log("Found Batman-adv settings - completing it")		
		self:__configureFromTable(o.config_settings.batman_adv)
	else
		self:log("No Batman-adv settings found, please check JSON file")
	end
end

function rdBatman.__configureFromTable(self,tbl)
	for k in pairs(tbl) do
    	local val = tbl[k]
		if(val == false)then --False  does not work well here
			val = '0'
		end
		if(val == true)then --True  does not work well here
			val = '1'
		end
		self.l_uci.cursor():set('batman-adv','bat0',k, val)
  	end
  	self.l_uci.cursor():save('batman-adv');
	self.l_uci.cursor():commit('batman-adv');
end

function rdBatman.__readAll(self,file)
	local f = io.open(file,"rb")
	local content = f:read("*all")
	f:close()
	return content
end

