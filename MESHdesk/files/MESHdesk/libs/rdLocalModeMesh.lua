require( "class" );

class "rdLocalModeMesh";

--Init function for object
function rdLocalModeMesh:rdLocalModeMesh()

    require('rdLogger');
    self.sys 	    = require "luci.sys";                                                                                                                                                
    self.util       = require "luci.util";    
    local uci 	    = require("uci")
    self.x	    = uci.cursor()
    self.version    = "1.0.0"
    self.tag	    = "MESHdesk"
    self.logger	    = rdLogger()
    self.debug	    = true
    self.json	    = require("json")
    self.wifi_config= '/etc/config/wireless';
    self.config_ssid= 'CONFIG #';	
end

function rdLocalModeMesh:getVersion()
	return self.version
end

function rdLocalModeMesh:log(m,p)
	if(self.debug)then
		self.logger:log(m,p)
	end
end


function rdLocalModeMesh:doTask()
	--First try to determine if it we need to offer the config option
	local config_option = true;
	if(config_option)then
		print("Do Config option thing");
		self:_doConfigMode();
	end
end


function rdLocalModeMesh._doConfigMode(self)

	print("Work Config Thing");
	--Start with a original network config
	os.execute("cp /etc/MESHdesk/configs/network_original /etc/config/network");
	--Start with a clean wifi interface setup.
	os.execute("rm "..self.wifi_config);
	--Generate a new WiFi default config file
	os.execute("wifi config >> "..self.wifi_config);

	local radio_list = {};


	--Now loop the config file activate ALL the radios
	self.x.foreach("wireless", "wifi-device", function(s) 
		table.insert(radio_list, s['.name']);
		self.x.set("wireless",s['.name'],'disabled',0);
	end);

	local ssid = self:_getSsid()

	--Now loop the config file change all interfaces's SSIDs
	self.x.foreach("wireless", "wifi-iface", function(s)
		self.x.set("wireless",s['.name'], 'ssid', ssid);
	end);
	self.x.commit('wireless');
	os.execute("wifi");

	--Also change the LAN Address to 10.1.2.3 (Easy as 1.2.3)
	print(self.x.get("network", "lan", "ipaddr"))
	self.x.set("network", "lan", "ipaddr", "10.1.2.3")
	self.x.commit("network");
	print("Network changes comitted");
	self.util.exec("/etc/init.d/network reload");
	self.util.exec("/etc/init.d/dnsmasq restart");
end

function rdLocalModeMesh._getSsid(self)
	interface = interface or "eth0"
	io.input("/sys/class/net/" .. interface .. "/address")
	t = io.read("*line")
	dashes, count = string.gsub(t, ":", "-")
	dashes = string.upper(dashes)
	return self.config_ssid..dashes
end
