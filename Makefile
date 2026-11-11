SHELL := /bin/bash
APPS_DIR := apps
BIN_DIR := bin
SRC_DIR := src
ASSETS_DIR := assets

TARGET_UNLOCK_NAME := Unlock Magic Trackpad Polling.app
TARGET_RESTORE_NAME := Restore Native 60Hz Display.app

APP_UNLOCK := $(APPS_DIR)/$(TARGET_UNLOCK_NAME)
APP_RESTORE := $(APPS_DIR)/$(TARGET_RESTORE_NAME)

.PHONY: all build clean apps test lint install build-unlock build-restore

all: test build

build: apps

apps: build-unlock build-restore

build-unlock: $(SRC_DIR)/unlock.applescript
	@mkdir -p "$(APPS_DIR)"
	rm -rf "$(APP_UNLOCK)"
	osacompile -o "$(APP_UNLOCK)" "$<"
	@mkdir -p "$(APP_UNLOCK)/Contents/Resources/bin"
	cp $(BIN_DIR)/trackpad-unlock.sh "$(APP_UNLOCK)/Contents/Resources/bin/"
	cp $(BIN_DIR)/detect-display.py "$(APP_UNLOCK)/Contents/Resources/bin/"
	chmod +x "$(APP_UNLOCK)/Contents/Resources/bin/"*
	@if [ -f "$(ASSETS_DIR)/applet-unlock.icns" ]; then \
		cp "$(ASSETS_DIR)/applet-unlock.icns" "$(APP_UNLOCK)/Contents/Resources/applet.icns"; \
	elif [ -f "$(ASSETS_DIR)/applet.icns" ]; then \
		cp "$(ASSETS_DIR)/applet.icns" "$(APP_UNLOCK)/Contents/Resources/applet.icns"; \
	fi
	/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.magictrackpad.pollingunlock" "$(APP_UNLOCK)/Contents/Info.plist" 2>/dev/null || \
	/usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string com.magictrackpad.pollingunlock" "$(APP_UNLOCK)/Contents/Info.plist"
	/usr/libexec/PlistBuddy -c "Set :CFBundleName Unlock Magic Trackpad Polling" "$(APP_UNLOCK)/Contents/Info.plist" 2>/dev/null || \
	/usr/libexec/PlistBuddy -c "Add :CFBundleName string Unlock Magic Trackpad Polling" "$(APP_UNLOCK)/Contents/Info.plist"
	/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString 2.0.0" "$(APP_UNLOCK)/Contents/Info.plist" 2>/dev/null || \
	/usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string 2.0.0" "$(APP_UNLOCK)/Contents/Info.plist"
	/usr/libexec/PlistBuddy -c "Set :CFBundleVersion 2.0.0" "$(APP_UNLOCK)/Contents/Info.plist" 2>/dev/null || \
	/usr/libexec/PlistBuddy -c "Add :CFBundleVersion string 2.0.0" "$(APP_UNLOCK)/Contents/Info.plist"
	/usr/libexec/PlistBuddy -c "Set :LSUIElement 1" "$(APP_UNLOCK)/Contents/Info.plist" 2>/dev/null || \
	/usr/libexec/PlistBuddy -c "Add :LSUIElement string 1" "$(APP_UNLOCK)/Contents/Info.plist"
	@echo "Built: $(APP_UNLOCK)"

build-restore: $(SRC_DIR)/restore.applescript
	@mkdir -p "$(APPS_DIR)"
	rm -rf "$(APP_RESTORE)"
	osacompile -o "$(APP_RESTORE)" "$<"
	@mkdir -p "$(APP_RESTORE)/Contents/Resources/bin"
	cp $(BIN_DIR)/trackpad-unlock.sh "$(APP_RESTORE)/Contents/Resources/bin/"
	cp $(BIN_DIR)/detect-display.py "$(APP_RESTORE)/Contents/Resources/bin/"
	chmod +x "$(APP_RESTORE)/Contents/Resources/bin/"*
	@if [ -f "$(ASSETS_DIR)/applet-restore.icns" ]; then \
		cp "$(ASSETS_DIR)/applet-restore.icns" "$(APP_RESTORE)/Contents/Resources/applet.icns"; \
	elif [ -f "$(ASSETS_DIR)/applet.icns" ]; then \
		cp "$(ASSETS_DIR)/applet.icns" "$(APP_RESTORE)/Contents/Resources/applet.icns"; \
	fi
	/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.magictrackpad.pollingrestore" "$(APP_RESTORE)/Contents/Info.plist" 2>/dev/null || \
	/usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string com.magictrackpad.pollingrestore" "$(APP_RESTORE)/Contents/Info.plist"
	/usr/libexec/PlistBuddy -c "Set :CFBundleName Restore Native 60Hz Display" "$(APP_RESTORE)/Contents/Info.plist" 2>/dev/null || \
	/usr/libexec/PlistBuddy -c "Add :CFBundleName string Restore Native 60Hz Display" "$(APP_RESTORE)/Contents/Info.plist"
	/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString 2.0.0" "$(APP_RESTORE)/Contents/Info.plist" 2>/dev/null || \
	/usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string 2.0.0" "$(APP_RESTORE)/Contents/Info.plist"
	/usr/libexec/PlistBuddy -c "Set :CFBundleVersion 2.0.0" "$(APP_RESTORE)/Contents/Info.plist" 2>/dev/null || \
	/usr/libexec/PlistBuddy -c "Add :CFBundleVersion string 2.0.0" "$(APP_RESTORE)/Contents/Info.plist"
	/usr/libexec/PlistBuddy -c "Set :LSUIElement 1" "$(APP_RESTORE)/Contents/Info.plist" 2>/dev/null || \
	/usr/libexec/PlistBuddy -c "Add :LSUIElement string 1" "$(APP_RESTORE)/Contents/Info.plist"
	@echo "Built: $(APP_RESTORE)"

test:
	/usr/bin/python3 -m unittest discover -s tests -p "test_*.py"

lint:
	bash -n $(BIN_DIR)/trackpad-unlock.sh
	python3 -m py_compile $(BIN_DIR)/detect-display.py

install: build
	cp -R "$(APP_UNLOCK)" /Applications/
	cp -R "$(APP_RESTORE)" /Applications/
	@echo "Installed apps to /Applications/"

clean:
	rm -rf "$(APP_UNLOCK)" "$(APP_RESTORE)"
