local SHA1 = require("./sha1")
local Util = require("./util")
local Auth={}
  
function Auth.token( password, scramble )
  if not password or #password == 0 then
    return ""
  end
  print("pw type:", type(password), "scrb type:", type(scramble))
  assert( type(password) == "string")  
  assert( type(scramble) == "string")

  local stage1 = SHA1.sha1_binary(password)
  local stage2 = SHA1.sha1_binary(stage1)
  local stage3 = SHA1.sha1_binary(scramble .. stage2 )
  local final = Util.xor( stage3, stage1 )
  print( "password:" )
  Util.dumpStringBytes(password)
  print( "scramble:" )
  Util.dumpStringBytes(scramble)
  print( "stage1:" )
  Util.dumpStringBytes(stage1)
  print( "stage2:" )
  Util.dumpStringBytes(stage2)
  print( "stage3:" )
  Util.dumpStringBytes(stage3)
  print( "final:" )
  Util.dumpStringBytes(final)
  return final
  
end


return Auth