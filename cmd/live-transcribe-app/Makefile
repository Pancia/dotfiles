APP = ../../bin/LiveTranscribe.app
BIN = $(APP)/Contents/MacOS/live-transcribe-app
FRAMEWORKS = -framework AppKit -framework Foundation -framework Carbon

# Code-signing identity for the bundle. macOS keys the microphone (TCC) grant to
# the signature's designated requirement. A stable self-signed identity keeps the
# grant across rebuilds; ad-hoc ("-") resets it every build. We auto-use the
# "LiveTranscribe Self-Signed" cert when it's in the keychain, else fall back to
# ad-hoc — so a bare `make` never silently resets your mic permission.
# Override explicitly with e.g. `make CODESIGN_IDENTITY=-`.
CODESIGN_IDENTITY ?= $(shell security find-certificate -c "LiveTranscribe Self-Signed" >/dev/null 2>&1 && echo "LiveTranscribe Self-Signed" || echo "-")

$(BIN): main.swift Info.plist
	mkdir -p $(APP)/Contents/MacOS
	cp Info.plist $(APP)/Contents/Info.plist
	swiftc -O -o $(BIN) main.swift $(FRAMEWORKS)
	codesign --force --identifier org.pancia.live-transcribe-app --sign "$(CODESIGN_IDENTITY)" $(APP)

.PHONY: clean
clean:
	rm -rf $(APP)
