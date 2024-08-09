#!/usr/bin/lua
-- Include libraries
-- SPDX-FileCopyrightText: 2024 Dirk van der Walt <dirkvanderwalt@gmail.com>
--
-- SPDX-License-Identifier: GPL-3.0-or-later

package.path = "/etc/MESHdesk/libs/?.lua;../libs/?.lua;./libs/?.lua;" .. package.path
function main()
    require("rdCoa")
    local coa = rdCoa()
    coa:check()
end
main()

