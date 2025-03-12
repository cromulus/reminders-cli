RELEASE_BUILD=./.build/apple/Products/Release
EXECUTABLE=reminders
API_EXECUTABLE=reminders-api
ARCHIVE=$(EXECUTABLE).tar.gz
API_ARCHIVE=$(API_EXECUTABLE).tar.gz

.PHONY: clean build-release package package-api test test-single

build-release:
	swift build --configuration release -Xswiftc -warnings-as-errors -Xswiftc -enable-upcoming-feature -Xswiftc DisableSwift6Isolation --arch arm64 --arch x86_64

test:
	swift test

test-single:
	@if [ -z "$(TEST)" ]; then \
		echo "Usage: make test-single TEST=\"TestClassName/testMethodName\""; \
	else \
		swift test --filter "$(TEST)"; \
	fi

package: build-release
	$(RELEASE_BUILD)/$(EXECUTABLE) --generate-completion-script zsh > _reminders
	tar -pvczf $(ARCHIVE) _reminders -C $(RELEASE_BUILD) $(EXECUTABLE)
	tar -zxvf $(ARCHIVE)
	@shasum -a 256 $(ARCHIVE)
	@shasum -a 256 $(EXECUTABLE)
	rm $(EXECUTABLE) _reminders

package-api: build-release
	tar -pvczf $(API_ARCHIVE) -C $(RELEASE_BUILD) $(API_EXECUTABLE)
	tar -zxvf $(API_ARCHIVE)
	@shasum -a 256 $(API_ARCHIVE)
	@shasum -a 256 $(API_EXECUTABLE)
	rm $(API_EXECUTABLE)

clean:
	rm -f $(EXECUTABLE) $(ARCHIVE) $(API_EXECUTABLE) $(API_ARCHIVE) _reminders
	swift package clean
