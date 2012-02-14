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