BIN = ../../bin/image-wall
SRC = main.swift
FRAMEWORKS = -framework AppKit -framework Foundation -framework UniformTypeIdentifiers -framework AVFoundation -framework AVKit -framework CoreMedia -F /System/Library/PrivateFrameworks -framework SkyLight

$(BIN): $(SRC)
	swiftc -o $(BIN) $(SRC) $(FRAMEWORKS)

.PHONY: clean
clean:
	rm -f $(BIN)
