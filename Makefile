run:
	luvit test.lua 2>&1 | ruby -pe 'gsub(/\t\//,"/")'

run2:
	luvit test2.lua 2>&1 | ruby -pe 'gsub(/\t\//,"/")'
