BIN = $(HOME)/.local/bin/mic-active
SRC = main.swift
FRAMEWORKS = -framework CoreAudio

$(BIN): $(SRC)
	swiftc -O -o $(BIN) $(SRC) $(FRAMEWORKS)

.PHONY: clean
clean:
	rm -f $(BIN)
