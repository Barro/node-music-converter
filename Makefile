FRONTEND_SOURCES := $(wildcard frontend/*.coffee)
FRONTEND_OBJECTS := $(addprefix build/,$(FRONTEND_SOURCES:.coffee=.js))

all: $(FRONTEND_OBJECTS)

build/%.js: %.coffee
	coffee -o $(shell dirname "$@") -c $^
