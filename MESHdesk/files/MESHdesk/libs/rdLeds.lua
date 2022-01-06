local rdLeds = {}

local socket = require("socket");

--[[--
A library which can be used to flash a specified LED in certain patterns


--]]-- 

rdLeds.defaultLed = {};

local short=0.3 --1unit
local long=short*3  --3units
local pause=short*6 --7 units but we subtract one short to only have 6 since our functions are padded with a short

-- Dragino / MP2
-- local led="/sys/class/leds/dragino2\:red\:usb/brightness"

-- OM2P
-- local led="/sys/class/leds/om2p\:blue\:lan/brightness"

--Picostation
local led="/sys/class/leds/gpio4/brightness"

local function sleep(sec)
    socket.select(nil, nil, sec)
end

local function sw_short()
	os.execute('echo 1 > ' .. led ) 
	sleep(short)
	os.execute('echo 0 > ' .. led ) 
	sleep(short)
end

local function sw_long()

	os.execute('echo 1 > ' .. led ) 
	sleep(long)
	os.execute('echo 0 > ' .. led )
	sleep(short)
end

local function sos()
	local i=true
	while(i)do
		sw_short()
		sw_short()
		sw_short()
		sw_long()
		sw_long()
		sw_long()
		sw_short()
		sw_short()
		sw_short()
		sleep(pause)
	end
end

local function a()
	local i=true
	while(i)do
		sw_short()
		sw_long()
		sleep(pause)	
	end
end

local function b()
	local i=true
	while(i)do
		sw_long()
		sw_short()
		sw_short()
		sw_short()
		sleep(pause)	
	end
end

local function c()
	local i=true
	while(i)do
		sw_long()
		sw_short()
		sw_long()
		sw_short()
		sleep(pause)	
	end
end

local function d()
	local i=true
	while(i)do
		sw_long()
		sw_short()
		sw_short()
		sleep(pause)	
	end
end

local function e()
	local i=true
	while(i)do
		sw_short()
		sleep(pause)	
	end
end

local function f()
	local i=true
	while(i)do
		sw_short()
		sw_short()
		sw_long()
		sw_short()
		sleep(pause)	
	end
end

-- Some Digits to indicate the Digits --

local function one()
	local i=true
	while(i)do
		sw_short()
		sw_long()
		sw_long()
		sw_long()
		sw_long()
		sleep(pause)	
	end
end

local function two()
	local i=true
	while(i)do
		sw_short()
		sw_short()
		sw_long()
		sw_long()
		sw_long()
		sleep(pause)	
	end
end

local function three()
	local i=true
	while(i)do
		sw_short()
		sw_short()
		sw_short()
		sw_long()
		sw_long()
		sleep(pause)	
	end
end


local function four()
	local i=true
	while(i)do
		sw_short()
		sw_short()
		sw_short()
		sw_short()
		sw_long()
		sleep(pause)	
	end
end


local function five()
	local i=true
	while(i)do
		sw_short()
		sw_short()
		sw_short()
		sw_short()
		sw_short()
		sleep(pause)	
	end
end

local function six()
	local i=true
	while(i)do
		sw_long()
		sw_short()
		sw_short()
		sw_short()
		sw_short()
		sleep(pause)	
	end
end

local function seven()
	local i=true
	while(i)do
		sw_long()
		sw_long()
		sw_short()
		sw_short()
		sw_short()
		sleep(pause)	
	end
end

local function eight()
	local i=true
	while(i)do
		sw_long()
		sw_long()
		sw_long()
		sw_short()
		sw_short()
		sleep(pause)	
	end
end

local function nine()
	local i=true
	while(i)do
		sw_long()
		sw_long()
		sw_long()
		sw_long()
		sw_short()
		sleep(pause)	
	end
end

local function zero()
	local i=true
	while(i)do
		sw_long()
		sleep(pause)	
	end
end


function rdLeds.clearLed()
	os.execute('echo 0 > ' .. led )
--	os.execute("killall led.lua")
end

function rdLeds.flash(what)
	if(what == 'a')then
		a()
	end
	
	if(what == 'b')then
		b()
	end
	
	if(what == 'c')then
		c()
	end
	
	if(what == 'd')then
		d()
	end
	
	if(what == 'e')then
		e()
	end
	
	if(what == 'f')then
		f()
	end
	
	if(what == '1')then
		one()
	end
	
	if(what == '2')then
		two()
	end
	
	if(what == '3')then
		three()
	end
	
	if(what == '4')then
		four()
	end
	
	if(what == '5')then
		five()
	end
	
	if(what == '6')then
		six()
	end
	
	if(what == '7')then
		seven()
	end
	
	if(what == '8')then
		eight()
	end
	
	if(what == '9')then
		nine()
	end
	
	if(what == '0')then
		zero()
	end
	
	
	if(what == 'sos')then
		sos()
	end
end

return rdLeds
