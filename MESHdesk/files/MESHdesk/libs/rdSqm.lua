require( "class" )

-- 25 JUL 2024 --

-------------------------------------------------------------------------------
-- Class to manage sqm items in /etc/config/sqm -------------------------------
-------------------------------------------------------------------------------

--[[

=== Section sample from /etc/config/sqm ===

config queue 'br_ex_vlan100'
	option enabled '1'
	option interface 'br-ex_vlan100'
	option download '4000'
	option upload '4000'
	option qdisc 'cake'
	option script 'piece_of_cake.qos'
	option linklayer 'none'
	option debug_logging '0'
	option verbosity '5'

--]]

class "rdSqm"

--Init function for object
function rdSqm:rdSqm()
    require('rdLogger');
	self.version 	= "1.0.1"
	self.tag	    = "MESHdesk"
	self.debug	    = false
	self.util       = require('luci.util'); --25Jul 2024 for posting command output
	self.fs         = require('nixio.fs');
	self.sqm_config = '/etc/config/sqm'
end
        
function rdSqm:getVersion()
	return self.version	
end

function rdSqm:configureFromTable(tbl)
	self:_configureFromTable(tbl)
end


function rdSqm:log(m,p)
	if(self.debug)then
		self.logger:log(m,p)
	end
end

--[[--
========================================================
=== Private functions start here =======================
========================================================
--]]--

function rdSqm:_configureFromTable(sqm_entries)
    local file_contents = ""

    for _, sqm_entry in ipairs(sqm_entries) do
        if sqm_entry.interfaces then
            for _, interface in ipairs(sqm_entry.interfaces) do
                local s_name = interface:gsub("-", "_")
                file_contents = file_contents .. string.format("config queue '%s'\n", s_name)
                file_contents = file_contents .. string.format("\toption interface '%s'\n", interface)

                for key, val in pairs(sqm_entry.detail) do
                    file_contents = file_contents .. string.format("\toption %s '%s'\n", key, tostring(val))
                end

                self:log(string.format("Create entry for %s", interface))
                file_contents = file_contents .. "\n"
            end
        end
    end

    self.util.exec("/etc/init.d/sqm stop")
    self.fs.unlink(self.sqm_config)
    self.fs.writefile(self.sqm_config, file_contents)
    self.util.exec("/etc/init.d/sqm start")
end
