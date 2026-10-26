APP     = ClaudeWidget
BUNDLE  = $(APP).app
BINARY  = .build/release/$(APP)
PLIST   = Sources/ClaudeWidget/Info.plist
SWIFT_FLAGS ?=

.PHONY: build bundle run clean install test

build:
	swift build $(SWIFT_FLAGS) -c release 2>&1

test:
	swiftc -parse-as-library Sources/ClaudeWidget/Models/UsageModels.swift Sources/ClaudeWidget/Services/AccountPageUsageService.swift Tests/ParserSmoke.swift -o .build/parser-smoke
	.build/parser-smoke

bundle: build
	rm -rf $(BUNDLE)
	mkdir -p $(BUNDLE)/Contents/MacOS
	mkdir -p $(BUNDLE)/Contents/Resources
	cp $(BINARY) $(BUNDLE)/Contents/MacOS/$(APP)
	cp $(PLIST)   $(BUNDLE)/Contents/Info.plist
	cp -R .build/release/ClaudeWidget_ClaudeWidget.bundle $(BUNDLE)/Contents/Resources/
	@echo "Bundle ready: $(BUNDLE)"

run: bundle
	open $(BUNDLE)

install: bundle
	rm -rf /Applications/$(BUNDLE)
	cp -R $(BUNDLE) /Applications/$(BUNDLE)
	@echo "Installed to /Applications/$(BUNDLE)"

clean:
	rm -rf .build $(BUNDLE)
