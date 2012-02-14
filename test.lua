-- make it looks like node-mysql semantics

local timer = require( "timer" ) -- luvit built-in
local MySQL = require( "./mysql" )

local client = MySQL.createClient( { database="test",user="passtestuser",port=3306,password="hoge", logfunc=nil } )
--local client = MySQL.createClient( { database="luvit_mysql_test_db",user="root",port=3306,password="" } )

client:ping( function()    print("ping received")  end)



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
    assert( not err )

    client:query( "INSERT INTO testtable SET name = 'george', age = 20, created=now()",
      function(err)
        assert( not err )
        print("INSERT DONE 1")
      end)
    client:query( "INSERT INTO testtable SET name = 'jack', age = 30, created=now()",
      function(err)
        assert( not err )
        print("INSERT DONE 2")        
      end)    
    client:query( "INSERT INTO testtable SET name = 'ken', age = 40, created=now()",
      function(err)
        assert( not err )
        print("INSERT DONE 3")
      end)
    
  end)


-- use timer because we're not sure about above INSERT finishes before following SELECT.
timer.setInterval( 2000, function()
    print("timer interval!")
    
    local q = client:query( "SELECT * FROM testtable", function(err,res,fields)
        assert(not err)
        assert( fields.id )
        assert( fields.name )
        assert( fields.age )
        assert( fields.created )
        assert( #res == 3 )
        assert( res[1].id == 1 )
        assert( res[1].name == "george" )
        assert( res[1].age == 20 )
        assert( res[1].created.year )
        assert( res[1].created.month )
        assert( res[1].created.day )
        assert( res[1].created.hour )
        assert( res[1].created.minute )
        assert( res[1].created.second )
        
        assert( res[2].id == 2 )
        assert( res[2].name == "jack" )
        assert( res[2].age == 30 )
        assert( res[2].created.year )
        assert( res[2].created.month )
        assert( res[2].created.day )
        assert( res[2].created.hour )
        assert( res[2].created.minute )
        assert( res[2].created.second )

        assert( res[3].id == 3 )
        assert( res[3].name == "ken" )
        assert( res[3].age == 40 )
        assert( res[3].created.year )
        assert( res[3].created.month )
        assert( res[3].created.day )
        assert( res[3].created.hour )
        assert( res[3].created.minute )
        assert( res[3].created.second )        
        
        process.exit(0)
      end)
  end)
