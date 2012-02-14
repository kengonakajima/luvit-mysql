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
  print( "xor: out:", #out )
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
  if packet.type == Constants.ERROR_PACKET then
    out = Error:new()
  end
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
  return out
end

  
return Util
