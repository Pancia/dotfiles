# Makefile for current-space
#
# Builds a utility to get the current macOS Mission Control space ID.
# Binary stays in lib/c/current-space/ and is called by bin/current-space wrapper.

CC = clang
CFLAGS = -Wall -Wextra -Werror -O2 -std=c99
FRAMEWORKS = -framework CoreFoundation -framework CoreGraphics

# Paths
SRC = current-space.c
TARGET = current-space

# Default target
all: $(TARGET)

# Build the binary
$(TARGET): $(SRC)
	@echo "Compiling $(SRC)..."
	$(CC) $(CFLAGS) $(FRAMEWORKS) -o $(TARGET) $(SRC)
	@echo "Build complete: $(TARGET)"

# Clean build artifacts
clean:
	@echo "Cleaning build artifacts..."
	@rm -f $(TARGET)
	@echo "Clean complete"

# Run the program after building
run: $(TARGET)
	./$(TARGET)

# Show help
help:
	@echo "Available targets:"
	@echo "  all        - Build the binary (default)"
	@echo "  clean      - Remove build artifacts"
	@echo "  run        - Build and run the program"
	@echo "  help       - Show this help message"

.PHONY: all clean run help
