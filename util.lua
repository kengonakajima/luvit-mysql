local table = require("table")
local string = require("string")
local Bit = require("bit")


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


return Util
