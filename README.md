Luvit port of node-mysql
===
<a href="http://travis-ci.org/kengonakajima/luvit-mysql"><img src="https://secure.travis-ci.org/kengonakajima/luvit-mysql.png"></a>

Luvit port of [node-mysql](https://github.com/felixge/node-mysql) .

Much code is from node-mysql JavaScript source. Thank for former work!


Example
====

<pre>
local MySQL = require( "./mysql" )

local client = MySQL.createClient( { database="test",user="passtestuser",port=3306,password="hoge", logfunc=nil } )

client:query( "CREATE DATABASE luvit_mysql_testdb", function(err)
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
    assert( not err )
    client:query( "INSERT INTO testtable SET name = 'ken', age = 40, created=now()",
      function(err)
        assert( not err )
      end)
    client:query( "SELECT * FROM testtable", function(err,res,fields)
        print(fields.name.fieldType, MySQL.FIELD_TYPE_VAR_STRING)
        for i,v in ipairs(res) do
          print(v.id, v.name, v.age, v.created.year, v.created.month, v.created.day )
        end
      end)
  end)
</pre>


HowTo
====
<pre>
shell> luvit test.lua
</pre>


TODO
====
 - support luvit's module system
