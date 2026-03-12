BIN = ../../bin/image-wall
SRC = main.swift
FRAMEWORKS = -framework AppKit -framework Foundation -framework UniformTypeIdentifiers

$(BIN): $(SRC)
	swiftc -o $(BIN) $(SRC) $(FRAMEWORKS)

.PHONY: clean
clean:
	rm -f $(BIN)
