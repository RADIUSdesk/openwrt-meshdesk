#!/usr/bin/lua
-- nlbw + L3 interface mapping + AP meta_data (exits) join
-- Pure Lua (no bit libs), works on OpenWrt Lua 5.1
-- Only keeps rows where IP matches an exit in meta_data.exits

local json = require("luci.jsonc")
local unpack = table and unpack or unpack


local function slurp(cmd)
  local f = io.popen(cmd); if not f then return "" end
  local s = f:read("*a") or ""; f:close(); return s
end

local function readfile(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local s = f:read("*a"); f:close(); return s
end

-- ---------- IP math (no bitops) ----------
local pow2 = {}; for i=0,32 do pow2[i] = 2^i end
local function ip_to_u32(ip)
  local a,b,c,d = ip:match("^(%d+)%.(%d+)%.(%d+)%.(%d+)$")
  if not a then return nil end
  return tonumber(a)*pow2[24] + tonumber(b)*pow2[16] + tonumber(c)*pow2[8] + tonumber(d)
end
local function subnet_key(u, prefix)
  local block = pow2[32 - prefix]
  return math.floor(u / block), block
end

-- ---------- Build L3 subnets from netifd ----------
local subnets = {}
do
  local s = slurp("ubus call network.interface dump '{}' 2>/dev/null")
  local ok, obj = pcall(json.parse, s)
  if ok and obj and obj.interface then
    for _, ifo in ipairs(obj.interface) do
      local ifname = ifo.interface
      local l3dev  = ifo.l3_device or ifo.device or ifname
      for _, a in ipairs(ifo["ipv4-address"] or {}) do
        local net_u = ip_to_u32(a.address)
        local prefix = tonumber(a.mask or 0)
        if net_u and prefix and prefix>=0 and prefix<=32 then
          local key, block = subnet_key(net_u, prefix)
          table.insert(subnets, { ifname=ifname, l3dev=l3dev, key=key, block=block, prefix=prefix })
        end
      end
    end
  end
end

local function l3_by_ip(ipstr)
  local u = ip_to_u32(ipstr)
  if not u then return nil end
  local best, bestp = nil, -1
  for _, s in ipairs(subnets) do
    local k = math.floor(u / s.block)
    if k == s.key and s.prefix > bestp then
      best, bestp = s, s.prefix
    end
  end
  return best
end

-- ---------- Read AP metadata ----------
local ap_id = nil
local exits_by_if = {}
local exits_by_dev = {}
do
  local cfg = readfile("/etc/MESHdesk/configs/current.json")
  if cfg and #cfg > 0 then
    local ok, obj = pcall(json.parse, cfg)
    if ok and obj and obj.meta_data then
      ap_id = obj.meta_data.ap_id or obj.meta_data.node_id
      for _, ex in ipairs(obj.meta_data.exits or {}) do
        if ex.interface then exits_by_if[ex.interface] = ex end
        if ex.device    then exits_by_dev[ex.device]    = ex end
      end
    end
  end
end

-- ---------- Read nlbw JSON ----------
local nlbw = slurp("nlbw -c json 2>/dev/null")
local ok, obj = pcall(json.parse, nlbw)
if not ok or type(obj) ~= "table" or type(obj.data) ~= "table" then
  io.stderr:write("Failed to read nlbw JSON\n")
  os.exit(1)
end

-- Append columns: l3if,l3dev,ap_id,ap_profile_exit_id,exit_type
obj.columns = obj.columns or {}
table.insert(obj.columns, "l3if")
table.insert(obj.columns, "l3dev")
table.insert(obj.columns, "ap_id")
table.insert(obj.columns, "ap_profile_exit_id")
table.insert(obj.columns, "exit_type")

-- Filtered data
local newdata = {}

for _, row in ipairs(obj.data) do
  local ip = row[5]
  local m = l3_by_ip(ip)

  local l3if  = m and m.ifname or json.null
  local l3dev = m and m.l3dev  or json.null

  local ex = nil
  if l3if  and l3if  ~= json.null then ex = exits_by_if[l3if]  end
  if not ex and l3dev and l3dev ~= json.null then ex = exits_by_dev[l3dev] end

  -- Only keep if matched an exit
  if ex then
    local ap_profile_exit_id = ex.ap_profile_exit_id or json.null
    local exit_type          = ex.type or json.null

    local newrow = { unpack(row) }
    table.insert(newrow, l3if)
    table.insert(newrow, l3dev)
    table.insert(newrow, ap_id or json.null)
    table.insert(newrow, ap_profile_exit_id)
    table.insert(newrow, exit_type)
    table.insert(newdata, newrow)
  end
end

obj.data = newdata

print(json.stringify(obj))

