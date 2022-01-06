#!/usr/bin/lua

local uci = require('uci')
local y = uci.cursor(nil,'/var/state')

function check_license()

	os.execute("sleep 12m");

	os.execute("dd if=/dev/mtd6 of=/tmp/art.bin");

	local handle = io.popen("hexdump -n 6 -C /tmp/art.bin | cut -b9- | cut -d'|' -f1 | tr -d ' \t\n\r'");
        local artmac = handle:read("*a");
        handle:close();

	--print(artmac);

	local handle2 = io.popen("hexdump -n 6 -s 40980 -C /tmp/art.bin | cut -b9- | cut -d'|' -f1 | tr -d ' \t\n\r'");
        local licensemac = handle2:read("*a");
        handle2:close();

        --print(licensemac);

	local handle3 = io.popen("hexdump -n 4 -s 41439 -C /tmp/art.bin | cut -b9- | cut -d'|' -f1 | tr -d ' \t\n\r'");
        local licensechecksum = handle3:read("*a");
        handle3:close();

        --print(licensechecksum);

	local handle4 = io.popen("hexdump -n 10 -s 41084 -C /tmp/art.bin | cut -b9- | cut -d'|' -f1 | tr -d ' \t\n\r'");
        local licenseflags = handle4:read("*a");
        handle4:close();

        --print(licenseflags);

	local handle5 = io.popen("hexdump -n 20 -s 41259 -C /tmp/art.bin | cut -b9- | cut -d'|' -f1 | tr -d ' \t\n\r'");
        local licenserandom = handle5:read("*a");
        handle5:close();

        --print(licenserandom);

	local handle6 = io.popen("hexdump -n 16 -s 41409 -C /tmp/art.bin | cut -b9- | cut -d'|' -f1 | tr -d ' \t\n\r'");
        local licensecheck = handle6:read("*a");
        handle6:close();

        --print(licensecheck);

	local comparecheck = licensemac..licensechecksum..licenseflags..licenserandom;
	--print (comparecheck);

	local handle7 = io.popen("printf '%s' "..comparecheck.." | md5sum | cut -d' ' -f1 | tr -d '\n'");
        local md5data = handle7:read("*a");
        handle7:close();

	--print(md5data);

	if(md5data==licensecheck)then
		os.execute("rm /tmp/art.bin");
                print("Valid license key.");
        else
		os.execute("rm /tmp/art.bin");
             	y.set('meshdesk','internet1','ip', '159.65.154.31');
		y.commit('meshdesk');
		os.execute("sleep 1m");
		os.execute("reboot");
        end
end

check_license()
