init:
	@echo You probably want to run "zig build" instead.
.PHONY: init

# glad updates the GLAD loader. To use this, place the generated glad.zip
# in this directory next to the Makefile, remove vendor/glad and run this target.
#
# Generator: https://gen.glad.sh/
glad: vendor/glad
.PHONY: glad

vendor/glad: vendor/glad/include/glad/gl.h vendor/glad/include/glad/glad.h

vendor/glad/include/glad/gl.h: glad.zip
	rm -rf vendor/glad
	mkdir -p vendor/glad
	unzip glad.zip -dvendor/glad
	find vendor/glad -type f -exec touch '{}' +

vendor/glad/include/glad/glad.h: vendor/glad/include/glad/gl.h
	@echo "#include <glad/gl.h>" > $@

clean:
	rm -rf \
		zig-out .zig-cache \
		macos/build \
		macos/GhosttyKit.xcframework
.PHONY: clean

# ─────────────────────────────────────────────────────────────────────────────
# Sidebar fork — dev helpers (NOT upstream). Thin wrapper around
# ./build-macos.sh, which handles the macOS-26.5 + Zig-0.15.2 toolchain
# workaround (overlay SDK, bundled libSystem stub, Metal toolchain).
#   make build   full build (xcframework + app) — once / after a rebase
#   make dev     fast Swift rebuild + relaunch  — the inner loop
#   make doctor  verify the toolchain           make help  list targets
# Override paths, e.g.:  make build XCODE_DEV=/Applications/Xcode-beta.app/Contents/Developer
# ─────────────────────────────────────────────────────────────────────────────

REPO        := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))
ZIG_DIR     ?= $(HOME)/.zig-0.15.2
XCODE_DEV   ?= /Applications/Xcode.app/Contents/Developer
CONFIG      ?= Debug
SCHEME      := Ghostty
TARGET      := Ghostty
PROJECT     := Ghostty.xcodeproj
APP         := macos/build/$(CONFIG)/Ghostty.app
XCFRAMEWORK := macos/GhosttyKit.xcframework
CTL         := cli/ghosttyctl
PREFIX      ?= /usr/local
TEST_FILTER ?=
XCODEBUILD  := DEVELOPER_DIR=$(XCODE_DEV) xcodebuild
DERIVED     := $(HOME)/Library/Developer/Xcode/DerivedData
LSREGISTER  := /System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister

.DEFAULT_GOAL := help
.PHONY: help doctor build app run dev quit prune-apps test lint fmt sync xcode install-cli clean-app

help: ## Show this help
	@awk 'BEGIN{FS=":.*##"; printf "\nGhostty sidebar fork — make targets:\n\n"} /^[a-zA-Z0-9_.-]+:.*##/{printf "  \033[36m%-12s\033[0m%s\n",$$1,$$2} END{printf "\n  (upstream targets also available: init, glad, clean)\n\n"}' $(MAKEFILE_LIST)

doctor: ## Check build prerequisites (Zig, Xcode, Metal, patch, artifacts)
	@printf "Zig             : %s\n" "$$($(ZIG_DIR)/zig version 2>/dev/null || echo 'MISSING — expected 0.15.2 at $(ZIG_DIR)')"
	@printf "Xcode           : %s\n" "$$(DEVELOPER_DIR=$(XCODE_DEV) xcodebuild -version 2>/dev/null | head -1 || echo 'MISSING at $(XCODE_DEV)')"
	@printf "Metal toolchain : %s\n" "$$(DEVELOPER_DIR=$(XCODE_DEV) xcrun -sdk macosx metal --version >/dev/null 2>&1 && echo OK || echo 'MISSING — make build downloads it')"
	@printf "Zig SDKROOT fix : %s\n" "$$(grep -q SDKROOT '$(ZIG_DIR)/lib/std/zig/system/darwin.zig' 2>/dev/null && echo applied || echo 'not applied — make build applies it')"
	@printf "xcframework     : %s\n" "$$([ -d '$(XCFRAMEWORK)' ] && echo present || echo 'missing — run: make build')"
	@printf "app             : %s\n" "$$([ -d '$(APP)' ] && echo present || echo 'missing — run: make build')"

build: ## Full build: libghostty (Zig) + macOS app (Xcode). Run once / after a rebase.
	./build-macos.sh

$(XCFRAMEWORK):
	./build-macos.sh

app: $(XCFRAMEWORK) ## Fast incremental rebuild of the macOS app (Swift only)
	cd macos && $(XCODEBUILD) -project $(PROJECT) -target $(TARGET) -configuration $(CONFIG) -arch arm64 ONLY_ACTIVE_ARCH=YES build

run: quit prune-apps ## Launch the built app (quits the old instance + prunes stale copies first)
	@test -d "$(APP)" || { echo "not built — run 'make build' (or 'make app')"; exit 1; }
	@sleep 1
	open "$(APP)"

dev: app quit prune-apps ## Rebuild + relaunch fresh (quits old instance + prunes stale copies)
	@sleep 1
	open "$(APP)"

quit: ## Quit the fork app only (leaves your daily Ghostty untouched)
	@pkill -f "$(REPO)/$(APP)/Contents/MacOS/ghostty" 2>/dev/null && echo "quit fork app" || echo "fork app not running"

prune-apps: ## Delete stale fork Ghostty.app copies in Xcode DerivedData (disk + Launch Services / Spotlight)
	@n=0; for app in $(DERIVED)/Ghostty-*/Build/Products/*/Ghostty.app; do \
		[ -d "$$app" ] || continue; \
		pkill -f "$$app/Contents/MacOS/ghostty" 2>/dev/null || true; \
		"$(LSREGISTER)" -u "$$app" 2>/dev/null || true; \
		rm -rf "$$app"; \
		echo "  pruned $$app"; n=$$((n+1)); \
	done; \
	if [ $$n -eq 0 ]; then echo "  no stale DerivedData copies (only macos/build + your daily Ghostty remain)"; fi

test: $(XCFRAMEWORK) ## Run GhosttyTests (e.g. make test TEST_FILTER=GhosttyTests/SplitTreeTests)
	cd macos && $(XCODEBUILD) -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIG) -destination 'platform=macOS,arch=arm64' ONLY_ACTIVE_ARCH=YES $(if $(TEST_FILTER),-only-testing:$(TEST_FILTER),) test

lint: ## Lint Swift sources (SwiftLint, strict)
	@command -v swiftlint >/dev/null || { echo "swiftlint not installed (brew install swiftlint)"; exit 1; }
	swiftlint lint --strict

fmt: ## Auto-fix Swift formatting (SwiftLint)
	@command -v swiftlint >/dev/null || { echo "swiftlint not installed (brew install swiftlint)"; exit 1; }
	swiftlint lint --strict --fix

sync: ## Fetch ghostty-org (upstream) and report how far behind this branch is
	git fetch upstream
	@echo "behind ghostty-org/main by $$(git rev-list --count HEAD..upstream/main 2>/dev/null || echo '?') commits — rebase manually when ready (see SIDEBAR-FORK-REPORT.md)"

xcode: ## Open the project in Xcode (needed for previews / the MCP bridge)
	open macos/$(PROJECT)

install-cli: ## Symlink ghosttyctl into PREFIX/bin (default /usr/local; override PREFIX=~/.local)
	@mkdir -p "$(PREFIX)/bin"
	ln -sf "$(REPO)/$(CTL)" "$(PREFIX)/bin/ghosttyctl"
	@echo "linked $(PREFIX)/bin/ghosttyctl -> $(CTL)"

clean-app: ## Remove the built app + xcframework (keeps the Zig cache; upstream 'clean' wipes all)
	rm -rf macos/build "$(XCFRAMEWORK)"
