local SHA1 = require("./sha1")
local Util = require("./util")
local Auth={}
  
function Auth.token( password, scramble )
  if not password or #password == 0 then
    return ""
  end
  assert( type(password) == "string")  
  assert( type(scramble) == "string")

  local stage1 = SHA1.sha1_binary(password)
  local stage2 = SHA1.sha1_binary(stage1)
  local stage3 = SHA1.sha1_binary(scramble .. stage2 )
  local final = Util.xor( stage3, stage1 )
  return final  
end


return Auth