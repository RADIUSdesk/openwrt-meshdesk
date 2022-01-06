require( "class" )

-------------------------------------------------------------------------------
-- Morse class used to flicker a morse code on a specified LED ----------------
-------------------------------------------------------------------------------
class "rdMorse"

--Init function for object
function rdMorse:rdMorse()
	local uci 	= require("uci")
	local s		= require("socket")
	self.version 	= "1.0.1"
	self.x		= uci.cursor()
	
	self.socket	= s
	
	self.led	= "/sys/class/leds/gpio4/brightness" --Set a default value this will be changed during initialisation
	self.debug	= false
	--self.debug	= true
	
	self.short	= 0.3 		--1unit
	self.long	= self.short*3	--3units
--	self.pause	= self.short    --7 units but we subtract one short to only have 6 since our loop is padded with a short
	self.pause	= self.short*6  --7 units but we subtract one short to only have 6 since our loop is padded with a short
	
	--Some boards has 1 as on  others has 0. This is the default 1 for on and 0 for off
	self.on		= '1'
	self.off	= '0'
	
	
	--Alpha characters
	self.a		= ". _"
	self.b		= "_ . . ."
	self.c		= "_ . _ ."
	self.d		= "_ . ."
	self.e		= "."
	self.f		= ". . _ ."
    self.g      = "_ _ ."
    self.h      = ". . . ."
    self.i      = ". ."

	
	--SOS
	self.sos	= ". . . _ _ _ . . ."
	
	--Numerics
	self.one	= ". " 
	self.two	= ". ." 
	self.three	= ". .  ." 
	self.four	= ". . . ." 
	self.five	= ". . . . ." 
	self.six	= ". . . . . ." 
	self.seven	= ". . . . . . ." 
	self.eight	= ". . . . . . . ." 
	self.nine	= ". . . . . . . . ." 
	self.zero	= "_" 
	
	--Short ones
	self.config = ". ."
	self.lan	= ". " 
	self.rone	= ". ."
	self.rtwo	= ". . ."
	self.wbw    = "_ "

	--Fast ones
	self.fast_error	= ". "; 

	
	--Determine the LED to use--
	--This is specified in the meshdesk config file under settings hardware
	--and has to match a hardware definition in the same file
	local hardware = self.x.get('meshdesk', 'settings','hardware')
	self.x.foreach('meshdesk', 'hardware',
		function(a)
			if(a['.name'] == hardware)then
				self.led = a['morse_led']
				if(a['swap_on_off'] == '1')then
					--print("Swapping on and off")
					self:swapOnOff()
				end
			end	
		end)
	
end
        
function rdMorse:getVersion()
	return self.version
end

function rdMorse:swapOnOff()
	--on
	if(self.on == '1')then
		self.on = '0'
	else
		self.on = '1'
	end
	
	--off
	if(self.off == '1')then
		self.off = '0'
	else 
		self.off = '1'
	end
end

function rdMorse:setLed(l)
	self.led	= l
end

function rdMorse:getLed()
	return self.led
end

function rdMorse:clearLed()
        os.execute('echo ' .. self.off .. ' > ' .. self.led )
end   

function rdMorse:startFlash(item)
	self:_flash(item)
end




--[[--
========================================================
=== Private functions start here =======================
========================================================
--]]--

function rdMorse._flash(self,item)

	if(self.debug)then
		print("Trying to flash ".. item)
		print(self[item])
	end
	
	local i = self[item]
	if(i == nil)then
		print("Item "..item.." not in the list of available morse codes")
		return
	end
	
	local j = true

	--if the item starts with "fast_" we will shorten the times; 
	if(string.match(item, 'fast_'))then
		self.short = 0.1
		self.pause = 0.1
	end


	while(j)do
		for piece in string.gmatch(i, "[^%s]+") do
			if(piece == '.')then
				self:_short()
			end
			if(piece == '_')then
				self:_long()
			end
		end
		self:_sleep(self.pause)
	end	

end

function rdMorse._sleep(self,time)
	self.socket.select(nil,nil,time)
end

function rdMorse._short(self)
	os.execute('echo ' .. self.on .. ' > ' .. self.led )
	self:_sleep(self.short)
	os.execute('echo ' .. self.off ..' > ' .. self.led )
	self:_sleep(self.short)
end

function rdMorse._long(self)
	os.execute('echo ' .. self.on .. ' > ' .. self.led )
	self:_sleep(self.long)
	os.execute('echo ' .. self.off .. ' > ' .. self.led )
	self:_sleep(self.short)
end
