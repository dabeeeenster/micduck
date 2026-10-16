PREFIX ?= $(HOME)/.local
DUCK_TO ?= 50
LABEL = io.github.dabeeeenster.micduck
PLIST = $(HOME)/Library/LaunchAgents/$(LABEL).plist
DOMAIN = gui/$(shell id -u)

micduck: micduck.swift
	swiftc -O micduck.swift -o micduck

install: micduck
	mkdir -p $(PREFIX)/bin $(HOME)/Library/LaunchAgents
	install -m 755 micduck $(PREFIX)/bin/micduck
	sed -e 's|@BIN@|$(PREFIX)/bin/micduck|' -e 's|@DUCK_TO@|$(DUCK_TO)|' \
		-e 's|@LABEL@|$(LABEL)|' -e 's|@HOME@|$(HOME)|' \
		launchd.plist.in > $(PLIST)
	launchctl bootout $(DOMAIN)/$(LABEL) 2>/dev/null || true
	launchctl bootstrap $(DOMAIN) $(PLIST)
	@echo "micduck is running and will start at login. Log: ~/Library/Logs/micduck.log"

uninstall:
	launchctl bootout $(DOMAIN)/$(LABEL) 2>/dev/null || true
	rm -f $(PLIST) $(PREFIX)/bin/micduck

clean:
	rm -f micduck

.PHONY: install uninstall clean
