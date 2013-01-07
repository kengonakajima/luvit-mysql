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
local Buffer = require("buffer").Buffer
local Util = require("./util")
local Constants = require("./constants")

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


function Parser:new(conf)
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
  if conf.logfunc then parser.log = conf.logfunc end

  function parser:advance(newState)
    local prevstate = self.state
    if not newState then
      self.state = self.state + 1
    else
      self.state = newState
    end
    self.packet.index = -1
  end

  parser.callbacks = {}
  function parser:on(evname,cb)
    self.callbacks[evname] = cb
  end
  function parser:emit( evname, ... )
    local cb = self.callbacks[evname]
    cb( ... )
  end
  
  function parser:emitPacket()
    local cb = self.callbacks["packet"]
    if not cb then error("no packet callback") end
    if cb then cb(self.packet) end

    self.greeted = true
    self.packet = nil
    self.state = Parser.STATE_PACKET_LENGTH
  end  

  function parser:lengthCoded( c, val, nextState )
    if not self.lengthCodedLength then
      if c == Parser.LENGTH_CODED_16BIT_WORD then
        self.lengthCodedLength = 2
      elseif c == Parser.LENGTH_CODED_24BIT_WORD then
        self.lengthCodedLength = 3
      elseif c == Parser.LENGTH_CODED_64BIT_WORD then
        self.lengthCodedLength = 8
      elseif c == Parser.LENGTH_CODED_NULL then
        self:advance(nextState)
        return nil
      elseif c < Parser.LENGTH_CODED_NULL then
        self:advance(nextState)
        return c
      end
      return 0
    end

    if c then
      val = val + POWS[ self.packet.index-1+1] * c
    end
    if self.packet.index == self.lengthCodedLength then
      self.lengthCodedLength = nil
      self:advance( nextState )
    end
    return val      
  end
  
  function parser:receive(data)
    self.log("<- parser.receive: len:", #data )

    local i = 1
    while i <= #data do   --    for i=1,#data do          use while for modifying loop counter inside the loop..

      local toContinue = false
      
      local c = string.byte(data,i)
      if self.state > Parser.STATE_PACKET_NUMBER then
        self.packet.received = self.packet.received + 1
      end

      if self.packet then
        self.log( "state:".. self.state.. " i:" ..i.. " c:" ..c.. " recvd:".. self.packet.received.. " len:".. self.packet.length .. " index:" .. self.packet.index .. " lcl:" .. (self.lengthCodedLength or "nil") .. " lcsl:" .. (self.lengthCodedStringLength or "nil")  )
      else
        self.log( "state:".. self.state.. " i:"..i.. " c:"..c )
      end

      
      if self.state == 0 then -- Parser.STATE_PACKET_LENGTH 
        if not self.packet then
          local packet = {}
          packet.log = self.log
          packet.index = 0
          packet.length = 0
          packet.received = 0
          packet.number = 0
          packet.callbacks = {}
          function packet:on( evname, cb )
            self.callbacks[evname] = cb
          end          
          function packet:emit( evname, data, iarg )
            self.log("packet.emit: #data:", #data, "iarg:", iarg, data  )
            local cb = self.callbacks[evname]
            cb(data,iarg)
          end
          self.packet = packet
        end        

        self.packet.length = self.packet.length + POWS[self.packet.index+1] * c
        if self.packet.index == 2 then
          self:advance()
        end
      elseif self.state == 1 then -- Parser.STATE_PACKET_NUMBER 
        self.packet.number = c
        if not self.greeted then
          self:advance( Parser.STATE_GREETING_PROTOCOL_VERSION )
        elseif self.receivingFieldPackets then
          self:advance( Parser.STATE_FIELD_CATALOG_LENGTH )
        elseif self.receivingRowPackets then
          self:advance( Parser.STATE_COLUMN_VALUE_LENGTH )
        else
          self:advance( Parser.STATE_FIELD_COUNT )
        end
      elseif self.state == 2 then -- Parser.STATE_GREETING_PROTOCOL_VERSION
        if c == 0xff then
          self.log("packet type set: error packet --------------")
          self.packet.type = Constants.ERROR_PACKET
          self:advance( Parser.STATE_ERROR_NUMBER )
        else
          self.log("packet type set: greeting packet ---------------")
          self.packet.type = Constants.GREETING_PACKET
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
          self:advance()
        end
      elseif self.state == 4 then
        if self.packet.index == 0 then
          self.packet.threadId = 0
        end
        -- 4 bytes, little endian
        self.packet.threadId = self.packet.threadId + POWS[ self.packet.index+1]*c
        if self.packet.index == 3 then
          self:advance()
        end
      elseif self.state == 5 then -- GREETING_SCRAMBLE_BUFF_1
        if self.packet.index == 0 then
          self.packet.scrambleBuffer = Buffer:new(8+12)
        end
        self.packet.scrambleBuffer[ self.packet.index+1 ] = c
        if self.packet.index == 7 then
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
          self:advance()
        end
      elseif self.state == 10 then -- GREETING_FILLER_2
        -- 13 bytes 0x0
        if self.packet.index == 12 then
          self:advance()
        end
      elseif self.state == 11 then -- GREETING_SCRAMBLE_BUFF_2
        -- 12 bytes - not 13 bytes like the protocol spec says ...(node-mysql)
        if self.packet.index < 12 then
          self.packet.scrambleBuffer[ self.packet.index + 8 + 1 ] = c
        end
      elseif self.state == 12 then -- FIELD_COUNT
        self.log("field_count. c:",c , self.packet.index )
        local toBreak = false
        if self.packet.index == 0 then
          if c == 0xff then
            self.log("packet type set: error packet 2 ---------------")
            self.packet.type = Constants.ERROR_PACKET
            self:advance(Parser.STATE_ERROR_NUMBER)
            toBreak = true
          elseif c == 0xfe and not self.authenticated then
            self.log("packet type set: use_old_password_protocol_packet --------------")
            self.packet.type = Constants.USE_OLD_PASSWORD_PROTOCOL_PACKET
            toBreak = true
          else
            if c == 0x0 then
              -- after the first OK PACKET, we are authenticated
              self.authenticated = true
              self.log("packet type set: ok packet ---------------------")
              self.packet.type = Constants.OK_PACKET
              self:advance( Parser.STATE_AFFECTED_ROWS)
              toBreak = true
            end
          end
        end

        if not toBreak then
          self.receivingFieldPackets = true
          self.log("packet type set: result_set_header_packet ------------------")
          self.packet.type = Constants.RESULT_SET_HEADER_PACKET
          self.packet.fieldCount = self:lengthCoded( c, self.packet.fieldCount, Parser.STATE_EXTRA_LENGTH )
          self.log("fieldCount:", self.packet.fieldCount )
        end
      elseif self.state == 13 then -- Parser.STATE_ERROR_NUMBER
        if self.packet.index == 0 then
          self.packet.errorNumber = 0
        end
        -- 2 bytes LE
        self.packet.errorNumber = self.packet.errorNumber + POWS[ self.packet.index + 1 ] * c
        if self.packet.index == 1 then
          if not self.greeted then
            self:advance( Parser.STATE_ERROR_MESSAGE )
          else
            self:advance()
          end
        end        
      elseif self.state == 14 then -- STATE_ERROR_SQL_STATE_MARKER
        -- 1 byte
        self.packet.sqlStateMarker = string.char(c)
        self.packet.sqlState = ""
        self:advance()
      elseif self.state == 15 then -- Parser.STATE_ERROR_SQL_STATE
        -- 5 chars
        if self.packet.index < 5 then
          self.packet.sqlState = self.packet.sqlState .. string.char(c)
        end
        if self.packet.index == 4 then
          self:advance( Parser.STATE_ERROR_MESSAGE )
        end
      elseif self.state == 16 then -- Parser.STATE_ERROR_MESSAGE
        if self.packet.received <= self.packet.length then
          self.packet.errorMessage = ( self.packet.errorMessage or "" ) .. string.char(c)
        end        
      elseif self.state == 17 then -- Parser.STATE_AFFECTED_ROWS               
        self.packet.affectedRows = self:lengthCoded( c, self.packet.affectedRows )
      elseif self.state == 18 then -- Parser.STATE_INSERT_ID
        self.packet.insertId = self:lengthCoded( c, self.packet.insertId )
      elseif self.state == 19 then -- Parser.STATE_SERVER_STATUS
        if self.packet.index == 0 then
          self.packet.serverStatus = 0
        end
        -- 2 bytes LE
        self.packet.serverStatus = self.packet.serverStatus + POWS[ self.packet.index+ 1 ] * c
        if self.packet.index == 1 then
          self:advance()
        end
      elseif self.state == 20 then -- Parser.STATE_WARNING_COUNT
        if self.packet.index == 0 then
          self.packet.warningCount = 0
        end
        -- 2 bytes LE
        self.packet.warningCount = self.packet.warningCount + POWS[ self.packet.index + 1 ] * c
        if self.packet.index == 1 then
          self.packet.message = ""
          self:advance()
        end
      elseif self.state == 21 then -- Parser.STATE_MESSAGE
        if self.packet.received <= self.packet.length then
          self.packet.message = self.packet.message .. string.char(c)
        end        
      elseif self.state == 22 then -- Parser.STATE_EXTRA_LENGTH
        self.packet.extra = ""
        self.lengthCodedStringLength = self:lengthCoded( c, self.lengthCodedStringLength )
      elseif self.state == 23 then  --  Parser.STATE_EXTRA_STRING
        self.packet.extra = self.packet.extra .. string.char(c)
      elseif self.state == 24 then -- Parser.STATE_FIELD_CATALOG_LENGTH
        local toBreak = false
        if self.packet.index == 0 then
          if c == 0xfe then
            self.log("packet type set: eof packet -------------------")
            self.packet.type = Constants.EOF_PACKET
            self:advance( Parser.STATE_EOF_WARNING_COUNT )
            toBreak = true
          else
            self.log("packet type set: field packet -------------------")
            self.packet.type = Constants.FIELD_PACKET
          end
          if not toBreak then
            self.lengthCodedStringLength = self:lengthCoded( c, self.lengthCodedStringLength )
          end
        end        
      elseif self.state == 25 then -- Parser.STATE_FIELD_CATALOG_STRING
        if self.packet.index == 0 then
          self.packet.catalog = ""
        end
        self.packet.catalog = self.packet.catalog .. string.char(c)
        if (self.packet.index + 1 ) == self.lengthCodedStringLength then
          self:advance()
        end        
      elseif self.state == 26 then -- Parser.STATE_FIELD_DB_LENGTH
        self.lengthCodedStringLength = self:lengthCoded( c, self.lengthCodedStringLength )
        if self.lengthCodedStringLength == 0 then
          self:advance()
        end        
      elseif self.state == 27 then -- Parser.STATE_FIELD_DB_STRING
        if self.packet.index == 0 then
          self.packet.db = ""
        end
        self.packet.db = self.packet.db .. string.char(c)
        if (self.packet.index + 1 ) == self.lengthCodedStringLength then
          self:advance()
        end        
      elseif self.state == 28 then -- Parser.STATE_FIELD_TABLE_LENGTH
        self.lengthCodedStringLength = self:lengthCoded(c, self.lengthCodedStringLength )
        if self.lengthCodedStringLength == 0 then
          self:advance()
        end        
      elseif self.state == 29 then -- Parser.STATE_FIELD_TABLE_STRING
        if self.packet.index == 0 then
          self.packet.table = ""
        end
        self.packet.table = self.packet.table .. string.char(c)
        if (self.packet.index + 1) == self.lengthCodedStringLength then
          self:advance()
        end        
      elseif self.state == 30 then -- Parser.STATE_FIELD_ORIGINAL_TABLE_LENGTH
        self.lengthCodedStringLength = self:lengthCoded( c, self.lengthCodedStringLength )
        if self.lengthCodedStringLength == 0 then
          self:advance()
        end        
      elseif self.state == 31 then -- Parser.STATE_FIELD_ORIGINAL_TABLE_STRING
        if self.packet.index == 0 then
          self.packet.originalTable = ""
        end
        self.packet.originalTable = self.packet.originalTable .. string.char(c)
        if (self.packet.index + 1) == self.lengthCodedStringLength then
          self:advance()
        end        
      elseif self.state == 32 then -- Parser.STATE_FIELD_NAME_LENGTH
        self.lengthCodedStringLength = self:lengthCoded( c, self.lengthCodedStringLength )        
      elseif self.state == 33 then -- Parser.STATE_FIELD_NAME_STRING
        if self.packet.index == 0 then
          self.packet.name = ""
        end
        self.packet.name = self.packet.name .. string.char(c)
        if (self.packet.index + 1 ) == self.lengthCodedStringLength then
          self:advance()
        end         
      elseif self.state == 34 then -- Parser.STATE_FIELD_ORIGINAL_NAME_LENGTH
        self.lengthCodedStringLength = self:lengthCoded( c, self.lengthCodedStringLength )
        if self.lengthCodedStringLength == 0 then
          self:advance()
        end        
      elseif self.state == 35 then -- Parser.STATE_FIELD_ORIGINAL_NAME_STRING
        if self.packet.index == 0 then
          self.packet.originalName = ""
        end
        self.packet.originalName = self.packet.originalName .. string.char(c)
        if ( self.packet.index + 1) == self.lengthCodedStringLength then
          self:advance()
        end        
      elseif self.state == 36 then -- Parser.STATE_FIELD_FILLER_1
        -- 1 bytes 0
        self:advance()
      elseif self.state == 37 then -- Parser.STATE_FIELD_CHARSET_NR
        if self.packet.index == 0 then
          self.packet.charsetNumber = 0
        end
        -- 2 bytes LE
        self.packet.charsetNumber = self.packet.charsetNumber + POWS[ self.packet.index + 1 ] * c
        if self.packet.index == 1 then
          self.log( "self.packet.charsetNumber:", self.packet.charsetNumber )
          self:advance()
        end        
      elseif self.state == 38 then -- Parser.STATE_FIELD_LENGTH
        if self.packet.index == 0 then
          self.packet.fieldLength = 0
        end
        -- 4 bytes LE
        self.packet.fieldLength = self.packet.fieldLength + POWS[ self.packet.index + 1 ] * c
        if self.packet.index == 3 then
          self.log("self.packet.fieldLength:", self.packet.fieldLength )
          self:advance()
        end        
      elseif self.state == 39 then -- Parser.STATE_FIELD_TYPE
        -- 1 byte
        self.packet.fieldType = c
        self:advance()
      elseif self.state == 40 then -- Parser.STATE_FIELD_FLAGS
        if self.packet.index == 0 then
          self.packet.flags = 0
        end
        -- 2 byte LE
        self.packet.flags = self.packet.flags + POWS[ self.packet.index + 1 ] * c
        if self.packet.index == 1 then
          self:advance()
        end        
      elseif self.state == 41 then -- Parser.STATE_FIELD_DECIMALS
        -- 1 byte
        self.packet.decimals = c
        self:advance()
      elseif self.state == 42 then -- Parser.STATE_FIELD_FILLER_2
        -- 2 bytes 0x00
        if self.packet.index == 1 then
          self:advance()
        end        
      elseif self.state == 43 then
        error("Parser.STATE_FIELD_DEFAULT                = 43,  TODO: only occurs for mysql_list_fields()")
      elseif self.state == 44 then -- Parser.STATE_EOF_WARNING_COUNT
        if self.packet.index == 0 then
          self.packet.warningCount = 0
        end
        -- 2 bytes LE
        self.packet.warningCount = self.packet.warningCount + POWS[ self.packet.index + 1 ] * c
        if self.packet.index == 1 then
          self:advance()
        end        
      elseif self.state == 45 then -- Parser.STATE_EOF_SERVER_STATUS
        if self.packet.index == 0 then
          self.packet.serverStatus = 0
        end
        -- 2 bytes LE
        self.packet.serverStatus = self.packet.serverStatus + POWS[ self.packet.index + 1 ] * c
        if self.packet.index == 1 then
          if self.receivingFieldPackets then
            self.receivingFieldPackets = false
            self.receivingRowPackets = true
          end
        end        
      elseif self.state == 46 then -- Parser.STATE_COLUMN_VALUE_LENGTH
        if self.packet.index == 0 then
          self.packet.columnLength = 0
          self.log("packet type set: row_data_packet ----------------")
          self.packet.type = Constants.ROW_DATA_PACKET
        end
        local toBreak = false
        if self.packet.received == 1 then
          if c == 0xfe then
            self.log("packet type set: eof packet ---------------")
            self.packet.type = Constants.EOF_PACKET
            self.receivingRowPackets = false
            self:advance( Parser.STATE_EOF_WARNING_COUNT )
            toBreak = true
          else
            self:emit( "packet", self.packet )
          end
        end
        if not toBreak then
          self.packet.columnLength = self:lengthCoded( c, self.packet.columnLength )
          if ( self.packet.columnLength == nil or self.packet.columnLength == 0 ) and ( self.lengthCodedStringLength == nil or self.lengthCodedStringLength == 0 ) then
            local cbarg = nil
            if self.packet.columnLength then cbarg = Buffer:new(0) end
            packet:emit( "data", cbarg, 0 )
            if self.packet.received < self.packet.length then
              self:advance( Parser.STATE_COLUMN_VALUE_LENGTH )
            else
              self.packet = nil
              self.state = Parser.STATE_PACKET_LENGTH
              toContinue = true
            end
          end          
        end        
      elseif self.state == 47 then -- Parser.STATE_COLUMN_VALUE_STRING
        local remaining = self.packet.columnLength - self.packet.index
        self.log("remaining:", remaining )
        local toRead
        if ( i-1 + remaining ) > #data then
          toRead = #data - (i-1)
          self.packet.index = self.packet.index + toRead
          self.packet:emit("data", string.sub( data, i, #data), remaining - toRead )
          -- the -1 offsets are because these values are also manipulated by the loop itself
          self.packet.received = self.packet.received + ( toRead - 1 );
          i = #data -- fin directry
        else
          self.packet:emit("data", string.sub( data, i, i + remaining - 1 ), 0 )
          
          i = i + remaining  -- all
          self.packet.received = self.packet.received + remaining - 1 -- -1, as above reason!
          self:advance( Parser.STATE_COLUMN_VALUE_LENGTH )
          -- advance() sets this to -1, but packet.index++ is skipped, so we need to manually fix
          self.packet.index = 0
        end
        if self.packet.received == self.packet.length then
          self.packet = nil
          self.state = Parser.STATE_PACKET_LENGTH
        end
        toContinue = true
      else
        error("invalid packet state:", self.state )
      end

      if not toContinue then
        -- go to next byte!
        self.packet.index = self.packet.index + 1
        if self.state > Parser.STATE_PACKET_NUMBER and self.packet.received == self.packet.length then
          self.log("emitPacket")
          self:emitPacket()
        end

        i = i + 1
      end      
    end

  end
  return parser
end

return Parser
