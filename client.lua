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
local Query = require("./query")
local OutgoingPacket = require( "./outgoing_packet")


Client={}
function Client:new(conf)
  local client = {}

  -- defaults
  client.host = "127.0.0.1"
  client.port = 3306
  client.user = "root"
  client.password = nil
  client.database = ""
  client.logging = false

  if conf.password then client.password = conf.password end
  if conf.user then client.user = conf.user end
  if conf.database then client.database = conf.database end
  if conf.port then client.port = conf.port end
  if conf.host then client.host = conf.host end
  if conf.logfunc then client.logfunc = conf.logfunc else client.logfunc = function()end end

  client.log = client.logfunc

  
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
  
  client.typeCast = true
  
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
      client:log("mysql:connected")
    end)

  function client:connectionErrorHandler()
    return function(err)
      local task = self.queue[1]
      local delegate = nil
      if task.delegate then delegate = task.delegate end

      if type(delegate)=="table" and delegate.handlePacket then
        delegate:emit("error",err)
        return
      end

      if not delegate then
        self:emit("error",err)
      else
        delegate(err)
        table.remove( self.queue, 1 )
      end
    end
  end

  
  client.socket:on("error", function(err)
      local f = client:connectionErrorHandler()
      f(err)
    end ) 
  client.socket:on("data", function(data)
      client.parser:receive(data)
    end ) 
  client.socket:on("end", function()
      local f = client:connectionErrorHandler()
      f("socket closed")
    end )
  
  client.parser = Parser:new({logfunc=client.logfunc})
  client.parser:on("packet", function(packet)
      client:handlePacket(packet)
    end)


    
  function client:handlePacket(packet)
    self.log("client.handlePacket called.  packet type:", packet.type )

    if packet.type == Constants.GREETING_PACKET then -- 0
      self.log("client:handlePacket: greeting packet. sending auth..")
      self:sendAuth(packet)
      return
    end

    if not self.connected then
      self.log("client:handlePacket: NOT CONNECTED YET. packet.type:", packet.type )
      if packet.type ~= Constants.ERROR_PACKET then
        self.connected = true
        if #self.queue > 0 then
          self.queue[1].fn()
        end
        return
      end
      local fn = self:connectionErrorHandler()
      fn( Util.packetToUserObject(packet) )
      return
    end


    ------
    
    local task = self.queue[1]
    local delegate = nil
    if task then delegate = task.delegate end

    if type(delegate)=="table" and delegate.handlePacket then -- for Query
      delegate:handlePacket(packet)
      return
    end    
    
    if packet.type ~= Constants.ERROR_PACKET then
      self.connected = true
      if delegate then
        delegate(nil, Util.packetToUserObject(packet))
      end
    else
      local userpacket = Util.packetToUserObject(packet)
      if delegate then
        delegate(userpacket)
      else
        self:emit("error", userpacket )
      end
    end

    self:dequeue()
  end 

  function client:sendAuth(greetingPacket)
    local token = Auth.token( self.password, Util.byteArrayToString(greetingPacket.scrambleBuffer ) )
    local packetSize = ( 4 + 4 + 1 + 23 ) + ( #self.user + 1 ) + ( #token + 1 ) + ( #self.database + 1 )
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

  function client:enqueue(f,delegate)
    table.insert( self.queue, { fn=f, delegate=delegate } )
    if #self.queue == 1 and self.connected then
      f()
    end
  end

  
  function client:query(sql,cb)
    self.log("query:", sql )
    assert( type(sql)=="string", "not implemented")

    local q = Query:new({sql=sql, logfunc=self.log, typeCast=self.typeCast})
    if cb then
      q.fields={}
      q.rows={}
      q:on("error",function(err)
          cb(err)
          self:dequeue()
        end)
      q:on("field",function(field)
          q.fields[field.name] = field
        end)
      q:on("row",function(row)
          table.insert( q.rows, row)
        end)
      q:on("end",function(result)
          if result then
            cb(nil,result)
          else
            cb(nil, q.rows, q.fields)
          end
          self:dequeue()
        end)
    else
      q:on("error",function(err)
          error(err.message)
          self:dequeue()
        end)
      q:on("end",function(result)
          self:dequeue()
        end)
    end

    -- put a func to a que
    self:enqueue( function()
        local pktlen = 1 + #sql
        local packet = OutgoingPacket:new( pktlen )
        packet:writeNumber( 1, Constants.COM_QUERY )
        packet:write(sql, 'utf-8' )
        self:write(packet)        
      end, q)
    return q
  end
  
  function client:write( packet )
    
    local s = Util.bufferToString(packet.buffer)    
    self.log( "->", packet.buffer.length, #s, packet.buffer:inspect() )
    local wlen = self.socket:write( s, function(err)
        assert(not err)
      end)
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
    val = Util.escapeString( val )
    return "'" .. val .. "'"
  end    

  function client:ping(cb)
    self:enqueue( function()
        local packet = OutgoingPacket:new(1)
        packet:writeNumber(1, Constants.COM_PING )
        self:write(packet)
      end, cb )        
  end

  function client:dequeue()
    table.remove( self.queue, 1 )
    if #self.queue == 0 then
      return
    end
    self.queue[1].fn()
  end
  return client
end

return Client
