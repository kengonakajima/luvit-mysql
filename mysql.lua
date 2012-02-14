local Client = require("./client")

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


return MySQL

