DEVTOOLS := /Library/Developer/CommandLineTools/Library/Developer
INSTALL_DIR ?= $(HOME)/Applications
LSREGISTER := /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

.PHONY: app package icon install run test clean

app:
	bash scripts/build-app.sh

# dist/TrafficControl.dmg + .zip; see scripts/package.sh for signing and notarization.
package:
	bash scripts/package.sh

icon:
	swift scripts/make-icon.swift

install: app
	mkdir -p "$(INSTALL_DIR)"
	-pkill -x TrafficControl
	rm -rf "$(INSTALL_DIR)/TrafficControl.app"
	cp -R build/TrafficControl.app "$(INSTALL_DIR)/"
	$(LSREGISTER) -f "$(INSTALL_DIR)/TrafficControl.app"
	@echo "Installed to $(INSTALL_DIR)/TrafficControl.app"

run: install
	open "$(INSTALL_DIR)/TrafficControl.app"

# With only the Command Line Tools installed, swift-testing needs its framework paths spelled out.
test:
	@if xcode-select -p | grep -q CommandLineTools; then \
		swift test -Xswiftc -F$(DEVTOOLS)/Frameworks -Xlinker -F$(DEVTOOLS)/Frameworks \
			-Xlinker -rpath -Xlinker $(DEVTOOLS)/Frameworks -Xlinker -rpath -Xlinker $(DEVTOOLS)/usr/lib; \
	else swift test; fi

clean:
	rm -rf .build build dist
