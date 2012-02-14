-- make it looks like node-mysql semantics

local timer = require( "timer" ) -- luvit built-in
local MySQL = require( "./mysql" )

local client = MySQL.createClient( { database="test",user="passtestuser",port=3306,password="hoge", logfunc=nil } )
--local client = MySQL.createClient( { database="luvit_mysql_test_db",user="root",port=3306,password="" } )

client:ping( function()    print("ping received")  end)

client:query( "select * from aho", function(err,res,fields)
    assert(not err)
    p(fields)
    p(res)
  end )



client:query( "CREATE DATABASE luvit_mysql_testdb", function(err)
    print("query error. code:", err.message, err.number, MySQL.ERROR_DB_CREATE_EXISTS )
    if err and err.number ~= MySQL.ERROR_DB_CREATE_EXISTS then
      error("cannot create db" )
    end
  end)


client:query( "USE luvit_mysql_testdb" )

client:query( "DROP TABLE IF EXISTS testtable", function(err,res,fields)
    assert(not err)
  end)


client:query( "CREATE TABLE testtable (id INT(11) AUTO_INCREMENT, name VARCHAR(255), age INT(11), created DATETIME, PRIMARY KEY (id) )",
  function(err,res,fields)
    print("CREATE TABLE DONE")
    for k,v in pairs(client) do
      print("cl:",k,v)
    end
    assert( not err )

    client:query( "INSERT INTO testtable SET name = 'george', age = 20, created=now()", function(err) assert( not err ) end)
    client:query( "INSERT INTO testtable SET name = 'jack', age = 30, created=now()", function(err) assert( not err ) end)    
    client:query( "INSERT INTO testtable SET name = 'ken', age = 40, created=now()", function(err) assert( not err ) end)
    
  end)


-- use timer because we're not sure about above INSERT finishes before following SELECT.
timer.setInterval( 2000, function()
    print("timer interval!")
    
    local q = client:query( "SELECT * FROM testtable", function(err,res,fields)
        assert(not err)
        p(fields)
        p(res)
      end)
  end)
