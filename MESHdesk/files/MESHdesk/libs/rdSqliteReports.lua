require("class")

-------------------------------------------------------------------------------
-- A class to collect and store device stats inside a SQLite DB ---------------
-------------------------------------------------------------------------------
class 'rdSqliteReports';

--Init function for object
function rdSqliteReports:rdSqliteReports()

	require('rdLogger');
	require('rdNetstats');
	local uci 		= require("uci")
	self.version 	= "1.0.0"
	self.json		= require("json")
	self.logger		= rdLogger()
	self.netstats	= rdNetstats()
	--self.debug		= true
	self.debug		= false
	self.x			= uci.cursor()
	self.luasql     = require('luasql.sqlite3');
    self.env        = assert (self.luasql.sqlite3());
    self.con        = assert (self.env:connect("/tmp/rd_report.db"));
    self.util       = require('luci.util');   
    self.tablesCreated	= false;
    self.max_rows   = 5000;
    
    self.new_file   = self.x.get('meshdesk', 'settings','config_file');
    self.old_file   = self.x.get('meshdesk', 'settings','previous_config_file');
    
end
        
function rdSqliteReports:getVersion()
	return self.version
end

function rdSqliteReports:initDb(hard)
    hard = hard or false;
	self:_initDb(hard);
end

function rdSqliteReports:runCollect()
    self:_clearIfNeeded();
	self:_doWifi();
end

function rdSqliteReports:runReport()
    return self:_getWifiReport();
end

function rdSqliteReports:purgeTables()
    self:_purgeTables();
    return true;
end

function rdSqliteReports:log(m,p)
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

function rdSqliteReports._clearIfNeeded(self)
    local c_s       = assert (self.con:execute([[SELECT COUNT(mac) as count from Stations;]]));   
    local row_s     = c_s:fetch ({}, "a");
    if(row_s.count > self.max_rows)then
        self:_purgeTables();
    end
end

function rdSqliteReports._purgeTables(self,hard)
    local res = assert (self.con:execute[[DELETE FROM Stations;]]);
end

function rdSqliteReports._initDb(self,hard)

    hard = hard or false;

    --The hard flag will drop the tables befroe recreating them (Typically run during statup)
    --Default will just create them if they do not exist
    if(hard)then 
        print("Droping the Tables");
        -- hard reset our table
        
        res = assert (self.con:execute[[
        DROP TABLE IF EXISTS Interfaces;
        ]]);
        res = assert (self.con:execute[[
        DROP TABLE IF EXISTS Stations;
        ]]);
    end
    
    res = assert (self.con:execute[[
        CREATE TABLE IF NOT EXISTS Radios(
            RadioId       INTEGER PRIMARY KEY, 
            RadioNumber   INTEGER NOT NULL
        );
    ]]);

    res = assert (self.con:execute[[
        CREATE TABLE IF NOT EXISTS Interfaces(
          InterfaceId   INTEGER PRIMARY KEY, 
          mac           TEXT NOT NULL,
          type          TEXT NOT NULL,
          txpower       TEXT NOT NULL,
          name          TEXT NOT NULL,
          channel       TEXT NOT NULL,
          ssid          TEXT NOT NULL,
          mesh_entry_id INTEGER,
          node_id INTEGER,
          RadioId INTEGER NOT NULL,
          FOREIGN KEY(RadioId) REFERENCES Radios(RadioId)
        );
    ]]);
    
    res = assert (self.con:execute[[
        CREATE TABLE IF NOT EXISTS Stations(
          StationId     INTEGER PRIMARY KEY,
          mac           TEXT NOT NULL,
          inactive_time INTEGER,
          rx_bytes      INTEGER,
          rx_packets    INTEGER,
          tx_bytes      INTEGER,
          tx_packets    INTEGER,
          tx_retries    INTEGER, 
          tx_failed     INTEGER,
          signal        INTEGER,
          avg           INTEGER,
          tx_bitrate    INTEGER,
          rx_bitrate    INTEGER,
          authorized    INTEGER,
          authenticated INTEGER,
          preamble      TEXT NOT NULL,
          wmm_wme       INTEGER,
          mpf           INTEGER,
          tdls_peer     INTEGER,    
          connected_time INTEGER,
          unix_timestamp TEXT NOT NULL,
          InterfaceId   INTEGER NOT NULL,
          FOREIGN KEY(InterfaceId) REFERENCES Interfaces(InterfaceId)
        );
    ]]);
       
    self.tablesCreated = true;  
end


function rdSqliteReports._getWifiReport(self)

    local w 	= {}
	w['radios']	= {};
	
	local c_r       = assert (self.con:execute([[SELECT RadioId,RadioNumber from Radios;]]));   
    local row_r     = c_r:fetch ({}, "a");
    while row_r do
    
        local phy           = row_r.RadioNumber;
        local radio_id      = row_r.RadioId;
        w['radios'][phy]    = {};
        w['radios'][phy]['interfaces']	= {}
        
        --Search for Interfaces for this radio
        local c_i           = assert (self.con:execute(string.format([[SELECT * from Interfaces where RadioId='%s';]],radio_id)));
        local row_i         = c_i:fetch ({}, "a");  
        while row_i do
            local stations 	= self:_getStations(row_i.InterfaceId);
            if(stations)then
            
                local frequency_band = 'two';
                if((tonumber(row_i.channel) >= 14)and(tonumber(row_i.channel) <= 140))then
                    frequency_band = 'five_lower';
                end
                if(tonumber(row_i.channel) > 140)then
                    frequency_band = 'five_upper';
                end
            
                table.insert(w['radios'][phy]['interfaces'],{ 
		            name            = row_i.name,
		            mac             = row_i.mac, 
		            ssid            = row_i.ssid, 
		            channel         = row_i.channel,
		            txpower         = self:_round(tonumber(row_i.txpower)),
		            type            = row_i.type,
		            node_id         = row_i.node_id,
		            mesh_entry_id   = row_i.mesh_entry_id,
		            frequency_band  = frequency_band,
		            stations        = stations
	            });
	        end
            row_i        = c_i:fetch (row_i, "a")
        end
        c_i:close();   
        row_r    = c_r:fetch (row_r, "a");          
    end
    c_r:close();
    --print(self.json.encode(w));
    return self.json.encode(w);
end

function rdSqliteReports._getStations(self,interface_id)

    local c_s       = assert (self.con:execute(string.format([[SELECT * from Stations where InterfaceId='%s';]],interface_id)));
    local row_s     = c_s:fetch ({}, "a");
    local stations  = {};
    local temp_s    = {};
    local empty     = true;
    while row_s do
    
        --[[ 
         
        --]]
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
        row_s    = c_s:fetch (row_s, "a");
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

function rdSqliteReports._numberOnly(self,item)
    item = item:gsub("^%a*%s+",""); --Add this to remove things like 'beacon -26 dBm'
    item = item:gsub("%s+(.-)%s*$","");
    return tonumber(item);
end

function rdSqliteReports._signalOnly(self,item)
    item = item:gsub("^%a*%s+",""); --Add this to remove things like 'beacon -26 dBm'
    item = item:gsub("%s+(.-)%s*$","");
    return tonumber(item);
end

function rdSqliteReports._bool(self,item)
    if(item == 'yes')then
        return 1;
    end
    return 0; --Default false
end

function rdSqliteReports._round(self,x)
  return x>=0 and math.floor(x+0.5) or math.ceil(x-0.5)
end

function rdSqliteReports._doWifi(self)

    local n_stats           = self.netstats:getWifi();
    --print(n_stats);
    local radio_structure   = self.json.decode(n_stats);
    
    
    for kr, vr in pairs(radio_structure['radios']) do
        --print("RADIO NUMBER "..kr)
        if (self:_getRadioId(kr) == nil)then  
          local res = assert (self.con:execute(string.format([[
                INSERT INTO Radios (RadioNumber)
                VALUES ('%s')]],kr)
            ))
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
            
                --Get the node_id and interface id from the meta_data
                if(self:_file_exists(self.new_file))then
                    local contents        = self:_readAll(self.new_file);        
	                local o               = self.json.decode(contents); 
                    if(o.success == true)then
                        if(o.meta_data)then
                            node_id         = o.meta_data.node_id;
                            if(o.meta_data[if_name])then
                                mesh_entry_id   = o.meta_data[if_name];
                            end   
                        end
                    end
                else
                    if(self:_file_exists(self.old_file))then
                        local contents        = self:_readAll(self.old_file);        
	                    local o               = self.json.decode(contents)  
                        if(o.success == true)then
                            if(o.meta_data)then
                                node_id = o.meta_data.node_id;
                                if(o.meta_data[if_name])then
                                    mesh_entry_id   = o.meta_data[if_name];
                                end   
                            end
                        end
                    end
                end
            
                local res = assert (self.con:execute(string.format([[
                    INSERT INTO Interfaces (mac,type,txpower,name,channel,ssid,mesh_entry_id,node_id,RadioId)
                    VALUES ('%s','%s','%s','%s','%s','%s','%s','%s','%s')]],
                        i_tbl['mac'],
                        i_tbl['type'],
                        i_tbl['txpower'],
                        i_tbl['name'],
                        i_tbl['channel'],
                        ssid,
                        mesh_entry_id,
                        node_id,
                        radio_id
                    )
                ))
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

function rdSqliteReports._addStationDetail(self,s_tbl)
    local ts    = os.time();
        
    --self.util.dumptable(s_tbl);
    
    local i_inactive_time   = self:_numberOnly(s_tbl['inactive time']);
    local i_connected_time  = self:_numberOnly(s_tbl['connected time']);
    local signal            = self:_signalOnly(s_tbl['signal']);
    local avg               = signal;

    if(s_tbl['signal avg'])then
        avg       = self:_signalOnly(s_tbl['signal avg']);
    end


    local tx_bitrate        = self:_numberOnly(s_tbl['tx bitrate']);
    local rx_bitrate        = self:_numberOnly(s_tbl['rx bitrate']);
    
    local authorized        = self:_bool(s_tbl['authorized']);
    local authenticated     = self:_bool(s_tbl['authenticated']);
    local wmm_wme           = self:_bool(s_tbl['WMM/WME']);
    local mpf               = self:_bool(s_tbl['MFP']);
    local tdls_peer         = self:_bool(s_tbl['TDLS peer']);
      
    local res   = assert (self.con:execute(string.format([[
        INSERT INTO Stations (mac,inactive_time,rx_bytes,rx_packets,tx_bytes,tx_packets,tx_retries,tx_failed,
        signal,avg,tx_bitrate,rx_bitrate,authorized,authenticated,preamble,wmm_wme,mpf,tdls_peer,connected_time,unix_timestamp,InterfaceId)
        VALUES ('%s','%s','%s','%s','%s','%s','%s','%s','%s','%s','%s','%s','%s','%s','%s','%s','%s','%s','%s','%s','%s')]],
            s_tbl['mac'], --1
            i_inactive_time, --2
            tonumber(s_tbl['rx bytes']), --3
            tonumber(s_tbl['rx packets']), --4
            tonumber(s_tbl['tx bytes']), --5
            tonumber(s_tbl['tx packets']), --6
            tonumber(s_tbl['tx retries']), --7
            tonumber(s_tbl['tx failed']), --8
            signal, --9
            avg, --10
            tx_bitrate, --11
            rx_bitrate, --12
            authorized, --13
            authenticated, --14
            s_tbl['preamble'], --15
            wmm_wme, --16
            mpf, --17
            tdls_peer, --18
            i_connected_time, --19
            ts, --20
            s_tbl['InterfaceId'] --21
        )
    ))

end

function rdSqliteReports._getRadioId(self,radio_number)
    local radio_id = null;
    local c = assert (self.con:execute(string.format([[SELECT RadioId from Radios where RadioNumber='%s';]],radio_number))); 
    local first_row = c:fetch({},"a");
    if(first_row)then
        radio_id = first_row.RadioId;
    end 
    c:close();
    return radio_id;
end

function rdSqliteReports._getInterfaceId(self,interface_name)
    local interface_id = null;
    local c = assert (self.con:execute(string.format([[SELECT InterfaceId from Interfaces where name='%s';]],interface_name))); 
    local first_row = c:fetch({},"a");
    if(first_row)then
        interface_id = first_row.InterfaceId ;
    end 
    c:close();
    return interface_id;
end

function rdSqliteReports._file_exists(self,name)
    local f=io.open(name,"r")                                          
        if f~=nil then io.close(f) return true else return false end       
end

function rdSqliteReports._readAll(self,file)                     
	local f = io.open(file, "rb")      
        local content = f:read("*all")     
        f:close()                          
        return content                     
end

