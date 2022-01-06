require( "class" );

class "rdLocalMesh";

--Init function for object
function rdLocalMesh:rdLocalMesh()

    require('rdLogger');
    local uci 	    = require("uci")
    self.x	        = uci.cursor()
    self.version    = "1.0.0"
    self.tag	    = "MESHdesk"
    self.logger	    = rdLogger()
    self.debug	    = true
end

function rdLocalMesh:getVersion()
	return self.version
end

function rdLocalMesh:log(m,p)
	if(self.debug)then
		self.logger:log(m,p)
	end
end

function rdLocalMesh:doGateway()

    local found = false;
    local mac   = rdLocalMesh:_getMac();
    local name  = "Local Gateway",
    
    self.x.foreach("local_mesh", "member", function(s) 
        if(s['mac'] == mac)then
            found = true;
        end
    end);
      
    if not found then
        local member    = self.x.add("local_mesh", "member")
		self.x.set('local_mesh',member,"human_name",name);
		self.x.set('local_mesh',member,'mac',mac);
		self.x.set('local_mesh',member,'role','gateway');
		self.x.set('local_mesh',member,'number_in_mesh',1);
		self.x.commit('local_mesh');   
    end 
    
    --Next we will use /etc/MESHdesk/configs/local_config_gateway.json 
    --Apply our unique settings to it and create /etc/MESHdesk/configs/local_config.json
    
    local mes_id    = rdLocalMesh:_getMac('eth0','_');
    local mesh_name = self.x.get('meshdesk','settings','local_network');
    local ssid      = self.x.get('meshdesk','settings','local_ssid');
    
    local f = assert(io.open('/etc/MESHdesk/configs/local_config_gateway.json', "r"))
    local t = f:read("*all")
    f:close();
    
    --Replace the mesh_id
    t = string.gsub(t, "REPL_MESH_ID", mes_id);
    --Replace the mesh name
    t = string.gsub(t, "REPL_MESH_NAME", mesh_name);
    --SSID for the mesh
    t = string.gsub(t, "REPL_MESH_SSID", ssid);
    --IP Number for this node
    t = string.gsub(t, "REPL_MESH_IP", "10.5.5.1");
    --Give the unique SSID name of Gateway
    t = string.gsub(t, "REPL_UNIQUE_SSID", "Local Gateway");
    
    local fw = assert(io.open('/etc/MESHdesk/configs/local_config.json', "w"));
    fw:write(t);
    fw:close();    
end

function rdLocalMesh._getMac(self,interface,delimiter)
	interface = interface or "eth0"
	delimiter = delimiter or '-'
	io.input("/sys/class/net/" .. interface .. "/address")
	t = io.read("*line")
	dashes, count = string.gsub(t, ":", delimiter)
	dashes = string.upper(dashes)
	return dashes
end

