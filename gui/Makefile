APP = CPULimitGUI.app
BINARY = .build/release/CPULimitGUI
CPULIMIT = ../src/cpulimit
SOURCES = $(wildcard Sources/CPULimitGUI/*.swift Sources/CPULimitGUI/Views/*.swift)

.PHONY: all app clean

all: app

$(CPULIMIT):
	$(MAKE) -C ../src

$(BINARY): $(SOURCES) Package.swift
	swift build -c release

app: $(BINARY) $(CPULIMIT)
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	cp Info.plist $(APP)/Contents/
	cp $(BINARY) $(APP)/Contents/MacOS/
	cp $(CPULIMIT) $(APP)/Contents/Resources/
	codesign --force -s - $(APP)
	@echo "构建完成: $(APP)"

clean:
	rm -rf .build $(APP)
