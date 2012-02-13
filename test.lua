-- make it looks like node-mysql semantics

local timer = require( "timer" ) -- luvit built-in
local mysql = require( "./mysql" )

local client = mysql.createClient( { database="test",user="passtestuser",port=3306,password="hoge" } )
--local client = mysql.createClient( { database="luvit_mysql_test_db",user="root",port=3306,password="" } )

client:ping( function()    print("ping received")  end)

local q = client:query( "select * from aho", function(err) error(err) end )
q:on("row", function(row)
    print("got a row:", row.name, row.age, row.created )
  end)
q:on("end", function()
    print("query finished" )
  end)


--[[--
client:query( "CREATE DATABASE testdb", function(err) 
    if err and err ~= mysql.ERROR_DB_CREATE_EXISTS then
      error("cannot create db" )
    end
  end)


client:query( "USE testdb" )

client:query( "DROP TABLE IF EXISTS testtable" )

client:query( "CREATE TABLE testtable (id INT(11) AUTO_INCREMENT, name VARCHAR(255), age INT(11), created DATETIME, PRIMARY KEY (id) )",
  function(err)
    assert( not err )

    client.query( "INSERT INTO testtable SET name = 'george', age = 20, created=now()", function(err) assert( not err ) end)
    client.query( "INSERT INTO testtable SET name = 'jack', age = 30, created=now()", function(err) assert( not err ) end)    
    client.query( "INSERT INTO testtable SET name = 'ken', age = 40, created=now()", function(err) assert( not err ) end)
    
  end)


-- use timer because we're not sure about above INSERT finishes before following SELECT.
timer.setInterval( 2000, function()
    print("timer interval!")
    
    local q = client:query( "SELECT * FROM testtable", function(err) assert(not err) end )

    q:on("row", function(row)
        print("got a row:", row.name, row.age, row.created )
      end)

    q:on("end", function()
        print("query finished" )
      end)

  end)

--]]--