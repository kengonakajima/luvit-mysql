local Parser = require("./parser")
local Util = require("./util")
local Constants = require("./constants")
local table = require("table")

-- OK,RESULT_SET_HEADER, FIELD, EOF, ROW_DATA, ROW_DATA,EOF : 1,3,4,5,6,6,5,

Query={}
function Query:new(conf)
  local q = {
    sql = conf.sql,
    typeCast = conf.typeCast
  }
  q.callbacks = {}
  function q:on( evname, fn )
    self.callbacks[evname] = fn
  end

  function q:emit( evname, a,b )
    local cb = self.callbacks[evname]
    print("Query:emitting event. name:",evname, "func:", cb )
    if cb then cb(a,b) end
  end
  

  function q:handlePacket(packet)
    print( "query.handlePacket called. type:", packet.type, "####################" )

    if packet.type == Constants.OK_PACKET then
      self:emit("end", Util.packetToUserObject(packet) )
    elseif packet.type == Constants.ERROR_PACKET then
      packet.sql = self.sql
      self:emit( "error", Util.packetToUserObject(packet))
    elseif packet.type == Constants.FIELD_PACKET then
      if not self.fields then self.fields = {} end
      table.insert( self.fields, packet)
      self:emit( "field", packet )
    elseif packet.type == Constants.EOF_PACKET then
      if not self.eofs then
        self.eofs = 1
      else
        self.eofs = self.eofs + 1
      end
      if self.eofs == 2 then
        self:emit( "end", nil, self.rows, self.fields )
      end
    elseif packet.type == Constants.ROW_DATA_PACKET then
      self.row = {}
      self.rowIndex = 1 -- it's lua!
      self.field = nil
      packet:on("data", function(buffer,remaining)
          print("query row_data_packet receives data. buffer:", buffer, "remaining:", remaining, "nfields:", #self.fields, "ri:", self.rowIndex, "f:", self.field  )
          
          if not self.field then
            self.field = self.fields[ self.rowIndex ]
            self.row[ self.field.name ] = ""
          end

          if buffer then
            self.row[ self.field.name ] = self.row[ self.field.name ] .. buffer
          else
            self.row[ self.field.name ] = nil
          end

          if remaining and remaining > 0 then
            return
          end

          self.rowIndex = self.rowIndex + 1

          if self.rowIndex == (#self.fields+1) then
            self:emit( "row", self.row )
            return
          end
          
          self.field = nil
        end)
    end
  end
  
  return q
end


return Query