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

