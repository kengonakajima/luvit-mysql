local table = require("table")
local string = require("string")
local Buffer = require("buffer").Buffer
local Util = require("./util")

local POWS = { 1, 256, 65536, 16777216 }



Parser={}
Parser.LENGTH_CODED_NULL = 251
Parser.LENGTH_CODED_16BIT_WORD= 252
Parser.LENGTH_CODED_24BIT_WORD= 253
Parser.LENGTH_CODED_64BIT_WORD= 254

-- Parser states
Parser.STATE_PACKET_LENGTH                = 0
Parser.STATE_PACKET_NUMBER                = 1
Parser.STATE_GREETING_PROTOCOL_VERSION    = 2
Parser.STATE_GREETING_SERVER_VERSION      = 3
Parser.STATE_GREETING_THREAD_ID           = 4
Parser.STATE_GREETING_SCRAMBLE_BUFF_1     = 5
Parser.STATE_GREETING_FILLER_1            = 6
Parser.STATE_GREETING_SERVER_CAPABILITIES = 7
Parser.STATE_GREETING_SERVER_LANGUAGE     = 8
Parser.STATE_GREETING_SERVER_STATUS       = 9
Parser.STATE_GREETING_FILLER_2            = 10
Parser.STATE_GREETING_SCRAMBLE_BUFF_2     = 11
Parser.STATE_FIELD_COUNT                  = 12
Parser.STATE_ERROR_NUMBER                 = 13
Parser.STATE_ERROR_SQL_STATE_MARKER       = 14
Parser.STATE_ERROR_SQL_STATE              = 15
Parser.STATE_ERROR_MESSAGE                = 16
Parser.STATE_AFFECTED_ROWS                = 17
Parser.STATE_INSERT_ID                    = 18
Parser.STATE_SERVER_STATUS                = 19
Parser.STATE_WARNING_COUNT                = 20
Parser.STATE_MESSAGE                      = 21
Parser.STATE_EXTRA_LENGTH                 = 22
Parser.STATE_EXTRA_STRING                 = 23
Parser.STATE_FIELD_CATALOG_LENGTH         = 24
Parser.STATE_FIELD_CATALOG_STRING         = 25
Parser.STATE_FIELD_DB_LENGTH              = 26
Parser.STATE_FIELD_DB_STRING              = 27
Parser.STATE_FIELD_TABLE_LENGTH           = 28
Parser.STATE_FIELD_TABLE_STRING           = 29
Parser.STATE_FIELD_ORIGINAL_TABLE_LENGTH  = 30
Parser.STATE_FIELD_ORIGINAL_TABLE_STRING  = 31
Parser.STATE_FIELD_NAME_LENGTH            = 32
Parser.STATE_FIELD_NAME_STRING            = 33
Parser.STATE_FIELD_ORIGINAL_NAME_LENGTH   = 34
Parser.STATE_FIELD_ORIGINAL_NAME_STRING   = 35
Parser.STATE_FIELD_FILLER_1               = 36
Parser.STATE_FIELD_CHARSET_NR             = 37
Parser.STATE_FIELD_LENGTH                 = 38
Parser.STATE_FIELD_TYPE                   = 39
Parser.STATE_FIELD_FLAGS                  = 40
Parser.STATE_FIELD_DECIMALS               = 41
Parser.STATE_FIELD_FILLER_2               = 42
Parser.STATE_FIELD_DEFAULT                = 43
Parser.STATE_EOF_WARNING_COUNT            = 44
Parser.STATE_EOF_SERVER_STATUS            = 45
Parser.STATE_COLUMN_VALUE_LENGTH          = 46
Parser.STATE_COLUMN_VALUE_STRING          = 47

-- Packet types

Parser.GREETING_PACKET                  = 0
Parser.OK_PACKET                        = 1
Parser.ERROR_PACKET                     = 2
Parser.RESULT_SET_HEADER_PACKET         = 3
Parser.FIELD_PACKET                     = 4
Parser.EOF_PACKET                       = 5
Parser.ROW_DATA_PACKET                  = 6
Parser.ROW_DATA_BINARY_PACKET           = 7
Parser.OK_FOR_PREPARED_STATEMENT_PACKET = 8
Parser.PARAMETER_PACKET                 = 9
Parser.USE_OLD_PASSWORD_PROTOCOL_PACKET = 10

function Parser:new()
  local parser = {
    state = Parser.STATE_PACKET_LENGTH,
    packet = nil,
    greeted = false,
    authenticated = false,
    receivingFieldPackets = false,
    receivingRowPackets = false,
    lengthCodedLength = nil,
    lengthCodedStringLength = nil    
  }

  function parser:advance(newState)
    local prevstate = self.state
    if not newState then
      self.state = self.state + 1
    else
      self.state = newState
    end
    self.packet.index = -1
    print("advance: from ", prevstate, "to", self.state )
  end

  parser.callbacks = {}
  function parser:on(evname,cb)
    self.callbacks[evname] = cb
    print("parser: set callback:",evname, cb )
  end
  function parser:emitPacket()
    local cb = self.callbacks["packet"]
    if not cb then error("no packet callback") end
    if cb then cb(self.packet) end
  end  
  
  function parser:receive(data)
    print("parser.receive: len:", #data, data )
    Util.dumpStringBytes(data)

    for i=1,#data do
      local c = string.byte(data,i)
      if self.state > Parser.STATE_PACKET_NUMBER then
        self.packet.received = self.packet.received + 1
      end

      print( "i:",i, "c:",c, "state:", self.state, "pktindex:", (self.packet and self.packet.index) )
      if self.state == 0 then -- Parser.STATE_PACKET_LENGTH 
        if not self.packet then
          self.packet = {}
          self.packet.index = 0
          self.packet.length = 0
          self.packet.received = 0
          self.packet.number = 0
        end        

        self.packet.length = self.packet.length + POWS[self.packet.index+1] * c
        if self.packet.index == 2 then
          print("packet.length:", self.packet.length )
          self:advance()
        end
      elseif self.state == 1 then -- Parser.STATE_PACKET_NUMBER 
        self.packet.number = c
        if not self.greeted then
          self:advance( Parser.STATE_GREETING_PROTOCOL_VERSION )
        elseif self.receivingFieldPackets then
          self:advance( Parser.STATE_FIELD_CATALOG_LENGTH )
        elseif self.receivingRowPackets then
          self:advance( Parser.STATE_COLUMN_VALUE_STRING )
        else
          self:advance( Parser.STATE_FIELD_COUNT )
        end
      elseif self.state == 2 then -- Parser.STATE_GREETING_PROTOCOL_VERSION
        if c == 0xff then
          self.packet.type = Parser.ERROR_PACKET
          self:advance( Parser.STATE_ERROR_NUMBER )
        else
          self.packet.type = Parser.GREETING_PACKET
          self.packet.protocolVersion = c
          self:advance()
        end
      elseif self.state == 3 then
        if self.packet.index ==0 then
          self.packet.serverVersion = ""
        end
        if c ~= 0 then
          self.packet.serverVersion = self.packet.serverVersion .. string.char(c)
        else
          print("svVer:", self.packet.serverVersion )
          self:advance()
        end
      elseif self.state == 4 then
        if self.packet.index == 0 then
          self.packet.threadId = 0
        end
        -- 4 bytes, little endian
        self.packet.threadId = self.packet.threadId + POWS[ self.packet.index+1]*c
        if self.packet.index == 3 then
          print( "thrId:", self.packet.threadId )
          self:advance()
        end
      elseif self.state == 5 then -- GREETING_SCRAMBLE_BUFF_1
        if self.packet.index == 0 then
          self.packet.scrambleBuffer = Buffer:new(8+12)
        end
        print("set SCRAMBLE: at:", self.packet.index + 1 )        
        self.packet.scrambleBuffer[ self.packet.index+1 ] = c
        if self.packet.index == 7 then
          print("scramblebuflen:", #self.packet.scrambleBuffer )
          self:advance()
        end
      elseif self.state == 6 then -- GREETING_FILLER_1
        -- 1 byte (0x0)
        assert( c == 0x0 )
        self:advance()
      elseif self.state == 7 then -- GREETING_SERVER_CAPABILITIES
        if self.packet.index == 0 then
          self.packet.serverCapabilities = 0
        end
        -- 2 bytes, LE
        self.packet.serverCapabilities = self.packet.serverCapabilities + POWS[ self.packet.index+1]*c
        if self.packet.index == 1 then
          print("capa:", self.packet.serverCapabilities )
          self:advance()
        end
      elseif self.state == 8 then -- GREETING_SERVER_LANGUAGE
        self.packet.serverLanguage = c
        self:advance()
      elseif self.state == 9 then -- GREETING_SERVER_STATUS
        if self.packet.index == 0 then
          self.packet.serverStatus = 0
        end
        -- 2 bytes LE
        self.packet.serverStatus = self.packet.serverStatus + POWS[ self.packet.index+1 ] * c
        if self.packet.index == 1 then
          print( "status:", self.packet.serverStatus)
          self:advance()
        end
      elseif self.state == 10 then -- GREETING_FILLER_2
        -- 13 bytes 0x0
        assert( c == 0x0 )
        if self.packet.index == 12 then
          self:advance()
        end
      elseif self.state == 11 then -- GREETING_SCRAMBLE_BUFF_2
        -- 12 bytes - not 13 bytes like the protocol spec says ...(node-mysql)
        if self.packet.index < 12 then
          print("set SCRAMBLE: at:", self.packet.index + 8 + 1, c )
          self.packet.scrambleBuffer[ self.packet.index + 8 + 1 ] = c
        end
      elseif self.state == 12 then -- FIELD_COUNT
        print("field_count")
        error("xxx")
      end
      -- go to next byte!
      self.packet.index = self.packet.index + 1      
    end
    if self.state > Parser.STATE_PACKET_NUMBER and self.packet.received == self.packet.length then
      self:emitPacket()
    end
  end
  return parser
end

return Parser
