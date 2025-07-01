RELEASE_BUILD=./.build/apple/Products/Release
EXECUTABLE=reminders
API_EXECUTABLE=reminders-api
ARCHIVE=$(EXECUTABLE).tar.gz
API_ARCHIVE=$(API_EXECUTABLE).tar.gz

.PHONY: clean build-release build-private build-private-release package package-api package-private test test-single

build-release:
	swift build --configuration release -Xswiftc -enable-upcoming-feature -Xswiftc DisableSwift6Isolation --arch arm64 --arch x86_64

build-private:
	swift build --configuration debug -Xswiftc -DPRIVATE_REMINDERS_ENABLED -Xswiftc -enable-upcoming-feature -Xswiftc DisableSwift6Isolation --arch arm64 --arch x86_64

build-private-release:
	swift build --configuration release -Xswiftc -DPRIVATE_REMINDERS_ENABLED -Xswiftc -enable-upcoming-feature -Xswiftc DisableSwift6Isolation --arch arm64 --arch x86_64

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

package-private: build-private-release
	$(RELEASE_BUILD)/$(EXECUTABLE) --generate-completion-script zsh > _reminders
	tar -pvczf $(EXECUTABLE)-private.tar.gz _reminders -C $(RELEASE_BUILD) $(EXECUTABLE)
	tar -zxvf $(EXECUTABLE)-private.tar.gz
	@shasum -a 256 $(EXECUTABLE)-private.tar.gz
	@shasum -a 256 $(EXECUTABLE)
	rm $(EXECUTABLE) _reminders
	@echo "Private API build packaged as $(EXECUTABLE)-private.tar.gz"

clean:
	rm -f $(EXECUTABLE) $(ARCHIVE) $(API_EXECUTABLE) $(API_ARCHIVE) _reminders $(EXECUTABLE)-private.tar.gz
	swift package clean
