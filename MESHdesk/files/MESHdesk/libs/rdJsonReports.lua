require("class")

-------------------------------------------------------------------------------
-- A class to collect and store device stats inside a JSON File ---------------
-------------------------------------------------------------------------------
class 'rdJsonReports';

--Init function for object
function rdJsonReports:rdJsonReports()

	require('rdLogger');
	require('rdNetstats');
	
	self.version 	= 'FEB_2021_a';
	self.tag	    = 'MESHdesk';
	self.debug	    = true;
	--self.debug	    = false;
	self.json	    = require('luci.json');
	self.uci    	= require('uci');
	self.x          = self.uci.cursor();
	self.logger		= rdLogger();
	self.netstats	= rdNetstats();
    self.jsonCreated= false;
    self.max_rows   = 5000;
    
    --These are object wide so we can manipulate and lookup
    self.lRadioNr   = 0;
    self.lIfNr      = 0;
    self.lStaNr     = 0;
    
    self.reportDir  = '/tmp/reports/';
    self.jRadios    = self.reportDir..'jRadios.json';
    self.jIfs       = self.reportDir..'jIfs.json';
    self.jStations  = self.reportDir..'jStations.json';
    
    self.nfs        = require('nixio.fs');
    self.util       = require('luci.util');
    self.sys        = require('luci.sys');
   
    self.new_file   = self.x.get('meshdesk', 'settings','config_file');
    self.old_file   = self.x.get('meshdesk', 'settings','previous_config_file');
    
end
        
function rdJsonReports:getVersion()
	return self.version
end

function rdJsonReports:initJson(hard)
    hard = hard or false;
	self:_initJson(hard);
end

function rdJsonReports:runCollect()
    self:_clearIfNeeded();
	self:_doWifi();
end

function rdJsonReports:runReport()
    return self:_getWifiReport();
end

function rdJsonReports:purgeJson()
    self:_purgeJson();
    return true;
end

function rdJsonReports:log(m,p)
	if(self.debug)then
		self.logger:log(m,p)
	end
end

--[[--
========================================================
=== Private functions start here =======================
========================================================
(Note they are in the pattern function <rdName>._function_name(self, arg...) and called self:_function_name(arg...) )
--]]--

function rdJsonReports._clearIfNeeded(self)
    local stations = self.json.decode(self.nfs.readfile(self.jStations)); 
    if(#stations > self.max_rows)then
        self:_purgeJson();
    end
end

function rdJsonReports._purgeJson(self,hard)
    local clean         = {};
    local clean_json    = self.json.encode(clean);
    self.nfs.writefile(self.jStations,clean_json);
end

function rdJsonReports._initJson(self,hard)

    hard = hard or false;
    --The hard flag will clear the JSON files if they don't exist (Typically run during statup) #FIXME DO WE NEED THE HARD FLAG?
    if(hard)then  
        self.nfs.mkdir(self.reportDir);  
        local clean         = {};
        local clean_json    = self.json.encode(clean);
        self.nfs.writefile(self.jRadios,clean_json);
        self.nfs.writefile(self.jIfs,clean_json);
        self.nfs.writefile(self.jStations,clean_json);
    end    
    self.jsonCreated = true;  
end


function rdJsonReports._getWifiReport(self)

    local w 	= {}
	w['radios']	= {};
	
	local radios = self.json.decode(self.nfs.readfile(self.jRadios));
    for a, radio in ipairs(radios) do   
	 
        local phy           = radio.RadioNumber;
        local radio_id      = radio.RadioId;
        w['radios'][phy]    = {};
        w['radios'][phy]['interfaces']	= {}
              
        --Search for Interfaces for this radio
        local ifs = self.json.decode(self.nfs.readfile(self.jIfs));
        for b, interface in ipairs(ifs) do
            if(radio_id  == interface.RadioId)then
                local stations 	= self:_getStations(interface.InterfaceId);
                if(stations)then   
                    local frequency_band = 'two';
                    if((tonumber(interface.channel) >= 14)and(tonumber(interface.channel) <= 140))then
                        frequency_band = 'five_lower';
                    end
                    if(tonumber(interface.channel) > 140)then
                        frequency_band = 'five_upper';
                    end
                
                    table.insert(w['radios'][phy]['interfaces'],{ 
		                name            = interface.name,
		                mac             = interface.mac, 
		                ssid            = interface.ssid, 
		                channel         = interface.channel,
		                txpower         = self:_round(tonumber(interface.txpower)),
		                type            = interface.type,
		                node_id         = interface.node_id,
		                mesh_entry_id   = interface.mesh_entry_id,
		                mode            = interface.mode,
		                frequency_band  = frequency_band,
		                stations        = stations
	                });
	            end
	        end
        end       
    end
    --print(self.json.encode(w));
    return self.json.encode(w);
end

function rdJsonReports._getStations(self,interface_id)

    local stations  = {};
    local temp_s    = {};
    local empty     = true;
    
    local s = self.json.decode(self.nfs.readfile(self.jStations));
    
    for a, row_s in ipairs(s) do        
        if(row_s.InterfaceId == interface_id)then
            empty = false;
            local mac = row_s.mac;
            if(temp_s[mac] == null)then --No Entry yet Add IT
                temp_s[mac] = { 
	                mac                 = row_s.mac,
	                
	                first_rx_bytes      = row_s.rx_bytes, 
	                first_rx_packets    = row_s.rx_packets,
	                first_tx_bytes      = row_s.tx_bytes,
	                first_tx_packets    = row_s.tx_packets,
	                first_timestamp     = row_s.unix_timestamp,
	                
	                rx_bytes            = 0, 
	                rx_packets          = 0,
	                tx_bytes            = 0,
	                tx_packets          = 0,
	                
	                total_rx_bytes      = 0,
	                total_rx_packets    = 0,
	                total_tx_bytes      = 0,
	                total_tx_packets    = 0,
	                
	                tx_retries          = row_s.tx_retries,
	                tx_failed           = row_s.tx_failed, 
	                signal_now          = row_s.signal,     
	                signal_avg          = row_s.avg,
	                tx_bitrate          = row_s.tx_bitrate,
	                rx_bitrate          = row_s.rx_bitrate,   
	                authorized          = row_s.authorized, 
	                authenticated       = row_s.authenticated,     
	                preamble            = row_s.preamble,
	                wmm_wme             = row_s.wmm_wme,
	                mpf                 = row_s.mpf,
	                tdls_peer           = row_s.tdls_peer,
	                unix_timestamp      = row_s.unix_timestamp,
	                connected_time      = row_s.connected_time
                }
            else
                --We got some entry now we have to be cautious
                local connected_delta   = tonumber(row_s.connected_time) - tonumber(temp_s[mac]['connected_time']);
                local unix_delta        = tonumber(row_s.unix_timestamp) - tonumber(temp_s[mac]['unix_timestamp']); 
                local unix_plus_one     = unix_delta +1;
                local unix_min_one      = unix_delta -1;
                
                --(connected_delta ==0) is to catch the iwinfo assolist items since it does not give value for connected_time so we make it 0
                 
                if(((unix_delta == connected_delta)or(unix_plus_one == connected_delta)or(unix_min_one == connected_delta)or(connected_delta ==0))and
                    ((row_s.tx_bytes >= temp_s[mac]['tx_bytes'])or(row_s.rx_bytes >= temp_s[mac]['rx_bytes']))
                )then --Add a bit of a tolerance
                    --Also to double check the values will always be higher thant the prevoius ones on one session
                    print("Same Session... Use the latest values... average the rest"); 
                    
                    temp_s[mac]['rx_bytes']         = row_s.rx_bytes - temp_s[mac]['first_rx_bytes'];
	                temp_s[mac]['rx_packets']       = row_s.rx_packets - temp_s[mac]['first_rx_packets'];   
	                temp_s[mac]['tx_bytes']         = row_s.tx_bytes - temp_s[mac]['first_tx_bytes'];
	                temp_s[mac]['tx_packets']       = row_s.tx_packets - temp_s[mac]['first_tx_packets'];

                    temp_s[mac]['signal_now']       = self:_round((tonumber(temp_s[mac]['signal_now'])+tonumber(row_s.signal))/2);
	                temp_s[mac]['signal_avg']       = self:_round((tonumber(temp_s[mac]['signal_avg'])+tonumber(row_s.avg))/2);  
                    temp_s[mac]['tx_bitrate']       = self:_round((tonumber(temp_s[mac]['tx_bitrate'])+tonumber(row_s.tx_bitrate))/2);
	                temp_s[mac]['rx_bitrate']       = self:_round((tonumber(temp_s[mac]['rx_bitrate'])+tonumber(row_s.rx_bitrate))/2); 
	                
	                --print("TX BITRATE "..temp_s[mac]['tx_bitrate']);  
                    --print("RX BITRATE "..temp_s[mac]['rx_bitrate']); 
                else
                    print("New Session... Add to current value ... new values for subsequent average calcs");
                    
                    --On the final processing we'll add the lot (total_rx_bytes and rx_bytes) to catch all
                    temp_s[mac]['total_rx_bytes']   = temp_s[mac]['total_rx_bytes'] + temp_s[mac]['rx_bytes'];
	                temp_s[mac]['total_rx_packets'] = temp_s[mac]['total_rx_packets'] + temp_s[mac]['rx_packets'];   
	                temp_s[mac]['total_tx_bytes']   = temp_s[mac]['total_tx_bytes'] + temp_s[mac]['tx_bytes'];
	                temp_s[mac]['total_tx_packets'] = temp_s[mac]['total_tx_packets']+ temp_s[mac]['tx_packets'];
                    
                    --Re-init the start bytes         
                    temp_s[mac]['first_rx_bytes']   = row_s.rx_bytes;
	                temp_s[mac]['first_rx_packets'] = row_s.rx_packets;   
	                temp_s[mac]['first_tx_bytes']   = row_s.tx_bytes;
	                temp_s[mac]['first_tx_packets'] = row_s.tx_packets; 
	                
	                 --Re-init the start bytes         
                    temp_s[mac]['rx_bytes']         = 0;
	                temp_s[mac]['rx_packets']       = 0;   
	                temp_s[mac]['tx_bytes']         = 0;
	                temp_s[mac]['tx_packets']       = 0;    
                    
                    
                    temp_s[mac]['signal_now']       = row_s.signal;
	                temp_s[mac]['signal_avg']       = row_s.avg;  
                    temp_s[mac]['tx_bitrate']       = row_s.tx_bitrate;
	                temp_s[mac]['rx_bitrate']       = row_s.rx_bitrate;   
                end 
                    --Use the latest values
                    temp_s[mac]['tx_retries']       = row_s.tx_retries;
	                temp_s[mac]['tx_failed']        = row_s.tx_failed;     
                    temp_s[mac]['connected_time']   = row_s.connected_time;
                    temp_s[mac]['unix_timestamp']   = row_s.unix_timestamp;    
            end
        
            --[[table.insert(stations,{ 
	            mac             = row_s.mac,
	            inactive_time   = row_s.inactive_time, 
	            rx_bytes        = row_s.rx_bytes, 
	            rx_packets      = row_s.rx_packets,
	            tx_bytes        = row_s.tx_bytes,
	            tx_packets      = row_s.tx_packets,
	            tx_retries      = row_s.tx_retries,
	            tx_failed       = row_s.tx_failed, 
	            rx_signal       = row_s.signal,     
	            avg             = row_s.avg,
	            tx_bitrate      = row_s.tx_bitrate,
	            rx_bitrate      = row_s.rx_bitrate,   
	            authorized      = row_s.authorized, 
	            authenticated   = row_s.authenticated,     
	            preamble        = row_s.preamble,
	            wmm_wme         = row_s.wmm_wme,
	            mpf             = row_s.mpf,
	            tdls_peer       = row_s.tdls_peer,
	            connected_time  = row_s.connected_time,
	            unix_timestamp  = row_s.unix_timestamp,
            });--]]
        end
    end   
    --return stations;
    if(empty)then
        return nil;
    else    
        for ks, vs in pairs(temp_s) do
            --Do the final adding and remove the values used to help count  
            vs.tx_bytes     = vs.tx_bytes + vs.total_tx_bytes;
            vs.rx_bytes     = vs.rx_bytes + vs.total_rx_bytes;
            vs.tx_packets   = vs.tx_packets + vs.total_tx_packets;
            vs.rx_packets   = vs.rx_packets + vs.total_rx_packets;
            vs.total_tx_bytes,vs.total_rx_bytes,vs.total_tx_packets,vs.total_rx_packets = nil;
            vs.first_tx_bytes,vs.first_rx_bytes,vs.first_tx_packets,vs.first_rx_packets = nil; 
            stations[ks] = vs
    
        end    
        return stations;      
    end
end

function rdJsonReports._numberOnly(self,item)
    item = item:gsub("^%a*%s+",""); --Add this to remove things like 'beacon -26 dBm'
    item = item:gsub("%s+(.-)%s*$","");
    return tonumber(item);
end

function rdJsonReports._signalOnly(self,item)
    item = item:gsub("^%a*%s+",""); --Add this to remove things like 'beacon -26 dBm'
    item = item:gsub("%s+(.-)%s*$","");
    return tonumber(item);
end

function rdJsonReports._bool(self,item)
    if(item == 'yes')then
        return 1;
    end
    return 0; --Default false
end

function rdJsonReports._round(self,x)
  return x>=0 and math.floor(x+0.5) or math.ceil(x-0.5)
end

function rdJsonReports._doWifi(self)

    local n_stats           = self.netstats:getWifiUbus();
    --print(n_stats);
    local radio_structure   = self.json.decode(n_stats);
    
    
    for kr, vr in pairs(radio_structure['radios']) do
        --print("RADIO NUMBER "..kr)
        if (self:_getRadioId(kr) == nil)then
            self:_addRadio(kr)
        end 
      
        for ki,vi in pairs(vr['interfaces'])do
            --Each Interface
            local i_tbl = {};
            for kid, vid in pairs(vi) do
                if(kid ~= 'stations')then
                    i_tbl[kid] = vid;
                end
            end
            --Now add the interface
            --We need the ID of the RADIO ... not the RADIO Number
            local radio_id = self:_getRadioId(kr);

            local ssid = i_tbl['ssid']
            if(ssid == nil)then
                ssid = '';
            end
            
            if(self:_getInterfaceId(i_tbl['name']) == nil)then
            
                local mesh_entry_id = -1;
                local node_id       = -1;
                local if_name       = i_tbl['name'];
                local mode          = 'mesh'; --Default value;
                                   
                --Get the node_id and interface id from the meta_data
                if(self:_file_exists(self.new_file))then
                    local contents        = self.nfs.readfile(self.new_file);        
	                local o               = self.json.decode(contents); 
                    if(o.success == true)then
                        if(o.meta_data)then
                            node_id         = o.meta_data.node_id;
                            mode            = o.meta_data.mode;
                            if(o.meta_data[if_name])then
                                mesh_entry_id   = o.meta_data[if_name];
                            end   
                        end
                    end
                else
                    if(self:_file_exists(self.old_file))then
                        local contents        = self.nfs.readfile(self.old_file);        
	                    local o               = self.json.decode(contents)  
                        if(o.success == true)then
                            if(o.meta_data)then
                                node_id = o.meta_data.node_id;
                                mode    = o.meta_data.mode;
                                if(o.meta_data[if_name])then
                                    mesh_entry_id   = o.meta_data[if_name];
                                end   
                            end
                        end
                    end
                end
                
                local interface = {
                    mac       = i_tbl['mac'],
                    type      = i_tbl['type'],
                    txpower   = i_tbl['txpower'],
                    name      = i_tbl['name'],
                    channel   = i_tbl['channel'],
                    ssid      = ssid,
                    mesh_entry_id = mesh_entry_id,
                    node_id   = node_id,
                    mode      = mode,
                    RadioId   = radio_id
                };
                self:_addInterface(interface);
            
            end
            
            local interface_id = self:_getInterfaceId(i_tbl['name']);
            --print("The Interface ID for "..i_tbl['name'].." is "..interface_id);    
            for ks,vs in pairs(vr['interfaces'][ki]['stations'])do
                local s_tbl = {}; --Each station
                for ksd, vsd in pairs(vs) do --Populate the table
                    s_tbl[ksd] = vsd;
                end
                --Add The Interface ID
                s_tbl['InterfaceId'] = interface_id;
                --Sent it off to be added to the Stations table
                self:_addStationDetail(s_tbl);
            end
        end
    end
end

function rdJsonReports._addStationDetail(self,s_tbl)
    local ts    = os.time();
           
    --self.util.dumptable(s_tbl);
    --print(s_tbl['connected time']);
    --print(s_tbl['inactive time']);
    
    local i_inactive_time   = s_tbl['inactive time'];
    if (type(i_inactive_time) == "string") then
        i_inactive_time  = self:_numberOnly(s_tbl['inactive time']);
    end
    
    local i_connected_time   = s_tbl['connected time'];
    if (type(i_inactive_time) == "string") then
        i_connected_time  = self:_numberOnly(s_tbl['connected time']);
    end
    
    local signal   = s_tbl['signal'];
    if (type(signal) == "string") then
        signal      = self:_signalOnly(s_tbl['signal']);
    end
           
    local avg   = signal;
    if(s_tbl['signal avg'])then
        avg     = s_tbl['signal avg'];
        if (type(avg) == "string") then
            avg  = self:_signalOnly(s_tbl['signal avg']);
        end
    end

    local tx_bitrate        = s_tbl['tx bitrate'];
    if (type(tx_bitrate) == "string") then
        tx_bitrate  = self:_numberOnly(s_tbl['tx bitrate']);
    end
    
    local rx_bitrate        = s_tbl['rx bitrate'];
    if (type(tx_bitrate) == "string") then
        rx_bitrate  = self:_numberOnly(s_tbl['rx bitrate']);
    end
        
    local authorized        = self:_bool(s_tbl['authorized']);
    local authenticated     = self:_bool(s_tbl['authenticated']);
    local wmm_wme           = self:_bool(s_tbl['WMM/WME']);
    local mpf               = self:_bool(s_tbl['MFP']);
    local tdls_peer         = self:_bool(s_tbl['TDLS peer']);
    
    self.lStaNr = self.lStaNr +1;
    
    local station = {
        StationId       =  self.lStaNr,
        mac             = s_tbl['mac'],
        inactive_time   = i_inactive_time,
        rx_bytes        = tonumber(s_tbl['rx bytes']),
        rx_packets      = tonumber(s_tbl['rx packets']),
        tx_bytes        = tonumber(s_tbl['tx bytes']),
        tx_packets      = tonumber(s_tbl['tx packets']),
        tx_retries      = tonumber(s_tbl['tx retries']),
        tx_failed       = tonumber(s_tbl['tx failed']),
        signal          = signal,
        avg             = avg,
        tx_bitrate      = tx_bitrate,
        rx_bitrate      = rx_bitrate,
        authorized      = authorized,
        authenticated   = authorized,
        preamble        = s_tbl['preamble'],
        wmm_wme         = wmm_wme,
        mpf             = mpf,
        tdls_peer       = tdls_peer,
        connected_time  = i_connected_time,
        unix_timestamp  = ts,
        InterfaceId     = s_tbl['InterfaceId']
    };
      
    local stations = self.json.decode(self.nfs.readfile(self.jStations));
    table.insert(stations,station)
    self.nfs.writefile(self.jStations,self.json.encode(stations));
end

--==== RADIOS ====
function rdJsonReports._getRadioId(self,radio_number)
    local radio_id = nil;
    local radios = self.json.decode(self.nfs.readfile(self.jRadios));
    for a, k in ipairs(radios) do   
        if(k['RadioNumber'] == radio_number)then      
            radio_id = k['RadioId'];
        end
        self.lRadioNr = a; --Update to have the latest last number   
    end
    return radio_id;  
end

function rdJsonReports._addRadio(self,radio_number)
    local radios = self.json.decode(self.nfs.readfile(self.jRadios));
    self.lRadioNr = self.lRadioNr +1;
    table.insert(radios,{ RadioId = self.lRadioNr, RadioNumber = radio_number})
    self.nfs.writefile(self.jRadios,self.json.encode(radios));
end

--==== INERFACES ====
function rdJsonReports._getInterfaceId(self,interface_name)
    local interface_id = nil;
    local ifs = self.json.decode(self.nfs.readfile(self.jIfs));
    for a, k in ipairs(ifs) do   
        if(k['name'] == interface_name)then      
            interface_id = k['InterfaceId'];
        end
        self.lIfNr = a; --Update to have the latest last number   
    end
    return interface_id;
end

function rdJsonReports._addInterface(self,interface)
    local interfaces = self.json.decode(self.nfs.readfile(self.jIfs));
    self.lIfNr = self.lIfNr +1;
    interface['InterfaceId'] =  self.lIfNr;
    table.insert(interfaces,interface);
    self.nfs.writefile(self.jIfs,self.json.encode(interfaces));
end

function rdJsonReports._file_exists(self,name)
    local f=io.open(name,"r")                                          
        if f~=nil then io.close(f) return true else return false end       
end

