FRONTEND_SCRIPTS := $(wildcard frontend/*.coffee)
FRONTEND_STYLES := $(wildcard frontend/*.styl)

FRONTEND_OBJECTS := $(addprefix build/,$(FRONTEND_SCRIPTS:.coffee=.js)) $(addprefix build/,$(FRONTEND_STYLES:.styl=.css))

all: $(FRONTEND_OBJECTS)

build/%.js: %.coffee
	node_modules/.bin/coffee -o $(shell dirname "$@") -c $^

build/%.css: %.styl
	node_modules/.bin/stylus --compress  -o $(shell dirname "$@") $^

install: $(FRONTEND_OBJECTS)
	npm install
