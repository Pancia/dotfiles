BIN = ../../bin/image-wall
SRC = main.swift
FRAMEWORKS = -framework AppKit -framework Foundation -framework UniformTypeIdentifiers -framework AVFoundation -framework AVKit -framework CoreMedia

$(BIN): $(SRC)
	swiftc -o $(BIN) $(SRC) $(FRAMEWORKS)

.PHONY: clean
clean:
	rm -f $(BIN)
