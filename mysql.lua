local table = require("table")
local math = require("math")
local string = require("string")
local net = require("net")
local Constants = require("./constants")
local Parser = require("./parser")
local Auth = require("./auth")
local Util = require("./util")
local Buffer = require("buffer").Buffer
local mysql = {}



Query={}
function Query:new()
  local query = {}
  return query
end

-----------------------

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

----------------------------




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


function mysql.escapeString(str)
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


function mysql.createClient(conf)
  local client = {}

  -- defaults
  client.host = "127.0.0.1"
  client.port = 3306
  client.user = "root"
  client.password = nil
  client.database = ""

  if conf.password then client.password = conf.password end
  if conf.user then client.user = conf.user end
  if conf.database then client.database = conf.database end
  if conf.port then client.port = conf.port end
  if conf.host then client.host = conf.host end
  
  
  local flags = {
    Constants.CLIENT_LONG_PASSWORD,
    Constants.CLIENT_FOUND_ROWS,
    Constants.CLIENT_LONG_FLAG,
    Constants.CLIENT_CONNECT_WITH_DB,
    Constants.CLIENT_ODBC,
    Constants.CLIENT_LOCAL_FILES,
    Constants.CLIENT_IGNORE_SPACE,
    Constants.CLIENT_PROTOCOL_41,
    Constants.CLIENT_INTERACTIVE,
    Constants.CLIENT_IGNORE_SIGPIPE,
    Constants.CLIENT_TRANSACTIONS,
    Constants.CLIENT_RESERVED,
    Constants.CLIENT_SECURE_CONNECTION,
    Constants.CLIENT_MULTI_STATEMENTS,
    Constants.CLIENT_MULTI_RESULTS
  }
  client.flags = 0
  for k,v in pairs(flags) do
    client.flags = client.flags + v
  end
  print("default flag:", client.flags )
  
--  this.typeCast = true;
--  this.flags = Client.defaultFlags;
  
  client.maxPacketSize = 0x01000000
  client.charsetNumber = Constants.UTF8_UNICODE_CI
  client.debug = true
  client.ending = false
  client.connected = false

  client.greeting = nil
  client.queue = {}
  client.socket = nil
  client.parser = nil

  client.socket = net.createConnection( client.port, client.host, function(err)
      if err then
        p(err)
        return
      end
      print("connected..")
    end)

  client.socket:on("error", function() error("error") end ) --this._connectionErrorHandler())
  client.socket:on("data", function(data) client.parser:receive(data) end ) -- parser.write.bind(parser))
  client.socket:on("end", function() error("end")  end )
  
  client.parser = Parser:new()
  client.parser:on("packet", function(packet)
      print("client: incoming packet. type:", packet.type )

      if packet.type == Parser.GREETING_PACKET then
        print("greeting packet. sending auth..")
        client:sendAuth(packet)
      end
    end )

  function client:sendAuth(greetingPacket)
    print("sendAuth. packet:", greetingPacket, "scrbuflen:", greetingPacket.scrambleBuffer.length )
    local token = Auth.token( self.password, Util.byteArrayToString(greetingPacket.scrambleBuffer ) )
    local packetSize = ( 4 + 4 + 1 + 23 ) + ( #self.user + 1 ) + ( #token + 1 ) + ( #self.database + 1 )
    print("sendAuth: #token:", #token, "packetsize:", packetSize )
    local packet = OutgoingPacket:new( packetSize, greetingPacket.number + 1 )
    packet:writeNumber( 4, self.flags )
    packet:writeNumber( 4, self.maxPacketSize )
    packet:writeNumber( 1, self.charsetNumber )
    packet:writeFiller(23)
    packet:writeNullTerminated(self.user)
    packet:writeLengthCoded(token)
    packet:writeNullTerminated(self.database)
    self:write(packet)
    self.greetingPacket = greetingPacket
  end
  
  function client:query(sql,cb)
    print("TODO: get query as a table and format it" )
    if type(q)=="table" then
      error("not implemented")
    end

    local q = Query:new(sql)
    if cb then
      self.fields={}
      self.rows={}
      q:on("error",function(err)
          cb(err)
          self:dequeue()
        end)
      q:on("field",function(field)
          self.fields[field.name]=field
        end)
      q:on("row",function(row)
          table.insert( self.rows, row)
        end)
      q:on("end",function(result)
          if result then
            print("insert/delete/update: end has a result:",result)
            cb(nil,result)
          else
            print("select: end hasnt a result")
            cb(nil,self.rows,self.fields)
          end
          self:dequeue()
        end)
    else
      q:on("error",function(err)
          error("error. TODO: call error callback?")
          self:dequeue()
        end)
      q:on("end",function(result)
          print("query ended")
          self:dequeue()
        end)
    end

    -- put a func to a que
    self:enqueue( function()
        print("queued function is called. sql:", sql )
        local pktlen = 1 + Buffer.byteLength( sql, 'utf-8')
        local packet = OutgoingPacket( pktlen )
        print("packet len:", pktlen, "packet:", packet )
        packet.writeNumber( 1, Constants.COM_QUERY )
        packet.write(sql, 'utf-8' )
        self:write(packet)        
      end)
  end
  
  function client:write( packet )
    
    local s = Util.bufferToString(packet.buffer)    
    print( "client: write: packet buffer len:", packet.buffer.length, #s, packet.buffer:inspect() )
    local wlen = self.socket:write( s, function(err)
        print("write error? ",err)
      end)
    print( "wlen:", wlen)
  end

  function client:escape(val)
    if nil == val then
      return "NULL"
    end
    if type(val)=="boolean" then
      if val then return "true" else return "false" end
    end
    if type(val)=="number" then
      return tostring(val)
    end
    if type(val)=="table" then
      if type( val.toISOString ) == "function" then
        return val:toISOString()
      else
        return tostring(val)
      end
    end

    -- to escape "\0" in lua, we cannot use string.gsub.
    val = mysql.escapeString( val )
    return "'" .. val .. "'"
  end    

  function client:ping(cb)
    self:enqueue( function()
        local packet = OutgoingPacket(1)
        packet.writeNumber(1, Constants.COM_PING )
        self:write(packet)
      end, cb )        
  end

  function client:enqueue(f,delegate)
    table.insert( self.queue, { fn=f, delegate=delegate } )
  end  
  
  return client
end

return mysql

