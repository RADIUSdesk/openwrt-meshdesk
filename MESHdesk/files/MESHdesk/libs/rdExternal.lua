require( "class" )

-------------------------------------------------------------------------------
-- Object to manage external programs (start and stop) ------------------------
-------------------------------------------------------------------------------
class "rdExternal"

--Init function for object
function rdExternal:rdExternal()
	self.version 	= "1.0.1"
end
        
function rdExternal:getVersion()
	return self.version
end

function rdExternal:start(program)
	os.execute(program)
end

function rdExternal:startOne(program,kill)
	print(program)
	if(kill)then
		if(self:pidof(kill))then
			os.execute("killall "..kill)
		end
	end
	os.execute(program)
end


function rdExternal:stop(program)
	if(self:pidof(program))then
		os.execute("killall "..program)
	end
end

function rdExternal:getOutput(command)
	local handle = io.popen(command)                                      
        local result = handle:read("*a")                                                 
        handle:close()  
	return result
end

function rdExternal:pidof(program)
	local handle = io.popen('pidof '.. program)                                      
        local result = handle:read("*a")                                                 
        handle:close()  
	result = string.gsub(result, "[\r\n]+$", "")                                     
	if(result ~= nil)then      
		if(tonumber(result) == nil)then --if more than one is running we simply return true
			if(string.len(result) > 1)then
				return true
			else
				return false
			end
		else                                                      
			return tonumber(result)
		end                                                  
	else      
		return false                                                             
	end 
end

--[[--
========================================================
=== Private functions start here =======================
========================================================
--]]--

