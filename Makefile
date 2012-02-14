
LUVIT=deps/luvit/build/luvit
LUVITCONFIG=$(LUVIT) deps/luvit/bin/luvit-config.lua

ifeq ($(shell uname -sm | sed -e s,x86_64,i386,),Darwin i386)
#osx
export CC=gcc #-arch i386
CFLAGS=$(shell luvit-config --cflags) -g -O3 -I./deps/luvit/deps/luajit/src
LIBS=$(shell luvit-config --libs)  ./deps/luvit/deps/luajit/src/libluajit.a
LDFLAGS=
else
# linux
CFLAGS=$(shell $(LUVITCONFIG) --cflags) -g -O3 -I./deps/luvit/deps/luajit/src
LIBS=$(shell $(LUVITCONFIG) --libs)  ./deps/luvit/deps/luajit/src/libluajit.so -lm -ldl
LDFLAGS=
endif





all:  test

test: $(LUVIT) 
	$(LUVIT) test.lua

$(LUVIT) :
	git submodule init
	git submodule update
	cd deps/luvit; ./configure; make



run:
	luvit test.lua 2>&1 | ruby -pe 'gsub(/\t\//,"/")'

