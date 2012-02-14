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


local Buffer = require("buffer").Buffer
local math = require("math")
local string = require("string")

OutgoingPacket={}
function OutgoingPacket:new(sz, pktNumber )
  local opkt = {}

  function opkt:writeNumber(bytes,n)
    assert(self.buffer and self.buffer.readUInt8) -- ensure luvit's Buffer
    self:writeByte(n % 256)
    if bytes == 1 then
      return
    end
    if bytes == 2 or bytes > 4 then
      error("writeNumber: 2 or >4 is not implemented" )
    end
    
    if bytes >= 3 then
      self:writeByte( math.floor( n / 256 ) % 256 )
      self:writeByte( math.floor( n / 65536 ) % 256 )
      if bytes == 3 then return end
    end
    self:writeByte( math.floor( n / 65536/256 ) % 256 )
  end
  
  --
  function opkt:writeFiller(bytes)
    for i=1,bytes do
      self:writeByte(0x0)
    end    
  end

  --
  function opkt:writeNullTerminated(bufOrString,encoding)
    self:write(bufOrString, encoding )
    self:writeByte(0x0)
  end

  --
  function opkt:writeLengthCoded(bufOrStringOrNumber, encoding )
    if not bufOrStringOrNumber then
      self:writeByte(251)
      return
    end
    if type(bufOrStringOrNumber) == "number" then
      if bufOrStringOrNumber <= 250 then
        self:writeByte(bufOrStringOrNumber)
        return
      end
      if bufOrStringOrNumber < 0xffff then
        self:writeByte(252)
        self:writeByte(bufOrStringOrNumber % 256 )
        self:writeByte( math.floor(bufOrStringOrNumber/256) % 256 )
      elseif bufOrStringOrNumber < 0xffffff then
        self:writeByte(253)
        self:writeByte(bufOrStringOrNumber % 256 )
        self:writeByte( math.floor(bufOrStringOrNumber/256) % 256 )
        self:writeByte( math.floor(bufOrStringOrNumber/256/256) % 256 )
      else
        error("8 byte length coded numbers not supported yet")
      end
      return
    end
    if type(bufOrStringOrNumber)=="string" then
      self:writeLengthCoded( #bufOrStringOrNumber )
      self:write( bufOrStringOrNumber, encoding)
      return
    end
    
    if bufOrStringOrNumber.readUInt8 then -- luvit's buffer
      self:writeLengthCoded( bufOrStringOrNumber.length )
      self:write(bufOrStringOrNumber)
      return
    end

    print("passed argument not a buffer, string or number",bufOrStringOrNumber)
    error("arg error")    
    
  end
  
  --
  function opkt:writeByte( b )  
    self.buffer[ self.index + 1 ] = b -- +1, it's lua!
    self.index = self.index + 1
  end
  
  function opkt:write(bufOrString, encoding)
    if type(bufOrString) == "string" then
      if self.index + #bufOrString > self.buffer.length then
        error("OutgoingPacket: input string too long" )
      end
      for i=1,#bufOrString do
        self:writeByte( string.byte(bufOrString,i) )
      end
      return
    end
    if bufOrString.readUInt8 then -- luvit's buffer
      for i=1,bufOrString.length do
        self:writeByte( bufOrString[i] )
      end
      return
    end

    error("OutgoingPacket:write: argument must be a buffer or a string" )
  end

  -- initialize
  opkt.buffer = Buffer:new( sz + 1 + 3 )
  opkt.index = 0
  opkt:writeNumber( 3, sz )
  opkt:writeNumber( 1, pktNumber or 0 )

  return opkt
end


return OutgoingPacket
