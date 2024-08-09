#!/usr/bin/lua

-- SPDX-FileCopyrightText: 2024 Dirk van der Walt <dirkvanderwalt@gmail.com>
--
-- SPDX-License-Identifier: GPL-3.0-or-later


-- Include libraries
package.path = "/etc/MESHdesk/libs/?.lua;" .. package.path;

require("rdCoovaChilli");
local a = rdCoovaChilli();
