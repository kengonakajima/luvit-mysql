run:
	luvit test.lua 2>&1 | ruby -pe 'gsub(/\t\//,"/")'
