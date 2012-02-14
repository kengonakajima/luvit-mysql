--[[

Copyright 2012 Kengo Nakajima. All Rights Reserved.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS-IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

--]]

local table = require("table")
local string = require("string")
local Bit = require("bit")
local Constants = require("./constants")

local Util = {}

function Util.byteArrayToString(t)
  local out = {}
  for i,b in ipairs(t) do
    out[i] = string.char(b)
  end
  return table.concat(out, "")  
end


-- xor 2 string
function Util.xor(a,b)
  assert(#a == #b)
  local out={}
  for i=1,#a do
    out[i] = Bit.bxor( string.byte(a,i), string.byte(b,i) )
  end
  return Util.byteArrayToString(out)
end

-- convert luvit buffer to binary string
function Util.bufferToString(b)
  local t ={}
  for i=1,b.length do
    t[i] = string.char(b[i])
  end
  return table.concat(t)  
end
function Util.dumpStringBytes(t)
  local ttt ={}
  for i=1,#t do
    table.insert( ttt, string.format( "%x", string.byte( t, i ) ) )
    if (i % 8)==0 then
      table.insert( ttt, "  " )
    end    
  end
  print( table.concat( ttt, " " ) )
end



local escapeStringRepl = {
  [0] = "\\0",
  [8] = "\\b",
  [9] = "\\t",  
  [10] = "\\n",
  [13] = "\\r",
  [26] = "\\Z",
  [34] = "\\\"",
  [39] = "\\\'",
  [92] = "\\\\"
}

function Util.escapeString(str)
  local out = {}
  for i=1,#str do
    local byte = string.byte( str, i )
    local to = escapeStringRepl[byte]
    if to then
      table.insert( out, to )
    else
      table.insert( out, string.char(byte) )
    end
  end
  return table.concat( out )  
end

function Util.packetToUserObject(packet)
  local out = {}

  for k,v in pairs(packet) do
    local newKey
    if k == "errorMessage" then
      newKey = "message"
    elseif k == "errorNumber" then
      newKey = "number"
    else
      newKey = k
    end      
    out[newKey] = v
  end
  -- always overwrite number
  if packet.errorNumber then out.number = packet.errorNumber end
  return out
end

function Util.convertStringDateToTable(s)
  local _,_,y,m,d,h,min,sec = string.find(s, "(%d+)-(%d+)-(%d+) (%d+):(%d+):(%d+)")
  return {  year = y, month = m, day = d, hour = h, minute = min, second = sec }
end
  
return Util
