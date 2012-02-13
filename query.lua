local Parser = require("./parser")

-- OK,RESULT_SET_HEADER, FIELD, EOF, ROW_DATA, ROW_DATA,EOF : 1,3,4,5,6,6,5,

Query={}
function Query:new()
  local q = {}
  q.callbacks = {}
  function q:on( evname, f )
    self.callbacks[evname] = f
  end

  function q:handlePacket(packet)
    print( "query.handlePacket called. type:", packet.type, "####################"  )
    packet:on( "data", function(data,iarg)
        print("packet.on data:", data )
      end)

    if packet.type == Parser.OK_PACKET then
      error("ok packet")
    elseif packet.type == Parser.ERROR_PACKET then
      error("error packet")
    elseif packet.type == Parser.FIELD_PACKET then
      error("field packet")      
    elseif packet.type == Parser.EOF_PACKET then
      error("eof packet")            
    elseif packet.type == Parser.ROW_DATA_PACKET then
      error("row data packet")                  
    else
      error("query: invalid packet type")
    end
    
      
  end
  
  
  return q
end


return Query