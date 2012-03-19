
LUVIT=deps/luvit/build/luvit

ifeq ($(shell uname -sm | sed -e s,x86_64,i386,),Darwin i386)
#osx
export CC=gcc #-arch i386
CFLAGS=$(shell $(LUVIT) --cflags) -g -O3 -I./deps/luvit/deps/luajit/src
LIBS=$(shell $(LUVIT) --libs)  
LDFLAGS=
else
# linux
CFLAGS=$(shell $(LUVIT) --cflags) -g -O3 -I./deps/luvit/deps/luajit/src
LIBS=$(shell $(LUVIT) --libs) -lm -ldl
LDFLAGS=
endif





all:  test

test: setup $(LUVIT) 
	$(LUVIT) test.lua

setup:
	mysql -u root -e "create database if not exists test"
	mysql -u root -e "use test; grant all on *.* to passtestuser@localhost; flush privileges"
	mysql -u root -e "set password for passtestuser@localhost = password('hoge')"

$(LUVIT) :
	git submodule init
	git submodule update
	cd deps/luvit; ./configure; make



run:
	luvit test.lua 2>&1 | ruby -pe 'gsub(/\t\//,"/")'

