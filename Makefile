# LED Spectrum Analyser - visualizer plug-in for Apple Music and iTunes (10.4+, incl. 10.7)
#
#   make            universal bundle (arm64 + x86_64) in build/
#   make ARCHS=arm64    Apple Silicon only (Music), smaller
#   make test       core unit tests (any platform with a C++11 compiler)
#   make harness    build and run the fake-host test harness (macOS), writes screenshots to build/screenshots
#   make install    copy the bundle to ~/Library/iTunes/iTunes Plug-ins
#   make zip        build/LED-Spectrum-Analyser.zip for distribution

NAME        := LED Spectrum Analyser
EXECUTABLE  := LEDSpectrumAnalyser
VERSION     := 3.1.0
BUILD       := build
BUNDLE      := $(BUILD)/$(NAME).bundle
ARCHS       ?= arm64 x86_64

# x86_64 runs on 10.13+ (anything that can run iTunes 10.7 via Retroactive); arm64 starts at 11.0
MIN_x86_64  ?= 10.13
MIN_arm64   ?= 11.0

CXX         ?= clang++
OPT         ?= -O2
WARNINGS    := -Wall -Wextra -Wno-unused-parameter
INCLUDES    := -Isrc/core -Isrc/mac -Isdk
CXXFLAGS    := -std=c++17 $(OPT) -g $(WARNINGS) $(INCLUDES) -fvisibility=hidden -fvisibility-inlines-hidden \
               -Werror=unguarded-availability-new -Werror=unguarded-availability $(EXTRA_CXXFLAGS)
OBJCFLAGS   := -fobjc-arc
FRAMEWORKS  := -framework Cocoa -framework QuartzCore -framework IOKit

CORE_SRC    := $(sort $(wildcard src/core/*.cpp))
MAC_SRC     := $(sort $(wildcard src/mac/*.mm))
SDK_SRC     := sdk/iTunesAPI.cpp
OBJS        := $(CORE_SRC:.cpp=.o) $(MAC_SRC:.mm=.o) $(SDK_SRC:.cpp=.o)

.PHONY: all bundle test harness install zip clean

all: bundle

define ARCH_RULES
$(BUILD)/$(1)/%.o: %.cpp
	@mkdir -p $$(dir $$@)
	$(CXX) $(CXXFLAGS) $$(if $$(findstring sdk/,$$<),-w,) -arch $(1) -mmacosx-version-min=$(MIN_$(1)) -c $$< -o $$@

$(BUILD)/$(1)/%.o: %.mm
	@mkdir -p $$(dir $$@)
	$(CXX) $(CXXFLAGS) $(OBJCFLAGS) -arch $(1) -mmacosx-version-min=$(MIN_$(1)) -c $$< -o $$@

$(BUILD)/$(1)/$(EXECUTABLE): $(addprefix $(BUILD)/$(1)/,$(OBJS))
	$(CXX) -bundle -arch $(1) -mmacosx-version-min=$(MIN_$(1)) $$^ $(FRAMEWORKS) -o $$@
endef

$(foreach a,$(ARCHS),$(eval $(call ARCH_RULES,$(a))))

$(BUILD)/$(EXECUTABLE): $(foreach a,$(ARCHS),$(BUILD)/$(a)/$(EXECUTABLE))
	lipo -create $^ -output $@

bundle: $(BUILD)/$(EXECUTABLE) resources/Info.plist resources/manual.html
	rm -rf "$(BUNDLE)"
	mkdir -p "$(BUNDLE)/Contents/MacOS" "$(BUNDLE)/Contents/Resources"
	cp $(BUILD)/$(EXECUTABLE) "$(BUNDLE)/Contents/MacOS/$(EXECUTABLE)"
	sed -e 's/@VERSION@/$(VERSION)/g' -e 's/@EXECUTABLE@/$(EXECUTABLE)/g' resources/Info.plist > "$(BUNDLE)/Contents/Info.plist"
	printf 'hvplhook' > "$(BUNDLE)/Contents/PkgInfo"
	cp resources/manual.html "$(BUNDLE)/Contents/Resources/$(NAME) Manual.html"
	codesign --force --sign - --timestamp=none "$(BUNDLE)"
	@echo "built $(BUNDLE)"
	@lipo -info "$(BUNDLE)/Contents/MacOS/$(EXECUTABLE)"

# core unit tests: native build, no frameworks needed
test:
	@mkdir -p $(BUILD)/test
	$(CXX) -std=c++11 -O1 -g $(WARNINGS) -Isrc/core $(CORE_SRC) tests/core_tests.cpp -o $(BUILD)/test/core_tests
	$(BUILD)/test/core_tests

# fake iTunes host: loads the bundle, drives it like Music / iTunes would, and saves screenshots
harness: bundle
	@mkdir -p $(BUILD)/harness $(BUILD)/screenshots
	$(CXX) -std=c++17 -g $(WARNINGS) -fno-objc-arc -DGL_SILENCE_DEPRECATION -Wno-deprecated-declarations -Isdk \
		$(foreach a,$(ARCHS),-arch $(a)) -mmacosx-version-min=$(MIN_x86_64) tests/host_harness.mm $(SDK_SRC) -w \
		$(FRAMEWORKS) -framework OpenGL -o $(BUILD)/harness/host_harness
	$(BUILD)/harness/host_harness "$(BUNDLE)" $(BUILD)/screenshots

install: bundle
	mkdir -p "$(HOME)/Library/iTunes/iTunes Plug-ins"
	rm -rf "$(HOME)/Library/iTunes/iTunes Plug-ins/$(NAME).bundle"
	cp -R "$(BUNDLE)" "$(HOME)/Library/iTunes/iTunes Plug-ins/"
	@echo "installed - quit and reopen Music / iTunes to load it"

zip: bundle
	rm -f $(BUILD)/LED-Spectrum-Analyser.zip
	cd $(BUILD) && ditto -c -k --keepParent "$(NAME).bundle" LED-Spectrum-Analyser.zip

clean:
	rm -rf $(BUILD)
