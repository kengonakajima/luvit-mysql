local net = require("net")
local constants = require("./constants")
local Parser = require("./parser")
local Auth = require("./auth")

local mysql = {}



Query={}
function Query.new()
  local query = {}
  return query
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

  client.host = "127.0.0.1"
  client.port = 3306
  client.user = "root"
  client.password = nil
  client.database = ""

  local flags = {
    constants.CLIENT_LONG_PASSWORD,
    constants.CLIENT_FOUND_ROWS,
    constants.CLIENT_LONG_FLAG,
    constants.CLIENT_CONNECT_WITH_DB,
    constants.CLIENT_ODBC,
    constants.CLIENT_LOCAL_FILES,
    constants.CLIENT_IGNORE_SPACE,
    constants.CLIENT_PROTOCOL_41,
    constants.CLIENT_INTERACTIVE,
    constants.CLIENT_IGNORE_SIGPIPE,
    constants.CLIENT_TRANSACTIONS,
    constants.CLIENT_RESERVED,
    constants.CLIENT_SECURE_CONNECTION,
    constants.CLIENT_MULTI_STATEMENTS,
    constants.CLIENT_MULTI_RESULTS
  }
  client.flags = 0
  for k,v in pairs(flags) do
    client.flags = client.flags + v
  end
  print("default flag:", client.flags )
  
--  this.typeCast = true;
--  this.flags = Client.defaultFlags;
  
  client.maxPacketSize = 0x01000000
  client.charsetNumber = constants.UTF8_UNICODE_CI
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
  
  client.parser = Parser.new()
  client.parser:on("packet", function(packet)
      print("client: incoming packet. type:", packet.type )

      if packet.type == Parser.GREETING_PACKET then
        print("greeting packet. sending auth..")
        client:sendAuth(packet)
      end
      

    end )

  
  function client:query(sql,cb)
    print("TODO: get query as a table and format it" )
    if type(q)=="table" then
      error("not implemented")
    end

    local q = Query.new(sql)
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
        packet.writeNumber( 1, constants.COM_QUERY )
        packet.write(sql, 'utf-8' )
        self:write(packet)        
      end)
  end
  
  function client:write( packet )
    print( "client: write: packet buffer len:", #packet.buffer )
    local wlen = self.socket:write( packet.buffer )
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
        packet.writeNumber(1, constants.COM_PING )
        self:write(packet)
      end, cb )        
  end

  function client:enqueue(f,delegate)
    table.insert( self.queue, { fn=f, delegate=delegate } )
  end  
  
  return client
end

return mysql

