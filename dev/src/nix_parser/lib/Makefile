# Makefile for building tree-sitter library for dev-shell

CC = gcc
CFLAGS = -Wall -fPIC -O2 -std=c99 -D_DEFAULT_SOURCE -I$(TREE_SITTER_INCLUDE) -I$(TREE_SITTER_DIR) -Itree-sitter-nix/src

TREE_SITTER_DIR = tree-sitter/lib/src
TREE_SITTER_INCLUDE = tree-sitter/lib/include

# Source files
TREE_SITTER_SRCS = $(TREE_SITTER_DIR)/lib.c

# Object files
TREE_SITTER_OBJS = tree_sitter.o

# Output library
LIB_NAME = tree-sitter/libtree-sitter.a

.PHONY: all clean

all: $(LIB_NAME)

# Compile tree-sitter library as single object
tree_sitter.o: $(TREE_SITTER_SRCS)
	$(CC) $(CFLAGS) -I$(TREE_SITTER_INCLUDE) -c $< -o $@

# Create static library
$(LIB_NAME): $(TREE_SITTER_OBJS)
	ar rcs $@ $^

clean:
	rm -f $(TREE_SITTER_OBJS) $(LIB_NAME)

# Build nix parser objects (placed inside the tree-sitter-nix submodule dir
# where project.json link-args expects them)
nix-parser: tree-sitter-nix/src/parser.o tree-sitter-nix/src/scanner.o

tree-sitter-nix/src/parser.o: tree-sitter-nix/src/parser.c
	$(CC) $(CFLAGS) -I$(TREE_SITTER_INCLUDE) -c $< -o $@

tree-sitter-nix/src/scanner.o: tree-sitter-nix/src/scanner.c
	$(CC) $(CFLAGS) -I$(TREE_SITTER_INCLUDE) -c $< -o $@
