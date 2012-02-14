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

local Client = require("./client")
local Constants = require("./constants")

Error={}
function Error:new()
  local e = {}
  return e
end

-----------------------
MySQL = {}
function MySQL.createClient(conf)
  local cl = Client:new(conf)
  return cl
end

for k,v in pairs(Constants) do
  MySQL[k]=v
end

return MySQL

