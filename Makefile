APP          = Canopy
BUNDLE       = $(APP).app
CONTENTS     = $(BUNDLE)/Contents
MACOS        = $(CONTENTS)/MacOS
RES          = $(CONTENTS)/Resources
BUILD        = .build/release/$(APP)
ICON_SRC     = Resources/AppIcon.icns
SHADER_DIR   = Sources/CanopyKit/Shaders
AIR_DIR      = .build/metal-air
METALLIB_OUT = $(RES)/default.metallib

METAL_SRCS   = $(SHADER_DIR)/PostProcess.metal \
               $(SHADER_DIR)/Meadow.metal \
               $(SHADER_DIR)/WildMeadow.metal \
               $(SHADER_DIR)/Moss.metal \
               $(SHADER_DIR)/Stream.metal \
               $(SHADER_DIR)/Dunes.metal

AIR_FILES    = $(patsubst $(SHADER_DIR)/%.metal,$(AIR_DIR)/%.air,$(METAL_SRCS))

.PHONY: app shaders icon run snapshot test install uninstall clean

app: icon
	swift build -c release
	rm -rf $(BUNDLE)
	mkdir -p $(MACOS) $(RES) $(AIR_DIR)
	@set -e; for src in $(METAL_SRCS); do \
		base=$$(basename $$src .metal); \
		xcrun -sdk macosx metal -O2 -I $(SHADER_DIR) -c $$src -o $(AIR_DIR)/$$base.air; \
	done
	xcrun -sdk macosx metallib $(AIR_DIR)/*.air -o $(METALLIB_OUT)
	cp $(BUILD) $(MACOS)/$(APP)
	cp -R .build/release/Canopy_CanopyKit.bundle $(RES)/ 2>/dev/null || true
	cp Resources/Info.plist $(CONTENTS)/Info.plist
	cp $(ICON_SRC) $(RES)/AppIcon.icns
	@echo "Built $(BUNDLE)"

icon: $(ICON_SRC)

$(ICON_SRC):
	swift scripts/generate_icon.swift Resources

run: app
	open $(BUNDLE)

snapshot:
	swift run -c release Canopy --snapshot .build/snapshots

test:
	swift test

install: app
	rm -rf /Applications/$(BUNDLE)
	cp -R $(BUNDLE) /Applications/$(BUNDLE)
	@echo "Installed to /Applications/$(BUNDLE)"

uninstall:
	rm -rf /Applications/$(BUNDLE)
	@echo "Removed /Applications/$(BUNDLE)"

clean:
	rm -rf $(BUNDLE) $(AIR_DIR)
	swift package clean
